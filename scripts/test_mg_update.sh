#!/usr/bin/env bash
# scripts/test_mg_update.sh - unit/integration tests for wrappers/mg_update.sh
# Usage: bash scripts/test_mg_update.sh                # unit tests only
#        MOLLUSCAGENES_INTEGRATION=1 bash ...          # also network-touching cases
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "${here}/.." && pwd)"
script="${repo}/wrappers/mg_update.sh"

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
assert_exit() {  # $1=expected-exit $2=cmd $3=label
    local actual
    eval "$2" >/dev/null 2>&1; actual=$?
    if [[ "$1" == "$actual" ]]; then PASS=$((PASS+1)); green "PASS $3"
    else FAIL=$((FAIL+1)); red "FAIL $3 expected-exit=$1 actual-exit=$actual"; fi
}

# Build a minimal molluscagenes-shaped repo (no git) under $1 and echo path.
# Caller `rm -rf` afterwards.
make_fixture_repo() {
    local d="$1"
    mkdir -p "$d/wrappers" "$d/metadata" "$d/scripts"
    : > "$d/wrappers/mg_fetch.sh"
    chmod +x "$d/wrappers/mg_fetch.sh"
    # Ship a real verify_download.sh so verify_data can delegate to it.
    cp "${repo}/wrappers/verify_download.sh" "$d/wrappers/verify_download.sh"
    chmod +x "$d/wrappers/verify_download.sh"
    # minimal canonical files the updater inspects
    cat > "$d/metadata/zenodo_manifest.tsv" <<'EOF'
filename	size_bytes	sha256	description
EOF
    echo "19825266" > "$d/metadata/zenodo_record.txt"
    cat > "$d/metadata/species_metadata.tsv" <<'EOF'
species_code	species_binomial	class	subclass	order	family
EOF
    cat > "$d/environment.yml" <<'EOF'
name: molluscagenes
channels: [conda-forge, bioconda]
dependencies: []
EOF
}

# Promote a fixture to git-mode at $1 by initializing .git/ and tagging at $2.
git_init_fixture() {
    local d="$1" tag="$2"
    git -C "$d" -c init.defaultBranch=main init -q
    git -C "$d" -c user.email=t@t -c user.name=t add -A
    git -C "$d" -c user.email=t@t -c user.name=t commit -q -m "initial"
    git -C "$d" tag "$tag"
}

# Add a second commit (with a marker file change) and tag it. Leaves HEAD on
# the new tag; caller may `git checkout <older>` to roll back.
git_add_tag() {
    local d="$1" tag="$2" marker="$3"
    echo "$marker" > "$d/wrappers/_release_marker.txt"
    git -C "$d" -c user.email=t@t -c user.name=t add -A
    git -C "$d" -c user.email=t@t -c user.name=t commit -q -m "release $tag"
    git -C "$d" tag "$tag"
}

# --- T1: --help and -h print usage and exit 0 ---
out=$(bash "$script" --help 2>&1); rc=$?
assert_eq "0" "$rc" "T1.help: --help exits 0"
assert_contains "Usage" "$out" "T1.help: --help prints Usage"
assert_contains "--repo-dir" "$out" "T1.help: --help mentions --repo-dir"
assert_contains "--dry-run" "$out" "T1.help: --help mentions --dry-run"
assert_contains "--check-only" "$out" "T1.help: --help mentions --check-only"
assert_contains "--force" "$out" "T1.help: --help mentions --force"
assert_contains "--track" "$out" "T1.help: --help mentions --track"

out=$(bash "$script" -h 2>&1); rc=$?
assert_eq "0" "$rc" "T1.help: -h exits 0"
assert_contains "Usage" "$out" "T1.help: -h prints Usage"

# --- T2: repo resolution (--repo-dir, walk-up, errors) ---
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fixture="$tmp/mg_install"
make_fixture_repo "$fixture"

out=$(bash "$script" --check-only --repo-dir "$fixture" 2>&1); rc=$?
assert_eq "0" "$rc" "T2.repo: --repo-dir to valid fixture exits 0"
assert_contains "$fixture" "$out" "T2.repo: --repo-dir echoes resolved repo path"

out=$(bash "$script" --check-only --repo-dir "$tmp/does-not-exist" 2>&1); rc=$?
assert_eq "4" "$rc" "T2.repo: nonexistent --repo-dir exits 4"
assert_contains "not a MolluscaGenes repo" "$out" "T2.repo: nonexistent --repo-dir errors clearly"

