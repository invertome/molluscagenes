# Shared helpers for MolluscaGenes wrappers. Sourced, not executed.
# Provides:
#   mg_load_config          source config.sh from the usual places
#   mg_die "msg"            print to stderr and exit 1
#   mg_require "tool"       abort if a CLI tool is missing
#   mg_sentinel_done "path" sentinel check (is_done / mark_done)
#   mg_log "path" "msg"     append a timestamped line to a run log
#   mg_log_versions "path"  dump versions of listed CLI tools
#   mg_join_species stdin   join a tsv by sseqid column to species_metadata.tsv

mg_die() { echo "error: $*" >&2; exit 1; }

mg_require() {
    for t in "$@"; do
        command -v "$t" >/dev/null 2>&1 || mg_die "required tool not found on PATH: $t"
    done
}

mg_load_config() {
    # Priority: caller-set $MG_CONFIG, then ./config.sh, then repo-root config.sh.
    local candidates=()
    [[ -n "${MG_CONFIG:-}" ]] && candidates+=("$MG_CONFIG")
    candidates+=("./config.sh")
    # Locate repo root from this file's path (../ relative to wrappers/)
    local self_dir
    self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    candidates+=("${self_dir}/../config.sh")
    for c in "${candidates[@]}"; do
        if [[ -f "$c" ]]; then
            # shellcheck disable=SC1090
            source "$c"
            export MG_CONFIG="$c"
            return 0
        fi
    done
    mg_die "no config.sh found. Copy config.sh.template to config.sh and edit paths."
}

mg_sentinel_path() { echo "${1}/.done"; }

mg_is_done() {
    local outdir="$1"
    [[ -f "$(mg_sentinel_path "$outdir")" ]]
}

mg_mark_done() {
    local outdir="$1"
    date -u +%Y-%m-%dT%H:%M:%SZ > "$(mg_sentinel_path "$outdir")"
}

mg_log() {
    local logpath="$1"; shift
    printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$logpath"
}

mg_log_versions() {
    local logpath="$1"; shift
    {
        echo "--- tool versions ($(date -u +%Y-%m-%dT%H:%M:%SZ)) ---"
        for t in "$@"; do
            if ! command -v "$t" >/dev/null 2>&1; then
                echo "$t: MISSING"; continue
            fi
            local v
            v=$("$t" --version 2>/dev/null | head -1) \
                || v=$("$t" -version 2>/dev/null | head -1) \
                || v=$("$t" -h 2>&1 | grep -Ei '^#? ?HMMER|^#? ?[0-9]+\.[0-9]+' | head -1) \
                || v="(version probe failed)"
            echo "$t: ${v:-(unknown)}"
        done
    } >> "$logpath"
}

# Read a tab-separated stream on stdin; augment with species metadata columns.
# Arguments:
#   $1  path to species_metadata.tsv
#   $2  0-based index of the sseqid column in the input stream
# Writes augmented TSV to stdout with appended columns:
#   species_code  species_binomial  class  order  family  phylum
# sseqid is split on literal "EVm" to recover the species code.
mg_join_species() {
    local metadata="$1"
    local sseqid_col="$2"
    local repo_root
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    python3 "${repo_root}/scripts/_join_species.py" "$metadata" "$sseqid_col"
}
