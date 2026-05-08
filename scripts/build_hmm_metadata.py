#!/usr/bin/env python3
"""Build hmm_metadata.tsv / .json from per-HMM headers + domain_list.tsv.

Each per_domain/*.hmm file is a HMMER3-format profile. We parse the header
(NAME / LENG / NSEQ / EFFN) and join with Pfam-level info from the v2 5-col
``hmm/domain_list.tsv``, which carries:

    accession    version    name    theme_id    subcategory_id

Display names for theme_id / subcategory_id are looked up in the curation
schema (sibling repo ``tiammat_mollusca/taxonomy/theme_subcategory_schema.tsv``).
``pfam_short_name`` and ``pfam_description`` are pulled from the original
Pfam-A 36.0 HMM bundle (``tiammat_mollusca/databases/pfam_original_1057.hmm``)
so the site can show informative tooltips offline.

Outputs (kept byte-identical):
    metadata/hmm_metadata.tsv      reproducibility copy (TSV)
    metadata/hmm_metadata.json     reproducibility copy (JSON)
    docs/data/hmm_metadata.json    site copy consumed by the HMM browser

Run:
    python scripts/build_hmm_metadata.py
"""

from __future__ import annotations

import csv
import json
import shutil
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
HMM_DIR = REPO_ROOT / "hmm"
PER_DOMAIN = HMM_DIR / "per_domain"
DOMAIN_LIST = HMM_DIR / "domain_list.tsv"
OUT_TSV = REPO_ROOT / "metadata" / "hmm_metadata.tsv"
OUT_JSON = REPO_ROOT / "metadata" / "hmm_metadata.json"
DOCS_JSON = REPO_ROOT / "docs" / "data" / "hmm_metadata.json"

# Sibling repo with the curation taxonomy + original Pfam bundle.
TIAMMAT_ROOT = REPO_ROOT.parent / "tiammat_mollusca"
SCHEMA_TSV = TIAMMAT_ROOT / "taxonomy" / "theme_subcategory_schema.tsv"
PFAM_ORIGINAL = TIAMMAT_ROOT / "databases" / "pfam_original_1057.hmm"

COLUMNS = [
    "pfam_accession", "pfam_version", "pfam_name",
    "pfam_short_name", "pfam_description",
    "theme_id", "theme", "subcategory_id", "subcategory",
    "hmm_name", "hmm_file", "hmm_length", "n_seed_sequences",
    "effn", "source",
]

HEADER_STOP = "HMM"  # first "HMM" line (alphabet header) ends the metadata header


def parse_hmm_header(path: Path) -> dict[str, str]:
    """Return {NAME, LENG, NSEQ, EFFN} from HMMER3 file. Only reads top of file."""
    fields: dict[str, str] = {}
    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            if (
                line.startswith(HEADER_STOP + " ")
                or line.startswith(HEADER_STOP + "\t")
                or line == HEADER_STOP
            ):
                break
            # HMMER3 header lines: "KEY  value"
            parts = line.split(None, 1)
            if len(parts) != 2:
                continue
            key, val = parts
            if key in ("NAME", "LENG", "NSEQ", "EFFN"):
                fields[key] = val.strip()
    return fields


def load_domain_list(path: Path) -> dict[str, dict]:
    """Return {pfam_name: {accession, version, theme_id, subcategory_id}}."""
    by_name: dict[str, dict] = {}
    with open(path) as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            by_name[row["name"]] = {
                "accession": row["accession"],
                "version": row["version"],
                "theme_id": row.get("theme", ""),
                "subcategory_id": row.get("subcategory", ""),
            }
    return by_name


def load_schema(path: Path) -> tuple[dict[str, str], dict[str, str]]:
    """Return (theme_id -> theme_name, subcategory_id -> subcategory_name)."""
    themes: dict[str, str] = {}
    subcats: dict[str, str] = {}
    if not path.is_file():
        print(f"WARNING: schema TSV not found at {path}; display names will be blank",
              file=sys.stderr)
        return themes, subcats
    with open(path) as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            tid = row["theme_id"]
            sid = row["subcategory_id"]
            themes.setdefault(tid, row["theme_name"])
            subcats.setdefault(sid, row["subcategory_name"])
    return themes, subcats


def parse_pfam_descriptions(path: Path) -> dict[str, dict]:
    """Scan a HMMER3 multi-profile file; return {accession_versionless: {...}}.

    The original Pfam bundle stores `NAME`, `ACC` (e.g. `PF00001.27`), and
    `DESC` per profile. We key by the bare accession (`PF00001`) so the
    lookup is robust to version drift.
    """
    by_acc: dict[str, dict] = {}
    if not path.is_file():
        print(
            f"WARNING: original Pfam bundle not found at {path}; "
            "pfam_description / pfam_short_name will be blank",
            file=sys.stderr,
        )
        return by_acc

    cur: dict[str, str] = {}
    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")
            if line.startswith("HMMER3"):
                # Start of a new profile -> flush previous record.
                if cur.get("ACC"):
                    acc_bare = cur["ACC"].split(".", 1)[0]
                    by_acc.setdefault(acc_bare, {
                        "name": cur.get("NAME", ""),
                        "desc": cur.get("DESC", ""),
                    })
                cur = {}
                continue
            if line.startswith("HMM "):
                # Past the header for this profile; skip until next HMMER3 line.
                continue
            parts = line.split(None, 1)
            if len(parts) != 2:
                continue
            key, val = parts
            if key in ("NAME", "ACC", "DESC"):
                cur[key] = val.strip()
        # Final record at EOF.
        if cur.get("ACC"):
            acc_bare = cur["ACC"].split(".", 1)[0]
            by_acc.setdefault(acc_bare, {
                "name": cur.get("NAME", ""),
                "desc": cur.get("DESC", ""),
            })
    return by_acc