# walk-up: invoke from inside a subdir of the fixture
mkdir -p "$fixture/scripts/_test_fixtures"
out=$(cd "$fixture/scripts/_test_fixtures" && bash "$script" --check-only 2>&1); rc=$?
assert_eq "0" "$rc" "T2.repo: walk-up from subdir exits 0"
assert_contains "$fixture" "$out" "T2.repo: walk-up resolves to fixture root"

# no flag, no env, cwd has no markers, script lives outside any repo: should fail.
# Copy the script to a non-repo dir so step 4 (script's own location fallback)
# also fails — matches the standalone-bootstrap scenario.
standalone="$tmp/standalone"
mkdir -p "$standalone"
cp "$script" "$standalone/mg_update.sh"
nomarker="$tmp/empty"
mkdir -p "$nomarker"
out=$(cd "$nomarker" && bash "$standalone/mg_update.sh" --check-only 2>&1); rc=$?
assert_eq "4" "$rc" "T2.repo: walk-up with no marker (standalone script) exits 4"
assert_contains "could not find" "$out" "T2.repo: walk-up failure has clear message"

# But: the same standalone script with --repo-dir to a valid fixture works.
out=$(cd "$nomarker" && bash "$standalone/mg_update.sh" --check-only --repo-dir "$fixture" 2>&1); rc=$?
assert_eq "0" "$rc" "T2.repo: standalone + --repo-dir to fixture exits 0"
assert_contains "$fixture" "$out" "T2.repo: standalone --repo-dir resolves correctly"

# directory exists but missing the marker files: should still fail
bare="$tmp/bare_dir"
mkdir -p "$bare/wrappers"   # has wrappers/ but not mg_fetch.sh or manifest
out=$(bash "$script" --check-only --repo-dir "$bare" 2>&1); rc=$?
assert_eq "4" "$rc" "T2.repo: dir without manifest+mg_fetch exits 4"

# MG_REPO_DIR env var works
out=$(MG_REPO_DIR="$fixture" bash "$script" --check-only 2>&1); rc=$?
assert_eq "0" "$rc" "T2.repo: MG_REPO_DIR env var resolves"
assert_contains "$fixture" "$out" "T2.repo: MG_REPO_DIR echoes resolved path"

# --- T3: detect_install + current version reporting ---

# Tarball-mode fixture: no .git/, no version marker
fx_tar="$tmp/install_tarball"
make_fixture_repo "$fx_tar"
out=$(bash "$script" --check-only --repo-dir "$fx_tar" 2>&1); rc=$?
assert_eq "0" "$rc"                "T3.tar: --check-only on tarball-mode exits 0"
assert_contains "mode: tarball" "$out" "T3.tar: detects tarball mode (no .git)"
assert_contains "current: unknown" "$out" "T3.tar: reports current=unknown when no .molluscagenes_version"

# Tarball-mode fixture with version marker
fx_tar2="$tmp/install_tarball_marked"
make_fixture_repo "$fx_tar2"
echo "v0.4.0" > "$fx_tar2/.molluscagenes_version"
out=$(bash "$script" --check-only --repo-dir "$fx_tar2" 2>&1)
assert_contains "mode: tarball" "$out" "T3.tar: still tarball mode with version marker"
assert_contains "current: v0.4.0" "$out" "T3.tar: reads .molluscagenes_version"

# Git-mode fixture: tagged commit
fx_git="$tmp/install_git"
make_fixture_repo "$fx_git"
git_init_fixture "$fx_git" "v0.4.0"
out=$(bash "$script" --check-only --repo-dir "$fx_git" 2>&1); rc=$?
assert_eq "0" "$rc"             "T3.git: --check-only on git-mode exits 0"
assert_contains "mode: git"     "$out" "T3.git: detects git mode (.git/ present)"
assert_contains "current: v0.4.0" "$out" "T3.git: reads current tag via git describe"

# --- T4: latest-version probe + already-at-latest no-op ---
# Tests use MG_UPDATE_LATEST_TAG to bypass network probes deterministically.

# Git mode, behind latest
out=$(MG_UPDATE_LATEST_TAG=v0.5.0 bash "$script" --check-only --repo-dir "$fx_git" 2>&1); rc=$?
assert_eq "0" "$rc"                    "T4.git-behind: exits 0"
assert_contains "latest: v0.5.0"  "$out" "T4.git-behind: reports latest"
assert_contains "update available" "$out" "T4.git-behind: announces update available"

# Git mode, already at latest
out=$(MG_UPDATE_LATEST_TAG=v0.4.0 bash "$script" --check-only --repo-dir "$fx_git" 2>&1); rc=$?
assert_eq "0" "$rc"                  "T4.git-latest: exits 0"
assert_contains "already at" "$out"  "T4.git-latest: announces already-at-latest"

