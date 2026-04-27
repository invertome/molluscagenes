#!/usr/bin/env bash
# generate_checksums.sh — compute SHA256 + size for every artifact in <staging_dir>,
# write MANIFEST.tsv (consumed by mg_fetch + verify_download). Mirrors the file to
# <repo>/metadata/zenodo_manifest.tsv so verify_download.sh works without Zenodo access.
#
# Usage:
#   generate_checksums.sh <staging_dir> [description-overrides.tsv]
#
# The optional 2nd argument is a 2-column TSV (filename, description) used to
# fill the description column in the manifest.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${here}/.." && pwd)"

[[ "${1:-}" == "-h" || "${1:-}" == "--help" || -z "${1:-}" ]] && {
    sed -n '2,11p' "$0"; exit 0
}

staging="$1"
descs_tsv="${2:-}"
[[ -d "$staging" ]] || { echo "not a directory: $staging" >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum required" >&2; exit 1; }

# Built-in default descriptions
default_desc() {
    case "$1" in
        mollusca_aa.fa.gz)              echo "Raw protein FASTA (gzipped) for ~333 mollusc species" ;;
        mollusca_mrna.fa.gz)            echo "Raw mRNA/transcript FASTA (gzipped) for ~333 mollusc species" ;;
        mollusca_aa.blast.tar.gz)       echo "BLAST protein database (all volumes + metadata)" ;;
        mollusca_mrna.blast.tar.gz)     echo "BLAST nucleotide database (all volumes + metadata)" ;;
        mollusca_aa.dmnd)               echo "DIAMOND protein database" ;;
        tiammat_mollusca_hmms.tar.gz)   echo "TIAMMAt mollusc-revised Pfam HMMs (combined + per-domain + indices)" ;;
        species_metadata.tsv)           echo "Per-species metadata (taxonomy, sequence counts, NCBI/WoRMS IDs)" ;;
        dict2.tsv)                      echo "Species code -> binomial dictionary" ;;
        MANIFEST.tsv)                   echo "This file: filename / size / sha256 / description for every artifact" ;;
        README.txt)                     echo "Top-level README for the deposit" ;;
        LICENSE)                        echo "GPL-3.0-or-later (code) + CC-BY-4.0 (data)" ;;
        *)                              echo "" ;;
    esac
}

# Optional override map
declare -A override
if [[ -n "$descs_tsv" && -f "$descs_tsv" ]]; then
    while IFS=$'\t' read -r fn desc; do
        override["$fn"]="$desc"
    done < "$descs_tsv"
fi

manifest_repo="${repo_root}/metadata/zenodo_manifest.tsv"
manifest_stage="${staging}/MANIFEST.tsv"

{
    printf 'filename\tsize_bytes\tsha256\tdescription\n'
    while IFS= read -r path; do
        fn=$(basename "$path")
        [[ "$fn" == "MANIFEST.tsv" ]] && continue
        size=$(stat -c '%s' "$path")
        sha=$(sha256sum "$path" | awk '{print $1}')
        desc="${override[$fn]:-$(default_desc "$fn")}"
        printf '%s\t%s\t%s\t%s\n' "$fn" "$size" "$sha" "$desc"
    done < <(find "$staging" -maxdepth 1 -type f ! -name 'MANIFEST.tsv' | sort)
} > "$manifest_stage"

cp "$manifest_stage" "$manifest_repo"

echo "wrote:" >&2
echo "  $manifest_stage" >&2
echo "  $manifest_repo (mirror, committed)" >&2
n=$(($(wc -l < "$manifest_stage") - 1))
echo "$n artifacts manifested." >&2
