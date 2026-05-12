#!/usr/bin/env bash
# scripts/test_taxon_filter.sh - unit tests for wrappers/_taxon_filter.sh
# Usage: bash scripts/test_taxon_filter.sh                # unit tests only
#        MOLLUSCAGENES_INTEGRATION=1 bash ...             # also run integration tests
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "${here}/.." && pwd)"
fixture="${here}/_test_fixtures/species_metadata_mini.tsv"
helper="${repo}/wrappers/_taxon_filter.sh"

PASS=0; FAIL=0
red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
assert_eq() {  # $1=expected $2=actual $3=label
    if [[ "$1" == "$2" ]]; then PASS=$((PASS+1)); green "PASS $3"
    else FAIL=$((FAIL+1)); red "FAIL $3 expected=<$1> actual=<$2>"; fi
}
assert_contains() {  # $1=needle $2=haystack $3=label
    if [[ "$2" == *"$1"* ]]; then PASS=$((PASS+1)); green "PASS $3"
    else FAIL=$((FAIL+1)); red "FAIL $3 needle=<$1> haystack=<$2>"; fi
}
assert_nonzero_exit() {  # $1=cmd $2=label
    if eval "$1" >/dev/null 2>&1; then FAIL=$((FAIL+1)); red "FAIL $2 expected nonzero exit"
    else PASS=$((PASS+1)); green "PASS $2"; fi
}

# --- Task 1: class lookup ---
unset TAXON_SPECIES_CODES TAXON_KEY TAXON_RESOLVED_RANK TAXON_RAW_VALUE
# shellcheck source=/dev/null
source "$helper"
resolve_taxon_filter "Gastropoda" "$fixture"
assert_eq "4"     "${#TAXON_SPECIES_CODES[@]}" "T1.class: 4 Gastropoda codes resolved"
assert_eq "class" "$TAXON_RESOLVED_RANK"       "T1.class: rank=class"

# --- Task 2: family, binomial, code, comma-union, rank:value ---
unset TAXON_SPECIES_CODES TAXON_KEY TAXON_RESOLVED_RANK TAXON_RAW_VALUE
resolve_taxon_filter "Octopodidae" "$fixture"
assert_eq "family" "$TAXON_RESOLVED_RANK"       "T2.family: rank=family"
assert_eq "3"      "${#TAXON_SPECIES_CODES[@]}" "T2.family: 3 Octopodidae codes"

unset TAXON_SPECIES_CODES TAXON_KEY TAXON_RESOLVED_RANK TAXON_RAW_VALUE
resolve_taxon_filter "Octopus bimaculoides" "$fixture"
assert_eq "species_binomial" "$TAXON_RESOLVED_RANK"       "T2.binomial: rank=species_binomial"
assert_eq "1"                "${#TAXON_SPECIES_CODES[@]}" "T2.binomial: 1 code"
assert_eq "Octbim"           "${TAXON_SPECIES_CODES[0]}"  "T2.binomial: code=Octbim"

unset TAXON_SPECIES_CODES TAXON_KEY TAXON_RESOLVED_RANK TAXON_RAW_VALUE
resolve_taxon_filter "Octbim" "$fixture"
assert_eq "species_code" "$TAXON_RESOLVED_RANK"       "T2.code: rank=species_code"
assert_eq "1"            "${#TAXON_SPECIES_CODES[@]}" "T2.code: 1 code"

unset TAXON_SPECIES_CODES TAXON_KEY TAXON_RESOLVED_RANK TAXON_RAW_VALUE
resolve_taxon_filter "Cephalopoda,Bivalvia" "$fixture"
assert_eq "7" "${#TAXON_SPECIES_CODES[@]}" "T2.union: 7 codes (4 ceph + 3 biv)"

unset TAXON_SPECIES_CODES TAXON_KEY TAXON_RESOLVED_RANK TAXON_RAW_VALUE
resolve_taxon_filter "class:Gastropoda" "$fixture"
assert_eq "4"     "${#TAXON_SPECIES_CODES[@]}" "T2.rankvalue: 4 codes (escape hatch)"
assert_eq "class" "$TAXON_RESOLVED_RANK"       "T2.rankvalue: rank=class"

# --- Task 3: no-match + ambiguity ---
assert_nonzero_exit "source $helper; resolve_taxon_filter 'NotARealTaxon' '$fixture'" "T3.nomatch: exits nonzero"
err=$( (source "$helper"; resolve_taxon_filter "NotARealTaxon" "$fixture") 2>&1 || true )
assert_contains "no species matches" "$err" "T3.nomatch: stderr message"

# Ambiguity: synthesize a fixture where 'Conida' appears as both an order and a family.
amb_fixture="${here}/_test_fixtures/species_metadata_ambig.tsv"
cp "$fixture" "$amb_fixture"
# Take an existing data row (NR==2), produce two copies: one with col 7 (order)=Conida,
# one with col 8 (family)=Conida. Use distinct species_codes so they're not deduped.
awk -F'\t' 'BEGIN{OFS="\t"} NR==2 {
    a=$0; $1="Synth01"; $7="Conida"; $8="SynthFamA"; print
    $0=a; $1="Synth02"; $7="SynthOrdB"; $8="Conida"; print
}' "$fixture" >> "$amb_fixture"
err=$( (source "$helper"; resolve_taxon_filter "Conida" "$amb_fixture") 2>&1 || true )
assert_contains "ambiguous" "$err" "T3.ambig: stderr says 'ambiguous'"
assert_nonzero_exit "source $helper; resolve_taxon_filter 'Conida' '$amb_fixture'" "T3.ambig: exits nonzero"
rm -f "$amb_fixture"

