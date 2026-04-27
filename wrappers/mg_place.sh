#!/usr/bin/env bash
# mg_place.sh — phylogenetic placement of a query against MolluscaGenes,
# mirroring the CrusTome iterative-BLAST workflow but parameterized.
#
# Pipeline (per CrusTome example.sh):
#   1. Iterative search (BLAST blastp or DIAMOND blastp), N rounds, accumulating hits
#   2. blastdbcmd extracts all unique hits as FASTA
#   3. Concatenate with the user's reference query FASTA
#   4. MAFFT-DASH alignment (--genafpair --maxiterate 10000)
#   5. ClipKit smart-gap trim
#   6. IQ-TREE2 round 1 on trimmed alignment (model selection + UFBoot + aBayes)
#   7. TreeShrink (q=0.05) to remove rogue tips (--skip-treeshrink to disable)
#   8. Re-align shrunk set, IQ-TREE2 round 2 with the selected model
#   9. sed-rename species-coded tips -> binomials via dict2.tsv
#
# Per-step .done sentinels enable resume; --force re-runs everything.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${here}/_common.sh"

usage() {
    cat >&2 <<'EOF'
Usage: mg_place.sh -q <reference.fa> -o <outdir> [options]

Required:
  -q PATH               reference query FASTA (your seed sequences)
  -o DIR                output directory

Options:
  -t N                  threads [$MG_THREADS, default 10]
  -e FLOAT              e-value for iterative searches [1e-96, per CrusTome]
  --search MODE         blastp | diamond  [blastp]
  --iterations N        rounds of iterative search [4]
  --max-hits N          per-iteration -max_target_seqs / --max-target-seqs [1000]
  --model STRING        IQ-TREE -m argument [TESTNEW]
  --bb N                IQ-TREE UFBoot replicates [1000]
  --bb-final N          IQ-TREE UFBoot replicates for final tree [10000]
  --skip-treeshrink     skip the TreeShrink prune step
  --force               re-run all steps even if .done sentinels are present
  -h | --help           this help

Outputs (key files):
  iter<N>/hits.tsv      BLAST/DIAMOND output for round N
  hits_all.fasta        accumulated unique hits
  input.fa              hits + reference (alignment input)
  alignment.fa          MAFFT-DASH output
  alignment.fa.clipkit  ClipKit-trimmed
  iqtree.contree        first IQ-TREE consensus tree (with bootstraps)
  iqtree.iqtree         IQ-TREE log incl. selected model
  treeshrink/           TreeShrink work dir (if not --skip-treeshrink)
  final.contree         final IQ-TREE consensus
  final.names.treefile  final tree with species_code IDs replaced by binomials
EOF
}

ref=""
outdir=""
threads=""
evalue="1e-96"
search="blastp"
iters="4"
max_hits="1000"
model="TESTNEW"
bb="1000"
bb_final="10000"
skip_ts="no"
force="no"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -q) ref="$2"; shift 2 ;;
        -o) outdir="$2"; shift 2 ;;
        -t) threads="$2"; shift 2 ;;
        -e) evalue="$2"; shift 2 ;;
        --search) search="$2"; shift 2 ;;
        --iterations) iters="$2"; shift 2 ;;
        --max-hits) max_hits="$2"; shift 2 ;;
        --model) model="$2"; shift 2 ;;
        --bb) bb="$2"; shift 2 ;;
        --bb-final) bb_final="$2"; shift 2 ;;
        --skip-treeshrink) skip_ts="yes"; shift ;;
        --force) force="yes"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
    esac
done

[[ -z "$ref"    ]] && { usage; mg_die "missing -q"; }
[[ -z "$outdir" ]] && { usage; mg_die "missing -o"; }
[[ -f "$ref"    ]] || mg_die "reference FASTA not found: $ref"
case "$search" in blastp|diamond) ;; *) mg_die "--search must be blastp|diamond" ;; esac
[[ "$iters" =~ ^[0-9]+$ ]] && (( iters >= 1 )) || mg_die "--iterations must be a positive integer"

mg_load_config
threads="${threads:-${MG_THREADS:-10}}"
mg_require mafft clipkit iqtree blastdbcmd
[[ "$search" == "blastp"  ]] && mg_require blastp
[[ "$search" == "diamond" ]] && mg_require diamond
[[ "$skip_ts" == "no"     ]] && mg_require run_treeshrink.py

