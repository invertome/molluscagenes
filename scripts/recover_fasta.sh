#!/usr/bin/env bash
# recover_fasta.sh — stream raw FASTA out of the BLAST databases into gzipped files.
# Pipes blastdbcmd into pigz directly so no uncompressed FASTA hits disk.
#
# Usage:
#   recover_fasta.sh <staging_dir>
#
# Outputs:
#   <staging_dir>/mollusca_aa.fa.gz
#   <staging_dir>/mollusca_mrna.fa.gz
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${here}/.." && pwd)"
# shellcheck source=../wrappers/_common.sh
source "${repo_root}/wrappers/_common.sh"

[[ "${1:-}" == "-h" || "${1:-}" == "--help" || -z "${1:-}" ]] && {
    sed -n '2,12p' "$0"; exit 0
}

staging="$1"
mkdir -p "$staging"
mg_load_config
mg_require blastdbcmd pigz

stream_one() {
    local db="$1"
    local dbtype="$2"
    local out="$3"
    if [[ -f "$out" ]]; then
        echo "  exists: $out (skipping; remove to rebuild)" >&2; return 0
    fi
    echo "  streaming $db ($dbtype) -> $out ..." >&2
    blastdbcmd -db "$db" -dbtype "$dbtype" -entry all -outfmt "%f" \
        | pigz -9 > "$out"
    echo "  wrote $(stat -c '%s' "$out") bytes" >&2
}

stream_one "$MG_BLAST_AA"   prot "${staging}/mollusca_aa.fa.gz"
stream_one "$MG_BLAST_MRNA" nucl "${staging}/mollusca_mrna.fa.gz"

echo "recover_fasta: done." >&2