# --- Task 3b: edge cases (case-insensitive, empty value, missing metadata, unknown rank) ---
# Case-insensitive: lowercase 'gastropoda' should still resolve to 4 codes / rank=class.
unset TAXON_SPECIES_CODES TAXON_KEY TAXON_RESOLVED_RANK TAXON_RAW_VALUE
resolve_taxon_filter "gastropoda" "$fixture"
assert_eq "4"     "${#TAXON_SPECIES_CODES[@]}" "T3b.case: lowercase 'gastropoda' resolves to 4 codes"
assert_eq "class" "$TAXON_RESOLVED_RANK"       "T3b.case: lowercase rank=class"

# Empty value: should exit nonzero with stderr (currently emits "no species matches ''").
assert_nonzero_exit "source $helper; resolve_taxon_filter '' '$fixture'" "T3b.empty: exits nonzero"
err=$( (source "$helper"; resolve_taxon_filter "" "$fixture") 2>&1 || true )
assert_contains "no species matches" "$err" "T3b.empty: stderr message"

# Missing metadata file: should exit nonzero with "metadata not found" in stderr.
assert_nonzero_exit "source $helper; resolve_taxon_filter 'Gastropoda' '/nonexistent/path.tsv'" "T3b.missing: exits nonzero"
err=$( (source "$helper"; resolve_taxon_filter "Gastropoda" "/nonexistent/path.tsv") 2>&1 || true )
assert_contains "metadata not found" "$err" "T3b.missing: stderr mentions 'metadata not found'"

# Unknown rank in escape hatch: should exit nonzero with rank-related stderr.
assert_nonzero_exit "source $helper; resolve_taxon_filter 'fakerank:Foo' '$fixture'" "T3b.unkrank: exits nonzero"
err=$( (source "$helper"; resolve_taxon_filter "fakerank:Foo" "$fixture") 2>&1 || true )
assert_contains "unknown rank" "$err" "T3b.unkrank: stderr mentions 'unknown rank'"

# --- Task 4: taxon_cache_key ---
unset TAXON_SPECIES_CODES TAXON_KEY TAXON_RESOLVED_RANK TAXON_RAW_VALUE
resolve_taxon_filter "Gastropoda" "$fixture"
taxon_cache_key
assert_contains "class_Gastropoda_" "$TAXON_KEY" "T4.key: prefix encodes rank+value"

# Same resolved set => same key regardless of input form (escape hatch collapses to same entry)
key1="$TAXON_KEY"
unset TAXON_SPECIES_CODES TAXON_KEY TAXON_RESOLVED_RANK TAXON_RAW_VALUE
resolve_taxon_filter "class:Gastropoda" "$fixture"
taxon_cache_key
assert_eq "$key1" "$TAXON_KEY" "T4.key: stable across input forms (Gastropoda == class:Gastropoda)"

# Union => 'union_' prefix
unset TAXON_SPECIES_CODES TAXON_KEY TAXON_RESOLVED_RANK TAXON_RAW_VALUE
resolve_taxon_filter "Cephalopoda,Bivalvia" "$fixture"
taxon_cache_key
assert_contains "union_" "$TAXON_KEY" "T4.key: comma-list uses union_ prefix"

# Key has exactly 12 trailing hex chars (sha1[0:12])
last12="${TAXON_KEY##*_}"
if [[ "$last12" =~ ^[0-9a-f]{12}$ ]]; then
    PASS=$((PASS+1)); green "PASS T4.key: trailing 12 hex chars"
else
    FAIL=$((FAIL+1)); red "FAIL T4.key: trailing token=<$last12> not 12 hex chars"
fi

# Reproducibility: same input twice => same key
unset TAXON_SPECIES_CODES TAXON_KEY TAXON_RESOLVED_RANK TAXON_RAW_VALUE
resolve_taxon_filter "Cephalopoda,Bivalvia" "$fixture"
taxon_cache_key
k_a="$TAXON_KEY"
unset TAXON_SPECIES_CODES TAXON_KEY TAXON_RESOLVED_RANK TAXON_RAW_VALUE
resolve_taxon_filter "Cephalopoda,Bivalvia" "$fixture"
taxon_cache_key
assert_eq "$k_a" "$TAXON_KEY" "T4.key: reproducible across runs"

# === T7.help / T8.help / T9.help / T10.help: --taxon-filter in --help output ===
# These are cheap unit-level assertions: --help doesn't need a real DB, so they
# run unconditionally (not gated on MOLLUSCAGENES_INTEGRATION).
help_blast=$(bash "${repo}/wrappers/mg_blast.sh" --help 2>&1 || true)
help_diamond=$(bash "${repo}/wrappers/mg_diamond.sh" --help 2>&1 || true)
help_hmmsearch=$(bash "${repo}/wrappers/mg_hmmsearch.sh" --help 2>&1 || true)
help_characterize=$(bash "${repo}/wrappers/mg_characterize.sh" --help 2>&1 || true)
assert_contains "--taxon-filter" "$help_blast"       "T7.help: mg_blast --help shows --taxon-filter"
assert_contains "--taxon-filter" "$help_diamond"     "T8.help: mg_diamond --help shows --taxon-filter"
assert_contains "--taxon-filter" "$help_hmmsearch"   "T9.help: mg_hmmsearch --help shows --taxon-filter"
assert_contains "--taxon-filter" "$help_characterize" "T10.help: mg_characterize --help shows --taxon-filter"