# Tarball mode, behind latest
out=$(MG_UPDATE_LATEST_TAG=v0.5.0 bash "$script" --check-only --repo-dir "$fx_tar2" 2>&1)
assert_contains "latest: v0.5.0"   "$out" "T4.tar-behind: reports latest"
assert_contains "update available" "$out" "T4.tar-behind: announces update available"

# Tarball mode, already at latest
out=$(MG_UPDATE_LATEST_TAG=v0.4.0 bash "$script" --check-only --repo-dir "$fx_tar2" 2>&1)
assert_contains "already at" "$out" "T4.tar-latest: announces already-at-latest"

# Full update (not --check-only) on already-at-latest = no-op, exit 0
out=$(MG_UPDATE_LATEST_TAG=v0.4.0 bash "$script" --no-verify-data --no-verify-tools --repo-dir "$fx_git" 2>&1); rc=$?
assert_eq "0" "$rc"                  "T4.noop: full run when already-at-latest exits 0"
assert_contains "already at" "$out"  "T4.noop: no-op message printed"

# --- T5: git-mode update + dirty-tree refusal + --force ---

# Two-tag fixture: v0.4.0 → v0.5.0, HEAD checked out at v0.4.0
fx_g2="$tmp/install_g2"
make_fixture_repo "$fx_g2"
git_init_fixture "$fx_g2" "v0.4.0"
git_add_tag "$fx_g2" "v0.5.0" "release-v0.5.0-marker"
git -C "$fx_g2" checkout -q v0.4.0
# sanity: HEAD at v0.4.0, marker file absent
assert_eq "v0.4.0" "$(git -C "$fx_g2" describe --tags --abbrev=0)" "T5.setup: HEAD at v0.4.0"
[[ ! -f "$fx_g2/wrappers/_release_marker.txt" ]] && PASS=$((PASS+1)) && green "PASS T5.setup: marker file absent at v0.4.0" \
    || { FAIL=$((FAIL+1)); red "FAIL T5.setup: marker file should be absent"; }

# --dry-run: prints plan, leaves tree unchanged
out=$(MG_UPDATE_LATEST_TAG=v0.5.0 bash "$script" --dry-run --repo-dir "$fx_g2" 2>&1); rc=$?
assert_eq "0" "$rc" "T5.dryrun: exits 0"
assert_contains "DRY RUN" "$out" "T5.dryrun: announces dry-run"
assert_eq "v0.4.0" "$(git -C "$fx_g2" describe --tags --abbrev=0)" "T5.dryrun: HEAD still at v0.4.0"
[[ ! -f "$fx_g2/wrappers/_release_marker.txt" ]] && PASS=$((PASS+1)) && green "PASS T5.dryrun: marker still absent" \
    || { FAIL=$((FAIL+1)); red "FAIL T5.dryrun: marker file appeared"; }

# Real run: checks out v0.5.0
out=$(MG_UPDATE_LATEST_TAG=v0.5.0 bash "$script" --no-verify-data --no-verify-tools --repo-dir "$fx_g2" 2>&1); rc=$?
assert_eq "0" "$rc" "T5.git: real-run exits 0"
assert_contains "v0.4.0 -> v0.5.0" "$out" "T5.git: reports tag delta"
assert_eq "v0.5.0" "$(git -C "$fx_g2" describe --tags --abbrev=0)" "T5.git: HEAD moved to v0.5.0"
[[ -f "$fx_g2/wrappers/_release_marker.txt" ]] && PASS=$((PASS+1)) && green "PASS T5.git: marker file now present" \
    || { FAIL=$((FAIL+1)); red "FAIL T5.git: marker file should be present"; }

# Dirty tree refusal: roll back to v0.4.0, dirty a tracked file, attempt update
git -C "$fx_g2" checkout -q v0.4.0
echo "local edit" >> "$fx_g2/wrappers/mg_fetch.sh"
out=$(MG_UPDATE_LATEST_TAG=v0.5.0 bash "$script" --repo-dir "$fx_g2" 2>&1); rc=$?
assert_eq "4" "$rc" "T5.dirty: refuses dirty tree with exit 4"
assert_contains "local changes" "$out" "T5.dirty: error mentions local changes"
assert_eq "v0.4.0" "$(git -C "$fx_g2" describe --tags --abbrev=0)" "T5.dirty: HEAD untouched after refusal"

# --force overrides
out=$(MG_UPDATE_LATEST_TAG=v0.5.0 bash "$script" --force --no-verify-data --no-verify-tools --repo-dir "$fx_g2" 2>&1); rc=$?
assert_eq "0" "$rc" "T5.force: --force succeeds on dirty tree"
assert_eq "v0.5.0" "$(git -C "$fx_g2" describe --tags --abbrev=0)" "T5.force: HEAD moved to v0.5.0"

