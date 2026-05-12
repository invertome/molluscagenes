# wrappers/_taxon_filter.sh -- taxon resolution + subset-DB cache key.
# Sourced (not executed) by search wrappers.
#
# Public functions:
#   resolve_taxon_filter <value> [<metadata-tsv>]
#     Sets TAXON_SPECIES_CODES (bash array), TAXON_RESOLVED_RANK (string),
#     TAXON_RAW_VALUE (string). Exits non-zero with a stderr message on
#     no-match or ambiguous match. Accepts plain values, comma-lists (union),
#     and the rank:value escape hatch.
#
#   taxon_cache_key
#     Sets TAXON_KEY = "<prefix>_<sha1[0:12]>" where prefix encodes the
#     resolved rank + sanitized value (for taxonomic ranks) or 'union_' for
#     mixed-rank comma-lists or 'species_' for binomial/code lookups. The
#     hash is over the sorted-unique species_codes, so different inputs that
#     resolve to the same set collapse to the same cache entry.

# Column layout in species_metadata.tsv (1-indexed, awk style):
#   1=species_code  2=species_binomial  3=ncbi_taxid  4=phylum
#   5=class         6=subclass          7=order       8=family
#   9..18: ids, counts, source, citation, marine flag
#
# Auto-detect priority (within Mollusca, phylum is uninformative):
#   class -> subclass -> order -> family -> species_binomial -> species_code.

resolve_taxon_filter() {
    local value="$1"
    local meta="${2:-}"
    if [[ -z "$meta" ]]; then
        if [[ -z "${MG_METADATA:-}" ]]; then
            echo "taxon-filter: MG_METADATA not set and no metadata path passed" >&2
            return 1
        fi
        meta="${MG_METADATA}/species_metadata.tsv"
    fi
    [[ -f "$meta" ]] || { echo "taxon-filter: metadata not found at $meta" >&2; return 1; }

    # Capture the raw user input for taxon_cache_key's human-readable prefix.
    TAXON_RAW_VALUE="$value"

    # Comma-list: union of per-token resolutions. Recurse with default IFS.
    # Comma-lists always mark rank as 'mixed' even when every token happens to
    # resolve to the same rank -- the union semantics is what matters for the
    # downstream cache-key prefix ('union_'), not which rank the tokens came from.
    if [[ "$value" == *,* ]]; then
        local acc_codes=() token
        local tokens=()
        IFS=',' read -r -a tokens <<< "$value"
        for token in "${tokens[@]}"; do
            # Strip surrounding whitespace.
            token="${token#"${token%%[![:space:]]*}"}"
            token="${token%"${token##*[![:space:]]}"}"
            [[ -z "$token" ]] && continue
            resolve_taxon_filter "$token" "$meta" || return 1
            acc_codes+=( "${TAXON_SPECIES_CODES[@]}" )
        done
        mapfile -t TAXON_SPECIES_CODES < <(printf '%s\n' "${acc_codes[@]}" | LC_ALL=C sort -u)
        TAXON_RESOLVED_RANK="mixed"
        # Restore top-level raw value (recursion clobbered it).
        TAXON_RAW_VALUE="$value"
        return 0
    fi

    # rank:value escape hatch -- restrict the awk scan to just that column.
    local pinned_rank=""
    if [[ "$value" == *:* ]]; then
        pinned_rank="${value%%:*}"
        value="${value#*:}"
        case "$pinned_rank" in
            class|subclass|order|family|species_binomial|species_code) ;;
            *) echo "taxon-filter: unknown rank '$pinned_rank' in 'rank:value' form" >&2; return 1 ;;
        esac
    fi

    # Single awk pass: scan columns in priority order; first hit per row wins.
    # When pinned_rank is set, only that column is checked.
    local raw
    raw=$(awk -F'\t' -v val="$value" -v pinned="$pinned_rank" '
        function lc(s) { return tolower(s) }
        function hit(rank, col) {
            if (lc($col) == lc(val) && $col != "") { print rank "\t" $1; return 1 }
            return 0
        }
        NR==1 { next }
        {
            if (pinned != "") {
                if      (pinned == "class")            hit("class", 5)
                else if (pinned == "subclass")         hit("subclass", 6)
                else if (pinned == "order")            hit("order", 7)
                else if (pinned == "family")           hit("family", 8)
                else if (pinned == "species_binomial") hit("species_binomial", 2)
                else if (pinned == "species_code")     hit("species_code", 1)
                next
            }
            if (hit("class", 5))            next
            if (hit("subclass", 6))         next
            if (hit("order", 7))            next
            if (hit("family", 8))           next
            if (hit("species_binomial", 2)) next
            hit("species_code", 1)
        }
    ' "$meta")

    if [[ -z "$raw" ]]; then
        echo "taxon-filter: no species matches '$value'." >&2
        return 1
    fi

    # Detect ambiguity: same value matched under multiple ranks.
    local ranks
    ranks=$(printf '%s\n' "$raw" | cut -f1 | LC_ALL=C sort -u)
    if [[ $(printf '%s\n' "$ranks" | wc -l) -gt 1 ]]; then
        echo "taxon-filter: ambiguous taxon '$value': matches ranks $(echo "$ranks" | tr '\n' ' ')." >&2
        echo "  Disambiguate with rank:value (e.g. --taxon-filter class:$value)." >&2
        return 1
    fi
    TAXON_RESOLVED_RANK="$ranks"

    # Deduplicated + sorted codes -> deterministic cache key downstream.
    mapfile -t TAXON_SPECIES_CODES < <(printf '%s\n' "$raw" | cut -f2 | LC_ALL=C sort -u)
    return 0
}

