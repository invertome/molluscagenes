# Changelog

All notable changes to MolluscaGenes are documented here. Format loosely
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project
does **not** follow strict semver because the database version and the code
version move together.

## v0.6.0 — 2026-05-25

### Added

- **Full per-HMM `-I` optimization completed across all 901 v0.3 QC-passing
  HMMs.** v0.5.0 had grid-optimized only the 49 over-generalized-but-salvageable
  HMMs; v0.6 extends the same 5-point grid (`-I ∈ {1e-5, 1e-10, 1e-15, 1e-20,
  1e-25}`) to a 200-HMM stratified sample of QC-passing HMMs, and v0.7 sweeps
  the remaining 701 QC-passing HMMs. Per HMM, the winning `-I` is selected
  by composite QC score (strong-hit rate at E≤1e-30 + sensitivity vs v2
  baseline − NOISE/OVERGEN/SPEC_LOSS penalties).
- 54 additional HMMs substituted into the bundle with grid-optimized
  revisions (on top of the 9 already in v0.5.0):
  - **From v0.6 stratified sample (11 HMMs):** `BACK` (`-I=1e-15`),
    `Bcl-2` (`-I=1e-10`), `CADH_Y-type_LIR` (`-I=1e-15`),
    `CaMBD` (`-I=1e-15`), `Chromo` (`-I=1e-15`), `DYH2-5-8_CC` (`-I=1e-5`),
    `GPHH` (`-I=1e-25`), `HMG_box` (`-I=1e-20`), `JmjC` (`-I=1e-15`),
    `PCI` (`-I=1e-20`), `Zona_pellucida` (`-I=1e-15`).
  - **From v0.7 full sweep of remaining 701 QC-passing HMMs (43 HMMs):**
    `ABC2_membrane` (`-I=1e-20`), `Acyltransferase` (`-I=1e-10`),
    `BIR` (`-I=1e-15`), `BRE` (`-I=1e-20`), `CBM39` (`-I=1e-5`),
    `CH` (`-I=1e-20`), `Clathrin_lg_ch` (`-I=1e-25`),
    `DAAF9_N` (`-I=1e-25`), `DCAF17` (`-I=1e-5`), `DHFR_1` (`-I=1e-20`),
    `E1_FCCH` (`-I=1e-20`), `EF-hand_2` (`-I=1e-15`),
    `EF-hand_3` (`-I=1e-25`), `Ephrin_lbd` (`-I=1e-15`),
    `Exportin-5` (`-I=1e-10`), `Helicase_C` (`-I=1e-15`),
    `Hexokinase_1` (`-I=1e-20`), `Hint` (`-I=1e-10`),
    `His_Phos_1` (`-I=1e-5`), `KCNQ_channel` (`-I=1e-10`),
    `KRAP_IP3R_bind` (`-I=1e-5`), `Laminin_B` (`-I=1e-20`),
    `Laminin_N` (`-I=1e-25`), `MACPF` (`-I=1e-20`),
    `MOZ_SAS` (`-I=1e-5`), `MUN` (`-I=1e-10`), `Maelstrom` (`-I=1e-10`),
    `Myosin_TH1` (`-I=1e-10`), `Neuro_bHLH` (`-I=1e-10`),
    `P2X_receptor` (`-I=1e-5`), `PI3Ka` (`-I=1e-10`), `RH1` (`-I=1e-15`),
    `Ricin_B_lectin` (`-I=1e-20`), `S8_pro-domain` (`-I=1e-20`),
    `SET` (`-I=1e-15`), `SMP_C2CD2L` (`-I=1e-5`),
    `SNF2-rel_dom` (`-I=1e-20`), `SRP_SPB` (`-I=1e-10`),
    `STAT_bind` (`-I=1e-10`), `TIP_N` (`-I=1e-10`), `TRP_2` (`-I=1e-20`),
    `Transferrin` (`-I=1e-10`), `zf-C4` (`-I=1e-25`).
- Methods-log update + design documents covering the v0.6/v0.7 grid
  optimization extension (`tiammat_mollusca/evaluation/eval_findings_v1.md`,
  `evaluation/v0{5,6,7}_per_hmm_winner.tsv`,
  `evaluation/v06_release_substitution_manifest.tsv`).
- Per-HMM response-curve figures
  (`evaluation/figures/v0{5,6,7}_response_curves.png`).

### Bundle composition

- 1,057 HMMs total: 838 v2 TIAMMAt revisions + 9 v0.5 + 11 v0.6 + 43 v0.7
  grid-optimized revisions + 139 original Pfam-A 36.0 fallback. Total
  TIAMMAt-revised count remains 918; the breakdown shift is internal to
  the revised set.
