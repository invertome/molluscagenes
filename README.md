# MolluscaGenes

A mollusc transcriptome and proteome resource paired with the
**TIAMMAt mollusc-revised Pfam HMMs** (190 domains), with command-line wrappers
for BLAST / DIAMOND / hmmsearch search, species extraction, and CrusTome-style
iterative-BLAST phylogenetic placement.

> **v0.1 — preliminary release.** The database used in the accompanying biorxiv
> preprint. A full rebuild (v1.0) is in progress on Unity HPC and will supersede
> v0.1 under the same Zenodo concept DOI.

- **Site:** <https://invertome.github.io/molluscagenes>
- **Database (Zenodo):** concept DOI `TBD` · v0.1 DOI `TBD`
- **License:** GPL-3.0-or-later (code) · CC-BY-4.0 (data on Zenodo)

---

## Contents

- `wrappers/` — user-facing CLI wrappers
- `scripts/` — reproducibility scripts (build metadata, recover FASTA from BLAST,
  build DIAMOND, package tarballs, generate checksums)
- `hmm/` — TIAMMAt mollusc-revised HMMs: combined `mollusca_revised_hmms.hmm` +
  hmmpress indices + `per_domain/` (190 individual HMMs) + `domain_list.tsv`
- `metadata/` — `species_metadata.tsv` (310 species × 16 fields), `hmm_metadata.tsv`
  (190 HMMs × 10 fields), `dict2.tsv` (species code ↔ binomial), and the Zenodo manifest
- `docs/` — GitHub Pages site (HMM browser, species browser)
- `environment.yml` — conda environment for all the wrappers
- `config.sh.template` — template config; `mg_fetch.sh` writes `config.sh` automatically

---

## Install

```bash
git clone https://github.com/invertome/molluscagenes
cd molluscagenes
conda env create -f environment.yml
conda activate molluscagenes
```

External tools (all pulled in by `environment.yml`):
BLAST+ ≥2.15, DIAMOND ≥2.1, HMMER ≥3.4, MAFFT ≥7.5, ClipKit, IQ-TREE 2 ≥2.3,
TreeShrink, pigz, jq, curl, biopython, requests, pandas.

## Get the database

```bash
bash wrappers/mg_fetch.sh /path/to/storage      # downloads, verifies, extracts
source config.sh                                # auto-written by mg_fetch
```

`mg_fetch.sh` reads the Zenodo record id from `metadata/zenodo_record.txt` (or
takes `--zenodo-record ID`), downloads every artifact in `metadata/zenodo_manifest.tsv`,
verifies SHA256, extracts the BLAST and HMM tarballs, and writes a populated
`config.sh`. Use `--dry-run` to preview the file list.

To verify an existing download: `bash wrappers/verify_download.sh /path/to/storage`.

---

## Wrappers

All wrappers source `config.sh`, write a `<outdir>/run.log` with the full
command line + tool versions + timing, and use `<outdir>/.done` sentinels for
resume (pass `--force` to override).

### `mg_blast.sh` — BLAST search

```bash
wrappers/mg_blast.sh -q query.fa -o out -d aa   # blastp vs mollusca_aa
wrappers/mg_blast.sh -q query.fa -o out -d mrna # blastn vs mollusca_mrna
```

Outputs `hits.tsv` (raw BLAST tabular) and `hits_with_species.tsv` (joined to
`species_metadata.tsv` so every hit comes with binomial/class/order/family).

### `mg_diamond.sh` — DIAMOND blastp/blastx

```bash
wrappers/mg_diamond.sh -q query.fa -o out --sensitivity more-sensitive
wrappers/mg_diamond.sh -q nucl.fa -o out --blastx          # translated-nucleotide query
```

Same output layout as `mg_blast.sh`. `--sensitivity` accepts every DIAMOND mode
from `fast` to `ultra-sensitive`. DIAMOND is protein-only on the database side;
there is no nucleotide DIAMOND db (use `mg_blast.sh -d mrna` for `blastn`).

### `mg_hmmsearch.sh` — hmmsearch

```bash
wrappers/mg_hmmsearch.sh -q seqs.fa -o out                 # default: full TIAMMAt HMM
wrappers/mg_hmmsearch.sh -q seqs.fa -o out --hmm my.hmm    # any HMM file
```

Outputs `hits.tbl` / `hits.domtbl` (raw) and `hits_with_species.tsv` (per-sequence
hits joined to species metadata).

### `mg_extract.sh` — extract FASTA for species or taxa

