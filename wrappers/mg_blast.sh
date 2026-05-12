#!/usr/bin/env bash
# mg_blast.sh — BLAST a query against mollusca_aa (blastp) or mollusca_mrna (blastn)
# and join hits to species_metadata.tsv for immediate species context.
#
# Usage:
#   mg_blast.sh -q <query.fa> -o <outdir> -d aa|mrna [-e 1e-5] [-t 10] [--outfmt '...'] [--force]
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${here}/_common.sh"
# shellcheck source=_taxon_filter.sh
source "${here}/_taxon_filter.sh"

usage() {
    cat >&2 <<EOF
Usage: $(basename "$0") -q <query.fa> -o <outdir> -d aa|mrna [options]

Required:
  -q PATH         query FASTA
  -o DIR          output directory (created if missing)
  -d aa|mrna      target db: aa = proteins (blastp), mrna = nucleotides (blastn)

Options:
  -e FLOAT        e-value threshold (-evalue) [1e-5]
  -t N            threads (-num_threads) [\$MG_THREADS, default 10]
  --max-hits N    -max_target_seqs [1000]
  --outfmt STR    BLAST -outfmt string (default: 15-col extended set)
  --task NAME     -task (blastp | blastp-fast | blastp-short for protein;
                  blastn | blastn-short | dc-megablast | megablast for nucleotide)
  --word-size N   -word_size  (auto-set by BLAST if omitted)
  --matrix NAME   -matrix (BLOSUM62 etc.; protein only)
  --culling N     -culling_limit
  --taxon-filter T   restrict the target DB to species in taxon T (class, order,
                     family, binomial, species code, or comma-list union). First
                     call builds a subset DB under metadata/_cache/subset_dbs/;
                     subsequent calls reuse it. Examples:
                       --taxon-filter Gastropoda
                       --taxon-filter "Octopus bimaculoides"
                       --taxon-filter Cephalopoda,Bivalvia
                       --taxon-filter class:Gastropoda   (escape hatch for ambiguity)
                     (Subset DB is reused as long as source DB hash matches;
                     --force re-runs the search, not the subset rebuild.)
  --extra "ARGS"  appended verbatim to the blastp/blastn command. Use this to
                  pass any flag we don't expose by name (-gapopen, -seg,
                  -comp_based_stats, -soft_masking, -best_hit_overhang, …).
                  Example: --extra "-gapopen 11 -gapextend 1 -seg yes"
  --force         re-run even if .done sentinel present
  -h | --help     this help
EOF
}

query=""
outdir=""
dbtype=""
evalue="1e-5"
threads=""
max_hits="1000"
outfmt_default='6 qseqid sseqid evalue bitscore pident nident qlen slen qstart qend sstart send length mismatch gapopen'
outfmt="$outfmt_default"
task=""
word_size=""
matrix=""
culling=""
extra=""
taxon_filter=""
taxon_filter_set="no"
force="no"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -q) query="$2"; shift 2 ;;
        -o) outdir="$2"; shift 2 ;;
        -d) dbtype="$2"; shift 2 ;;
        -e) evalue="$2"; shift 2 ;;
        -t) threads="$2"; shift 2 ;;
        --max-hits) max_hits="$2"; shift 2 ;;
        --outfmt) outfmt="$2"; shift 2 ;;
        --task) task="$2"; shift 2 ;;
        --word-size) word_size="$2"; shift 2 ;;
        --matrix) matrix="$2"; shift 2 ;;
        --culling) culling="$2"; shift 2 ;;
        --taxon-filter) taxon_filter="${2:-}"; taxon_filter_set="yes"; shift 2 ;;
        --extra) extra="$2"; shift 2 ;;
        --force) force="yes"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
    esac
done

[[ -z "$query"  ]] && { usage; mg_die "missing -q"; }
[[ -z "$outdir" ]] && { usage; mg_die "missing -o"; }
[[ -z "$dbtype" ]] && { usage; mg_die "missing -d aa|mrna"; }
# Empty --taxon-filter is almost certainly a user error (e.g. shell-quoted "").
# Check this with the other flag-presence validations, BEFORE we touch the
# filesystem (otherwise an absent query file would mask this error).
if [[ "$taxon_filter_set" == "yes" && -z "$taxon_filter" ]]; then
    mg_die "--taxon-filter passed but value is empty"
fi
[[ -f "$query"  ]] || mg_die "query not found: $query"
[[ "$dbtype" == "aa" || "$dbtype" == "mrna" ]] || mg_die "-d must be aa or mrna (got: $dbtype)"

mg_load_config
threads="${threads:-${MG_THREADS:-10}}"

case "$dbtype" in
    aa)   db="$MG_BLAST_AA";   cmd="blastp" ;;
    mrna) db="$MG_BLAST_MRNA"; cmd="blastn" ;;
esac

mg_require "$cmd"

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
    mg_log "$log" "taxon-filter: resolving '$taxon_filter' (kind=$dbtype) — building subset DB if not cached..."
    resolve_taxon_filter "$taxon_filter"
    taxon_cache_key
    ensure_subset_db blast "$dbtype"
    db="$SUBSET_DB_PATH"
    mg_log "$log" "taxon-filter: ${#TAXON_SPECIES_CODES[@]} species resolved; using subset db at $db (key=$TAXON_KEY)"
else
    [[ -f "${db}.pal" || -f "${db}.phr" || -f "${db}.00.phr" || -f "${db}.nal" || -f "${db}.nhr" || -f "${db}.00.nhr" ]] \
        || mg_die "BLAST db not found at ${db} (check \$MG_BLAST_${dbtype^^} in config.sh)"
fi

mg_log "$log" "mg_blast.sh: $cmd vs $db"
mg_log "$log" "command: $0 $*"
mg_log "$log" "query: $query"
mg_log "$log" "evalue: $evalue  threads: $threads  max_hits: $max_hits"
mg_log_versions "$log" "$cmd"

extra_args=()
[[ -n "$task"      ]] && extra_args+=( -task "$task" )
[[ -n "$word_size" ]] && extra_args+=( -word_size "$word_size" )
[[ -n "$matrix"    ]] && extra_args+=( -matrix "$matrix" )
[[ -n "$culling"   ]] && extra_args+=( -culling_limit "$culling" )
if [[ -n "$extra" ]]; then
    # shellcheck disable=SC2206
    eval "extra_passthrough=( $extra )"
    extra_args+=( "${extra_passthrough[@]}" )
fi

mg_log "$log" "running $cmd ${extra_args[*]:-}..."
"$cmd" \
    -query "$query" \
    -db "$db" \
    -num_threads "$threads" \
    -max_target_seqs "$max_hits" \
    -evalue "$evalue" \
    -outfmt "$outfmt" \
    "${extra_args[@]}" \
    -out "$hits_raw"

nhits=$(wc -l < "$hits_raw" | awk '{print $1}')
mg_log "$log" "$nhits hits written to $hits_raw"

mg_log "$log" "joining species metadata..."
# outfmt 6 places sseqid at column index 1 (0-based)
mg_join_species "$MG_METADATA/species_metadata.tsv" 1 < "$hits_raw" > "$hits_joined"

mg_log "$log" "wrote $hits_joined"
mg_mark_done "$outdir"
mg_log "$log" "done."
echo "$hits_joined"
