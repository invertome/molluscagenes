#!/usr/bin/env bash
# package_blast.sh — tar+gzip the BLAST db volumes into single archives ready for Zenodo.
#
# Usage:
#   package_blast.sh <staging_dir>
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${here}/.." && pwd)"
# shellcheck source=../wrappers/_common.sh
source "${repo_root}/wrappers/_common.sh"

[[ "${1:-}" == "-h" || "${1:-}" == "--help" || -z "${1:-}" ]] && {
    sed -n '2,7p' "$0"; exit 0
}

staging="$1"
mkdir -p "$staging"
mg_load_config

pack_one() {
    local stem="$1"   # e.g. mollusca_aa
    local out="${staging}/${stem}.blast.tar.gz"
    if [[ -f "$out" ]]; then
        echo "  exists: $out (skipping)" >&2; return 0
    fi
    local src_dir; src_dir="$(dirname "$(eval echo "\$MG_BLAST_${stem##*_}")")"
    local prefix="${stem}"
    [[ "$stem" == "mollusca_aa" ]] && src_dir="$(dirname "$MG_BLAST_AA")"
    [[ "$stem" == "mollusca_mrna" ]] && src_dir="$(dirname "$MG_BLAST_MRNA")"
    echo "  packing $stem from $src_dir/${prefix}.* -> $out" >&2
    tar czf "$out" -C "$src_dir" $(cd "$src_dir" && ls "${prefix}".* | sort)
    echo "  wrote $(stat -c '%s' "$out") bytes" >&2
}

pack_one mollusca_aa
pack_one mollusca_mrna

echo "package_blast: done." >&2