# --- T6: tarball-mode update via rsync overlay ---

# Build a "release" tree that mimics what `git archive` / GH tarball produces.
release_src="$tmp/release_src/invertome-molluscagenes-deadbee"
mkdir -p "$release_src"
make_fixture_repo "$release_src"
echo "release-v0.5.0-marker" > "$release_src/wrappers/_release_marker.txt"
# new file introduced in v0.5.0 that wasn't in v0.4.0
echo "new-in-v0.5" > "$release_src/wrappers/new_in_v05.sh"
# Tarball it up like GH does
release_tarball="$tmp/release_v0.5.0.tar.gz"
tar -czf "$release_tarball" -C "$tmp/release_src" "invertome-molluscagenes-deadbee"

# Build an "installed" tarball-mode fixture at v0.4.0, with user-local files
# that must survive the update.
fx_tar3="$tmp/install_tar3"
make_fixture_repo "$fx_tar3"
echo "v0.4.0" > "$fx_tar3/.molluscagenes_version"
# User-local files / dirs that must be preserved:
echo "user-paths" > "$fx_tar3/config.sh"
mkdir -p "$fx_tar3/metadata/_cache/subset_dbs/abcd1234"
echo "cache" > "$fx_tar3/metadata/_cache/subset_dbs/abcd1234/manifest.json"
mkdir -p "$fx_tar3/downloads" "$fx_tar3/runs"
echo "user-download" > "$fx_tar3/downloads/foo.fa"
echo "user-run" > "$fx_tar3/runs/bar.log"

# Dry-run leaves everything alone
out=$(MG_UPDATE_LATEST_TAG=v0.5.0 MG_UPDATE_TARBALL_PATH="$release_tarball" \
      bash "$script" --dry-run --repo-dir "$fx_tar3" 2>&1); rc=$?
assert_eq "0" "$rc" "T6.dryrun: exits 0"
assert_contains "DRY RUN" "$out" "T6.dryrun: announces dry-run"
assert_eq "v0.4.0" "$(cat "$fx_tar3/.molluscagenes_version")" "T6.dryrun: version marker unchanged"
[[ ! -f "$fx_tar3/wrappers/new_in_v05.sh" ]] && PASS=$((PASS+1)) && green "PASS T6.dryrun: new file not yet present" \
    || { FAIL=$((FAIL+1)); red "FAIL T6.dryrun: new file appeared prematurely"; }

# Real run
out=$(MG_UPDATE_LATEST_TAG=v0.5.0 MG_UPDATE_TARBALL_PATH="$release_tarball" \
      bash "$script" --no-verify-data --no-verify-tools --repo-dir "$fx_tar3" 2>&1); rc=$?
assert_eq "0" "$rc" "T6.tar: real-run exits 0"
assert_contains "v0.4.0 -> v0.5.0" "$out" "T6.tar: reports tag delta"
assert_eq "v0.5.0" "$(cat "$fx_tar3/.molluscagenes_version")" "T6.tar: version marker bumped"
[[ -f "$fx_tar3/wrappers/new_in_v05.sh" ]] && PASS=$((PASS+1)) && green "PASS T6.tar: new file overlaid" \
    || { FAIL=$((FAIL+1)); red "FAIL T6.tar: new file missing after update"; }
[[ -f "$fx_tar3/wrappers/_release_marker.txt" ]] && PASS=$((PASS+1)) && green "PASS T6.tar: release marker present" \
    || { FAIL=$((FAIL+1)); red "FAIL T6.tar: release marker missing"; }

# Local files preserved
assert_eq "user-paths" "$(cat "$fx_tar3/config.sh")" "T6.tar: config.sh preserved"
assert_eq "cache" "$(cat "$fx_tar3/metadata/_cache/subset_dbs/abcd1234/manifest.json")" "T6.tar: cache preserved"
assert_eq "user-download" "$(cat "$fx_tar3/downloads/foo.fa")" "T6.tar: downloads/ preserved"
assert_eq "user-run" "$(cat "$fx_tar3/runs/bar.log")" "T6.tar: runs/ preserved"

# --- T7: environment.yml diff + smart cache purge ---