- The 54 newly substituted HMMs span `-I` values from 1e-5 to 1e-25, with
  no single value dominating (per-`-I` count among v0.6+v0.7 winners:
  1e-5: 8, 1e-10: 16, 1e-15: 12, 1e-20: 14, 1e-25: 6).
- Bundle SHA256:
  `d8a3ff85af17cab9d7be9ac5d888b428a656f793245d7b775f3c2da3be728e10`

### Methodology finding

The v0.7 full sweep of the 701 remaining QC-passing HMMs returned a 6.1%
substitution yield — slightly *higher* than the v0.6 stratified sample's
5.5% despite the v0.6 sample being upper-biased by a "likelihood-to-benefit"
heuristic. This empirically demonstrates that the v2 production `-I=1e-3`
setting is not universally optimal: roughly **1 in 16 QC-passing HMMs has
a clearly better per-HMM `-I` somewhere in the {1e-5..1e-25} grid**, and
selecting that better value produces a TIAMMAt revision that beats the
v2 baseline by ≥5pp strong-hit rate while preserving the sensitivity floor.

## v0.5.3 — 2026-05-14

### Fixed

- `wrappers/mg_update.sh` latest-tag discovery (tarball mode): same root
  cause as v0.5.2 — `/releases/latest` 404s when no GitHub Release object
  exists for any tag. Replaced with `/repos/{owner}/{repo}/tags`, filtered
  for stable (no `-rc`/`-beta`/`-alpha`) and picking the first entry (the
  list is commit-date desc). Without this, `latest_version()` in tarball
  mode returned `"unknown"` and the subsequent tarball download failed
  with `tarball/unknown`. v0.5.2 fixed half the chain; v0.5.3 closes the
  other half.
- `scripts/test_mg_update.sh` T12 (integration): now omits the
  `MG_UPDATE_LATEST_TAG` override so the test exercises *both* the live
  latest-discovery path AND the live tarball-download path. Catches this
  full class of bug end-to-end.

## v0.5.2 — 2026-05-14

### Fixed

- `wrappers/mg_update.sh` (tarball mode): replaced the GitHub
  `/releases/tags/{tag}` endpoint with `/tarball/{tag}`. The previous
  endpoint 404s on tags that weren't promoted to GitHub Release objects,
  which is the project's actual release convention (we tag, we don't create
  Release objects). The new endpoint works for any ref and 302s to codeload.
  Without this, tarball-mode users running `mg_update.sh` against any current
  tag would have hit "could not get tarball URL". v0.5.1 shipped with the
  bug; v0.5.2 fixes it.
- `scripts/test_mg_update.sh`: added an `MOLLUSCAGENES_INTEGRATION=1`-gated
  network test (T12) that hits the real `invertome/molluscagenes` tarball
  endpoint, so this class of breakage gets caught in CI / by-hand validation
  rather than by users.

## v0.5.1 — 2026-05-14

### Added

- `wrappers/mg_update.sh` — in-place install refresh script. Auto-detects
  `git clone` vs release-tarball installs and brings the repo to the latest
  stable release tag, then verifies the installed Zenodo data against the new
  manifest. Includes standalone bootstrap mode (`curl` the script, run with
  `--repo-dir`) for users without `wrappers/mg_update.sh` yet. Never
  auto-downloads Zenodo data: prints the `mg_fetch.sh` command on mismatch.
  Snapshots `environment.yml` + `metadata/species_metadata.tsv` pre-update to
  emit a `conda env update` advisory and to conditionally purge
  `metadata/_cache/subset_dbs/`. Exit codes `0/1/2/3/4` for clean / data
  stale / env stale / both / hard failure.
- `scripts/test_mg_update.sh` — 100+ unit/integration cases covering both
  install modes, dry-run, dirty-tree refusal, `--force`, version detection,
  env diff, cache purge, tool presence, data verification, and the
  combined-status exit codes. Tests use `MG_UPDATE_LATEST_TAG` /
  `MG_UPDATE_TARBALL_PATH` / `MG_UPDATE_REQUIRED_TOOLS` env overrides so the
  harness runs offline. Verified on Unity busco_env (SLURM 57681011,
  103/103 pass, 19 s wall).
- README + site (`docs/index.html`): new "Updating an existing install"
  section with the curl one-liner, flag summary, and exit codes.

## v0.5.0 — 2026-05-14

### Added

