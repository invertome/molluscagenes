# Changelog

All notable changes to MolluscaGenes are documented here. Format loosely
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project
does **not** follow strict semver because the database version and the code
version move together.

## v0.3.0 — 2026-05-08

### Fixed

- **Per-HMM specificity QC** — flagged 148 of 1,057 revised HMMs as
  over-generalized (NOISE / OVERGEN / SPEC_LOSS criteria); reverted these to
  the original Pfam-A 36.0 profile. The headline detection gain corrects
  from inflated +36.3% (v0.2) to honest +11.7% (v0.3).
- **Taxonomy re-curation** — 783 of 1,057 primary subcategory assignments
  corrected. The "10.6 RNA editing" bucket dropped from 75 garbage entries
  (substring-matching bug on "interact") to 5 legitimate ADAR-related
  entries.

### Changed

- HMM bundle is now a hybrid: 909 TIAMMAt-revised + 148 original-Pfam-fallback
  (preserves drop-in compatibility with downstream tools indexed by Pfam
  accession; filenames still end in `_REVISION.hmm` for path stability).
- SHA-256 of `mollusca_revised_hmms.hmm` updated to
  `1818e0d56612b68478e39a6dbc71dcb786b6df4e2ced63c5c17d15b133595d42`.
- Notice banner removed from all docs pages (the v0.2 issues are addressed).

### Added

- `evaluation/hmm_specificity_qc.tsv` — per-HMM specificity report
  (1,049 HMMs analyzed; 148 flagged).
- `tiammat_mollusca/scripts/build_hybrid_qc_tblouts.py` — reproducer for
  QC'd tblouts.
- `tiammat_mollusca/scripts/compare_detection_qcd.py` — v0.3 comparison
  driver.

## v0.2.0 — 2026-05-08

### Changed

- **HMM resource**: replaces the 190-domain v1 prototype with **1,057
  mollusc-optimized HMMs** (TIAMMAt-revised against 212 mollusc proteomes
  from MolluscaGenes v1). Same Pfam-A 36.0 accessions; revised models are
  drop-in compatible with downstream tooling.
- Curation taxonomy: 12 themes / 99 subcategories (was a flat ~50 categories
  in v0.1).

### Added

- `docs/hmms_evaluation.html` — comprehensive evaluation report (six
  RefSeq proteomes, methodology, results tables, six figures, specificity
  decomposition, reproducibility checksums).
- `scripts/build_domain_list.py` — reproducer for the v2 `hmm/domain_list.tsv`
  schema (5-column: accession, version, name, theme, subcategory).
- Per-domain HMM bundle expanded from 190 to 1,057 files in `hmm/per_domain/`.

### Verified

- SHA-256 of `mollusca_revised_hmms.hmm`:
  `dc6ddaa195074d89a0fdd543b554c21c9a8e55873fc800f54ebaadc0e0f84c14` (matches
  the canonical reference build).

## [0.1.0] — 2026-04-27 — Preliminary release

First public release, accompanying the biorxiv preprint.

- Concept DOI: [10.5281/zenodo.19825265](https://doi.org/10.5281/zenodo.19825265)
- v0.1 DOI: [10.5281/zenodo.19825266](https://doi.org/10.5281/zenodo.19825266)

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
