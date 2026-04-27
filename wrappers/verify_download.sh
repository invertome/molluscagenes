#!/usr/bin/env bash
# verify_download.sh — checksum-verify downloaded MolluscaGenes artifacts against
# the manifest shipped with the repo (metadata/zenodo_manifest.tsv).
#
# Usage:
#   verify_download.sh <storage_dir>
#
# Manifest format (tab-separated, with header):
#   filename        size_bytes      sha256          description
#
# Files in <storage_dir> are checked one by one. Reports every mismatch and
# returns non-zero if any check fails.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${here}/.." && pwd)"

usage() {
    cat >&2 <<EOF
Usage: $(basename "$0") <storage_dir>

Verifies SHA256 + size of every file in <storage_dir> against the manifest at
${repo_root#${PWD}/}/metadata/zenodo_manifest.tsv.

Exit 0 on success, non-zero on any mismatch or missing file.
EOF
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" || -z "${1:-}" ]] && { usage; exit 0; }
storage="$1"
[[ -d "$storage" ]] || { echo "error: not a directory: $storage" >&2; exit 1; }

manifest="${repo_root}/metadata/zenodo_manifest.tsv"
[[ -f "$manifest" ]] || { echo "error: manifest not found: $manifest" >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "error: sha256sum required but not found" >&2; exit 1; }

fail=0
ok=0
missing=0
echo "verifying against $manifest" >&2

while IFS=$'\t' read -r fname expected_size expected_sha desc; do
    [[ "$fname" == "filename" ]] && continue   # skip header
    [[ -z "$fname" ]] && continue
    path="${storage}/${fname}"
    if [[ ! -f "$path" ]]; then
        printf '  MISS  %s\n' "$fname" >&2
        missing=$((missing + 1)); continue
    fi
    actual_size=$(stat -c '%s' "$path")
    if [[ "$actual_size" != "$expected_size" ]]; then
        printf '  SIZE  %s  (expected=%s, got=%s)\n' "$fname" "$expected_size" "$actual_size" >&2
        fail=$((fail + 1)); continue
    fi
    actual_sha=$(sha256sum "$path" | awk '{print $1}')
    if [[ "$actual_sha" != "$expected_sha" ]]; then
        printf '  SHA   %s  (expected=%s, got=%s)\n' "$fname" "$expected_sha" "$actual_sha" >&2
        fail=$((fail + 1)); continue
    fi
    printf '  OK    %s\n' "$fname"
    ok=$((ok + 1))
done < "$manifest"

echo
printf 'verify_download: ok=%d  failed=%d  missing=%d\n' "$ok" "$fail" "$missing" >&2
[[ "$fail" -eq 0 && "$missing" -eq 0 ]]
