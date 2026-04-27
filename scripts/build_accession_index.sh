#!/usr/bin/env bash
# Build a per-species accession cache from the BLAST databases. Run once; refresh
# when the underlying BLAST db changes (a fingerprint file guards re-runs).
#
# Output layout (under <repo>/metadata/_cache/):
#   aa/<species_code>.txt      one accession per line, for each species present in aa db
#   mrna/<species_code>.txt    same for mrna db
#   fingerprint.tsv            mtime + size of each BLAST db vol; re-run rebuilds if changed
#
# Usage:
#   scripts/build_accession_index.sh              # source config.sh, build both
#   scripts/build_accession_index.sh --force      # rebuild even if fingerprint matches
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${here}/.." && pwd)"
# shellcheck source=../wrappers/_common.sh
source "${repo_root}/wrappers/_common.sh"

force="no"
case "${1:-}" in
    --force) force="yes" ;;
    -h|--help)
        sed -n '2,12p' "$0"; exit 0 ;;
esac

mg_load_config
mg_require blastdbcmd awk

cache="${MG_METADATA:-${repo_root}/metadata}/_cache"
mkdir -p "${cache}/aa" "${cache}/mrna"
fp="${cache}/fingerprint.tsv"

# Fingerprint based on the BLAST db alias files + largest volume's .psq/.nsq mtime/size.
compute_fp() {
    for db in "$MG_BLAST_AA" "$MG_BLAST_MRNA"; do
        for ext in .pal .nal .00.psq .00.nsq .01.psq .01.nsq; do
            [[ -f "${db}${ext}" ]] && stat -c '%n %Y %s' "${db}${ext}"
        done
    done
}

new_fp="$(compute_fp)"
if [[ "$force" != "yes" && -f "$fp" ]]; then
    old_fp="$(cat "$fp")"
    if [[ "$old_fp" == "$new_fp" ]]; then
        echo "accession index up-to-date (fingerprint match). Use --force to rebuild." >&2
        exit 0
    fi
fi

# Clean previous per-species files
rm -f "${cache}/aa/"*.txt "${cache}/mrna/"*.txt 2>/dev/null || true

build_one() {
    local db="$1"
    local dbtype="$2"
    local outdir="$3"
    echo "splitting ${db} (${dbtype}) -> ${outdir}/" >&2
    blastdbcmd -db "$db" -dbtype "$dbtype" -entry all -outfmt "%a" \
        | awk -v dir="$outdir" '
            { split($0, a, "EVm"); code = a[1]; if (code == "") next;
              print $0 > (dir "/" code ".txt") }'
    local n
    n=$(ls "$outdir"/*.txt 2>/dev/null | wc -l)
    echo "  wrote $n per-species files under $outdir" >&2
}

build_one "$MG_BLAST_AA"   prot "${cache}/aa"
build_one "$MG_BLAST_MRNA" nucl "${cache}/mrna"

echo "$new_fp" > "$fp"
echo "done. fingerprint saved to $fp" >&2