```bash
wrappers/mg_extract.sh -s Octbim -o out -d aa                                  # one code
wrappers/mg_extract.sh -s "Octopus bimaculoides" --by binomial -o out          # by binomial
wrappers/mg_extract.sh -s Cephalopoda --by class -o out -d both --merge        # all cephalopods, both dbs, single FASTA
wrappers/mg_extract.sh -s @list.txt -o out                                     # codes from a file
```

`--by` accepts `code` (default), `binomial`, `class`, `order`, `family`, `phylum`.
First run on a fresh BLAST db builds an accession-by-species cache (~2 min, ~600 MB
under `metadata/_cache/`); subsequent runs hit the cache directly.

### `mg_characterize.sh` — combined search

```bash
wrappers/mg_characterize.sh -q query.fa -o out
```

Runs `mg_blast`, `mg_diamond`, and `mg_hmmsearch` in parallel against the query.
Aggregates per-query best hits into `summary.tsv` and renders a self-contained
`report.html`. Skip individual searches with `--skip blast|diamond|hmm`.

### `mg_place.sh` — phylogenetic placement (CrusTome-style)

```bash
wrappers/mg_place.sh -q seeds.fa -o out
wrappers/mg_place.sh -q seeds.fa -o out --search diamond --iterations 4 --skip-treeshrink
```

Mirrors the CrusTome workflow:

1. Iterative search (BLAST blastp by default; `--search diamond` for DIAMOND
   blastp), 4 rounds, accumulating unique hits.
2. `blastdbcmd -entry_batch` extraction of accumulated hits.
3. Concatenate with the user's reference FASTA.
4. MAFFT-DASH alignment (`--genafpair --maxiterate 10000`).
5. ClipKit smart-gap trim.
6. IQ-TREE 2 round 1 (model selection, UFBoot, aBayes).
7. TreeShrink (q=0.05) — disable with `--skip-treeshrink`.
8. Re-align the shrunk set, IQ-TREE 2 round 2 with the model selected in round 1.
9. Replace species-code prefixes with binomials via `dict2.tsv`.

Per-step `.done` sentinels in the output directory enable resume; `--force`
re-runs every step from scratch.

---

## Metadata

### `metadata/species_metadata.tsv` (310 rows × 16 columns)

| Column | Description |
| --- | --- |
| `species_code` | 5–7-letter alphanumeric code (authoritative key) |
| `species_binomial` | Genus species |
| `ncbi_taxid` | NCBI taxonomy ID |
| `phylum` / `class` / `subclass` / `order` / `family` | NCBI taxonomy lineage |
| `worms_aphia_id` | WoRMS AphiaID |
| `n_proteins` / `n_transcripts` | Sequence counts in this release |
| `mean_protein_len` | Mean protein length, residues |
| `data_source` | `EvidentialGene assembly` for v0.1 |
| `source_accession` | Upstream accession if known (mostly empty in v0.1; v1.0 will populate) |
| `sequencing_type` | `transcriptome` for species with sequences |
| `reference_citation_doi` | Source publication DOI (mostly empty in v0.1) |

98 of the 310 species have `n_proteins = n_transcripts = 0` — they are listed for
transparency as "planned but not yet in this release". v1.0 will close that gap.

### `metadata/hmm_metadata.tsv` (190 rows × 10 columns)

`pfam_accession`, `pfam_version`, `pfam_name`, `category`, `hmm_name`, `hmm_file`,
`hmm_length`, `n_seed_sequences`, `effn`, `source`. The `category` field tags every
HMM with a biological grouping (GPCR, VGIC, LGIC, Insulin/ILP, …) — useful for
filtering on the [HMM browser](https://invertome.github.io/molluscagenes/hmms.html).

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

Streams BLAST output through pigz / `diamond makedb --in -` so no uncompressed
FASTA hits disk. Peak temporary disk ≈ 25 GB beyond the source BLAST databases.

---

## Citation

```
Perez-Moreno JL, Katz PS. MolluscaGenes: a mollusc transcriptome resource with
mollusc-optimized Pfam HMMs (v0.1). Zenodo, 2026. DOI: TBD

Perez-Moreno JL, Katz PS. [Title TBD]. biorxiv, 2026. DOI: TBD
```

The full machine-readable block is in [`CITATION.cff`](CITATION.cff).

## Acknowledgments

- The [CrusTome](https://github.com/invertome/crustome) database and its example
  workflow inspired the structure of this resource and the iterative-BLAST
  phylogeny pipeline.
- The [TIAMMAt](https://github.com/AnnaConn/TIAMMAt) workflow produced the
  mollusc-revised HMMs.
- Pfam / InterPro for the original profile HMMs.
- NCBI Taxonomy and WoRMS for the cross-link metadata.

## Contact

Issues and questions: <https://github.com/invertome/molluscagenes/issues>
