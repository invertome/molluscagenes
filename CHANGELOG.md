# Changelog

All notable changes to MolluscaGenes are documented here. Format loosely
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project
does **not** follow strict semver because the database version and the code
version move together.

## [0.1.0] — 2026-04-24 — Preliminary release

First public release, accompanying the biorxiv preprint.

### Data

- `mollusca_aa` — protein BLAST database across ~333 mollusc species.
- `mollusca_mrna` — nucleotide BLAST database (transcripts / mRNAs).
- `mollusca_aa.dmnd` — DIAMOND protein database built from the same source.
- `tiammat_mollusca_hmms` — TIAMMAt mollusc-revised Pfam HMMs (190 domains).

All database artifacts are hosted on Zenodo; this repo ships the HMMs, the
metadata tables, and the code.

### Code

- Wrappers: `mg_blast`, `mg_diamond`, `mg_hmmsearch`, `mg_characterize`,
  `mg_place`, `mg_extract`, `mg_fetch`, `verify_download`.
- Metadata tables: `species_metadata.tsv` (333 species × ~12 fields),
  `hmm_metadata.tsv` / `.json` (190 HMMs × ~9 fields).
- GitHub Pages site (index / HMM browser / species browser).

### Known limitations

- This is a **preliminary** release. A full rebuild (v1.0) based on a new
  Snakemake pipeline is in progress and will supersede v0.1 under the same
  Zenodo concept DOI.
- No BUSCO completeness scores in the metadata for v0.1 — will be added in v1.0.
