#!/usr/bin/env bash
# mg_diamond.sh — DIAMOND blastp against mollusca_aa.dmnd with species metadata join.
#
# DIAMOND is protein-only: this is always blastp (protein query -> protein db).
# For translated-nucleotide searches use `--blastx` (query is nucleotide FASTA).
#
# Usage:
#   mg_diamond.sh -q <query.fa> -o <outdir> [-e 1e-5] [-t 10] [--sensitivity more-sensitive] [--blastx] [--force]
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${here}/_common.sh"

usage() {
    cat >&2 <<EOF
Usage: $(basename "$0") -q <query.fa> -o <outdir> [options]

Required:
  -q PATH                   query FASTA
  -o DIR                    output directory

Options:
  -e FLOAT                  e-value [1e-5]
  -t N                      threads [\$MG_THREADS, default 10]
  --max-hits N              --max-target-seqs [1000]
  --sensitivity MODE        fast | mid-sensitive | sensitive | more-sensitive | very-sensitive | ultra-sensitive [more-sensitive]
  --blastx                  run blastx (nucleotide query) instead of blastp
  --outfmt STR              diamond outfmt 6 column string (default matches mg_blast)
  --force                   re-run even if .done sentinel present
  -h | --help               this help
EOF
}

query=""
outdir=""
evalue="1e-5"
threads=""
max_hits="1000"
sens="more-sensitive"
mode="blastp"
outfmt_default='6 qseqid sseqid evalue bitscore pident nident qlen slen qstart qend sstart send length mismatch gapopen'
outfmt="$outfmt_default"
force="no"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -q) query="$2"; shift 2 ;;
        -o) outdir="$2"; shift 2 ;;
        -e) evalue="$2"; shift 2 ;;
        -t) threads="$2"; shift 2 ;;
        --max-hits) max_hits="$2"; shift 2 ;;
        --sensitivity) sens="$2"; shift 2 ;;
        --blastx) mode="blastx"; shift ;;
        --outfmt) outfmt="$2"; shift 2 ;;
        --force) force="yes"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
    esac
done

[[ -z "$query"  ]] && { usage; mg_die "missing -q"; }
[[ -z "$outdir" ]] && { usage; mg_die "missing -o"; }
[[ -f "$query"  ]] || mg_die "query not found: $query"

case "$sens" in
    fast|mid-sensitive|sensitive|more-sensitive|very-sensitive|ultra-sensitive) ;;
    *) mg_die "invalid --sensitivity: $sens" ;;
esac

mg_load_config
threads="${threads:-${MG_THREADS:-10}}"
[[ -f "$MG_DIAMOND_AA" ]] || mg_die "DIAMOND db not found: $MG_DIAMOND_AA (check \$MG_DIAMOND_AA in config.sh)"
mg_require "diamond"

mkdir -p "$outdir"
log="${outdir}/run.log"
hits_raw="${outdir}/hits.tsv"
hits_joined="${outdir}/hits_with_species.tsv"

if mg_is_done "$outdir" && [[ "$force" != "yes" ]]; then
    echo "already done (sentinel present). Use --force to re-run." >&2
    exit 0
fi

: > "$log"
mg_log "$log" "mg_diamond.sh: diamond $mode vs $MG_DIAMOND_AA"
mg_log "$log" "command: $0 $*"
mg_log "$log" "query: $query  sensitivity: $sens  evalue: $evalue  threads: $threads"
mg_log_versions "$log" "diamond"

# Split outfmt string into words for diamond's --outfmt which takes space-separated args
# (diamond accepts '6 qseqid sseqid ...' as the -f flag)
read -r -a outfmt_arr <<< "$outfmt"

mg_log "$log" "running diamond $mode --$sens..."
diamond "$mode" \
    --query "$query" \
    --db "$MG_DIAMOND_AA" \
    --threads "$threads" \
    --max-target-seqs "$max_hits" \
    --evalue "$evalue" \
    --"$sens" \
    --outfmt "${outfmt_arr[@]}" \
    --out "$hits_raw" \
    --quiet 2>> "$log"

nhits=$(wc -l < "$hits_raw" | awk '{print $1}')
mg_log "$log" "$nhits hits written to $hits_raw"

mg_log "$log" "joining species metadata..."
mg_join_species "$MG_METADATA/species_metadata.tsv" 1 < "$hits_raw" > "$hits_joined"

mg_log "$log" "wrote $hits_joined"
mg_mark_done "$outdir"
mg_log "$log" "done."
echo "$hits_joined"
