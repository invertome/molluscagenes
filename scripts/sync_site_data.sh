#!/usr/bin/env bash
# sync_site_data.sh — copy the metadata files the site fetches into docs/data/.
# GitHub Pages serves from main:/docs, so anything outside docs/ is unreachable
# at runtime. Run this whenever metadata changes; commit docs/data/ alongside.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${here}/.." && pwd)"

src="${repo_root}/metadata"
dst="${repo_root}/docs/data"
mkdir -p "$dst"

cp "${src}/hmm_metadata.json"     "${dst}/hmm_metadata.json"
cp "${src}/species_metadata.tsv"  "${dst}/species_metadata.tsv"

echo "synced:" >&2
echo "  ${src}/hmm_metadata.json -> ${dst}/" >&2
echo "  ${src}/species_metadata.tsv -> ${dst}/" >&2