mkdir -p "$outdir"
log="${outdir}/run.log"
[[ "$force" == "yes" ]] && rm -f "${outdir}"/.step_*.done "${outdir}/.done"

if [[ ! -f "$log" ]]; then : > "$log"; fi
mg_log "$log" "mg_place.sh: search=$search iters=$iters model=$model"
mg_log "$log" "command: $0 $*"
mg_log "$log" "ref=$ref evalue=$evalue threads=$threads max_hits=$max_hits"
mg_log_versions "$log" mafft clipkit iqtree run_treeshrink.py blastp diamond blastdbcmd

step_done() { [[ -f "${outdir}/.step_${1}.done" ]]; }
step_mark() { date -u +%Y-%m-%dT%H:%M:%SZ > "${outdir}/.step_${1}.done"; }

OUTFMT='6 qseqid sseqid evalue bitscore pident nident qlen slen qstart qend sstart send length mismatch gapopen'

# --- Iterative search rounds 1..N ---
prev_query="$ref"
> "${outdir}/hits_all.list"

for ((i=1; i<=iters; i++)); do
    iter_dir="${outdir}/iter${i}"
    mkdir -p "$iter_dir"
    iter_hits="${iter_dir}/hits.tsv"
    iter_list="${iter_dir}/hits.list"
    iter_fa="${iter_dir}/hits.fasta"

    if step_done "iter${i}"; then
        mg_log "$log" "step iter${i}: SKIP (already done)"
    else
        mg_log "$log" "step iter${i}: searching $prev_query against MolluscaGenes ($search)..."
        if [[ "$search" == "blastp" ]]; then
            blastp -query "$prev_query" -db "$MG_BLAST_AA" \
                   -num_threads "$threads" -max_target_seqs "$max_hits" \
                   -evalue "$evalue" -outfmt "$OUTFMT" -out "$iter_hits" 2>> "$log"
        else
            read -r -a fmt_arr <<< "$OUTFMT"
            diamond blastp --query "$prev_query" --db "$MG_DIAMOND_AA" \
                    --threads "$threads" --max-target-seqs "$max_hits" \
                    --evalue "$evalue" --more-sensitive \
                    --outfmt "${fmt_arr[@]}" --out "$iter_hits" --quiet 2>> "$log"
        fi

        cut -f2 "$iter_hits" | awk '!seen[$0]++' > "$iter_list"
        blastdbcmd -db "$MG_BLAST_AA" -dbtype prot -entry_batch "$iter_list" -outfmt "%f" > "$iter_fa" 2>> "$log"
        nhits=$(wc -l < "$iter_list")
        mg_log "$log" "  iter${i}: $nhits unique hits, $(grep -c '^>' "$iter_fa") sequences extracted"
        cat "$iter_list" >> "${outdir}/hits_all.list"
        step_mark "iter${i}"
    fi
    prev_query="${iter_dir}/hits.fasta"
done

# Dedupe accumulated list, extract once for the alignment input
if ! step_done "extract_all"; then
    awk '!seen[$0]++' "${outdir}/hits_all.list" > "${outdir}/hits_all.dedup.list"
    blastdbcmd -db "$MG_BLAST_AA" -dbtype prot -entry_batch "${outdir}/hits_all.dedup.list" -outfmt "%f" \
        > "${outdir}/hits_all.fasta" 2>> "$log"
    n_total=$(grep -c '^>' "${outdir}/hits_all.fasta")
    mg_log "$log" "extracted $n_total unique sequences across all iterations"
    step_mark "extract_all"
fi

# Combine with reference
if ! step_done "combine"; then
    cat "${outdir}/hits_all.fasta" "$ref" > "${outdir}/input.fa"
    mg_log "$log" "wrote input.fa ($(grep -c '^>' "${outdir}/input.fa") sequences)"
    step_mark "combine"
fi

# --- MAFFT-DASH alignment ---
if ! step_done "mafft"; then
    mg_log "$log" "MAFFT-DASH aligning..."
    mafft --dash --originalseqonly --genafpair --maxiterate 10000 \
          --thread "$threads" "${outdir}/input.fa" > "${outdir}/alignment.fa" 2>> "$log"
    mg_log "$log" "  alignment: $(grep -c '^>' "${outdir}/alignment.fa") sequences"
    step_mark "mafft"
fi

