#!/usr/bin/env bash
# package_hmms.sh — package the TIAMMAt mollusc-revised HMMs (combined HMM + indices
# + per-domain HMMs + domain_list.tsv) into a single tarball ready for Zenodo.
#
# Usage:
#   package_hmms.sh <staging_dir>
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

hmm_dir="${repo_root}/hmm"
[[ -f "${hmm_dir}/mollusca_revised_hmms.hmm" ]] || mg_die "expected ${hmm_dir}/mollusca_revised_hmms.hmm"

# Ensure hmmpress indices exist
if [[ ! -f "${hmm_dir}/mollusca_revised_hmms.hmm.h3p" ]]; then
    mg_require hmmpress
    echo "  running hmmpress..." >&2
    hmmpress "${hmm_dir}/mollusca_revised_hmms.hmm"
fi

out="${staging}/tiammat_mollusca_hmms.tar.gz"
if [[ -f "$out" ]]; then
    echo "  exists: $out (skipping)" >&2; exit 0
fi

echo "  packaging HMMs -> $out" >&2
tar czf "$out" -C "${repo_root}" \
    hmm/mollusca_revised_hmms.hmm \
    hmm/mollusca_revised_hmms.hmm.h3f \
    hmm/mollusca_revised_hmms.hmm.h3i \
    hmm/mollusca_revised_hmms.hmm.h3m \
    hmm/mollusca_revised_hmms.hmm.h3p \
    hmm/per_domain \
    hmm/domain_list.tsv

echo "  wrote $(stat -c '%s' "$out") bytes" >&2
echo "package_hmms: done." >&2