# Helper: build a release tarball that mutates a specific file vs the v0.4
# baseline.  $1=tag, $2=base_fixture, $3=env_yml_content, $4=spp_meta_content,
# echoes the tarball path.
make_release_tarball_with() {
    local tag="$1" base="$2" env_content="$3" spp_content="$4"
    local srcdir="$tmp/rel_${tag}/invertome-molluscagenes-${tag}sha"
    rm -rf "$tmp/rel_${tag}"
    mkdir -p "$srcdir"
    # copy baseline content + overwrite mutated files
    cp -r "$base"/. "$srcdir"
    rm -rf "$srcdir/.molluscagenes_version" "$srcdir/config.sh" \
           "$srcdir/metadata/_cache" "$srcdir/downloads" "$srcdir/runs"
    printf '%s' "$env_content" > "$srcdir/environment.yml"
    printf '%s' "$spp_content" > "$srcdir/metadata/species_metadata.tsv"
    local out="$tmp/rel_${tag}.tar.gz"
    tar -czf "$out" -C "$tmp/rel_${tag}" "invertome-molluscagenes-${tag}sha"
    echo "$out"
}

# Baseline content for installed fixtures
env_baseline=$'name: molluscagenes\nchannels: [conda-forge, bioconda]\ndependencies: []\n'
spp_baseline=$'species_code\tspecies_binomial\tclass\tsubclass\torder\tfamily\n'
spp_v2=$'species_code\tspecies_binomial\tclass\tsubclass\torder\tfamily\nNew1\tNew species\tCephalopoda\t.\t.\t.\n'
env_v2=$'name: molluscagenes\nchannels: [conda-forge, bioconda]\ndependencies: [hmmer=3.4]\n'

# Fixture A: environment.yml unchanged, species_metadata.tsv unchanged
fx_a="$tmp/install_t7a"
make_fixture_repo "$fx_a"; echo "v0.4.0" > "$fx_a/.molluscagenes_version"
mkdir -p "$fx_a/metadata/_cache/subset_dbs/keyA"; echo "preserve-me" > "$fx_a/metadata/_cache/subset_dbs/keyA/manifest.json"
tar_a=$(make_release_tarball_with "v0.5.0" "$fx_a" "$env_baseline" "$spp_baseline")
out=$(MG_UPDATE_LATEST_TAG=v0.5.0 MG_UPDATE_TARBALL_PATH="$tar_a" \
      bash "$script" --no-verify-data --no-verify-tools --repo-dir "$fx_a" 2>&1); rc=$?
assert_eq "0" "$rc" "T7a: unchanged env+spp exits 0"
[[ ! "$out" == *"environment.yml changed"* ]] && PASS=$((PASS+1)) && green "PASS T7a: no env advisory when unchanged" \
    || { FAIL=$((FAIL+1)); red "FAIL T7a: env advisory printed when unchanged"; }
[[ -f "$fx_a/metadata/_cache/subset_dbs/keyA/manifest.json" ]] && PASS=$((PASS+1)) && green "PASS T7a: cache preserved when spp_meta unchanged" \
    || { FAIL=$((FAIL+1)); red "FAIL T7a: cache erroneously purged"; }

# Fixture B: environment.yml changed, env NOT active
fx_b="$tmp/install_t7b"
make_fixture_repo "$fx_b"; echo "v0.4.0" > "$fx_b/.molluscagenes_version"
tar_b=$(make_release_tarball_with "v0.5.0" "$fx_b" "$env_v2" "$spp_baseline")
out=$(MG_UPDATE_LATEST_TAG=v0.5.0 MG_UPDATE_TARBALL_PATH="$tar_b" \
      CONDA_DEFAULT_ENV="" bash "$script" --no-verify-data --no-verify-tools --repo-dir "$fx_b" 2>&1); rc=$?
assert_eq "0" "$rc" "T7b: env changed but not active -> exit 0"
assert_contains "environment.yml changed" "$out" "T7b: env-change advisory printed"
assert_contains "conda env update" "$out" "T7b: includes conda env update hint"

# Fixture C: environment.yml changed, env IS active
fx_c="$tmp/install_t7c"
make_fixture_repo "$fx_c"; echo "v0.4.0" > "$fx_c/.molluscagenes_version"
tar_c=$(make_release_tarball_with "v0.5.0" "$fx_c" "$env_v2" "$spp_baseline")
out=$(MG_UPDATE_LATEST_TAG=v0.5.0 MG_UPDATE_TARBALL_PATH="$tar_c" \
      CONDA_DEFAULT_ENV="molluscagenes" bash "$script" --no-verify-tools --no-verify-data --repo-dir "$fx_c" 2>&1); rc=$?
assert_eq "2" "$rc" "T7c: env changed AND active -> exit 2"
assert_contains "environment.yml changed" "$out" "T7c: env-change advisory printed"