# --- ClipKit trim ---
if ! step_done "clipkit"; then
    mg_log "$log" "ClipKit trimming (smart-gap)..."
    cut -d ' ' -f1 "${outdir}/alignment.fa" > "${outdir}/aligned.fa"
    clipkit "${outdir}/aligned.fa" -m smart-gap 2>> "$log"
    # produces aligned.fa.clipkit
    step_mark "clipkit"
fi

# --- IQ-TREE round 1 (trimmed) ---
if ! step_done "iqtree1"; then
    mg_log "$log" "IQ-TREE round 1 (trimmed) ..."
    iqtree -s "${outdir}/aligned.fa.clipkit" -pre "${outdir}/iqtree" \
           -nt "$threads" -m "$model" -msub nuclear -bb "$bb" -bnni -abayes 2>> "$log"
    step_mark "iqtree1"
fi

# Capture the model IQ-TREE selected (e.g. LG+R5) for the final round
selected_model=""
if [[ -f "${outdir}/iqtree.iqtree" ]]; then
    selected_model=$(grep -E '^Best-fit model' "${outdir}/iqtree.iqtree" | head -1 | awk -F': ' '{print $2}' | awk '{print $1}')
fi
[[ -z "$selected_model" ]] && selected_model="$model"
mg_log "$log" "selected model for final round: $selected_model"

# --- TreeShrink ---
if [[ "$skip_ts" == "no" ]]; then
    if ! step_done "treeshrink"; then
        mg_log "$log" "TreeShrink (q=0.05) ..."
        ts_dir="${outdir}/treeshrink/run"
        mkdir -p "$ts_dir"
        cp "${outdir}/iqtree.contree" "${ts_dir}/input.tree"
        cp "${outdir}/aligned.fa.clipkit" "${ts_dir}/input.fasta"
        run_treeshrink.py -i "${outdir}/treeshrink" -q 0.05 >> "$log" 2>&1
        step_mark "treeshrink"
    fi
    final_input_fa="${outdir}/treeshrink/run/output.fasta"
else
    final_input_fa="${outdir}/aligned.fa.clipkit"
fi

# --- Re-align (post-shrink) + IQ-TREE final ---
if ! step_done "iqtree_final"; then
    if [[ "$skip_ts" == "no" ]]; then
        mg_log "$log" "Re-aligning post-TreeShrink ..."
        mafft --dash --originalseqonly --genafpair --maxiterate 10000 \
              --thread "$threads" "$final_input_fa" > "${outdir}/realigned.fa" 2>> "$log"
        final_aln="${outdir}/realigned.fa"
    else
        final_aln="$final_input_fa"
    fi
    mg_log "$log" "IQ-TREE final round (model=$selected_model) ..."
    iqtree -s "$final_aln" -pre "${outdir}/final" \
           -nt "$threads" -mset "$selected_model" -nstop 250 \
           -bb "$bb_final" -bnni -abayes 2>> "$log"
    step_mark "iqtree_final"
fi

# --- Replace species-coded IDs with binomials ---
if ! step_done "rename"; then
    mg_log "$log" "Renaming tip IDs (species_code prefixes -> binomials) ..."
    dict="${MG_METADATA}/dict2.tsv"
    [[ -f "$dict" ]] || mg_die "dict2.tsv not found at $dict"

    # CrusTome's sed-substitute idiom: build a sed script from the dict and apply.
    # We replace the SPECIES-CODE PREFIX (anchored at start of label) — not arbitrary
    # substrings — to avoid clobbering matches inside accession bodies.
    # IQ-TREE labels look like "AcacriEVm000001t1" so the prefix anchor is the start of
    # any whitespace- or punctuation-bounded token in the Newick string.
    awk -F'\t' 'NR>0 && NF>=2 {gsub(/[ \t]/,"_",$2); print "s/\\b"$1"EVm/"$2"_EVm/g"}' "$dict" \
        > "${outdir}/.rename.sed"
    sed -f "${outdir}/.rename.sed" "${outdir}/final.contree" > "${outdir}/final.names.contree"
    sed -f "${outdir}/.rename.sed" "${outdir}/final.treefile" > "${outdir}/final.names.treefile" 2>/dev/null \
        || cp "${outdir}/final.contree" "${outdir}/final.names.treefile"
    mg_log "$log" "wrote final.names.contree and final.names.treefile"
    step_mark "rename"
fi

mg_mark_done "$outdir"
mg_log "$log" "all steps complete."
echo "${outdir}/final.names.contree"
