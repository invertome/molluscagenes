#!/usr/bin/env bash
# mg_extract.sh — extract FASTA for a set of species from the BLAST databases.
#
# Usage:
#   mg_extract.sh -s <selector> -o <outdir> [-d aa|mrna|both] [--by code|binomial|class|order|family|phylum] [--merge] [-t N] [--force]
#
# Selector (-s) forms:
#   Single value:  -s Alibip
#   Comma list:    -s Alibip,Aegche,Oxoal1
#   File (@path):  -s @species.txt       (one token per line)
#   Binomial:      -s "Octopus bimaculoides" --by binomial
#   Taxonomy rank: -s Cephalopoda --by class
#                  -s Pectinidae   --by family
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "${here}/_common.sh"

usage() {
    cat >&2 <<'EOF'
Usage: mg_extract.sh -s <selector> -o <outdir> [options]

Required:
  -s SEL       species selector (see below)
  -o DIR       output directory

Options:
  -d aa|mrna|both     which database to extract from [both]
  --by TYPE           selector type: code | binomial | class | order | family | phylum [code]
  --merge             merge all extracted sequences into a single FASTA per db
  -t N                threads (for parallel blastdbcmd calls) [$MG_THREADS]
  --force             rebuild accession cache even if fingerprint matches
  -h | --help         this help

Selector forms:
  Single: -s Alibip
  Comma list: -s Alibip,Aegche
  File: -s @species.txt (one species per line)
  With --by binomial: -s "Octopus bimaculoides"
  With --by class: -s Cephalopoda

Outputs:
  <outdir>/<code>_aa.fa           per-species protein FASTA (default)
  <outdir>/<code>_mrna.fa         per-species mRNA FASTA
  <outdir>/extracted_aa.fa        merged protein (with --merge)
  <outdir>/extracted_mrna.fa      merged mRNA (with --merge)
  <outdir>/extracted_species.tsv  species_code, binomial, class, n_proteins, n_transcripts
  <outdir>/run.log                provenance
EOF
}

sel=""
outdir=""
dbtype="both"
by="code"
merge="no"
threads=""
force="no"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s) sel="$2"; shift 2 ;;
        -o) outdir="$2"; shift 2 ;;
        -d) dbtype="$2"; shift 2 ;;
        --by) by="$2"; shift 2 ;;
        --merge) merge="yes"; shift ;;
        -t) threads="$2"; shift 2 ;;
        --force) force="yes"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
    esac
done

[[ -z "$sel"    ]] && { usage; mg_die "missing -s"; }
[[ -z "$outdir" ]] && { usage; mg_die "missing -o"; }
case "$dbtype" in aa|mrna|both) ;; *) mg_die "-d must be aa|mrna|both" ;; esac
case "$by" in code|binomial|class|order|family|phylum) ;; *) mg_die "--by must be code|binomial|class|order|family|phylum" ;; esac

mg_load_config
threads="${threads:-${MG_THREADS:-10}}"
repo_root="$(cd "${here}/.." && pwd)"
metadata_tsv="${MG_METADATA}/species_metadata.tsv"
cache="${MG_METADATA}/_cache"
[[ -f "$metadata_tsv" ]] || mg_die "species_metadata.tsv not found at $metadata_tsv"
mg_require blastdbcmd

# Ensure the accession index exists (and is fresh). Delegate to the build script.
if [[ "$force" == "yes" ]] || [[ ! -f "${cache}/fingerprint.tsv" ]]; then
    bash "${repo_root}/scripts/build_accession_index.sh" ${force:+--force} >&2
fi

mkdir -p "$outdir"
log="${outdir}/run.log"
: > "$log"
mg_log "$log" "mg_extract.sh: sel=$sel by=$by dbtype=$dbtype merge=$merge"
mg_log "$log" "command: $0 $*"
mg_log_versions "$log" blastdbcmd

# Resolve selector -> list of species codes via species_metadata.tsv
codes_file="${outdir}/.selector_codes.txt"
python3 - "$metadata_tsv" "$sel" "$by" > "$codes_file" <<'PY'
import csv, sys
meta_path, sel, by = sys.argv[1], sys.argv[2], sys.argv[3]
# Expand selector: single, comma-list, or @file
tokens = []
if sel.startswith("@"):
    with open(sel[1:]) as f:
        tokens = [t.strip() for t in f if t.strip()]
else:
    tokens = [t.strip() for t in sel.split(",") if t.strip()]

# Load metadata, build lookup maps
rows = []
with open(meta_path) as f:
    for r in csv.DictReader(f, delimiter="\t"):
        rows.append(r)

by_field = {
    "code": "species_code",
    "binomial": "species_binomial",
    "class": "class",
    "order": "order",
    "family": "family",
    "phylum": "phylum",
}[by]

selected = []
for t in tokens:
    t_ci = t.lower()
    matched = [r["species_code"] for r in rows if r.get(by_field, "").lower() == t_ci]
    if not matched and by == "binomial":
        # Also tolerate underscore form
        matched = [r["species_code"] for r in rows if r.get(by_field, "").replace(" ", "_").lower() == t_ci.replace(" ", "_")]
    if not matched:
        print(f"# no match for selector token: {t}", file=sys.stderr)
    selected.extend(matched)

