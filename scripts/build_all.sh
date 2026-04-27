#!/usr/bin/env bash
# build_all.sh — orchestrate the full Zenodo artifact build pipeline.
# Streams everything to <staging_dir>; safe under tight disk budgets (~25 GB peak
# beyond the existing BLAST dbs).
#
# Usage:
#   build_all.sh <staging_dir> [--skip-fasta] [--skip-diamond] [--skip-blast-tar] [--skip-hmms]
#
# After this completes, <staging_dir> contains every file Zenodo will receive
# plus MANIFEST.tsv. Hand the directory to your Zenodo upload tool of choice
# (web UI, zenodo_get, or a future mg_publish.sh).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${here}/.." && pwd)"

usage() {
    cat >&2 <<EOF
Usage: $(basename "$0") <staging_dir> [options]

Builds the full set of Zenodo artifacts:
  mollusca_aa.fa.gz              raw protein FASTA
  mollusca_mrna.fa.gz            raw mRNA FASTA
  mollusca_aa.dmnd               DIAMOND protein db
  mollusca_aa.blast.tar.gz       BLAST protein db archive
  mollusca_mrna.blast.tar.gz     BLAST mRNA db archive
  tiammat_mollusca_hmms.tar.gz   HMMs + indices + per_domain
  species_metadata.tsv           mirror from repo
  dict2.tsv                      mirror from repo
  README.txt                     deposit-level README
  LICENSE                        GPL-3.0 + CC-BY-4.0 note
  MANIFEST.tsv                   sha256 + sizes + descriptions

Options:
  --skip-fasta            skip raw FASTA (.fa.gz) generation
  --skip-diamond          skip DIAMOND .dmnd build
  --skip-blast-tar        skip BLAST tarball packaging
  --skip-hmms             skip HMM tarball packaging
  --skip-checksums        skip MANIFEST.tsv generation (do this last manually)
  -h | --help             this help

Disk: peak is roughly the staging size at completion (~13 GB) plus brief temp
during diamond makedb. With original BLAST dbs (~16 GB) on disk, total ~30 GB.
EOF
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" || -z "${1:-}" ]] && { usage; exit 0; }
staging="$1"; shift || true

skip_fasta="no"; skip_diamond="no"; skip_blast_tar="no"; skip_hmms="no"; skip_checksums="no"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-fasta) skip_fasta="yes" ;;
        --skip-diamond) skip_diamond="yes" ;;
        --skip-blast-tar) skip_blast_tar="yes" ;;
        --skip-hmms) skip_hmms="yes" ;;
        --skip-checksums) skip_checksums="yes" ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
    esac
    shift
done

mkdir -p "$staging"
echo "build_all: staging=$staging" >&2
df -h "$staging" | tail -1 >&2

# 1. DIAMOND first (uses streamed input, no FASTA on disk; smallest output among the big artifacts)
[[ "$skip_diamond" == "no" ]] && {
    echo "[1/6] DIAMOND db ..." >&2
    "${here}/build_diamond.sh" "$staging"
}

# 2. Raw FASTAs
[[ "$skip_fasta" == "no" ]] && {
    echo "[2/6] raw FASTAs ..." >&2
    "${here}/recover_fasta.sh" "$staging"
}

# 3. BLAST tarballs
[[ "$skip_blast_tar" == "no" ]] && {
    echo "[3/6] BLAST tarballs ..." >&2
    "${here}/package_blast.sh" "$staging"
}

# 4. HMM tarball
[[ "$skip_hmms" == "no" ]] && {
    echo "[4/6] HMM tarball ..." >&2
    "${here}/package_hmms.sh" "$staging"
}

# 5. Mirror metadata into the staging area
echo "[5/6] mirroring metadata + license ..." >&2
cp "${repo_root}/metadata/species_metadata.tsv" "${staging}/species_metadata.tsv"
cp "${repo_root}/metadata/dict2.tsv"           "${staging}/dict2.tsv"
cp "${repo_root}/LICENSE"                      "${staging}/LICENSE"

cat > "${staging}/README.txt" <<'EOF'
MolluscaGenes v0.1 - preliminary release
========================================

Preliminary release of the MolluscaGenes mollusc transcriptome + proteome
database, paired with the TIAMMAt mollusc-revised Pfam HMMs.

Contents (this Zenodo deposit):
  mollusca_aa.fa.gz              raw protein FASTA (gzipped)
  mollusca_mrna.fa.gz            raw mRNA FASTA (gzipped)
  mollusca_aa.dmnd               DIAMOND protein database
  mollusca_aa.blast.tar.gz       BLAST protein database (all volumes)
  mollusca_mrna.blast.tar.gz     BLAST nucleotide database (all volumes)
  tiammat_mollusca_hmms.tar.gz   TIAMMAt mollusc-revised Pfam HMMs (190 domains)
  species_metadata.tsv           per-species metadata (taxonomy, counts)
  dict2.tsv                      species code -> binomial dictionary
  MANIFEST.tsv                   sha256 + size + description for each file
  LICENSE                        license terms (see below)
  README.txt                     this file

Downloading and using:
  We strongly recommend using the wrappers and metadata that ship with the
  GitHub repository:
      https://github.com/invertome/molluscagenes
  The repo's wrappers/mg_fetch.sh will download every file in this deposit,
  verify checksums, extract the tarballs, and write a populated config.sh
  ready for the rest of the wrapper scripts.

License:
  Code (GitHub repository): GPL-3.0-or-later
  Data (this Zenodo deposit): CC-BY-4.0

Citation:
  See CITATION.cff in the GitHub repo for the recommended citation block.
  Cite both the software (this deposit's DOI) and the biorxiv preprint.

Provenance:
  v0.1 is a preliminary release based on EvidentialGene-assembled
  transcriptomes for ~333 mollusc species. A full rebuild (v1.0) is in
  progress on Unity HPC and will supersede v0.1 under the same Zenodo
  concept DOI.
EOF

# 6. Manifest
[[ "$skip_checksums" == "no" ]] && {
    echo "[6/6] checksums + MANIFEST.tsv ..." >&2
    "${here}/generate_checksums.sh" "$staging"
}

echo >&2
echo "build_all: complete." >&2
echo "staging directory contents:" >&2
ls -la "$staging" >&2
