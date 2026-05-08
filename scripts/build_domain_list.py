#!/usr/bin/env python3
"""Build hmm/domain_list.tsv (5-col schema) for the v2 HMM bundle.

Schema: accession\tversion\tname\ttheme\tsubcategory

Sources:
- hmm/per_domain/<NAME>_REVISION.hmm — list of revised HMMs (parses NAME field)
- ../tiammat_mollusca/databases/pfam_original_1057.hmm — provides NAME -> ACC (Pfam version)
  mapping (revised HMMs lack ACC headers)
- ../tiammat_mollusca/taxonomy/domain_categories.tsv — accession -> subcategory_id
- ../tiammat_mollusca/taxonomy/theme_subcategory_schema.tsv — subcategory_id -> theme_id

The script is deterministic: rows are sorted by accession ascending.

Run from the molluscagenes/ repo root:
    python scripts/build_domain_list.py
"""

from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
TIAMMAT = REPO_ROOT.parent / "tiammat_mollusca"

HMM_DIR = REPO_ROOT / "hmm" / "per_domain"
PFAM_ORIGINAL_HMM = TIAMMAT / "databases" / "pfam_original_1057.hmm"
DOMAIN_CATEGORIES_TSV = TIAMMAT / "taxonomy" / "domain_categories.tsv"
THEME_SCHEMA_TSV = TIAMMAT / "taxonomy" / "theme_subcategory_schema.tsv"
OUTPUT_TSV = REPO_ROOT / "hmm" / "domain_list.tsv"


def parse_hmm_name(hmm_path: Path) -> str:
    """Return the NAME field from an HMMER3 HMM file header."""
    with hmm_path.open() as fh:
        for line in fh:
            if line.startswith("NAME"):
                return line.split(None, 1)[1].strip()
            if line.startswith("HMM "):
                break
    raise ValueError(f"No NAME field in {hmm_path}")


def parse_pfam_name_to_acc(pfam_hmm: Path) -> dict[str, str]:
    """Walk the concatenated Pfam HMM file, return {NAME: ACC} mapping.

    ACC is the dotted Pfam version (e.g. 'PF00001.27'); the bare accession
    is the part before the dot ('PF00001').
    """
    mapping: dict[str, str] = {}
    current_name: str | None = None
    with pfam_hmm.open() as fh:
        for line in fh:
            if line.startswith("NAME"):
                current_name = line.split(None, 1)[1].strip()
            elif line.startswith("ACC"):
                if current_name is None:
                    raise ValueError(f"ACC before NAME in {pfam_hmm}")
                mapping[current_name] = line.split(None, 1)[1].strip()
                current_name = None
    return mapping


def load_domain_categories(path: Path) -> dict[str, str]:
    """Load accession -> subcategory_id from domain_categories.tsv."""
    out: dict[str, str] = {}
    with path.open() as fh:
        header = next(fh).rstrip("\n").split("\t")
        if header != ["accession", "category"]:
            raise ValueError(f"unexpected header in {path}: {header}")
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) != 2:
                continue
            out[parts[0]] = parts[1]
    return out


def load_subcategory_to_theme(path: Path) -> dict[str, str]:
    """Load subcategory_id -> theme_id from theme_subcategory_schema.tsv."""
    out: dict[str, str] = {}
    with path.open() as fh:
        header = next(fh).rstrip("\n").split("\t")
        expected = ["theme_id", "theme_name", "subcategory_id",
                    "subcategory_name", "description"]
        if header != expected:
            raise ValueError(f"unexpected header in {path}: {header}")
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3:
                continue
            theme_id, _theme_name, subcat_id = parts[0], parts[1], parts[2]
            if subcat_id in out and out[subcat_id] != theme_id:
                raise ValueError(
                    f"conflicting theme for subcategory {subcat_id}: "
                    f"{out[subcat_id]} vs {theme_id}"
                )
            out[subcat_id] = theme_id
    return out


def strip_rev_suffix(name: str) -> str:
    """Convert revised HMM NAME ('7tm_1_REV') to base Pfam name ('7tm_1')."""
    if name.endswith("_REV"):
        return name[:-4]
    return name


def main() -> int:
    hmm_files = sorted(HMM_DIR.glob("*.hmm"))
    if not hmm_files:
        print(f"ERROR: no HMM files in {HMM_DIR}", file=sys.stderr)
        return 1

    pfam_name_to_acc = parse_pfam_name_to_acc(PFAM_ORIGINAL_HMM)
    accession_to_subcat = load_domain_categories(DOMAIN_CATEGORIES_TSV)
    subcat_to_theme = load_subcategory_to_theme(THEME_SCHEMA_TSV)

    rows: list[tuple[str, str, str, str, str]] = []
    errors: list[str] = []

    for hmm_path in hmm_files:
        revised_name = parse_hmm_name(hmm_path)
        base_name = strip_rev_suffix(revised_name)

        if base_name not in pfam_name_to_acc:
            errors.append(
                f"{hmm_path.name}: NAME '{base_name}' not in Pfam original HMM"
            )
            continue

        version = pfam_name_to_acc[base_name]  # e.g. PF00001.27
        accession = version.split(".", 1)[0]   # e.g. PF00001

        if accession not in accession_to_subcat:
            errors.append(
                f"{hmm_path.name}: accession {accession} ({base_name}) "
                f"missing from domain_categories.tsv"
            )
            continue

        subcategory = accession_to_subcat[accession]
        if subcategory not in subcat_to_theme:
            errors.append(
                f"{hmm_path.name}: subcategory '{subcategory}' "
                f"missing from theme_subcategory_schema.tsv"
            )
            continue

        theme = subcat_to_theme[subcategory]
        rows.append((accession, version, base_name, theme, subcategory))

    # Reverse-direction orphan check: every accession in domain_categories.tsv
    # should have a matching HMM (we've staged 1057 HMMs).
    accessions_seen = {r[0] for r in rows}
    extra_taxonomy = set(accession_to_subcat) - accessions_seen
    if extra_taxonomy:
        errors.append(
            f"{len(extra_taxonomy)} accessions in domain_categories.tsv "
            f"have no matching HMM: {sorted(extra_taxonomy)[:5]}..."
        )

    if errors:
        print("ERRORS:", file=sys.stderr)
        for err in errors:
            print(f"  {err}", file=sys.stderr)
        return 1

    rows.sort(key=lambda r: r[0])

    with OUTPUT_TSV.open("w") as fh:
        fh.write("accession\tversion\tname\ttheme\tsubcategory\n")
        for row in rows:
            fh.write("\t".join(row) + "\n")

    print(f"Wrote {len(rows)} rows to {OUTPUT_TSV}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