taxon_cache_key() {
    # Requires resolve_taxon_filter to have run first.
    if [[ -z "${TAXON_SPECIES_CODES[*]:-}" ]]; then
        echo "taxon_cache_key: call resolve_taxon_filter first" >&2
        return 1
    fi

    local hash prefix value_part
    # Hash over sorted-unique species_codes -> reproducible across input forms.
    hash=$(printf '%s\n' "${TAXON_SPECIES_CODES[@]}" | LC_ALL=C sort -u | sha1sum | cut -c1-12)

    case "${TAXON_RESOLVED_RANK:-}" in
        class|subclass|order|family)
            # rank:value escape collapses to the same key as the plain form,
            # so strip any leading "<rank>:" from the raw value before encoding.
            value_part="${TAXON_RAW_VALUE#*:}"
            # If there was no colon, the strip is a no-op; if there was, we
            # keep only the value portion.
            [[ "$TAXON_RAW_VALUE" == *:* ]] || value_part="$TAXON_RAW_VALUE"
            prefix="${TAXON_RESOLVED_RANK}_${value_part}_"
            ;;
        species_binomial|species_code)
            prefix="species_"
            ;;
        mixed)
            prefix="union_"
            ;;
        *)
            prefix="taxon_"
            ;;
    esac

    # Sanitize: replace spaces and slashes with underscores so the key is a
    # safe path component.
    prefix=$(printf '%s' "$prefix" | tr ' /' '__')
    TAXON_KEY="${prefix}${hash}"
}

