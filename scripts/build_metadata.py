#!/usr/bin/env python3
"""Build species_metadata.tsv from dict2.tsv + NCBI taxonomy + WoRMS + BLAST db counts.

Run from anywhere; writes to <repo>/metadata/species_metadata.tsv and caches
external API responses under <repo>/metadata/_cache/ (gitignored).

Usage:
    python scripts/build_metadata.py
    python scripts/build_metadata.py --validate          # re-read TSV, assert schema
    python scripts/build_metadata.py --skip-network      # use cache only
    python scripts/build_metadata.py --blast-aa /path    # override aa db path
    python scripts/build_metadata.py --blast-mrna /path  # override mrna db path
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from xml.etree import ElementTree as ET

import requests
from Bio import Entrez

REPO_ROOT = Path(__file__).resolve().parent.parent
DICT_PATH = REPO_ROOT / "metadata" / "dict2.tsv"
OUT_PATH = REPO_ROOT / "metadata" / "species_metadata.tsv"
SCHEMA_PATH = REPO_ROOT / "metadata" / "species_metadata.schema.json"
CACHE_DIR = REPO_ROOT / "metadata" / "_cache"
LOG_PATH = REPO_ROOT / "metadata" / "_cache" / "build_metadata.log"

DEFAULT_BLAST_AA = "/home/workspace/Desktop/projects/umass/CR/data/20250320/mollusca_aa"
DEFAULT_BLAST_MRNA = "/home/workspace/Desktop/projects/umass/CR/data/20250320/mollusca_mrna"

ENTREZ_EMAIL = os.environ.get("NCBI_EMAIL", "xibalbanus@gmail.com")
NCBI_API_KEY = os.environ.get("NCBI_API_KEY")
WORMS_BASE = "https://www.marinespecies.org/rest"

COLUMNS = [
    "species_code", "species_binomial", "ncbi_taxid",
    "phylum", "class", "subclass", "order", "family",
    "worms_aphia_id", "molluscabase_id",
    "n_proteins", "n_transcripts", "mean_protein_len",
    "data_source", "source_accession", "sequencing_type",
    "reference_citation_doi",
]


def log(msg: str) -> None:
    line = f"[{time.strftime('%H:%M:%S')}] {msg}"
    print(line, file=sys.stderr)
    with open(LOG_PATH, "a") as f:
        f.write(line + "\n")


def load_dict(path: Path) -> list[tuple[str, str]]:
    rows = []
    with open(path) as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 2:
                rows.append((parts[0], parts[1]))
    return rows


def binomial_from_dict(raw: str) -> str:
    """Convert dict-form names (Genus_species, Genus_sp., ...) to display form."""
    return raw.replace("_", " ").strip()


def count_from_blast(db: str, dbtype: str) -> tuple[dict[str, int], dict[str, int]]:
    """Return (counts_by_code, summed_len_by_code) for a BLAST db.

    Species code is the accession prefix up to 'EVm' (protein) or 'EVm' equivalent.
    Falls back to full accession if no 'EVm' split found.
    """
    log(f"counting sequences in {db} ({dbtype})...")
    cmd = ["blastdbcmd", "-db", db, "-dbtype", dbtype, "-entry", "all",
           "-outfmt", "%a\t%l"]
    counts: dict[str, int] = {}
    lens: dict[str, int] = {}
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True)
    assert proc.stdout is not None
    for line in proc.stdout:
        parts = line.rstrip("\n").split("\t")
        if len(parts) != 2:
            continue
        acc, length_s = parts
        try:
            length = int(length_s)
        except ValueError:
            continue
        # Split at 'EVm' (EvidentialGene main) — same convention for aa + mrna
        code = acc.split("EVm", 1)[0] if "EVm" in acc else acc[:6]
        counts[code] = counts.get(code, 0) + 1
        lens[code] = lens.get(code, 0) + length
    proc.wait()
    log(f"  -> {sum(counts.values())} sequences across {len(counts)} codes")
    return counts, lens


# --------------------------- NCBI taxonomy ------------------------------

def _entrez_setup() -> None:
    Entrez.email = ENTREZ_EMAIL
    if NCBI_API_KEY:
        Entrez.api_key = NCBI_API_KEY


def _cached_json(path: Path) -> dict | None:
    if path.exists():
        try:
            return json.loads(path.read_text())
        except Exception:
            return None
    return None


def _save_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2))


def ncbi_lookup(binomial: str, skip_network: bool = False) -> dict:
    """Return dict with taxid + phylum/class/subclass/order/family. Cached."""
    cache = CACHE_DIR / "ncbi" / f"{binomial.replace(' ', '_').replace('/', '_')}.json"
    cached = _cached_json(cache)
    if cached is not None:
        return cached
    if skip_network:
        return {"ncbi_taxid": "", "phylum": "", "class": "", "subclass": "", "order": "", "family": ""}
    _entrez_setup()
    # Try exact match first, then progressively simplify.
    queries = [binomial]
    # Strip trailing sp / sp. / sp.<N> / sp<N> / aff. / cf.
    s1 = re.sub(r"\s+(sp\.?\d*|sp\._\d+|aff\.?|cf\.?)(\s.*)?$", "", binomial).strip()
    # Drop parenthetical subgenus: "Mizuhopecten (Patinopecten) yessoensis" -> "Mizuhopecten yessoensis"
    s2 = re.sub(r"\s*\([^)]*\)\s*", " ", s1).strip()
    for s in (s1, s2):
        if s and s not in queries:
            queries.append(s)
    # Last-resort fallback: genus only
    genus = queries[-1].split()[0] if queries[-1] else ""
    if genus and genus not in queries:
        queries.append(genus)
    out = {"ncbi_taxid": "", "phylum": "", "class": "", "subclass": "", "order": "", "family": ""}
    for idx, q in enumerate(queries):
        try:
            h = Entrez.esearch(db="taxonomy", term=f'"{q}"[Scientific Name]', retmax=1)
            r = Entrez.read(h); h.close()
            ids = r.get("IdList", [])
            if not ids:
                h = Entrez.esearch(db="taxonomy", term=q, retmax=1)
                r = Entrez.read(h); h.close()
                ids = r.get("IdList", [])
            if not ids:
                continue
            taxid = ids[0]
            # Retry on 429 with backoff
            for attempt in range(3):
                try:
                    h = Entrez.efetch(db="taxonomy", id=taxid)
                    xml = h.read(); h.close()
                    break
                except Exception as e:
                    if "429" in str(e) and attempt < 2:
                        time.sleep(2 ** attempt)
                        continue
                    raise
            root = ET.fromstring(xml)
            sci_name = root.findtext(".//Taxon/ScientificName") or ""
            candidate = {"ncbi_taxid": taxid, "phylum": "", "class": "",
                         "subclass": "", "order": "", "family": ""}
            for taxon in root.findall(".//LineageEx/Taxon"):
                rank = taxon.findtext("Rank")
                name = taxon.findtext("ScientificName") or ""
                if rank in ("phylum", "class", "subclass", "order", "family"):
                    candidate[rank] = name
            # First-query exemption: accept non-Mollusca hits ONLY when this is the
            # original binomial (idx 0) AND NCBI's ScientificName exactly matches —
            # that's a legit outgroup with its real binomial. Fallback queries must
            # always resolve to Mollusca (stops fungal/viral homonym hits at the genus level).
            is_exact_first_match = (idx == 0 and sci_name.lower() == q.lower())
            phy = candidate["phylum"]
            if phy and phy != "Mollusca" and not is_exact_first_match:
                log(f"  rejected non-Mollusca match for {binomial!r} (q={q!r}): phy={phy} (NCBI={sci_name!r})")
                continue
            if not phy and idx > 0:
                continue
            out = candidate
            break
        except Exception as e:
            log(f"  NCBI lookup failed for {q!r}: {e}")
            time.sleep(1)
    _save_json(cache, out)
    return out


def worms_lookup(binomial: str, skip_network: bool = False) -> str:
    """Return WoRMS AphiaID (string, may be empty). Cached."""
    cache = CACHE_DIR / "worms" / f"{binomial.replace(' ', '_').replace('/', '_')}.json"
    cached = _cached_json(cache)
    if cached is not None:
        return cached.get("aphia_id", "")
    if skip_network:
        return ""
    simplified = re.sub(r"\s+(sp\.?|sp\._\d+|aff\.?|cf\.?)(\s.*)?$", "", binomial).strip()
    try:
        url = f"{WORMS_BASE}/AphiaIDByName/{requests.utils.quote(simplified)}?marine_only=false"
        r = requests.get(url, timeout=10)
        if r.status_code == 200:
            txt = r.text.strip()
            # WoRMS returns a bare integer or null
            aphia = txt if txt.isdigit() else ""
        elif r.status_code == 204:
            aphia = ""
        else:
            aphia = ""
    except Exception as e:
        log(f"  WoRMS lookup failed for {binomial!r}: {e}")
        aphia = ""
    _save_json(cache, {"aphia_id": aphia})
    return aphia


# --------------------------- Output ------------------------------

def write_schema(path: Path) -> None:
    schema = {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "title": "MolluscaGenes species_metadata.tsv",
        "description": "Per-species metadata for MolluscaGenes v0.1.",
        "tableFormat": "TSV with header row",
        "columns": {
            "species_code": {"type": "string", "required": True,
                "description": "5-7 letter alphanumeric species code (authoritative key)."},
            "species_binomial": {"type": "string", "required": True,
                "description": "Genus + species (or Genus sp. for unidentified), space-separated."},
            "ncbi_taxid": {"type": "string",
                "description": "NCBI taxonomy ID; may be empty for undescribed species or unmatched names."},
            "phylum": {"type": "string", "description": "From NCBI taxonomy lineage. Usually Mollusca."},
            "class": {"type": "string", "description": "From NCBI taxonomy lineage."},
            "subclass": {"type": "string", "description": "From NCBI taxonomy lineage; often empty."},
            "order": {"type": "string", "description": "From NCBI taxonomy lineage."},
            "family": {"type": "string", "description": "From NCBI taxonomy lineage."},
            "worms_aphia_id": {"type": "string",
                "description": "WoRMS (World Register of Marine Species) AphiaID; may be empty."},
            "molluscabase_id": {"type": "string",
                "description": "MolluscaBase identifier. Federated with WoRMS — same AphiaID resolves on both sites; mirrored from worms_aphia_id."},
            "n_proteins": {"type": "integer",
                "description": "Count of protein sequences in mollusca_aa for this species."},
            "n_transcripts": {"type": "integer",
                "description": "Count of nucleotide transcripts in mollusca_mrna for this species."},
            "mean_protein_len": {"type": "number",
                "description": "Mean protein length (residues) across this species."},
            "data_source": {"type": "string",
                "description": "Source workflow. 'EvidentialGene assembly' for species with sequences; empty otherwise."},
            "source_accession": {"type": "string",
                "description": "Upstream accession if known. v0.1 leaves this mostly empty; v1.0 will populate from NCBI BioProject linkage."},
            "sequencing_type": {"type": "string",
                "description": "'transcriptome' for species with sequences; empty for dict-only entries."},
            "reference_citation_doi": {"type": "string",
                "description": "DOI of source publication if known. v0.1 leaves this empty; v1.0 will populate via NCBI BioProject linkage."},
        },
        "notes": [
            "Species with n_proteins=0 and n_transcripts=0 are listed for transparency: they were planned for inclusion but no sequences are in this release.",
            "v1.0 will add BUSCO completeness, source_accession, and reference_citation_doi.",
        ],
    }
    path.write_text(json.dumps(schema, indent=2))


def write_tsv(rows: list[dict], path: Path) -> None:
    with open(path, "w") as f:
        f.write("\t".join(COLUMNS) + "\n")
        for row in rows:
            f.write("\t".join(str(row.get(c, "")) for c in COLUMNS) + "\n")


def validate(path: Path) -> int:
    schema = json.loads(SCHEMA_PATH.read_text())
    cols_expected = list(schema["columns"].keys())
    with open(path) as f:
        header = f.readline().rstrip("\n").split("\t")
        if header != cols_expected:
            log(f"FAIL: header mismatch. Expected {cols_expected}, got {header}")
            return 1
        n = 0
        for i, line in enumerate(f, 2):
            cells = line.rstrip("\n").split("\t")
            if len(cells) != len(cols_expected):
                log(f"FAIL: row {i} has {len(cells)} cells, expected {len(cols_expected)}")
                return 1
            n += 1
    log(f"OK: {n} rows, all conforming to schema.")
    return 0


# --------------------------- Main ------------------------------

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--blast-aa", default=DEFAULT_BLAST_AA)
    ap.add_argument("--blast-mrna", default=DEFAULT_BLAST_MRNA)
    ap.add_argument("--skip-network", action="store_true",
                    help="Don't call NCBI/WoRMS; use cache only.")
    ap.add_argument("--validate", action="store_true",
                    help="Validate existing TSV against schema, don't rebuild.")
    args = ap.parse_args()

    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)

    if args.validate:
        return validate(OUT_PATH)

    log("=== build_metadata.py start ===")
    log(f"dict: {DICT_PATH}")
    log(f"blast aa: {args.blast_aa}")
    log(f"blast mrna: {args.blast_mrna}")
    log(f"NCBI_API_KEY: {'set' if NCBI_API_KEY else 'not set (rate-limited to 3 req/s)'}")

    dict_rows = load_dict(DICT_PATH)
    log(f"dict: {len(dict_rows)} entries")

    aa_counts, aa_lens = count_from_blast(args.blast_aa, "prot")
    mrna_counts, _ = count_from_blast(args.blast_mrna, "nucl")

    write_schema(SCHEMA_PATH)

    rows = []
    total = len(dict_rows)
    for i, (code, raw_name) in enumerate(dict_rows, 1):
        binomial = binomial_from_dict(raw_name)
        n_p = aa_counts.get(code, 0)
        n_t = mrna_counts.get(code, 0)
        mean_len = round(aa_lens.get(code, 0) / n_p, 1) if n_p else ""

        has_seqs = (n_p > 0 or n_t > 0)
        data_source = "EvidentialGene assembly" if has_seqs else ""
        seq_type = "transcriptome" if has_seqs else ""

        tax = ncbi_lookup(binomial, skip_network=args.skip_network)
        aphia = worms_lookup(binomial, skip_network=args.skip_network)

        rows.append({
            "species_code": code,
            "species_binomial": binomial,
            "ncbi_taxid": tax["ncbi_taxid"],
            "phylum": tax["phylum"],
            "class": tax["class"],
            "subclass": tax["subclass"],
            "order": tax["order"],
            "family": tax["family"],
            "worms_aphia_id": aphia,
            # MolluscaBase shares the AphiaID registry with WoRMS — every WoRMS
            # AphiaID resolves on molluscabase.org. We mirror the value into a
            # dedicated column so the metadata is explicit about both authorities.
            "molluscabase_id": aphia,
            "n_proteins": n_p,
            "n_transcripts": n_t,
            "mean_protein_len": mean_len,
            "data_source": data_source,
            "source_accession": "",
            "sequencing_type": seq_type,
            "reference_citation_doi": "",
        })
        if i % 25 == 0 or i == total:
            log(f"  {i}/{total} species processed (last: {code} / {binomial})")

    write_tsv(rows, OUT_PATH)
    log(f"wrote {OUT_PATH} ({len(rows)} rows)")
    log(f"wrote {SCHEMA_PATH}")
    log("=== build_metadata.py done ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
