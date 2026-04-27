#!/usr/bin/env python3
"""Build hmm_metadata.tsv / .json from per-HMM headers + domain_list.tsv.

Each per_domain/*.hmm file is a HMMER3-format profile. We parse the header
(NAME / LENG / NSEQ / EFFN) and join with Pfam-level info (accession / version /
name / category) from hmm/domain_list.tsv.

Outputs:
    metadata/hmm_metadata.tsv    human-readable
    metadata/hmm_metadata.json   consumed by the GitHub Pages HMM browser

Run:
    python scripts/build_hmm_metadata.py
"""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
HMM_DIR = REPO_ROOT / "hmm"
PER_DOMAIN = HMM_DIR / "per_domain"
DOMAIN_LIST = HMM_DIR / "domain_list.tsv"
OUT_TSV = REPO_ROOT / "metadata" / "hmm_metadata.tsv"
OUT_JSON = REPO_ROOT / "metadata" / "hmm_metadata.json"

COLUMNS = [
    "pfam_accession", "pfam_version", "pfam_name", "category",
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
            if line.startswith(HEADER_STOP + " ") or line.startswith(HEADER_STOP + "\t") or line == HEADER_STOP:
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
    """Return {pfam_name: {accession, version, category}}."""
    by_name: dict[str, dict] = {}
    with open(path) as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            by_name[row["name"]] = {
                "accession": row["accession"],
                "version": row["version"],
                "category": row["category"],
            }
    return by_name


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
    rows = []
    missing_in_list = []

    for hf in hmm_files:
        hdr = parse_hmm_header(hf)
        pfam_name = infer_pfam_name_from_file(hf.name)
        dinfo = domain_map.get(pfam_name)
        if dinfo is None:
            missing_in_list.append(pfam_name)
            dinfo = {"accession": "", "version": "", "category": ""}
        row = {
            "pfam_accession": dinfo["accession"],
            "pfam_version": dinfo["version"],
            "pfam_name": pfam_name,
            "category": dinfo["category"],
            "hmm_name": hdr.get("NAME", ""),
            "hmm_file": f"hmm/per_domain/{hf.name}",
            "hmm_length": hdr.get("LENG", ""),
            "n_seed_sequences": hdr.get("NSEQ", ""),
            "effn": hdr.get("EFFN", ""),
            "source": "TIAMMAt mollusc-revised",
        }
        rows.append(row)

    rows.sort(key=lambda r: (r["category"] or "zzz", r["pfam_name"].lower()))

    OUT_TSV.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT_TSV, "w") as f:
        f.write("\t".join(COLUMNS) + "\n")
        for r in rows:
            f.write("\t".join(str(r[c]) for c in COLUMNS) + "\n")

    with open(OUT_JSON, "w") as f:
        json.dump({
            "generated_by": "scripts/build_hmm_metadata.py",
            "source": "TIAMMAt mollusc-revised Pfam HMMs",
            "columns": COLUMNS,
            "rows": rows,
        }, f, indent=2)

    print(f"parsed {len(rows)} HMMs")
    print(f"  wrote {OUT_TSV}")
    print(f"  wrote {OUT_JSON}")
    if missing_in_list:
        print(f"  WARNING: {len(missing_in_list)} HMMs not in domain_list.tsv:", file=sys.stderr)
        for n in missing_in_list[:10]:
            print(f"    {n}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