# Fixture D: species_metadata.tsv changed -> cache purged
fx_d="$tmp/install_t7d"
make_fixture_repo "$fx_d"; echo "v0.4.0" > "$fx_d/.molluscagenes_version"
mkdir -p "$fx_d/metadata/_cache/subset_dbs/keyD"; echo "doomed" > "$fx_d/metadata/_cache/subset_dbs/keyD/manifest.json"
tar_d=$(make_release_tarball_with "v0.5.0" "$fx_d" "$env_baseline" "$spp_v2")
out=$(MG_UPDATE_LATEST_TAG=v0.5.0 MG_UPDATE_TARBALL_PATH="$tar_d" \
      bash "$script" --no-verify-data --no-verify-tools --repo-dir "$fx_d" 2>&1); rc=$?
assert_eq "0" "$rc" "T7d: spp_meta changed -> exit 0"
assert_contains "species_metadata.tsv changed" "$out" "T7d: cache-purge message printed"
[[ ! -d "$fx_d/metadata/_cache/subset_dbs/keyD" ]] && PASS=$((PASS+1)) && green "PASS T7d: cache entry purged" \
    || { FAIL=$((FAIL+1)); red "FAIL T7d: cache entry should be purged"; }

# Fixture E: species_metadata.tsv changed but --no-purge-cache -> cache kept
fx_e="$tmp/install_t7e"
make_fixture_repo "$fx_e"; echo "v0.4.0" > "$fx_e/.molluscagenes_version"
mkdir -p "$fx_e/metadata/_cache/subset_dbs/keyE"; echo "keep-me" > "$fx_e/metadata/_cache/subset_dbs/keyE/manifest.json"
tar_e=$(make_release_tarball_with "v0.5.0" "$fx_e" "$env_baseline" "$spp_v2")
out=$(MG_UPDATE_LATEST_TAG=v0.5.0 MG_UPDATE_TARBALL_PATH="$tar_e" \
      bash "$script" --no-purge-cache --no-verify-data --no-verify-tools --repo-dir "$fx_e" 2>&1); rc=$?
assert_eq "0" "$rc" "T7e: --no-purge-cache exits 0"
[[ -f "$fx_e/metadata/_cache/subset_dbs/keyE/manifest.json" ]] && PASS=$((PASS+1)) && green "PASS T7e: --no-purge-cache preserved cache" \
    || { FAIL=$((FAIL+1)); red "FAIL T7e: cache purged despite --no-purge-cache"; }

# --- T8: verify_tools (default + missing + --no-verify-tools) ---

# Use a separate fresh fixture so prior-cycle state doesn't bleed in.
fx_t8="$tmp/install_t8"
make_fixture_repo "$fx_t8"; echo "v0.4.0" > "$fx_t8/.molluscagenes_version"
tar_t8=$(make_release_tarball_with "v0.5.0" "$fx_t8" "$env_baseline" "$spp_baseline")

# Default tool list = always-present POSIX tools -> exit 0, "tools" section printed
out=$(MG_UPDATE_LATEST_TAG=v0.5.0 MG_UPDATE_TARBALL_PATH="$tar_t8" \
      MG_UPDATE_REQUIRED_TOOLS="ls cat awk" bash "$script" --no-verify-data --repo-dir "$fx_t8" 2>&1); rc=$?
assert_eq "0" "$rc" "T8.ok: all required tools present -> exit 0"
assert_contains "tools:" "$out" "T8.ok: tools section header printed"
assert_contains "OK   ls" "$out" "T8.ok: ls reported OK"

# Inject a missing tool
fx_t8b="$tmp/install_t8b"
make_fixture_repo "$fx_t8b"; echo "v0.4.0" > "$fx_t8b/.molluscagenes_version"
tar_t8b=$(make_release_tarball_with "v0.5.0" "$fx_t8b" "$env_baseline" "$spp_baseline")
out=$(MG_UPDATE_LATEST_TAG=v0.5.0 MG_UPDATE_TARBALL_PATH="$tar_t8b" \
      MG_UPDATE_REQUIRED_TOOLS="ls definitely_not_a_tool_xyz123 awk" bash "$script" --repo-dir "$fx_t8b" 2>&1); rc=$?
assert_eq "2" "$rc" "T8.miss: missing tool -> exit 2"
assert_contains "MISS definitely_not_a_tool_xyz123" "$out" "T8.miss: missing tool flagged"

# --no-verify-tools: skip check, no tools section, exit 0
fx_t8c="$tmp/install_t8c"
make_fixture_repo "$fx_t8c"; echo "v0.4.0" > "$fx_t8c/.molluscagenes_version"
tar_t8c=$(make_release_tarball_with "v0.5.0" "$fx_t8c" "$env_baseline" "$spp_baseline")
out=$(MG_UPDATE_LATEST_TAG=v0.5.0 MG_UPDATE_TARBALL_PATH="$tar_t8c" \
      MG_UPDATE_REQUIRED_TOOLS="ls definitely_not_a_tool_xyz123 awk" bash "$script" --no-verify-tools --no-verify-data --repo-dir "$fx_t8c" 2>&1); rc=$?