# Dedupe, preserve order
seen = set()
for c in selected:
    if c not in seen:
        print(c); seen.add(c)
PY

n_codes=$(grep -cv '^#' "$codes_file" || true)
[[ "$n_codes" -eq 0 ]] && mg_die "selector '$sel' (--by $by) matched no species."
mg_log "$log" "selector resolved to $n_codes species code(s)."

extract_one() {
    local code="$1" dt="$2"
    local db="" ext=""
    case "$dt" in
        aa)   db="$MG_BLAST_AA";   ext="aa";   dbtype_flag="prot" ;;
        mrna) db="$MG_BLAST_MRNA"; ext="mrna"; dbtype_flag="nucl" ;;
    esac
    local acc_file="${cache}/${dt}/${code}.txt"
    local out_fa="${outdir}/${code}_${ext}.fa"
    if [[ ! -s "$acc_file" ]]; then
        printf '%s\t%s\t%s\n' "$code" "$dt" "no-accessions" >> "${outdir}/.extract_status.tsv"
        return 0
    fi
    blastdbcmd -db "$db" -dbtype "$dbtype_flag" -entry_batch "$acc_file" -outfmt "%f" > "$out_fa" 2>> "$log" \
        || { printf '%s\t%s\t%s\n' "$code" "$dt" "blastdbcmd-failed" >> "${outdir}/.extract_status.tsv"; return 0; }
    local n; n=$(grep -c '^>' "$out_fa")
    printf '%s\t%s\t%d\n' "$code" "$dt" "$n" >> "${outdir}/.extract_status.tsv"
}

export -f extract_one mg_log mg_die
export outdir log cache MG_BLAST_AA MG_BLAST_MRNA

: > "${outdir}/.extract_status.tsv"

# Fan out with xargs for simple parallelism
while read -r code; do
    [[ -z "$code" || "$code" =~ ^# ]] && continue
    case "$dbtype" in
        aa)   echo "$code aa" ;;
        mrna) echo "$code mrna" ;;
        both) echo "$code aa"; echo "$code mrna" ;;
    esac
done < "$codes_file" \
    | xargs -n 2 -P "$threads" bash -c 'extract_one "$1" "$2"' --

# Build extracted_species.tsv
python3 - "$metadata_tsv" "${outdir}/.extract_status.tsv" > "${outdir}/extracted_species.tsv" <<'PY'
import csv, sys
from collections import defaultdict
meta_path, status_path = sys.argv[1], sys.argv[2]
meta = {}
with open(meta_path) as f:
    for r in csv.DictReader(f, delimiter="\t"):
        meta[r["species_code"]] = r
counts = defaultdict(lambda: {"aa": 0, "mrna": 0})
with open(status_path) as f:
    for line in f:
        parts = line.rstrip("\n").split("\t")
        if len(parts) != 3: continue
        code, dt, v = parts
        try: counts[code][dt] = int(v)
        except ValueError: counts[code][dt] = 0
out_cols = ["species_code","species_binomial","class","order","family","n_aa_extracted","n_mrna_extracted"]
print("\t".join(out_cols))
for code in sorted(counts):
    m = meta.get(code, {})
    print("\t".join([code, m.get("species_binomial",""), m.get("class",""),
                     m.get("order",""), m.get("family",""),
                     str(counts[code]["aa"]), str(counts[code]["mrna"])]))
PY

# Optional merge. Snapshot the per-species file list into an array BEFORE writing the
# merged output — otherwise the destination filename (extracted_aa.fa) matches the same
# *_aa.fa glob and rm wipes the merged result along with the per-species files.
shopt -s nullglob
if [[ "$merge" == "yes" ]]; then
    if [[ "$dbtype" == "aa" || "$dbtype" == "both" ]]; then
        local_files=( "${outdir}"/*_aa.fa )
        if (( ${#local_files[@]} > 0 )); then
            cat "${local_files[@]}" > "${outdir}/extracted_aa.fa"
            rm -f "${local_files[@]}"
            mg_log "$log" "merged ${#local_files[@]} protein FASTAs into extracted_aa.fa"
        else
            mg_log "$log" "no protein FASTAs to merge"
        fi
    fi
    if [[ "$dbtype" == "mrna" || "$dbtype" == "both" ]]; then
        local_files=( "${outdir}"/*_mrna.fa )
        if (( ${#local_files[@]} > 0 )); then
            cat "${local_files[@]}" > "${outdir}/extracted_mrna.fa"
            rm -f "${local_files[@]}"
            mg_log "$log" "merged ${#local_files[@]} mRNA FASTAs into extracted_mrna.fa"
        else
            mg_log "$log" "no mRNA FASTAs to merge"
        fi
    fi
fi
shopt -u nullglob

rm -f "${outdir}/.selector_codes.txt" "${outdir}/.extract_status.tsv"
mg_log "$log" "done. see extracted_species.tsv for counts."
echo "$outdir/extracted_species.tsv"
