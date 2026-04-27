#!/usr/bin/env python3
"""Read a TSV on stdin, append species metadata columns based on a sseqid column.

Usage: _join_species.py <species_metadata.tsv> <sseqid_col_index>

Appended columns: species_code, species_binomial, class, order, family, phylum.
The species_code is recovered by splitting the sseqid on the literal 'EVm'.
The first input row is heuristically treated as a header if >half its cells are
non-numeric; in that case the six metadata column names are appended.
"""
import csv
import sys


def is_numericish(s: str) -> bool:
    t = s
    for ch in (".", "-", "e", "E", "+"):
        t = t.replace(ch, "", 1)
    return t.isdigit()


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    meta_path = sys.argv[1]
    col = int(sys.argv[2])
    meta: dict[str, dict] = {}
    with open(meta_path) as f:
        for r in csv.DictReader(f, delimiter="\t"):
            meta[r["species_code"]] = r
    extra_cols = ["species_code", "species_binomial", "class", "order", "family", "phylum"]

    first = True
    for raw in sys.stdin:
        line = raw.rstrip("\n")
        if not line or line.startswith("#"):
            sys.stdout.write(raw)
            continue
        parts = line.split("\t")
        if first:
            first = False
            non_numeric = sum(1 for p in parts if not is_numericish(p))
            if non_numeric > len(parts) // 2:
                print("\t".join(parts + extra_cols))
                continue
        if col >= len(parts):
            print("\t".join(parts + [""] * len(extra_cols)))
            continue
        sseqid = parts[col]
        code = sseqid.split("EVm", 1)[0] if "EVm" in sseqid else ""
        m = meta.get(code, {})
        add = [code, m.get("species_binomial", ""), m.get("class", ""),
               m.get("order", ""), m.get("family", ""), m.get("phylum", "")]
        print("\t".join(parts + add))
    return 0


if __name__ == "__main__":
    sys.exit(main())