# --- Tasks 5 & 6: ensure_subset_db (integration-gated) ---
# Requires a real BLAST database bundle on disk. Skipped by default; opt in with
# MOLLUSCAGENES_INTEGRATION=1.
if [[ "${MOLLUSCAGENES_INTEGRATION:-0}" == "1" ]]; then
    if [[ ! -f "${repo}/config.sh" ]]; then
        echo "[integration] config.sh missing at ${repo}/config.sh -- skipping ensure_subset_db tests" >&2
    else
        # shellcheck source=/dev/null
        source "${repo}/config.sh"

        # --- T5: FASTA build via mg_extract --------------------------------
        tmpdir=$(mktemp -d)
        unset TAXON_SPECIES_CODES TAXON_KEY TAXON_RESOLVED_RANK TAXON_RAW_VALUE SUBSET_DB_PATH
        resolve_taxon_filter "Scaphopoda" "${MG_METADATA}/species_metadata.tsv"
        taxon_cache_key
        MG_TAXON_CACHE_ROOT="$tmpdir" ensure_subset_db fasta aa
        rc=$?
        assert_eq "0" "$rc" "T5.fasta: ensure_subset_db exit 0"
        if [[ -s "${SUBSET_DB_PATH:-/dev/null}" ]]; then
            PASS=$((PASS+1)); green "PASS T5.fasta: subset.fa nonzero"
        else
            FAIL=$((FAIL+1)); red "FAIL T5.fasta: subset.fa missing or empty (path=${SUBSET_DB_PATH:-<unset>})"
        fi
        if [[ -s "$tmpdir/$TAXON_KEY/manifest.json" ]] && jq empty "$tmpdir/$TAXON_KEY/manifest.json" >/dev/null 2>&1; then
            PASS=$((PASS+1)); green "PASS T5.manifest: valid JSON"
        else
            FAIL=$((FAIL+1)); red "FAIL T5.manifest: missing or invalid at $tmpdir/$TAXON_KEY/manifest.json"
        fi

        # T5.fasta.deep (I4): FASTA starts with '>', has >0 sequences, and the
        # sequence count agrees with the manifest record. Catches: empty rebuild,
        # mid-rebuild crash leaving partial file, manifest/FASTA drift.
        first_char=$(head -c 1 "$SUBSET_DB_PATH")
        n_seqs=$(grep -c '^>' "$SUBSET_DB_PATH")
        manifest_n=$(jq -r '.n_seqs.aa // 0' "$tmpdir/$TAXON_KEY/manifest.json")
        if [[ "$first_char" == ">" && "$n_seqs" -gt 0 && "$n_seqs" == "$manifest_n" ]]; then
            PASS=$((PASS+1)); green "PASS T5.fasta.deep: valid FASTA, $n_seqs seqs, matches manifest"
        else
            FAIL=$((FAIL+1)); red "FAIL T5.fasta.deep: first=$first_char n=$n_seqs manifest=$manifest_n"
        fi
        rm -rf "$tmpdir"

        # --- T6: BLAST + DIAMOND formats, cache hit, invalidation ---------
        # Use a fresh tmpdir so T6 is independent of T5's artifacts.
        tmpdir=$(mktemp -d)
        unset TAXON_SPECIES_CODES TAXON_KEY TAXON_RESOLVED_RANK TAXON_RAW_VALUE SUBSET_DB_PATH
        resolve_taxon_filter "Scaphopoda" "${MG_METADATA}/species_metadata.tsv"
        taxon_cache_key

        # T6.blast: build BLAST DB on top of cached FASTA
        MG_TAXON_CACHE_ROOT="$tmpdir" ensure_subset_db blast aa
        # BLAST may emit .phr or .00.phr depending on input size; check both.
        blast_idx=$(ls "$tmpdir/$TAXON_KEY/aa/subset.fa".??r 2>/dev/null | head -1)
        if [[ -n "$blast_idx" && -s "$blast_idx" ]]; then
            PASS=$((PASS+1)); green "PASS T6.blast: BLAST index file present ($blast_idx)"
        else
            FAIL=$((FAIL+1)); red "FAIL T6.blast: no .phr / .nhr found under $tmpdir/$TAXON_KEY/aa/"
        fi

        # T6.diamond
        MG_TAXON_CACHE_ROOT="$tmpdir" ensure_subset_db diamond aa
        dmnd="$tmpdir/$TAXON_KEY/aa/subset.fa.dmnd"
        if [[ -s "$dmnd" ]]; then
            PASS=$((PASS+1)); green "PASS T6.diamond: .dmnd exists"
        else
            FAIL=$((FAIL+1)); red "FAIL T6.diamond: $dmnd missing"
        fi

        # T6.cache-hit (I5): on cache hit the FASTA is not moved, so inode
        # is unchanged. Inode is granularity-independent — no `sleep` needed.
        fasta="$tmpdir/$TAXON_KEY/aa/subset.fa"
        pre_inode=$(stat -c %i "$fasta")
        MG_TAXON_CACHE_ROOT="$tmpdir" ensure_subset_db fasta aa
        post_inode=$(stat -c %i "$fasta")
        assert_eq "$pre_inode" "$post_inode" "T6.cache: fasta inode unchanged on cache hit"

        # T6.invalidate: corrupt the manifest hash, expect rebuild.
        # Capture pre-tamper sequence count for the content-preservation check (I3).
        n_pre=$(grep -c '^>' "$fasta")
        post_mtime=$(stat -c %Y "$fasta")
        manifest="$tmpdir/$TAXON_KEY/manifest.json"
        jq '.source_db_hash.aa = "deadbeefdeadbeef"' "$manifest" > "$manifest.tmp" && mv "$manifest.tmp" "$manifest"
        sleep 1
        MG_TAXON_CACHE_ROOT="$tmpdir" ensure_subset_db fasta aa
        after=$(stat -c %Y "$fasta")
        if [[ "$after" -gt "$post_mtime" ]]; then
            PASS=$((PASS+1)); green "PASS T6.invalidate: rebuilt on hash mismatch"
        else
            FAIL=$((FAIL+1)); red "FAIL T6.invalidate: fasta not rebuilt (pre=$post_mtime after=$after)"
        fi

        # T6.invalidate.content (I3): rebuild produced the SAME sequence count,
        # not "any" content. Catches: rebuild silently extracting an empty set
        # or a truncated FASTA while still updating mtime/hash.
        n_post=$(grep -c '^>' "$fasta")
        if [[ "$n_pre" -gt 0 && "$n_pre" == "$n_post" ]]; then
            PASS=$((PASS+1)); green "PASS T6.invalidate.content: $n_pre seqs preserved"
        else
            FAIL=$((FAIL+1)); red "FAIL T6.invalidate.content: n_pre=$n_pre n_post=$n_post"
        fi

        # T6.mrna (I6): build mRNA subset DB to exercise the parallel code path
        # (source_ext=nsq, dtype=nucl, .nhr sibling). Scaphopoda mrna is ~220K
        # seqs so this is tractable in tests.
        MG_TAXON_CACHE_ROOT="$tmpdir" ensure_subset_db blast mrna
        rc=$?
        mrna_fasta="$tmpdir/$TAXON_KEY/mrna/subset.fa"
        mrna_nhr=$(ls "$mrna_fasta".??r 2>/dev/null | head -1)
        if [[ "$rc" -eq 0 && -s "$mrna_fasta" && -n "$mrna_nhr" && -s "$mrna_nhr" ]]; then
            PASS=$((PASS+1)); green "PASS T6.mrna: blast/mrna build with .nhr ($mrna_nhr)"
        else
            FAIL=$((FAIL+1)); red "FAIL T6.mrna: rc=$rc fasta=$mrna_fasta nhr=$mrna_nhr"
        fi

        # T7.manifest-merge (I7): aa was built into this TAXON_KEY first, then
        # mrna into the same key above — manifest must contain BOTH under
        # source_db_hash and n_seqs (merge, not overwrite).
        keys=$(jq -r '.source_db_hash | keys | join(",")' "$tmpdir/$TAXON_KEY/manifest.json")
        n_seqs_keys=$(jq -r '.n_seqs | keys | join(",")' "$tmpdir/$TAXON_KEY/manifest.json")
        if [[ "$keys" == "aa,mrna" && "$n_seqs_keys" == "aa,mrna" ]]; then
            PASS=$((PASS+1)); green "PASS T7.manifest-merge: source_db_hash + n_seqs both have aa and mrna"
        else
            FAIL=$((FAIL+1)); red "FAIL T7.manifest-merge: source_db_hash keys=$keys n_seqs keys=$n_seqs_keys"
        fi

        rm -rf "$tmpdir"

        # === T7.mg_blast: --taxon-filter wires through mg_blast end-to-end ===
        # Self-BLAST a Scaphopoda query (AntentEVm041426t1) against a
        # Scaphopoda-only subset DB. Verifies (a) wrapper exit 0, (b) the joined
        # hits file is populated, (c) every hit's class column == "Scaphopoda".
        # Column 18 in hits_with_species.tsv is `class` (15 BLAST outfmt 6 cols
        # + 3 prepended metadata cols: species_code, species_binomial, class).
        tinytmp=$(mktemp -d)
        blastdbcmd -db "$MG_BLAST_AA" -entry "AntentEVm041426t1" -outfmt "%f" \
            > "${tinytmp}/q.fa" 2>/dev/null \
            || blastdbcmd -db "$MG_BLAST_AA" -entry all -outfmt "%a" 2>/dev/null \
                | grep -m 1 '^Antent' \
                | xargs -I {} blastdbcmd -db "$MG_BLAST_AA" -entry {} -outfmt "%f" \
                    > "${tinytmp}/q.fa"
        if [[ ! -s "${tinytmp}/q.fa" ]]; then
            FAIL=$((FAIL+1)); red "FAIL T7.mg_blast: could not build query FASTA"
        else
            MG_TAXON_CACHE_ROOT="${tinytmp}/cache" \
                bash "${repo}/wrappers/mg_blast.sh" \
                    -q "${tinytmp}/q.fa" -o "${tinytmp}/out" -d aa \
                    --taxon-filter Scaphopoda -t 2 -e 1 \
                    > "${tinytmp}/stdout" 2>&1
            rc=$?
            if [[ "$rc" -eq 0 ]]; then
                PASS=$((PASS+1)); green "PASS T7.mg_blast.exit: rc=0"
            else
                FAIL=$((FAIL+1)); red "FAIL T7.mg_blast.exit: rc=$rc"
                cat "${tinytmp}/stdout"
            fi
            if [[ -s "${tinytmp}/out/hits_with_species.tsv" ]]; then
                PASS=$((PASS+1)); green "PASS T7.mg_blast.hits: hits file populated"
            else
                FAIL=$((FAIL+1)); red "FAIL T7.mg_blast.hits: empty or missing"
            fi
            # Class column = position 18 (15 BLAST + species_code, binomial, class).
            classes=$(cut -f18 "${tinytmp}/out/hits_with_species.tsv" 2>/dev/null | LC_ALL=C sort -u)
            if [[ "$classes" == "Scaphopoda" ]]; then
                PASS=$((PASS+1)); green "PASS T7.mg_blast.restrict: only Scaphopoda hits present"
            else
                FAIL=$((FAIL+1)); red "FAIL T7.mg_blast.restrict: foreign-class hits present (classes=<$classes>)"
                head -3 "${tinytmp}/out/hits_with_species.tsv"
            fi
            # T7.mg_blast.selfhit: the query accession must self-hit in the subset
            # DB (otherwise the subset was built without the query species).
            # Word-boundary regex avoids matching e.g. AntentEVm041426t10 when the
            # query is AntentEVm041426t1.
            query_acc=$(grep -m1 '^>' "${tinytmp}/q.fa" | sed 's/^>//' | awk '{print $1}')
            if grep -qE "(^|[[:space:]])${query_acc}([[:space:]]|$)" "${tinytmp}/out/hits_with_species.tsv"; then
                PASS=$((PASS+1)); green "PASS T7.mg_blast.selfhit: query accession $query_acc present in hits"
            else
                FAIL=$((FAIL+1)); red "FAIL T7.mg_blast.selfhit: $query_acc absent (subset DB built without query species?)"
            fi
        fi
        rm -rf "$tinytmp"

        # === T7.mg_blast.regression: no --taxon-filter still works ===
        # Regression check: confirm the no-flag path didn't break when we moved
        # the BLAST-db existence check into the else branch.
        tinytmp=$(mktemp -d)
        blastdbcmd -db "$MG_BLAST_AA" -entry all -outfmt "%a" 2>/dev/null \
            | grep -m1 '^Antent' > "${tinytmp}/acc"
        blastdbcmd -db "$MG_BLAST_AA" -entry_batch "${tinytmp}/acc" -outfmt "%f" > "${tinytmp}/q.fa"
        bash "${repo}/wrappers/mg_blast.sh" -q "${tinytmp}/q.fa" -o "${tinytmp}/out" \
            -d aa -e 1e-30 -t 2 >/dev/null 2>&1
        rc=$?
        if [[ "$rc" -eq 0 && -s "${tinytmp}/out/hits_with_species.tsv" ]]; then
            PASS=$((PASS+1)); green "PASS T7.mg_blast.regression: no-flag path still works"
        else
            FAIL=$((FAIL+1)); red "FAIL T7.mg_blast.regression: rc=$rc"
        fi
        rm -rf "$tinytmp"

        # === T8.mg_diamond: --taxon-filter wires through mg_diamond end-to-end ===
        # Same shape as T7. Diamond is protein-only, so kind is always aa.
        # Skip gracefully if diamond is missing on PATH.
        if command -v diamond >/dev/null 2>&1; then
            tinytmp=$(mktemp -d)
            blastdbcmd -db "$MG_BLAST_AA" -entry "AntentEVm041426t1" -outfmt "%f" \
                > "${tinytmp}/q.fa" 2>/dev/null \
                || blastdbcmd -db "$MG_BLAST_AA" -entry all -outfmt "%a" 2>/dev/null \
                    | grep -m 1 '^Antent' \
                    | xargs -I {} blastdbcmd -db "$MG_BLAST_AA" -entry {} -outfmt "%f" \
                        > "${tinytmp}/q.fa"
            if [[ ! -s "${tinytmp}/q.fa" ]]; then
                FAIL=$((FAIL+1)); red "FAIL T8.mg_diamond: could not build query FASTA"
            else
                MG_TAXON_CACHE_ROOT="${tinytmp}/cache" \
                    bash "${repo}/wrappers/mg_diamond.sh" \
                        -q "${tinytmp}/q.fa" -o "${tinytmp}/out" \
                        --taxon-filter Scaphopoda -t 2 -e 1 \
                        > "${tinytmp}/stdout" 2>&1
                rc=$?
                if [[ "$rc" -eq 0 ]]; then
                    PASS=$((PASS+1)); green "PASS T8.mg_diamond.exit: rc=0"
                else
                    FAIL=$((FAIL+1)); red "FAIL T8.mg_diamond.exit: rc=$rc"
                    cat "${tinytmp}/stdout"
                fi
                if [[ -s "${tinytmp}/out/hits_with_species.tsv" ]]; then
                    PASS=$((PASS+1)); green "PASS T8.mg_diamond.hits: hits file populated"
                else
                    FAIL=$((FAIL+1)); red "FAIL T8.mg_diamond.hits: empty or missing"
                fi
                classes=$(cut -f18 "${tinytmp}/out/hits_with_species.tsv" 2>/dev/null | LC_ALL=C sort -u)
                if [[ "$classes" == "Scaphopoda" ]]; then
                    PASS=$((PASS+1)); green "PASS T8.mg_diamond.restrict: only Scaphopoda hits present"
                else
                    FAIL=$((FAIL+1)); red "FAIL T8.mg_diamond.restrict: foreign-class hits present (classes=<$classes>)"
                    head -3 "${tinytmp}/out/hits_with_species.tsv"
                fi
                # T8.mg_diamond.selfhit: word-boundary self-hit check, parallel to T7.
                query_acc=$(grep -m1 '^>' "${tinytmp}/q.fa" | sed 's/^>//' | awk '{print $1}')
                if grep -qE "(^|[[:space:]])${query_acc}([[:space:]]|$)" "${tinytmp}/out/hits_with_species.tsv"; then
                    PASS=$((PASS+1)); green "PASS T8.mg_diamond.selfhit: query accession $query_acc present in hits"
                else
                    FAIL=$((FAIL+1)); red "FAIL T8.mg_diamond.selfhit: $query_acc absent (subset DB built without query species?)"
                fi
            fi
            rm -rf "$tinytmp"

            # === T8.mg_diamond.regression: no --taxon-filter (gated on diamond DB) ===
            # The source DIAMOND DB isn't always present (e.g. test hosts that
            # haven't rebuilt the .dmnd). Gate the regression check on its
            # presence so this test stays portable.
            if [[ -f "$MG_DIAMOND_AA" ]]; then
                tinytmp=$(mktemp -d)
                blastdbcmd -db "$MG_BLAST_AA" -entry all -outfmt "%a" 2>/dev/null \
                    | grep -m1 '^Antent' > "${tinytmp}/acc"
                blastdbcmd -db "$MG_BLAST_AA" -entry_batch "${tinytmp}/acc" -outfmt "%f" > "${tinytmp}/q.fa"
                bash "${repo}/wrappers/mg_diamond.sh" -q "${tinytmp}/q.fa" -o "${tinytmp}/out" \
                    -e 1e-30 -t 2 >/dev/null 2>&1
                rc=$?
                if [[ "$rc" -eq 0 && -s "${tinytmp}/out/hits_with_species.tsv" ]]; then
                    PASS=$((PASS+1)); green "PASS T8.mg_diamond.regression: no-flag path still works"
                else
                    FAIL=$((FAIL+1)); red "FAIL T8.mg_diamond.regression: rc=$rc"
                fi
                rm -rf "$tinytmp"
            else
                green "SKIP T8.mg_diamond.regression: $MG_DIAMOND_AA absent on this host"
            fi
        else
            echo "[integration] diamond not on PATH -- skipping T8.mg_diamond tests" >&2
        fi

        # === T9.mg_hmmsearch: --taxon-filter replaces target FASTA ===
        # hmmsearch is HMM -> sequences; with --taxon-filter we auto-build the
        # subset FASTA and use it as the target. Verifies (a) exit 0, (b)
        # hits.tbl populated, (c) every per-sequence hit's class is Scaphopoda
        # (joined column added by mg_join_species), (d) the subset-FASTA log
        # line is present.
        tinytmp=$(mktemp -d)
        # Use a small HMM (Neur_chan_LBD_REVISION) for fast scan; fall back to MG_HMM.
        if [[ -f "${repo}/hmm/per_domain/Neur_chan_LBD_REVISION.hmm" ]]; then
            hmm_path="${repo}/hmm/per_domain/Neur_chan_LBD_REVISION.hmm"
        else
            hmm_path="$MG_HMM"
        fi
        MG_TAXON_CACHE_ROOT="${tinytmp}/cache" \
            bash "${repo}/wrappers/mg_hmmsearch.sh" \
                --hmm "$hmm_path" -o "${tinytmp}/out" \
                --taxon-filter Scaphopoda -t 2 \
                > "${tinytmp}/stdout" 2>&1
        rc=$?
        if [[ "$rc" -eq 0 ]]; then
            PASS=$((PASS+1)); green "PASS T9.mg_hmmsearch.exit: rc=0"
        else
            FAIL=$((FAIL+1)); red "FAIL T9.mg_hmmsearch.exit: rc=$rc"
            cat "${tinytmp}/stdout"
        fi
        if [[ -s "${tinytmp}/out/hits.tbl" ]]; then
            PASS=$((PASS+1)); green "PASS T9.mg_hmmsearch.hits: hits.tbl exists"
        else
            FAIL=$((FAIL+1)); red "FAIL T9.mg_hmmsearch.hits: missing hits.tbl"
        fi
        # Restriction check: extract the class column and assert it's exactly
        # "Scaphopoda" (catches Polyplacophora/Solenogastres/Caudofoveata leaks
        # that the previous grep-blocklist missed).
        # Schema: mg_hmmsearch.sh:182 normalizes hmm tblout to NF=18, then
        # _join_species.py appends species_code (19), species_binomial (20),
        # class (21), order (22), family (23), phylum (24). So class = $21.
        if [[ -s "${tinytmp}/out/hits_with_species.tsv" ]]; then
            classes=$(awk -F'\t' '!/^#/ {print $21}' "${tinytmp}/out/hits_with_species.tsv" | LC_ALL=C sort -u | grep -v '^$')
            if [[ "$classes" == "Scaphopoda" ]]; then
                PASS=$((PASS+1)); green "PASS T9.mg_hmmsearch.restrict: only Scaphopoda hits (n_classes=1)"
            else
                FAIL=$((FAIL+1)); red "FAIL T9.mg_hmmsearch.restrict: classes=$classes"
                head -3 "${tinytmp}/out/hits_with_species.tsv"
            fi
        fi
        # Subset-FASTA log line
        if grep -q "subset FASTA at" "${tinytmp}/out/run.log"; then
            PASS=$((PASS+1)); green "PASS T9.mg_hmmsearch.log: log mentions subset FASTA"
        else
            FAIL=$((FAIL+1)); red "FAIL T9.mg_hmmsearch.log: no subset-FASTA line in run.log"
        fi

        # Mutual-exclusion check: -q AND --taxon-filter together => mg_die
        err=$(bash "${repo}/wrappers/mg_hmmsearch.sh" -q "${tinytmp}/out/hits.tbl" --taxon-filter Scaphopoda -o "${tinytmp}/dummy" 2>&1 || true)
        assert_contains "mutually exclusive" "$err" "T9.mg_hmmsearch.mutex: rejects -q + --taxon-filter"

        # Regression: -q-only path (no taxon filter) still works
        blastdbcmd -db "$MG_BLAST_AA" -entry all -outfmt "%a" 2>/dev/null | grep -m1 '^Antent' > "${tinytmp}/acc"
        blastdbcmd -db "$MG_BLAST_AA" -entry_batch "${tinytmp}/acc" -outfmt "%f" > "${tinytmp}/regression_q.fa"
        bash "${repo}/wrappers/mg_hmmsearch.sh" \
            --hmm "$hmm_path" -q "${tinytmp}/regression_q.fa" -o "${tinytmp}/regression_out" -t 2 \
            > "${tinytmp}/regression_stdout" 2>&1
        rc=$?
        if [[ "$rc" -eq 0 && -s "${tinytmp}/regression_out/hits.tbl" ]]; then
            PASS=$((PASS+1)); green "PASS T9.mg_hmmsearch.regression: -q-only path still works"
        else
            FAIL=$((FAIL+1)); red "FAIL T9.mg_hmmsearch.regression: rc=$rc"
        fi
        rm -rf "$tinytmp"

        # === T10.mg_characterize: --taxon-filter forwarded to blast+diamond, not hmm ===
        # Use --skip diamond because MG_DIAMOND_AA may not exist on this host
        # (same gating rationale as T8.mg_diamond.regression).
        tinytmp=$(mktemp -d)
        blastdbcmd -db "$MG_BLAST_AA" -entry all -outfmt "%a" 2>/dev/null | grep -m1 '^Antent' > "${tinytmp}/acc"
        blastdbcmd -db "$MG_BLAST_AA" -entry_batch "${tinytmp}/acc" -outfmt "%f" > "${tinytmp}/q.fa"
        MG_TAXON_CACHE_ROOT="${tinytmp}/cache" \
            bash "${repo}/wrappers/mg_characterize.sh" \
                -q "${tinytmp}/q.fa" -o "${tinytmp}/out" \
                --taxon-filter Scaphopoda --skip diamond -e 1 -t 2 \
                > "${tinytmp}/stdout" 2>&1
        rc=$?
        if [[ "$rc" -eq 0 ]]; then
            PASS=$((PASS+1)); green "PASS T10.mg_characterize.exit: rc=0"
        else
            FAIL=$((FAIL+1)); red "FAIL T10.mg_characterize.exit: rc=$rc"
            cat "${tinytmp}/stdout"
        fi
        # BLAST sub-dir hits should all be Scaphopoda. mg_characterize's blast
        # subdir is the standalone mg_blast schema: 15 BLAST cols + species_code
        # (16) + species_binomial (17) + class (18). So class = $18. Same
        # extract/sort/equals pattern as T7/T8 — catches Polyplacophora /
        # Solenogastres / Caudofoveata leaks the previous grep-blocklist missed.
        if [[ -s "${tinytmp}/out/blast/hits_with_species.tsv" ]]; then
            classes=$(awk -F'\t' '!/^#/ {print $18}' "${tinytmp}/out/blast/hits_with_species.tsv" | LC_ALL=C sort -u | grep -v '^$')
            if [[ "$classes" == "Scaphopoda" ]]; then
                PASS=$((PASS+1)); green "PASS T10.mg_characterize.blast_restrict: BLAST hits restricted to Scaphopoda (n_classes=1)"
            else
                FAIL=$((FAIL+1)); red "FAIL T10.mg_characterize.blast_restrict: classes=$classes"
                head -3 "${tinytmp}/out/blast/hits_with_species.tsv"
            fi
        fi
        # HMM sub-dir hits should NOT be restricted (the hmm step still operates on user query)
        if [[ -s "${tinytmp}/out/hmm/hits.tbl" ]]; then
            PASS=$((PASS+1)); green "PASS T10.mg_characterize.hmm_unaffected: hmm step ran"
        else
            FAIL=$((FAIL+1)); red "FAIL T10.mg_characterize.hmm_unaffected: hmm hits missing"
        fi
        # Verify the log says taxon-filter applies to blast/diamond only
        if grep -q "applied to blast/diamond only" "${tinytmp}/out/run.log"; then
            PASS=$((PASS+1)); green "PASS T10.mg_characterize.log: scope note logged"
        else
            FAIL=$((FAIL+1)); red "FAIL T10.mg_characterize.log: scope note missing"
        fi
        rm -rf "$tinytmp"

        # === T10.mg_characterize.regression: no --taxon-filter still works ===
        # Regression check parallel to T7/T8/T9 — confirm the no-flag path
        # didn't break when we reordered validations / wired forwarding.
        # --skip diamond --skip hmm keeps this fast and avoids the diamond
        # source-DB dependency (same gating rationale as T8 regression).
        tinytmp=$(mktemp -d)
        blastdbcmd -db "$MG_BLAST_AA" -entry all -outfmt "%a" 2>/dev/null | grep -m1 '^Antent' > "${tinytmp}/acc"
        blastdbcmd -db "$MG_BLAST_AA" -entry_batch "${tinytmp}/acc" -outfmt "%f" > "${tinytmp}/q.fa"
        bash "${repo}/wrappers/mg_characterize.sh" \
            -q "${tinytmp}/q.fa" -o "${tinytmp}/out" \
            --skip diamond --skip hmm -e 1 -t 2 \
            > "${tinytmp}/stdout" 2>&1
        rc=$?
        if [[ "$rc" -eq 0 && -s "${tinytmp}/out/blast/hits_with_species.tsv" ]]; then
            PASS=$((PASS+1)); green "PASS T10.mg_characterize.regression: no-flag path still works"
        else
            FAIL=$((FAIL+1)); red "FAIL T10.mg_characterize.regression: rc=$rc"
            cat "${tinytmp}/stdout"
        fi
        rm -rf "$tinytmp"

        # === T11.concurrency: two parallel mg_blast calls, same fresh cache ===
        # Both processes contend on flock; one builds the subset DB, the other waits
        # then sees the cached result. Both runs must succeed with non-empty hits files.
        tinytmp=$(mktemp -d)
        # Build a query (same self-hit Antent strategy used elsewhere)
        blastdbcmd -db "$MG_BLAST_AA" -entry all -outfmt "%a" 2>/dev/null | grep -m1 '^Antent' > "${tinytmp}/acc"
        blastdbcmd -db "$MG_BLAST_AA" -entry_batch "${tinytmp}/acc" -outfmt "%f" > "${tinytmp}/q.fa"

        # Use a SMALL taxon (Polyplacophora has only ~10 species, fast to build).
        # Both calls share the same MG_TAXON_CACHE_ROOT - that's the point of the test.
        cache_root="${tinytmp}/shared_cache"

        # Launch both wrappers in parallel
        MG_TAXON_CACHE_ROOT="$cache_root" bash "${repo}/wrappers/mg_blast.sh" \
            -q "${tinytmp}/q.fa" -o "${tinytmp}/outA" -d aa \
            --taxon-filter Polyplacophora -t 2 -e 1 \
            > "${tinytmp}/stdoutA" 2>&1 &
        pidA=$!
        MG_TAXON_CACHE_ROOT="$cache_root" bash "${repo}/wrappers/mg_blast.sh" \
            -q "${tinytmp}/q.fa" -o "${tinytmp}/outB" -d aa \
            --taxon-filter Polyplacophora -t 2 -e 1 \
            > "${tinytmp}/stdoutB" 2>&1 &
        pidB=$!
        wait "$pidA"; rcA=$?
        wait "$pidB"; rcB=$?

        # T11.exitA / T11.exitB: both calls must exit 0
        [[ "$rcA" -eq 0 ]] && PASS=$((PASS+1)) && green "PASS T11.exitA: mg_blast process A rc=0" \
            || { FAIL=$((FAIL+1)); red "FAIL T11.exitA: rcA=$rcA"; cat "${tinytmp}/stdoutA"; }
        [[ "$rcB" -eq 0 ]] && PASS=$((PASS+1)) && green "PASS T11.exitB: mg_blast process B rc=0" \
            || { FAIL=$((FAIL+1)); red "FAIL T11.exitB: rcB=$rcB"; cat "${tinytmp}/stdoutB"; }

        # T11.hitsA / T11.hitsB: both calls produced valid hits files
        [[ -s "${tinytmp}/outA/hits_with_species.tsv" ]] \
            && PASS=$((PASS+1)) && green "PASS T11.hitsA: A produced hits" \
            || { FAIL=$((FAIL+1)); red "FAIL T11.hitsA: empty"; }
        [[ -s "${tinytmp}/outB/hits_with_species.tsv" ]] \
            && PASS=$((PASS+1)) && green "PASS T11.hitsB: B produced hits" \
            || { FAIL=$((FAIL+1)); red "FAIL T11.hitsB: empty"; }

        # T11.both_polypl: both wrappers' hits are restricted to Polyplacophora (subset DB correctly built)
        classesA=$(awk -F'\t' '!/^#/ {print $18}' "${tinytmp}/outA/hits_with_species.tsv" | LC_ALL=C sort -u | grep -v '^$')
        classesB=$(awk -F'\t' '!/^#/ {print $18}' "${tinytmp}/outB/hits_with_species.tsv" | LC_ALL=C sort -u | grep -v '^$')
        if [[ "$classesA" == "Polyplacophora" && "$classesB" == "Polyplacophora" ]]; then
            PASS=$((PASS+1)); green "PASS T11.both_polypl: both processes' hits restricted to Polyplacophora"
        else
            FAIL=$((FAIL+1)); red "FAIL T11.both_polypl: classesA='$classesA' classesB='$classesB'"
        fi

        # T11.single_build: only ONE actual subset-FASTA build occurred.
        # The lock ensures serialization; the second caller sees the cache as already-built.
        # We can't observe "number of mg_extract.sh subprocess invocations" directly, but the
        # cache should contain exactly ONE TAXON_KEY directory and the FASTA mtime should be
        # within a small window (single makeblastdb pass), not two.
        n_keys=$(find "$cache_root" -mindepth 1 -maxdepth 1 -type d | wc -l)
        [[ "$n_keys" -eq 1 ]] && PASS=$((PASS+1)) && green "PASS T11.single_build: one TAXON_KEY dir under shared cache" \
            || { FAIL=$((FAIL+1)); red "FAIL T11.single_build: n_keys=$n_keys (expected 1)"; }

        # T11.manifest_valid: the shared manifest survived parallel access - it's valid JSON
        manifest=$(find "$cache_root" -name manifest.json | head -1)
        if [[ -n "$manifest" ]] && jq empty "$manifest" 2>/dev/null; then
            PASS=$((PASS+1)); green "PASS T11.manifest_valid: shared manifest is valid JSON"
        else
            FAIL=$((FAIL+1)); red "FAIL T11.manifest_valid: $manifest"
        fi

        rm -rf "$tinytmp"
    fi
fi

echo
echo "tests: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
