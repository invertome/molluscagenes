#!/usr/bin/env bash
# build_diamond.sh — build mollusca_aa.dmnd by streaming the protein FASTA from
# blastdbcmd directly into `diamond makedb --in -`. No intermediate FASTA on disk.
#
# Usage:
#   build_diamond.sh <staging_dir>
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${here}/.." && pwd)"
# shellcheck source=../wrappers/_common.sh
source "${repo_root}/wrappers/_common.sh"

[[ "${1:-}" == "-h" || "${1:-}" == "--help" || -z "${1:-}" ]] && {
    sed -n '2,9p' "$0"; exit 0
}

staging="$1"
mkdir -p "$staging"
mg_load_config
mg_require blastdbcmd diamond

out="${staging}/mollusca_aa.dmnd"
if [[ -f "$out" ]]; then
    echo "  exists: $out (skipping; remove to rebuild)" >&2; exit 0
fi

threads="${MG_THREADS:-10}"
echo "streaming protein FASTA into diamond makedb (threads=$threads)..." >&2
blastdbcmd -db "$MG_BLAST_AA" -dbtype prot -entry all -outfmt "%f" \
    | diamond makedb --in - --db "${out%.dmnd}" --threads "$threads" --quiet

echo "wrote $out ($(stat -c '%s' "$out") bytes)" >&2