def infer_pfam_name_from_file(filename: str) -> str:
    """`7tm_1_REVISION.hmm` -> `7tm_1`."""
    stem = filename
    for suffix in (".hmm", "_REVISION"):
        if stem.endswith(suffix):
            stem = stem[: -len(suffix)]
    return stem


def main() -> int:
    hmm_files = sorted(PER_DOMAIN.glob("*.hmm"))
    if not hmm_files:
        print(f"no HMM files found under {PER_DOMAIN}", file=sys.stderr)
        return 1

    domain_map = load_domain_list(DOMAIN_LIST)
    theme_names, subcat_names = load_schema(SCHEMA_TSV)
    pfam_meta = parse_pfam_descriptions(PFAM_ORIGINAL)

    rows = []
    missing_in_list: list[str] = []
    missing_theme: set[str] = set()
    missing_subcat: set[str] = set()

    for hf in hmm_files:
        hdr = parse_hmm_header(hf)
        pfam_name = infer_pfam_name_from_file(hf.name)
        dinfo = domain_map.get(pfam_name)
        if dinfo is None:
            missing_in_list.append(pfam_name)
            dinfo = {"accession": "", "version": "", "theme_id": "", "subcategory_id": ""}

        theme_id = dinfo["theme_id"]
        subcat_id = dinfo["subcategory_id"]
        theme_disp = theme_names.get(theme_id, "")
        subcat_disp = subcat_names.get(subcat_id, "")
        if theme_id and not theme_disp:
            missing_theme.add(theme_id)
        if subcat_id and not subcat_disp:
            missing_subcat.add(subcat_id)

        acc_bare = dinfo["accession"]
        pmeta = pfam_meta.get(acc_bare, {})

        row = {
            "pfam_accession": dinfo["accession"],
            "pfam_version": dinfo["version"],
            "pfam_name": pfam_name,
            # Pfam HMM `DESC` is a one-line label (e.g.
            # "7 transmembrane receptor (rhodopsin family)"). It maps
            # cleanly onto the v0.1 ``pfam_short_name`` slot. The longer
            # prose ``pfam_description`` is InterPro-only; left blank
            # offline so the site degrades gracefully.
            "pfam_short_name": pmeta.get("desc", ""),
            "pfam_description": "",
            "theme_id": theme_id,
            "theme": theme_disp,
            "subcategory_id": subcat_id,
            "subcategory": subcat_disp,
            "hmm_name": hdr.get("NAME", ""),
            "hmm_file": f"hmm/per_domain/{hf.name}",
            "hmm_length": hdr.get("LENG", ""),
            "n_seed_sequences": hdr.get("NSEQ", ""),
            "effn": hdr.get("EFFN", ""),
            "source": "TIAMMAt mollusc-revised",
        }
        rows.append(row)

    rows.sort(key=lambda r: (
        r["theme_id"] or "zzz",
        r["subcategory_id"] or "zzz",
        r["pfam_name"].lower(),
    ))

    OUT_TSV.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT_TSV, "w") as f:
        f.write("\t".join(COLUMNS) + "\n")
        for r in rows:
            f.write("\t".join(str(r[c]) for c in COLUMNS) + "\n")

    payload = {
        "generated_by": "scripts/build_hmm_metadata.py",
        "source": "TIAMMAt mollusc-revised Pfam HMMs",
        "columns": COLUMNS,
        "rows": rows,
    }
    with open(OUT_JSON, "w") as f:
        json.dump(payload, f, indent=2)

    DOCS_JSON.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(OUT_JSON, DOCS_JSON)

    print(f"wrote {len(rows)} rows")
    print(f"  {OUT_TSV}")
    print(f"  {OUT_JSON}")
    print(f"  {DOCS_JSON}")
    if missing_in_list:
        print(
            f"  WARNING: {len(missing_in_list)} HMMs not in domain_list.tsv:",
            file=sys.stderr,
        )
        for n in missing_in_list[:10]:
            print(f"    {n}", file=sys.stderr)
    if missing_theme:
        print(
            f"  WARNING: {len(missing_theme)} theme IDs not in schema:",
            sorted(missing_theme),
            file=sys.stderr,
        )
    if missing_subcat:
        print(
            f"  WARNING: {len(missing_subcat)} subcategory IDs not in schema:",
            sorted(missing_subcat),
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
