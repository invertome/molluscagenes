#!/usr/bin/env python3
"""Aggregate characterize/{blast,diamond,hmm} results into a per-query-protein TSV.

Usage: _summarize_characterize.py <characterize_outdir> <species_metadata.tsv>

Output columns (TSV to stdout):
  query                  query sequence id
  blast_n_hits           count of BLAST hits (mollusca_aa)
  blast_best_hit         best hit's sseqid + species_binomial
  blast_best_evalue
  blast_best_pident
  diamond_n_hits         count of DIAMOND hits
  diamond_best_hit
  diamond_best_evalue
  diamond_best_pident
  hmm_top_domain         best HMM (lowest E-value)
  hmm_top_domain_evalue
  hmm_n_domains_signif   count of significant HMM matches (E < threshold; we just count anything in tbl)
  species_top_blast      species_binomial of BLAST best hit
  species_top_diamond    species_binomial of DIAMOND best hit
"""

from __future__ import annotations

import csv
import sys
from pathlib import Path
from collections import defaultdict


def parse_blast_diamond(path: Path):
    """outfmt 6: qseqid sseqid evalue bitscore pident ..."""
    if not path.is_file():
        return {}
    by_q = defaultdict(list)
    with open(path) as f:
        for line in f:
            if not line.strip() or line.startswith("#"):
                continue
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 5:
                continue
            q, s = parts[0], parts[1]
            try:
                ev = float(parts[2])
                pid = float(parts[4])
            except (ValueError, IndexError):
                continue
            by_q[q].append((ev, pid, s))
    return by_q


def parse_hmm_tbl(path: Path):
    """hmmsearch --tblout: target_name acc query_name acc full_E full_score full_bias dom_E ..."""
    if not path.is_file():
        return {}
    # We're looking up *per-target* (the query protein). Each tbl line is a (HMM, sequence) match.
    # When we run hmmsearch with HMM file as profile and query.fa as target, target_name is
    # the query sequence id and query_name is the HMM id.
    by_q = defaultdict(list)
    with open(path) as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            parts = line.split()
            if len(parts) < 5:
                continue
            target = parts[0]   # query sequence id
            hmm_q = parts[2]    # HMM model id (Pfam name + _REV)
            try:
                e_full = float(parts[4])
            except ValueError:
                continue
            by_q[target].append((e_full, hmm_q))
    return by_q


def species_lookup(meta_path: Path):
    m = {}
    with open(meta_path) as f:
        for r in csv.DictReader(f, delimiter="\t"):
            m[r["species_code"]] = r["species_binomial"]
    return m


def species_from_sseqid(s: str, meta: dict) -> str:
    code = s.split("EVm", 1)[0] if "EVm" in s else ""
    return meta.get(code, "")


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    meta_path = Path(sys.argv[2])
    meta = species_lookup(meta_path)

    blast = parse_blast_diamond(outdir / "blast" / "hits.tsv")
    diamond = parse_blast_diamond(outdir / "diamond" / "hits.tsv")
    hmm = parse_hmm_tbl(outdir / "hmm" / "hits.tbl")

    queries = set(blast) | set(diamond) | set(hmm)

    cols = [
        "query",
        "blast_n_hits", "blast_best_hit", "blast_best_evalue", "blast_best_pident",
        "diamond_n_hits", "diamond_best_hit", "diamond_best_evalue", "diamond_best_pident",
        "hmm_top_domain", "hmm_top_domain_evalue", "hmm_n_domains_signif",
        "species_top_blast", "species_top_diamond",
    ]
    print("\t".join(cols))

    for q in sorted(queries):
        row = {c: "" for c in cols}
        row["query"] = q

        bh = blast.get(q, [])
        if bh:
            bh_sorted = sorted(bh, key=lambda x: x[0])
            best = bh_sorted[0]
            row["blast_n_hits"] = str(len(bh))
            row["blast_best_hit"] = best[2]
            row["blast_best_evalue"] = f"{best[0]:.2e}"
            row["blast_best_pident"] = f"{best[1]:.1f}"
            row["species_top_blast"] = species_from_sseqid(best[2], meta)

        dh = diamond.get(q, [])
        if dh:
            dh_sorted = sorted(dh, key=lambda x: x[0])
            best = dh_sorted[0]
            row["diamond_n_hits"] = str(len(dh))
            row["diamond_best_hit"] = best[2]
            row["diamond_best_evalue"] = f"{best[0]:.2e}"
            row["diamond_best_pident"] = f"{best[1]:.1f}"
            row["species_top_diamond"] = species_from_sseqid(best[2], meta)

        hh = hmm.get(q, [])
        if hh:
            hh_sorted = sorted(hh, key=lambda x: x[0])
            row["hmm_top_domain"] = hh_sorted[0][1]
            row["hmm_top_domain_evalue"] = f"{hh_sorted[0][0]:.2e}"
            row["hmm_n_domains_signif"] = str(len(hh))

        print("\t".join(row[c] for c in cols))

    return 0


if __name__ == "__main__":
    sys.exit(main())
