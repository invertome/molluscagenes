#!/usr/bin/env bash
# mg_hmmsearch.sh — hmmsearch of a protein query against the TIAMMAt mollusc-revised HMMs
# (or a user-supplied HMM file), with species-metadata join on per-hit sequences.
#
# Usage:
#   mg_hmmsearch.sh -q <target_seqdb_or_query.fa> -o <outdir> [-t 10] [--hmm <path>] [--evalue 1e-5] [--force]
#
# Convention: hmmsearch runs HMM -> sequences. If you pass a FASTA query, we search
# the HMMs against those sequences. If you want to search your sequences against the
# full MolluscaGenes proteome, use mg_blast/mg_diamond instead (hmmsearch against
# mollusca_aa.fa.gz is also supported via --target-db).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${here}/_common.sh"

usage() {
    cat >&2 <<EOF
Usage: $(basename "$0") -q <sequences.fa> -o <outdir> [options]

Required:
  -q PATH                 target protein FASTA (the sequences to scan with each HMM)
  -o DIR                  output directory

Options:
  --hmm PATH              HMM file [default: \$MG_HMM, the full TIAMMAt mollusc HMMs]
  -t N                    threads [\$MG_THREADS, default 10]
  -E FLOAT                full-sequence E-value threshold [1e-5]
  --domE FLOAT            per-domain E-value threshold [1e-5]
  --force                 re-run even if .done sentinel present
  -h | --help             this help

Notes:
  Output files:
    hits.tbl              per-sequence tabular output (--tblout)
    hits.domtbl           per-domain tabular output (--domtblout)
    hits_with_species.tsv per-sequence hits joined to species_metadata.tsv
EOF
}

query=""
outdir=""
hmm=""
threads=""
evalue="1e-5"
dome="1e-5"
force="no"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -q) query="$2"; shift 2 ;;
        -o) outdir="$2"; shift 2 ;;
        --hmm) hmm="$2"; shift 2 ;;
        -t) threads="$2"; shift 2 ;;
        -E) evalue="$2"; shift 2 ;;
        --domE) dome="$2"; shift 2 ;;
        --force) force="yes"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
    esac
done

[[ -z "$query"  ]] && { usage; mg_die "missing -q"; }
[[ -z "$outdir" ]] && { usage; mg_die "missing -o"; }
[[ -f "$query"  ]] || mg_die "target FASTA not found: $query"

mg_load_config
threads="${threads:-${MG_THREADS:-10}}"
hmm="${hmm:-$MG_HMM}"
[[ -f "$hmm" ]] || mg_die "HMM file not found: $hmm (check \$MG_HMM in config.sh)"
mg_require "hmmsearch"

mkdir -p "$outdir"
log="${outdir}/run.log"
tbl="${outdir}/hits.tbl"
domtbl="${outdir}/hits.domtbl"
joined="${outdir}/hits_with_species.tsv"

if mg_is_done "$outdir" && [[ "$force" != "yes" ]]; then
    echo "already done (sentinel present). Use --force to re-run." >&2
    exit 0
fi

: > "$log"
mg_log "$log" "mg_hmmsearch.sh: hmmsearch"
mg_log "$log" "command: $0 $*"
mg_log "$log" "hmm: $hmm"
mg_log "$log" "target: $query  E: $evalue  domE: $dome  threads: $threads"
mg_log_versions "$log" "hmmsearch"

mg_log "$log" "running hmmsearch..."
hmmsearch \
    --cpu "$threads" \
    -E "$evalue" --domE "$dome" \
    --tblout "$tbl" \
    --domtblout "$domtbl" \
    "$hmm" "$query" > "${outdir}/hmmsearch.stdout" 2>> "$log"

nhits=$(grep -vc '^#' "$tbl" || true)
mg_log "$log" "$nhits per-sequence hits written to $tbl"

mg_log "$log" "joining species metadata (per-sequence hits)..."
# hmmsearch --tblout format: target_name acc query_name acc E_full score bias ...
# target_name (the matched sequence) is column 0 (0-based) on non-comment lines.
grep -v '^#' "$tbl" | awk 'BEGIN{OFS="\t"} {NF=18; $1=$1; print}' \
    | mg_join_species "$MG_METADATA/species_metadata.tsv" 0 > "$joined"

mg_log "$log" "wrote $joined"
mg_mark_done "$outdir"
mg_log "$log" "done."
echo "$joined"