# ensure_subset_db <format> <kind>
#   format: fasta | blast | diamond
#   kind:   aa | mrna
# Pre-conditions:
#   - resolve_taxon_filter + taxon_cache_key must have already run (so
#     TAXON_SPECIES_CODES + TAXON_KEY are populated).
#   - MG_BLAST_AA / MG_BLAST_MRNA / MG_METADATA must be set (source config.sh).
# Side effects:
#   - Builds (or reuses) a per-taxon subset FASTA at
#       <cache_root>/<TAXON_KEY>/<kind>/subset.fa
#     and, for format=blast|diamond, builds the corresponding sibling index
#     files alongside the FASTA. Writes provenance (manifest.json, species.tsv,
#     species.txt) under <cache_root>/<TAXON_KEY>/.
#   - Sets SUBSET_DB_PATH to the FASTA path (BLAST + DIAMOND both accept the
#     basename and pick up sibling .phr/.dmnd files automatically).
# Returns 0 on success; nonzero with a stderr message on bad args, missing
# config, empty extraction, or builder failure.
ensure_subset_db() {
    local format="${1:-}" kind="${2:-}"

    # --- Validate args
    case "$format" in
        fasta|blast|diamond) ;;
        *) echo "ensure_subset_db: format must be fasta|blast|diamond (got '${format}')" >&2; return 2 ;;
    esac
    case "$kind" in
        aa|mrna) ;;
        *) echo "ensure_subset_db: kind must be aa|mrna (got '${kind}')" >&2; return 2 ;;
    esac

    # --- Validate preconditions from earlier steps
    if [[ -z "${TAXON_KEY:-}" ]]; then
        echo "ensure_subset_db: TAXON_KEY unset (run resolve_taxon_filter + taxon_cache_key first)" >&2
        return 2
    fi
    if [[ -z "${TAXON_SPECIES_CODES[*]:-}" ]]; then
        echo "ensure_subset_db: TAXON_SPECIES_CODES is empty" >&2
        return 2
    fi
    if [[ -z "${MG_METADATA:-}" ]]; then
        echo "ensure_subset_db: MG_METADATA not set (source config.sh first)" >&2
        return 2
    fi

    # --- Validate source-DB env per kind
    local source_db source_ext
    case "$kind" in
        aa)
            source_db="${MG_BLAST_AA:-}"; source_ext="psq"
            [[ -n "$source_db" ]] || { echo "ensure_subset_db: MG_BLAST_AA not set" >&2; return 2; }
            ;;
        mrna)
            source_db="${MG_BLAST_MRNA:-}"; source_ext="nsq"
            [[ -n "$source_db" ]] || { echo "ensure_subset_db: MG_BLAST_MRNA not set" >&2; return 2; }
            ;;
    esac

    # --- Cache layout
    local root key_dir subset_dir fasta lockfile manifest
    root="${MG_TAXON_CACHE_ROOT:-${MG_METADATA}/_cache/subset_dbs}"
    key_dir="${root}/${TAXON_KEY}"
    subset_dir="${key_dir}/${kind}"
    fasta="${subset_dir}/subset.fa"
    lockfile="${key_dir}/.lock"
    manifest="${key_dir}/manifest.json"
    mkdir -p "$subset_dir" || { echo "ensure_subset_db: cannot mkdir $subset_dir" >&2; return 1; }

    # --- Concurrency lock (single builder per taxon-key)
    # Lock fd is closed automatically on any return via trap RETURN, so every
    # error path below is just `return 1` without manual `exec {lock_fd}>&-`.
    local lock_fd=""
    _taxon_unlock() { [[ -n "$lock_fd" ]] && exec {lock_fd}>&-; lock_fd=""; }
    trap _taxon_unlock RETURN
    exec {lock_fd}> "$lockfile" || { echo "ensure_subset_db: cannot open lockfile $lockfile" >&2; return 1; }
    if ! flock "$lock_fd"; then
        echo "ensure_subset_db: failed to acquire flock on $lockfile" >&2
        return 1
    fi

    # --- Source-DB fingerprint (for cache invalidation)
    # Single-volume layout: ${source_db}.${source_ext}
    # Multi-volume layout: ${source_db}.00.${source_ext}, .01., ... + a ${source_db}.[pn]al alias file.
    local src_hash="" src_single="${source_db}.${source_ext}" src_vol0="${source_db}.00.${source_ext}"
    if [[ -f "$src_single" ]]; then
        src_hash=$(sha256sum "$src_single" | awk '{print $1}')
    elif [[ -f "$src_vol0" ]]; then
        # Hash just the first volume — cheap fingerprint, change in any later volume
        # is fine for our purposes (it'd reflect a bundle update, which is rare).
        src_hash=$(sha256sum "$src_vol0" | awk '{print $1}')
    else
        echo "ensure_subset_db: source DB volumes not found at ${src_single} nor ${src_vol0}" >&2
        return 1
    fi
    # Take leading 64 hex chars (sha256 is already 64; defensive trim)
    src_hash="${src_hash:0:64}"
    # Validate hash format — sha256sum may print empty on a missing/unreadable file even if -f passed (race).
    if [[ -z "$src_hash" || ${#src_hash} -ne 64 ]]; then
        echo "ensure_subset_db: failed to compute source-DB hash for $kind (file=$src_single, hash='$src_hash')" >&2
        return 1
    fi

    # --- Decide rebuild vs reuse
    local need_build="no" stored_hash=""
    if [[ -s "$fasta" && -s "$manifest" ]]; then
        stored_hash=$(jq -r --arg k "$kind" '.source_db_hash[$k] // ""' "$manifest" 2>/dev/null || true)
        if [[ "$stored_hash" != "$src_hash" ]]; then
            need_build="yes"
        fi
    else
        need_build="yes"
    fi

    if [[ "$need_build" == "yes" ]]; then
        # --- Stage species codes for mg_extract
        local codes_file="${subset_dir}/.species_codes.txt"
        printf '%s\n' "${TAXON_SPECIES_CODES[@]}" > "$codes_file"

        # --- Delegate extraction to mg_extract.sh
        # mg_extract.sh sources its own config via mg_load_config, so we just
        # need a clean workdir under our subset_dir.
        local extract_workdir="${subset_dir}/.extract_workdir"
        rm -rf "$extract_workdir"
        # Diagnostic log — not a dotfile so `ls` shows it. Retained on failure for inspection.
        local stderr_log="${subset_dir}/extract_stderr.log"
        local mg_extract_sh
        mg_extract_sh="$(dirname "${BASH_SOURCE[0]}")/mg_extract.sh"
        if ! bash "$mg_extract_sh" \
                -s "@${codes_file}" --by code \
                -o "$extract_workdir" -d "$kind" --merge \
                >/dev/null 2>"$stderr_log"; then
            echo "ensure_subset_db: mg_extract.sh failed for ${TAXON_KEY}/${kind}; see ${stderr_log}" >&2
            [[ -s "$stderr_log" ]] && sed 's/^/  /' "$stderr_log" >&2
            return 1
        fi

        local merged_src="${extract_workdir}/extracted_${kind}.fa"
        if [[ ! -s "$merged_src" ]]; then
            echo "ensure_subset_db: extraction produced empty FASTA for ${TAXON_KEY}/${kind}; see ${stderr_log}" >&2
            return 1
        fi

        # --- Atomic FASTA placement (C1)
        # Order matters: stage under .new -> invalidate siblings -> atomic rename -> manifest.
        # This ensures no reader ever sees a fresh FASTA paired with stale sibling indexes
        # or with a manifest still describing the previous build.
        mv "$merged_src" "${fasta}.new" || { echo "ensure_subset_db: failed to stage ${fasta}.new" >&2; return 1; }
        # Remove all subset.fa.* siblings (BLAST + DIAMOND indexes + alias files) but keep subset.fa.
        # Glob requires >=1 char after the dot, so subset.fa itself is preserved.
        # Also clears any leftover .new from a prior aborted call.
        find "${subset_dir}" -maxdepth 1 -name 'subset.fa.*' ! -name 'subset.fa.new' -exec rm -f {} +
        mv "${fasta}.new" "$fasta" || { echo "ensure_subset_db: failed to rename ${fasta}.new -> ${fasta}" >&2; return 1; }

        if [[ -f "${extract_workdir}/extracted_species.tsv" ]]; then
            cp "${extract_workdir}/extracted_species.tsv" "${key_dir}/species.tsv"
        fi
        # Keep the resolved species code list for human inspection / debugging
        cp "$codes_file" "${key_dir}/species.txt"
        rm -f "$codes_file" "$stderr_log"
        rm -rf "$extract_workdir"

        # --- Manifest write/merge (jq, atomic via tmp + mv)
        local now n_seqs codes_json
        now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        n_seqs=$(grep -c '^>' "$fasta" || true)
        codes_json=$(printf '%s\n' "${TAXON_SPECIES_CODES[@]}" | jq -R . | jq -s .)
        if [[ -s "$manifest" ]]; then
            jq --arg k "$kind" --arg h "$src_hash" --arg ts "$now" --argjson n "$n_seqs" \
               '.source_db_hash[$k]=$h | .n_seqs[$k]=$n | .built_at[$k]=$ts' \
               "$manifest" > "${manifest}.tmp" \
                && mv "${manifest}.tmp" "$manifest"
        else
            TAXON_KEY="$TAXON_KEY" jq -n \
                --arg key "$TAXON_KEY" \
                --arg k "$kind" --arg h "$src_hash" --arg ts "$now" \
                --argjson n "$n_seqs" --argjson codes "$codes_json" \
                '{
                    key:           $key,
                    n_species:     ($codes | length),
                    source_db_hash: { ($k): $h },
                    n_seqs:         { ($k): $n },
                    built_at:       { ($k): $ts },
                    species_codes:  $codes
                 }' > "$manifest"
        fi
    fi

    # --- Format dispatch: build the requested index alongside the FASTA
    case "$format" in
        fasta)
            SUBSET_DB_PATH="$fasta"
            ;;
        blast)
            local need_blast="no"
            case "$kind" in
                aa)
                    [[ -f "${fasta}.phr" || -f "${fasta}.00.phr" ]] || need_blast="yes" ;;
                mrna)
                    [[ -f "${fasta}.nhr" || -f "${fasta}.00.nhr" ]] || need_blast="yes" ;;
            esac
            if [[ "$need_blast" == "yes" ]]; then
                local dtype mb_log="${subset_dir}/makeblastdb.log"
                case "$kind" in aa) dtype="prot" ;; mrna) dtype="nucl" ;; esac
                if ! makeblastdb -in "$fasta" -dbtype "$dtype" -parse_seqids \
                        >/dev/null 2>"$mb_log"; then
                    echo "ensure_subset_db: makeblastdb failed for $fasta; see $mb_log" >&2
                    [[ -s "$mb_log" ]] && sed 's/^/  /' "$mb_log" >&2
                    return 1
                fi
                rm -f "$mb_log"
            fi
            # BLAST accepts the bare basename; sibling .phr/.psq/.pin are auto-detected.
            SUBSET_DB_PATH="$fasta"
            ;;
        diamond)
            local dmnd="${fasta}.dmnd" dm_log="${subset_dir}/diamond.log"
            if [[ ! -s "$dmnd" ]]; then
                if ! diamond makedb --in "$fasta" -d "$fasta" \
                        >/dev/null 2>"$dm_log"; then
                    echo "ensure_subset_db: diamond makedb failed for $fasta; see $dm_log" >&2
                    [[ -s "$dm_log" ]] && sed 's/^/  /' "$dm_log" >&2
                    return 1
                fi
                rm -f "$dm_log"
            fi
            # DIAMOND accepts the basename (it tries <db>.dmnd) or the explicit .dmnd path.
            SUBSET_DB_PATH="$fasta"
            ;;
    esac

    # Lock is released by `trap _taxon_unlock RETURN` on the return below.
    return 0
}