assert_eq "0" "$rc" "T8.skip: --no-verify-tools skips the check"
[[ ! "$out" == *"tools:"* ]] && PASS=$((PASS+1)) && green "PASS T8.skip: tools section absent" \
    || { FAIL=$((FAIL+1)); red "FAIL T8.skip: tools section printed despite --no-verify-tools"; }

# --- T9: verify_data (manifest-driven) ---

# All cases skip verify-tools to keep exit codes focused on data status.

# Fixture with empty manifest (header only) -> verify_download trivially OK.
fx_t9a="$tmp/install_t9a"
make_fixture_repo "$fx_t9a"; echo "v0.4.0" > "$fx_t9a/.molluscagenes_version"
tar_t9a=$(make_release_tarball_with "v0.5.0" "$fx_t9a" "$env_baseline" "$spp_baseline")
data_a="$tmp/data_t9a"; mkdir -p "$data_a"
out=$(MG_UPDATE_LATEST_TAG=v0.5.0 MG_UPDATE_TARBALL_PATH="$tar_t9a" \
      MG_BLAST_DIR="$data_a" bash "$script" --no-verify-tools --repo-dir "$fx_t9a" 2>&1); rc=$?
assert_eq "0" "$rc" "T9.ok: empty manifest verifies OK -> exit 0"
assert_contains "data: all files match manifest" "$out" "T9.ok: success message"

# MG_BLAST_DIR unset -> skip with advisory, status=2
fx_t9b="$tmp/install_t9b"
make_fixture_repo "$fx_t9b"; echo "v0.4.0" > "$fx_t9b/.molluscagenes_version"
tar_t9b=$(make_release_tarball_with "v0.5.0" "$fx_t9b" "$env_baseline" "$spp_baseline")
out=$(env -u MG_BLAST_DIR \
      MG_UPDATE_LATEST_TAG=v0.5.0 MG_UPDATE_TARBALL_PATH="$tar_t9b" \
      bash "$script" --no-verify-tools --repo-dir "$fx_t9b" 2>&1); rc=$?
assert_eq "2" "$rc" "T9.unset: MG_BLAST_DIR unset -> exit 2"
assert_contains "MG_BLAST_DIR not set" "$out" "T9.unset: clear advisory"

# Data stale: manifest mentions a file, but installed data has a wrong sha
fx_t9c="$tmp/install_t9c"
make_fixture_repo "$fx_t9c"; echo "v0.4.0" > "$fx_t9c/.molluscagenes_version"
# Build a release tarball that updates the manifest to reference a file
mfst=$'filename\tsize_bytes\tsha256\tdescription\nblob.bin\t4\tdeadbeef00000000000000000000000000000000000000000000000000000000\ttestblob\n'
release_t9c_src="$tmp/rel_t9c/invertome-molluscagenes-t9csha"
rm -rf "$tmp/rel_t9c"; mkdir -p "$release_t9c_src"
cp -r "$fx_t9c"/. "$release_t9c_src"
rm -rf "$release_t9c_src/.molluscagenes_version" "$release_t9c_src/metadata/_cache" \
       "$release_t9c_src/downloads" "$release_t9c_src/runs"
printf '%s' "$mfst" > "$release_t9c_src/metadata/zenodo_manifest.tsv"
tar_t9c="$tmp/rel_t9c.tar.gz"
tar -czf "$tar_t9c" -C "$tmp/rel_t9c" "invertome-molluscagenes-t9csha"
# Installed data: file with size 4 but wrong sha
data_c="$tmp/data_t9c"; mkdir -p "$data_c"
printf 'XXXX' > "$data_c/blob.bin"
out=$(MG_UPDATE_LATEST_TAG=v0.5.0 MG_UPDATE_TARBALL_PATH="$tar_t9c" \
      MG_BLAST_DIR="$data_c" bash "$script" --no-verify-tools --repo-dir "$fx_t9c" 2>&1); rc=$?
assert_eq "1" "$rc" "T9.stale: sha mismatch -> exit 1"
assert_contains "data is out of date" "$out" "T9.stale: clear stale message"
assert_contains "mg_fetch.sh" "$out" "T9.stale: remediation includes mg_fetch.sh"

# --no-verify-data: skip even when stale, exit 0
out=$(MG_UPDATE_LATEST_TAG=v0.5.0 MG_UPDATE_TARBALL_PATH="$tar_t9c" \
      MG_BLAST_DIR="$data_c" bash "$script" --no-verify-data --no-verify-tools --repo-dir "$fx_t9c" 2>&1); rc=$?
