#!/usr/bin/env bash
# mg_characterize.sh — run BLAST + DIAMOND + hmmsearch on a query in parallel,
# aggregate into a single summary report (HTML + TSV).
#
# Usage:
#   mg_characterize.sh -q <query.fa> -o <outdir> [-t 10] [-e 1e-5] [--skip blast|diamond|hmm] [--force]
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${here}/_common.sh"

usage() {
    cat >&2 <<EOF
Usage: $(basename "$0") -q <query.fa> -o <outdir> [options]

Required:
  -q PATH         protein query FASTA
  -o DIR          output directory

Options:
  -t N               threads [\$MG_THREADS, default 10]
  -e FLOAT           e-value threshold for BLAST/DIAMOND [1e-5]
  --hmm-E FLOAT      e-value threshold for hmmsearch [1e-5]
  --skip MODE        skip a search: blast | diamond | hmm  (repeatable)
  --max-hits N       -max_target_seqs / --max-target-seqs [500]
  --taxon-filter T   restrict the BLAST and DIAMOND target databases to species
                     in taxon T (class, order, family, binomial, code, or
                     comma-list union). Does NOT affect the hmmsearch step,
                     which always scans the user query to identify families.
                     Examples:
                       --taxon-filter Cephalopoda
                       --taxon-filter "Octopus bimaculoides"
                       --taxon-filter Gastropoda,Bivalvia
  --force            re-run even if .done sentinels are present
  -h | --help        this help

Outputs:
  <outdir>/blast/      mg_blast results (vs mollusca_aa)
  <outdir>/diamond/    mg_diamond results
  <outdir>/hmm/        mg_hmmsearch results
  <outdir>/summary.tsv per-query-protein consolidated table
  <outdir>/report.html simple HTML rollup
  <outdir>/run.log     provenance
EOF
}

query=""
outdir=""
threads=""
evalue="1e-5"
hmm_e="1e-5"
max_hits="500"
force="no"
skip_blast="no"
skip_diamond="no"
skip_hmm="no"
taxon_filter=""
taxon_filter_set="no"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -q) query="$2"; shift 2 ;;
        -o) outdir="$2"; shift 2 ;;
        -t) threads="$2"; shift 2 ;;
        -e) evalue="$2"; shift 2 ;;
        --hmm-E) hmm_e="$2"; shift 2 ;;
        --skip) case "$2" in
                    blast) skip_blast="yes" ;;
                    diamond) skip_diamond="yes" ;;
                    hmm) skip_hmm="yes" ;;
                    *) mg_die "--skip must be blast|diamond|hmm" ;;
                esac; shift 2 ;;
        --max-hits) max_hits="$2"; shift 2 ;;
        --taxon-filter) taxon_filter="${2:-}"; taxon_filter_set="yes"; shift 2 ;;
        --force) force="yes"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
    esac
done

[[ -z "$query"  ]] && { usage; mg_die "missing -q"; }
[[ -z "$outdir" ]] && { usage; mg_die "missing -o"; }
# Empty --taxon-filter is almost certainly a user error (e.g. shell-quoted "").
# Check this with the other flag-presence validations, BEFORE we touch the
# filesystem (otherwise an absent query file would mask this error). Matches
# the ordering in mg_blast.sh / mg_diamond.sh.
if [[ "$taxon_filter_set" == "yes" && -z "$taxon_filter" ]]; then
    mg_die "--taxon-filter passed but value is empty"
fi
[[ -f "$query"  ]] || mg_die "query not found: $query"

mg_load_config
threads="${threads:-${MG_THREADS:-10}}"

mkdir -p "$outdir"
log="${outdir}/run.log"
: > "$log"
mg_log "$log" "mg_characterize.sh: query=$query"
mg_log "$log" "command: $0 $*"
mg_log "$log" "skip: blast=$skip_blast diamond=$skip_diamond hmm=$skip_hmm"
mg_log "$log" "taxon-filter: ${taxon_filter:-<none>} (applied to blast/diamond only; hmm is unaffected)"

force_flag=""; [[ "$force" == "yes" ]] && force_flag="--force"

# Build the taxon-filter forwarding arg (empty array if flag not set).
# Forwarded to mg_blast and mg_diamond only — NOT to mg_hmmsearch, because the
# hmm step here scans the user's query FASTA to identify families (a different
# question from the BLAST/DIAMOND "restrict the target DB" question).
taxon_args=()
[[ "$taxon_filter_set" == "yes" ]] && taxon_args=( --taxon-filter "$taxon_filter" )

# Launch the three searches in parallel (those not skipped). All write to subdirs.
pids=()
[[ "$skip_blast"   == "no" ]] && {
    "${here}/mg_blast.sh"     -q "$query" -o "${outdir}/blast"   -d aa -e "$evalue" -t "$threads" --max-hits "$max_hits" "${taxon_args[@]}" $force_flag >> "$log" 2>&1 &
    pids+=($!)
}
[[ "$skip_diamond" == "no" ]] && {
    "${here}/mg_diamond.sh"   -q "$query" -o "${outdir}/diamond"      -e "$evalue" -t "$threads" --max-hits "$max_hits" "${taxon_args[@]}" $force_flag >> "$log" 2>&1 &
    pids+=($!)
}
# Deliberately NOT forwarding --taxon-filter here: characterize's hmm step
# scans the user query to identify which HMM families match it, not a database
# that needs taxon restriction.
[[ "$skip_hmm"     == "no" ]] && {
    "${here}/mg_hmmsearch.sh" -q "$query" -o "${outdir}/hmm"      -E "$hmm_e" -t "$threads" $force_flag >> "$log" 2>&1 &
    pids+=($!)
}

# Wait for all and capture failures (don't exit on first failure — let the others finish)
fail="no"
for p in "${pids[@]}"; do
    if ! wait "$p"; then
        fail="yes"
        mg_log "$log" "WARN: subprocess pid=$p exited non-zero"
    fi
done
[[ "$fail" == "yes" ]] && mg_log "$log" "(some search wrappers failed; report will reflect what's available)"

# Aggregate
repo_root="$(cd "${here}/.." && pwd)"
python3 "${repo_root}/scripts/_summarize_characterize.py" "$outdir" "$MG_METADATA/species_metadata.tsv" \
    > "${outdir}/summary.tsv"
mg_log "$log" "wrote summary.tsv"

python3 "${repo_root}/scripts/_render_characterize_html.py" "$outdir" \
    > "${outdir}/report.html"
mg_log "$log" "wrote report.html"

mg_log "$log" "done."
echo "${outdir}/report.html"
