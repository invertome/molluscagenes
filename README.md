# MolluscaGenes

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.19825265.svg)](https://doi.org/10.5281/zenodo.19825265)
[![License](https://img.shields.io/badge/code-GPL--3.0-881C1C.svg)](LICENSE)
[![Data License](https://img.shields.io/badge/data-CC--BY--4.0-1f3a52.svg)](https://creativecommons.org/licenses/by/4.0/)

A taxonomically comprehensive **mollusc transcriptome and proteome resource**
paired with the **TIAMMAt mollusc-revised Pfam HMMs**, with command-line
wrappers for BLAST / DIAMOND / hmmsearch search, species and taxon FASTA
extraction, and iterative-BLAST phylogenetic placement.

> **v0.5 — biorxiv release.** The mollusc transcriptome / proteome
> resource and HMM bundle paired with the accompanying biorxiv preprint.
> A full rebuild (v1.0) is in progress and will supersede v0.5 under the
> same Zenodo concept DOI.

- **Site:** <https://invertome.github.io/molluscagenes>
- **Database (Zenodo):**
  - Concept DOI (always latest): [`10.5281/zenodo.19825265`](https://doi.org/10.5281/zenodo.19825265)
  - v0.1 DOI (pinned): [`10.5281/zenodo.19825266`](https://doi.org/10.5281/zenodo.19825266)
- **License:** GPL-3.0-or-later (code) · CC-BY-4.0 (data on Zenodo)

---

## What's included

- **1,057 mollusc-optimized Pfam HMMs** — TIAMMAt-revised against 212
  mollusc proteomes. 918 carry a TIAMMAt revision; 139 use the
  original Pfam-A 36.0 profile (HMMs that do not meet the per-HMM
  specificity bar against the six-proteome evaluation panel).
- **12-theme / 104-subcategory curation taxonomy** for each domain.
- **Evaluation report** at `docs/hmms_evaluation.html` documents
  methodology, per-theme detection gains, and per-HMM specificity QC.
- SHA-256 of canonical concat:
  `1818e0d56612b68478e39a6dbc71dcb786b6df4e2ced63c5c17d15b133595d42`.

---

## Why MolluscaGenes

Mollusca, the second-largest animal phylum (>70,000 described species across
eight classes), has historically been under-served by genomic resources.
Mollusc transcriptomes are scattered across NCBI BioProjects, MolluscDB,
MateDB, and individual lab repositories. Detection of divergent protein
homologs across the phylum is further constrained by the bias of public
HMM resources (e.g. Pfam) toward vertebrate and ecdysozoan sequences,
which can miss legitimate molluscan family members because of lineage-specific
substitution patterns.

MolluscaGenes addresses both: it consolidates de-novo and previously published
transcriptomes for ~300 species spanning all eight molluscan classes into a
single searchable resource, and ships **TIAMMAt mollusc-optimized HMMs** —
Pfam profiles iteratively re-trained against molluscan sequence diversity for
substantially higher sensitivity on lophotrochozoan homologs.

## Database scale

- **~300 species** spanning all eight classes (Gastropoda, Bivalvia,
  Cephalopoda, Polyplacophora, Scaphopoda, Solenogastres, Caudofoveata,
  Monoplacophora).
- **~17 million transcript sequences** (~16.8 Gb of nucleotide data).
- **~17 million predicted protein sequences** (~3.3 Gb of amino-acid data).
- **1,057 mollusc-optimized HMMs** (909 TIAMMAt-revised, 148 original
  Pfam-A 36.0 fallback after per-HMM specificity QC) organized by a
  12-theme / 104-subcategory curation taxonomy (innate immunity,
  developmental signalling, Ca²⁺ signalling, VGIC, GPCR, LGIC, shell
  biomineralization, epigenetic regulation, chemoreception, circadian,
  neuropeptide processing, toxin biology, synaptic function, …).

| Class | Species |
| --- | ---: |
| Gastropoda | ~140 |
| Bivalvia | ~62 |
| Solenogastres | ~36 |
| Cephalopoda | ~28 |
| Polyplacophora | ~26 |
| Caudofoveata | ~8 |
| Scaphopoda | ~5 |
| Monoplacophora | 1 |

(Exact species counts and metadata are in
[`metadata/species_metadata.tsv`](metadata/species_metadata.tsv) and on the
[species browser](https://invertome.github.io/molluscagenes/species.html).
The current release includes ~299 species.)

## How the resource was built

Raw reads were sourced from the NCBI Sequence Read Archive (paired-end
Illumina, ≥20M read-pairs/sample, prioritizing tissue diversity and
under-represented classes), supplemented with pre-assembled transcriptomes
from MateDB and MolluscDB. The pipeline is the
[`nf-core/denovotranscript`](https://nf-co.re/denovotranscript) multi-assembler
workflow:

1. **QC**: `fastp` v0.23.4 (Q20 sliding window, min length 50, low-complexity filter).
2. **Assembly**: Trinity v2.15.1 + rnaSPAdes v3.15.5 (k=25,49,73), merged.
3. **Redundancy reduction**: EvidentialGene v2023.07.15 (98% clustering, retains main + alternate transcripts).
4. **Quality gate**: BUSCO v5.4.7 (Metazoa odb10) — assemblies <30% completeness excluded.
5. **Annotation**: DIAMOND blastp vs. RefSeq (E≤1e-20) + InterProScan (Pfam, SMART, CDD, SUPERFAMILY, Gene3D) + eggNOG-mapper.
6. **HMM optimization**: TIAMMAt iterative refinement (initial Pfam → hmmsearch → MAFFT E-INS-i → hmmbuild → repeat 3–5×) validated against 6 held-out proteomes (*Aplysia californica*, *Crassostrea gigas*, *Lingula anatina*, *Lottia gigantea*, *Octopus bimaculoides*, *Pomacea canaliculata*).

The pipeline source for the upcoming v1.0 rebuild lives at the sibling
[MolluscaGenes pipeline repository](https://github.com/invertome/molluscagenes-pipeline)
(coming soon).

## Repository contents

- `wrappers/` — user-facing CLI wrappers.
- `scripts/` — reproducibility scripts (build metadata, recover FASTA, build
  DIAMOND, package tarballs, generate checksums, sync site data).
- `hmm/` — TIAMMAt mollusc-revised HMMs: combined `mollusca_revised_hmms.hmm` +
  hmmpress indices + `per_domain/` (1,057 individual HMMs) + `domain_list.tsv`.
- `metadata/` — `species_metadata.tsv`, `hmm_metadata.tsv` /`.json`, `dict2.tsv`,
  Zenodo manifest.
- `docs/` — GitHub Pages site (HMM browser with multi-select download, species
  browser with filterable TSV export).
- `environment.yml`, `config.sh.template`, `CITATION.cff`, `CHANGELOG.md`, `LICENSE` (GPL-3.0).

---

## Install

```bash
git clone https://github.com/invertome/molluscagenes
cd molluscagenes
conda env create -f environment.yml
conda activate molluscagenes
```

External tools pulled in by `environment.yml`: BLAST+ ≥2.15, DIAMOND ≥2.1,
HMMER ≥3.4, MAFFT ≥7.5, ClipKit ≥2.3, IQ-TREE 2 ≥2.3, TreeShrink ≥1.3, pigz, jq,
curl, biopython, requests, pandas.

## Get the database

```bash
bash wrappers/mg_fetch.sh /path/to/storage      # downloads, verifies, extracts
source config.sh                                # auto-written by mg_fetch
```

`mg_fetch.sh` reads the Zenodo record id from `metadata/zenodo_record.txt`
(or `--zenodo-record ID`), downloads every artifact in
`metadata/zenodo_manifest.tsv`, verifies SHA256, extracts the BLAST/HMM
tarballs, and writes a populated `config.sh`.

To re-verify an existing download: `bash wrappers/verify_download.sh /path/to/storage`.

## Updating an existing install

`wrappers/mg_update.sh` refreshes the repo (scripts, wrappers, metadata, docs)
to the latest stable release tag, then verifies your installed Zenodo data
against the new manifest. Works against both `git clone` and release-tarball
installs (auto-detected).

```bash
# in a git-clone install
bash wrappers/mg_update.sh

# or, against an existing install from outside it
bash /path/to/mg_update.sh --repo-dir /path/to/molluscagenes
```

If you don't have `wrappers/mg_update.sh` yet (older install predating it),
download just the script and point it at your existing install:

```bash
curl -fsSLO https://raw.githubusercontent.com/invertome/molluscagenes/main/wrappers/mg_update.sh
chmod +x mg_update.sh
./mg_update.sh --repo-dir /path/to/molluscagenes
```

After the first successful run the script is in place at
`wrappers/mg_update.sh`; subsequent updates use that copy.

The data on Zenodo is **never auto-downloaded** by `mg_update.sh` — it only
checks SHA256 against the new manifest and prints the exact `mg_fetch.sh`
command to run if anything is out of date.

Useful flags:

| Flag | Effect |
|------|--------|
| `--check-only` | Report current vs. latest version + data status; touch nothing. |
| `--dry-run` | Print the full update plan without modifying anything. |
| `--force` | In `git` mode, proceed even if the working tree is dirty. |
| `--track main` | Pull `main` HEAD instead of the latest tag (bleeding edge). |
| `--no-verify-data` | Skip the post-update Zenodo data check. |
| `--no-verify-tools` | Skip the conda env / tool presence check. |
| `--no-purge-cache` | Keep `metadata/_cache/subset_dbs/` even if `species_metadata.tsv` changed. |

Exit codes: `0` clean · `1` data stale (run `mg_fetch.sh`) · `2` env tools
missing or `environment.yml` changed while the env is active · `3` both ·
`4` hard failure.

---

## Wrappers — CLI reference

All wrappers source `config.sh`, write a `<outdir>/run.log` with the full
command line, tool versions, and timing, and use `<outdir>/.done` sentinels
for resume (pass `--force` to override).

Every wrapper that calls an external tool exposes the most-used flags by
name **and** an `--extra "ARGS"` passthrough so any flag we haven't named
is still reachable. The `--extra` string is split on whitespace and appended
verbatim to the underlying tool — example:

```bash
wrappers/mg_blast.sh -q q.fa -o out -d aa --extra "-gapopen 11 -gapextend 1 -seg yes"
```

### `mg_blast.sh` — BLAST search

| Flag | BLAST flag | Default | Notes |
| --- | --- | --- | --- |
| `-q PATH` | `-query` | — | query FASTA |
| `-o DIR` | — | — | output directory |
| `-d aa\|mrna` | — | — | `aa` → `blastp`, `mrna` → `blastn` |
| `-e FLOAT` | `-evalue` | 1e-5 | e-value threshold |
| `-t N` | `-num_threads` | `$MG_THREADS` (10) | threads |
| `--max-hits N` | `-max_target_seqs` | 1000 | per-query hit cap |
| `--outfmt STR` | `-outfmt` | 15-col tabular | passed verbatim |
| `--task NAME` | `-task` | (auto) | e.g. `blastp-fast`, `blastn-short`, `dc-megablast` |
| `--word-size N` | `-word_size` | (auto) | seed word length |
| `--matrix NAME` | `-matrix` | BLOSUM62 | protein only |
| `--culling N` | `-culling_limit` | (off) | hit-culling threshold |
| `--extra "..."` | (passthrough) | — | any other BLAST flag |

Writes `hits.tsv` (raw) and `hits_with_species.tsv` (joined to
`species_metadata.tsv` so every row has binomial / class / order / family).

### `mg_diamond.sh` — DIAMOND blastp / blastx

| Flag | DIAMOND flag | Default | Notes |
| --- | --- | --- | --- |
| `-q PATH` | `--query` | — | query FASTA |
| `-o DIR` | — | — | output directory |
| `-e FLOAT` | `--evalue` | 1e-5 | e-value threshold |
| `-t N` | `--threads` | `$MG_THREADS` | threads |
| `--max-hits N` | `--max-target-seqs` | 1000 | per-query hit cap |
| `--sensitivity MODE` | `--<mode>` | `more-sensitive` | `fast`, `mid-sensitive`, `sensitive`, `more-sensitive`, `very-sensitive`, `ultra-sensitive` |
| `--blastx` | (subcommand) | `blastp` | translated nucleotide query |
| `--outfmt STR` | `--outfmt` | 15-col tabular | passed verbatim |
| `--query-cover PCT` | `--query-cover` | — | min % query coverage |
| `--subject-cover PCT` | `--subject-cover` | — | min % subject coverage |
| `--id PCT` | `--id` | — | min % identity |
| `--extra "..."` | (passthrough) | — | any other DIAMOND flag |

DIAMOND databases are protein-only: there is no nucleotide DIAMOND db. For
fast nucleotide-vs-nucleotide use `mg_blast.sh -d mrna`.

### `mg_hmmsearch.sh` — HMMER hmmsearch

| Flag | hmmsearch flag | Default | Notes |
| --- | --- | --- | --- |
| `-q PATH` | (target db) | — | protein FASTA to scan |
| `-o DIR` | — | — | output directory |
| `--hmm PATH` | (HMM file) | `$MG_HMM` | full TIAMMAt HMM by default |
| `-t N` | `--cpu` | `$MG_THREADS` | threads |
| `-E FLOAT` | `-E` | 1e-5 | full-sequence E-value |
| `--domE FLOAT` | `--domE` | 1e-5 | per-domain E-value |
| `-T FLOAT` | `-T` | — | full-sequence bit-score threshold |
| `--domT FLOAT` | `--domT` | — | per-domain bit-score threshold |
| `--incE FLOAT` | `--incE` | — | inclusion E-value |
| `--cut-ga` | `--cut_ga` | — | use Pfam gathering thresholds |
| `--cut-nc` | `--cut_nc` | — | use Pfam noise cutoffs |
| `--cut-tc` | `--cut_tc` | — | use Pfam trusted cutoffs |
| `--extra "..."` | (passthrough) | — | any other hmmsearch flag |

The `--cut-*` cutoffs are mutually exclusive with `-E / --domE / -T`.

Writes `hits.tbl` (per-sequence), `hits.domtbl` (per-domain), and
`hits_with_species.tsv` (per-sequence, joined to species metadata).

### `mg_extract.sh` — extract FASTA for species or taxa

```bash
wrappers/mg_extract.sh -s Octbim -o out -d aa                              # one code
wrappers/mg_extract.sh -s "Octopus bimaculoides" --by binomial -o out      # by binomial
wrappers/mg_extract.sh -s Cephalopoda --by class -o out -d both --merge    # by class, both dbs, merged
wrappers/mg_extract.sh -s @list.txt -o out                                 # codes from a file
```

`--by` accepts `code` (default), `binomial`, `class`, `order`, `family`,
`phylum`. First run on a fresh BLAST db builds an accession-by-species
cache (~2 min, ~600 MB under `metadata/_cache/`); subsequent runs hit
the cache directly.

**Taxon-restricted searches.** All four search wrappers (`mg_blast.sh`,
`mg_diamond.sh`, `mg_hmmsearch.sh`, `mg_characterize.sh`) accept
`--taxon-filter <taxon>` to restrict the target database to a class, order,
family, binomial, species code, or comma-separated union. The first call
materializes the subset DB under `metadata/_cache/subset_dbs/`; subsequent
calls against the same taxon are I/O-bound. See
[Example 6 in the tutorials](docs/examples.html#example-6) for the full walkthrough.

```bash
# All cephalopod BLAST hits for a query (subset DB auto-built on first run):
wrappers/mg_blast.sh -q my_query.fa -o out -d aa --taxon-filter Cephalopoda

# DIAMOND, restricted to two molluscan classes:
wrappers/mg_diamond.sh -q my_query.fa -o out --taxon-filter Gastropoda,Bivalvia

# HMM scan against Cephalopoda subset (no -q needed — subset is auto-built):
wrappers/mg_hmmsearch.sh --hmm hmm/per_domain/Neur_chan_LBD_REVISION.hmm \
    -o out --taxon-filter Cephalopoda
```

### `mg_characterize.sh` — combined search

```bash
wrappers/mg_characterize.sh -q query.fa -o out
```

Runs `mg_blast`, `mg_diamond`, and `mg_hmmsearch` in parallel against
the query, aggregates per-query best hits into `summary.tsv`, and renders
a self-contained `report.html`. Skip individual searches with
`--skip blast|diamond|hmm`.

### `mg_place.sh` — phylogenetic placement

```bash
wrappers/mg_place.sh -q seeds.fa -o out                                          # default settings
wrappers/mg_place.sh -q seeds.fa -o out --search diamond --skip-treeshrink       # faster, no rogue prune
wrappers/mg_place.sh -q seeds.fa -o out --mafft-mode einsi --clipkit-mode kpic-smart-gap
wrappers/mg_place.sh -q seeds.fa -o out --model "LG+R10" --bb 5000 --bb-final 10000
```

Pipeline:

1. Iterative search (4 rounds by default; BLAST blastp or DIAMOND blastp), accumulating unique hits.
2. `blastdbcmd -entry_batch` extraction of accumulated hits.
3. Concatenate with the user's reference FASTA.
4. **MAFFT** alignment.
5. **ClipKit** trim.
6. **IQ-TREE 2** round 1 (model selection, UFBoot, aBayes).
7. **TreeShrink** rogue-tip prune (skip with `--skip-treeshrink`).
8. Re-align the shrunk set, **IQ-TREE 2** round 2 with the model selected in round 1.
9. Replace species-code prefixes with binomials via `dict2.tsv`.

Per-step `.done` sentinels enable resume; `--force` re-runs every step.

#### Iterative search options

| Flag | Default | Underlying |
| --- | --- | --- |
| `--search blastp\|diamond` | `blastp` | which search tool to use |
| `-e FLOAT` | 1e-96 | `-evalue` / `--evalue` |
| `--iterations N` | 4 | rounds |
| `--max-hits N` | 1000 | `-max_target_seqs` / `--max-target-seqs` |
| `--search-extra "..."` | — | passthrough to BLAST/DIAMOND each round |

#### MAFFT options

| Flag | Default | Underlying |
| --- | --- | --- |
| `--mafft-mode MODE` | `dash` | `dash` (DASH structure-aware), `localpair` (=L-INS-i), `globalpair`, `genafpair` (=E-INS-i), `linsi`, `einsi` |
| `--mafft-maxiterate N` | 10000 | `--maxiterate` |
| `--mafft-extra "..."` | — | passthrough |

#### ClipKit options

| Flag | Default | Underlying |
| --- | --- | --- |
| `--clipkit-mode MODE` | `smart-gap` | any ClipKit mode: `gappy`, `kpic`, `kpi`, `kpic-gappy`, `kpi-gappy`, `kpic-smart-gap`, `kpi-smart-gap`, `smart-gap` |
| `--clipkit-extra "..."` | — | passthrough |

#### IQ-TREE 2 options

| Flag | Default | Underlying |
| --- | --- | --- |
| `--model STRING` | `TESTNEW` | `-m` (round 1; round 2 uses the model that round 1 selected) |
| `--iqtree-msub MODE` | `nuclear` | `-msub`: `nuclear`, `mitochondrial`, `chloroplast`, `viral` |
| `--bb N` | 1000 | `-bb` UFBoot for round 1 |
| `--bb-final N` | 10000 | `-bb` UFBoot for final tree |
| `--iqtree-extra "..."` | — | passthrough (e.g. `"-alrt 1000 -lbp 1000"`) |

#### TreeShrink options

| Flag | Default | Underlying |
| --- | --- | --- |
| `--skip-treeshrink` | (off) | skip the prune step |
| `--treeshrink-q FLOAT` | 0.05 | `-q` quantile threshold |
| `--treeshrink-extra "..."` | — | passthrough |

---

## Metadata

### `metadata/species_metadata.tsv`

| Column | Description |
| --- | --- |
| `species_code` | 5–7-letter alphanumeric code (authoritative key) |
| `species_binomial` | Genus species |
| `ncbi_taxid` | NCBI taxonomy ID |
| `phylum` / `class` / `subclass` / `order` / `family` | NCBI taxonomy lineage |
| `worms_aphia_id` | WoRMS AphiaID |
| `n_proteins` / `n_transcripts` | Sequence counts in this release |
| `mean_protein_len` | Mean protein length, residues |
| `data_source` | `EvidentialGene assembly` for the current release |
| `source_accession` | Upstream accession if known (mostly empty in the current release; v1.0 will populate) |
| `sequencing_type` | `transcriptome` for species with sequences |
| `reference_citation_doi` | Source publication DOI (mostly empty in the current release) |

Species with `n_proteins = n_transcripts = 0` are listed for transparency
as "planned but not yet in this release". v1.0 will close that gap.

> `--taxon-filter` resolves against the `class`, `subclass`, `order`, `family`,
> `species_binomial`, and `species_code` columns above; auto-detection scans in
> that priority order and errors on ambiguity (use `--taxon-filter rank:value`
> to disambiguate).


### `metadata/hmm_metadata.tsv`

`pfam_accession`, `pfam_version`, `pfam_name`, `category`, `hmm_name`, `hmm_file`,
`hmm_length`, `n_seed_sequences`, `effn`, `source`. The `category` field tags
every HMM with a biological grouping (GPCR, VGIC, LGIC, Insulin/ILP, …) and
drives the filter on the
[HMM browser](https://invertome.github.io/molluscagenes/hmms.html).

### Rebuilding the metadata

```bash
python3 scripts/build_metadata.py            # NCBI + WoRMS + BLAST counts
python3 scripts/build_hmm_metadata.py        # parse HMM headers + domain_list.tsv
bash    scripts/sync_site_data.sh            # mirror into docs/data/ for Pages
```

---

## Building the Zenodo deposit (maintainer)

```bash
bash scripts/build_all.sh /path/to/staging
# -> mollusca_aa.fa.gz, mollusca_mrna.fa.gz, mollusca_aa.dmnd,
#    mollusca_aa.blast.tar.gz, mollusca_mrna.blast.tar.gz,
#    tiammat_mollusca_hmms.tar.gz, species_metadata.tsv, dict2.tsv,
#    LICENSE, README.txt, MANIFEST.tsv
```

Streams BLAST output through pigz / `diamond makedb --in -` so no
uncompressed FASTA hits disk. Peak temporary disk ≈ 25 GB beyond the
source BLAST databases.

---

## Citation

```
Pérez-Moreno JL, Katz PS. MolluscaGenes: a transcriptomic database for the
Mollusca (v0.1). Zenodo, 2026. https://doi.org/10.5281/zenodo.19825266

Pérez-Moreno JL, Katz PS. MolluscaGenes: A Transcriptomic Database for the
Mollusca. biorxiv, 2026. DOI: TBD (preprint pending).
```

For citing the latest version regardless of release, use the concept DOI
[`10.5281/zenodo.19825265`](https://doi.org/10.5281/zenodo.19825265). The full
machine-readable block is in [`CITATION.cff`](CITATION.cff).

## Acknowledgments

- The [TIAMMAt](https://github.com/mtassia/TIAMMAt) workflow
  ([Tassia et al. 2021](https://academic.oup.com/mbe/article/38/12/5806/6359823))
  produced the mollusc-revised HMMs.
- Pfam / InterPro for the original profile HMMs.
- NCBI Taxonomy and WoRMS for the cross-link metadata.
- The [`nf-core/denovotranscript`](https://nf-co.re/denovotranscript) pipeline
  team for the assembly workflow.

## Authorship

Developed in the [Katz Lab](https://sites.google.com/a/umass.edu/katzlab/home),
Department of Biology, [University of Massachusetts Amherst](https://www.umass.edu).

## Contact

Issues and questions: <https://github.com/invertome/molluscagenes/issues>