assert_eq "0" "$rc" "T9.skip: --no-verify-data exits 0 despite stale data"
[[ ! "$out" == *"data is out of date"* ]] && PASS=$((PASS+1)) && green "PASS T9.skip: stale message suppressed" \
    || { FAIL=$((FAIL+1)); red "FAIL T9.skip: stale message printed despite --no-verify-data"; }

# --- T10: combined exit code 3 (env_status=2 AND data_status=1) ---

fx_t10="$tmp/install_t10"
make_fixture_repo "$fx_t10"; echo "v0.4.0" > "$fx_t10/.molluscagenes_version"
# Release tarball whose manifest references blob.bin with deadbeef sha
mfst10=$'filename\tsize_bytes\tsha256\tdescription\nblob.bin\t4\tdeadbeef00000000000000000000000000000000000000000000000000000000\ttestblob\n'
release_t10_src="$tmp/rel_t10/invertome-molluscagenes-t10sha"
rm -rf "$tmp/rel_t10"; mkdir -p "$release_t10_src"
cp -r "$fx_t10"/. "$release_t10_src"
rm -rf "$release_t10_src/.molluscagenes_version" "$release_t10_src/metadata/_cache" \
       "$release_t10_src/downloads" "$release_t10_src/runs"
printf '%s' "$mfst10" > "$release_t10_src/metadata/zenodo_manifest.tsv"
tar_t10="$tmp/rel_t10.tar.gz"
tar -czf "$tar_t10" -C "$tmp/rel_t10" "invertome-molluscagenes-t10sha"
# Installed data: file with size 4, wrong sha -> data status=1
data_t10="$tmp/data_t10"; mkdir -p "$data_t10"; printf 'XXXX' > "$data_t10/blob.bin"
# Inject a missing required tool -> env_status=2
out=$(MG_UPDATE_LATEST_TAG=v0.5.0 MG_UPDATE_TARBALL_PATH="$tar_t10" \
      MG_BLAST_DIR="$data_t10" \
      MG_UPDATE_REQUIRED_TOOLS="ls definitely_missing_xyz123 awk" \
      bash "$script" --repo-dir "$fx_t10" 2>&1); rc=$?
assert_eq "3" "$rc" "T10.combined: missing tool + stale data -> exit 3"
assert_contains "MISS definitely_missing_xyz123" "$out" "T10.combined: tool advisory"
assert_contains "data is out of date" "$out" "T10.combined: data advisory"

# --- T11: real-world sanity (run against the actual worktree repo as a
# tarball-mode install — works because worktree has .git/, so we force-mock
# the install via --check-only on the real fixture's parent.  Limited test:
# just confirm --check-only doesn't blow up against the actual worktree.) ---
out=$(MG_UPDATE_LATEST_TAG="$(git -C "$repo" describe --tags --abbrev=0 2>/dev/null)" \
      bash "$script" --check-only --repo-dir "$repo" 2>&1); rc=$?
assert_eq "0" "$rc" "T11.real: --check-only on real worktree exits 0"
assert_contains "mode: git" "$out" "T11.real: detected as git install"
assert_contains "already at" "$out" "T11.real: reports current==latest (we mocked latest)"

# --- T12: integration (network) — gated by MOLLUSCAGENES_INTEGRATION=1.
# Catches breakage of the real GitHub tarball endpoint used in tarball mode.
if [[ "${MOLLUSCAGENES_INTEGRATION:-0}" == "1" ]]; then
    fx_t12="$tmp/install_t12"
    make_fixture_repo "$fx_t12"; echo "v0.0.0" > "$fx_t12/.molluscagenes_version"
    real_latest=$(curl -fsSL --max-time 15 \
        'https://api.github.com/repos/invertome/molluscagenes/tags' \
        2>/dev/null | jq -r '.[0].name // empty' 2>/dev/null)
    if [[ -n "$real_latest" ]]; then
        out=$(MG_UPDATE_LATEST_TAG="$real_latest" \
              bash "$script" --no-verify-data --no-verify-tools --repo-dir "$fx_t12" 2>&1); rc=$?
        assert_eq "0" "$rc" "T12.net: tarball download from real repo succeeds (exit 0)"
        assert_contains "v0.0.0 -> $real_latest" "$out" "T12.net: tag delta reported"
        assert_eq "$real_latest" "$(cat "$fx_t12/.molluscagenes_version")" "T12.net: version marker bumped to live tag"
    else
        echo "  SKIP T12.net: could not reach github.com/invertome/molluscagenes (offline?)"
    fi
fi

echo
echo "tests: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
