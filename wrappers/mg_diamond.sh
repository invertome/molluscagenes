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
# shellcheck source=_taxon_filter.sh
source "${here}/_taxon_filter.sh"

usage() {
    cat >&2 <<EOF
Usage: $(basename "$0") -q <query.fa> -o <outdir> [options]

Required:
  -q PATH                   query FASTA
  -o DIR                    output directory

Options:
  -e FLOAT                  --evalue [1e-5]
  -t N                      --threads [\$MG_THREADS, default 10]
  --max-hits N              --max-target-seqs [1000]
  --sensitivity MODE        fast | mid-sensitive | sensitive | more-sensitive | very-sensitive | ultra-sensitive [more-sensitive]
  --blastx                  run blastx (nucleotide query) instead of blastp
  --outfmt STR              diamond -f / --outfmt 6 column string (default matches mg_blast)
  --query-cover PCT         --query-cover (min % query coverage, 0-100)
  --subject-cover PCT       --subject-cover (min % subject coverage, 0-100)
  --id PCT                  --id (min % identity, 0-100)
  --taxon-filter T          restrict the target DB to species in taxon T (class,
                            order, family, binomial, species code, or comma-list
                            union). First call builds a subset DB under
                            metadata/_cache/subset_dbs/; subsequent calls reuse
                            it. Examples:
                              --taxon-filter Gastropoda
                              --taxon-filter "Octopus bimaculoides"
                              --taxon-filter Cephalopoda,Bivalvia
                              --taxon-filter class:Gastropoda  (escape hatch)
                            (Subset DB is reused as long as source DB hash matches;
                            --force re-runs the search, not the subset rebuild.)
  --extra "ARGS"            appended verbatim to diamond. Use for any flag we
                            don't expose by name (--masking, --comp-based-stats,
                            --frameshift, --no-unlink, …). Example:
                            --extra "--comp-based-stats 1 --masking 0"
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
query_cover=""
subject_cover=""
min_id=""
extra=""
taxon_filter=""
taxon_filter_set="no"
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
        --query-cover) query_cover="$2"; shift 2 ;;
        --subject-cover) subject_cover="$2"; shift 2 ;;
        --id) min_id="$2"; shift 2 ;;
        --taxon-filter) taxon_filter="${2:-}"; taxon_filter_set="yes"; shift 2 ;;
        --extra) extra="$2"; shift 2 ;;
        --force) force="yes"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
    esac
done

[[ -z "$query"  ]] && { usage; mg_die "missing -q"; }
[[ -z "$outdir" ]] && { usage; mg_die "missing -o"; }
# Empty --taxon-filter is almost certainly a user error (e.g. shell-quoted "").
# Check this with the other flag-presence validations, BEFORE we touch the
# filesystem (otherwise an absent query file would mask this error).
if [[ "$taxon_filter_set" == "yes" && -z "$taxon_filter" ]]; then
    mg_die "--taxon-filter passed but value is empty"
fi
[[ -f "$query"  ]] || mg_die "query not found: $query"

case "$sens" in
    fast|mid-sensitive|sensitive|more-sensitive|very-sensitive|ultra-sensitive) ;;
    *) mg_die "invalid --sensitivity: $sens" ;;
esac

mg_load_config
threads="${threads:-${MG_THREADS:-10}}"
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

if [[ -n "$taxon_filter" ]]; then
    mg_log "$log" "taxon-filter: resolving '$taxon_filter' (kind=aa) — building subset DB if not cached..."
    resolve_taxon_filter "$taxon_filter"
    taxon_cache_key
    ensure_subset_db diamond aa
    MG_DIAMOND_AA="$SUBSET_DB_PATH"
    mg_log "$log" "taxon-filter: ${#TAXON_SPECIES_CODES[@]} species resolved; using subset db at $MG_DIAMOND_AA (key=$TAXON_KEY)"
else
    [[ -f "$MG_DIAMOND_AA" ]] || mg_die "DIAMOND db not found: $MG_DIAMOND_AA (check \$MG_DIAMOND_AA in config.sh)"
fi

mg_log "$log" "mg_diamond.sh: diamond $mode vs $MG_DIAMOND_AA"
mg_log "$log" "command: $0 $*"
mg_log "$log" "query: $query  sensitivity: $sens  evalue: $evalue  threads: $threads"
mg_log_versions "$log" "diamond"

# Split outfmt string into words for diamond's --outfmt which takes space-separated args
# (diamond accepts '6 qseqid sseqid ...' as the -f flag)
read -r -a outfmt_arr <<< "$outfmt"

extra_args=()
[[ -n "$query_cover"   ]] && extra_args+=( --query-cover "$query_cover" )
[[ -n "$subject_cover" ]] && extra_args+=( --subject-cover "$subject_cover" )
[[ -n "$min_id"        ]] && extra_args+=( --id "$min_id" )
if [[ -n "$extra" ]]; then
    eval "extra_passthrough=( $extra )"
    extra_args+=( "${extra_passthrough[@]}" )
fi

mg_log "$log" "running diamond $mode --$sens ${extra_args[*]:-}..."
diamond "$mode" \
    --query "$query" \
    --db "$MG_DIAMOND_AA" \
    --threads "$threads" \
    --max-target-seqs "$max_hits" \
    --evalue "$evalue" \
    --"$sens" \
    --outfmt "${outfmt_arr[@]}" \
    "${extra_args[@]}" \
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