- **Per-HMM inclusion-threshold optimization** for the 49 HMMs flagged by
  the v0.3 specificity QC pass. A 5-point grid (`-I ∈ {1e-5, 1e-10, 1e-15,
  1e-20, 1e-25}`) was run per HMM in addition to the existing v2 production
  point (`-I=1e-3`) and a uniform-strict point (`-I=1e-30`), giving a
  7-point characterization curve per HMM. The per-HMM winning `-I` is
  selected by a composite QC score combining strong-hit rate (E ≤ 1e-30),
  sensitivity relative to the original Pfam baseline, and specificity-flag
  penalties (NOISE / OVERGEN / SPEC_LOSS).
- 9 HMMs substituted into the bundle with their per-HMM-optimized
  revisions, each at a different `-I`:
  `EF-hand_11` (`-I=1e-20`),
  `EF-hand_like` (`-I=1e-10`),
  `EF_HAND_1_PLCG` (`-I=1e-10`),
  `Ig_SEMA7A` (`-I=1e-10`),
  `MCLC` (`-I=1e-30`),
  `Myo5a` (`-I=1e-5`),
  `PRKG1_interact` (`-I=1e-25`),
  `Spectrin_7` (`-I=1e-15`),
  `bHLH_HIF1A` (`-I=1e-15`).
- Methods-log section + design documents covering the grid optimization
  protocol and scope (`tiammat_mollusca/evaluation/eval_findings_v1.md`,
  `docs/plans/2026-05-11-tiammat-v05-per-hmm-optimization-design.md`).
- Per-HMM response-curve figure
  (`tiammat_mollusca/evaluation/figures/v05_response_curves.png`).

### Bundle composition

- 1,057 HMMs total: 909 v2 TIAMMAt revisions + 9 v0.5 grid-optimized
  revisions + 139 original Pfam-A 36.0 profiles for HMMs where no `-I`
  value passed the QC gates (sensitivity floor + clean NOISE/OVERGEN flag).
- The 9 substituted HMMs contribute **+213 strong-evidence detections**
  and **+982 total detections** across the 6-proteome evaluation panel.
- Bundle SHA256:
  `917844a7e2bc2885a2fe1c661635e8738a3eb60153b2cacfdbf7cce450da2ae8`

## v0.4.0 — 2026-05-12

### Added

- `--taxon-filter` flag on `mg_blast.sh`, `mg_diamond.sh`, `mg_hmmsearch.sh`,
  and `mg_characterize.sh`. Restricts the target database to a class, order,
  family, binomial, species code, or comma-separated union. Auto-detects rank
  from `metadata/species_metadata.tsv`; use `rank:value` form (e.g.
  `--taxon-filter class:Gastropoda`) to disambiguate when a name matches
  multiple ranks. Subset DBs cached under
  `metadata/_cache/subset_dbs/<key>/` with source-DB SHA256 in
  `manifest.json` for auto-invalidation. New helper
  `wrappers/_taxon_filter.sh`. In `mg_characterize`, the flag applies to
  BLAST + DIAMOND only (the hmm step scans the user's query, not a
  database). See Example 6 in `docs/examples.html` for the full walkthrough.

### Fixed

- `mg_hmmsearch.sh` no longer exits non-zero when a query produces zero
  domain hits: the post-search `grep -v '^#'` pipeline used to trip
  `pipefail` when there were no non-comment rows in `hits.tbl`. Replaced
  with an awk filter that handles empty input gracefully.

## v0.3.0 — 2026-05-08

### Hybrid HMM bundle

- 909 of 1,057 HMMs carry the TIAMMAt mollusc-optimized revision; 148
  use the original Pfam-A 36.0 profile (per-HMM specificity QC against
  the six-proteome evaluation panel determines which version is shipped).
- SHA-256 of `mollusca_revised_hmms.hmm`:
  `1818e0d56612b68478e39a6dbc71dcb786b6df4e2ced63c5c17d15b133595d42`.

### Curation taxonomy

- 12-theme / 104-subcategory taxonomy for the 1,057 Pfam domains.
- Hand-validated assignments for 1,057 / 1,057 domains; complete table
  at `tiammat_mollusca/taxonomy/domain_list.tsv`.

### Evaluation report

- New page `docs/hmms_evaluation.html` documents the per-HMM specificity
  QC methodology, per-theme detection gains, and per-domain results.

### Reproducibility

- `tiammat_mollusca/scripts/build_hybrid_qc_tblouts.py`,
  `compare_detection_qcd.py`,
  `qc_v04_revisions.py` (preview of v0.4 optimization protocol),
  `evaluation/hmm_specificity_qc.tsv` per-HMM report,
  `evaluation/tiammat_optimization_recommendations.tsv`.

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
