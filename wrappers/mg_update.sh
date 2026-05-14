#!/usr/bin/env bash
# mg_update.sh - in-place refresh for a MolluscaGenes install.
# Updates the repo's scripts/wrappers/metadata/docs to the latest stable release
# tag, then verifies the installed Zenodo data against the new manifest.
#
# Works in two install layouts (auto-detected):
#   git-mode    : repo cloned via `git clone` (has a .git/ directory)
#   tarball-mode: repo extracted from a release tarball (no .git/)
#
# Also runnable standalone: download just this file, then point it at an
# existing install with --repo-dir.
set -uo pipefail

usage() {
    cat <<'EOF'
Usage: mg_update.sh [options]

Refresh a MolluscaGenes install to the latest stable release tag, then verify
the installed Zenodo data against the new manifest.

Options:
  --repo-dir <path>     override auto-discovery of the repo root
                        (use when running the script standalone, from outside
                        the repo)
  --track main          pull main HEAD instead of latest stable tag
  --force               proceed even if the git working tree is dirty
  --dry-run             print everything that would happen; touch nothing
  --check-only          report current vs latest version + data status only;
                        do not fetch, do not modify anything
  --no-verify-data      skip post-update data manifest verification
  --no-verify-tools     skip conda env / tool presence check
  --no-purge-cache      keep metadata/_cache/subset_dbs/ even if
                        species_metadata.tsv changed
  -h | --help           this help

Exit codes:
  0  clean - code at latest, data verified, env tools present
  1  data is stale (re-run wrappers/mg_fetch.sh)
  2  env tools missing or environment.yml changed while env is active
  3  both 1 and 2
  4  hard failure (network, git error, dirty tree without --force, repo not found)
EOF
}

# --- arg parsing -------------------------------------------------------------
repo_dir=""
track="latest-tag"
force="no"
dry_run="no"
check_only="no"
verify_data="yes"
verify_tools="yes"
purge_cache="yes"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo-dir)         repo_dir="$2"; shift 2 ;;
        --track)            track="$2"; shift 2 ;;
        --force)            force="yes"; shift ;;
        --dry-run)          dry_run="yes"; shift ;;
        --check-only)       check_only="yes"; shift ;;
        --no-verify-data)   verify_data="no"; shift ;;
        --no-verify-tools)  verify_tools="no"; shift ;;
        --no-purge-cache)   purge_cache="no"; shift ;;
        -h|--help)          usage; exit 0 ;;
        --)                 shift; break ;;
        -*)                 echo "unknown arg: $1" >&2; usage >&2; exit 4 ;;
        *)                  echo "unexpected positional arg: $1" >&2; usage >&2; exit 4 ;;
    esac
done

# --- helpers -----------------------------------------------------------------
err()  { printf 'mg_update: %s\n' "$*" >&2; }
info() { printf 'mg_update: %s\n' "$*"; }

# A path is a MolluscaGenes repo if it contains both marker files.
is_molluscagenes_repo() {
    local d="$1"
    [[ -d "$d" && -f "$d/wrappers/mg_fetch.sh" && -f "$d/metadata/zenodo_manifest.tsv" ]]
}

# Walk up from $1 looking for a directory that satisfies is_molluscagenes_repo.
# Echoes the path on success, returns 1 on failure.
walk_up_for_repo() {
    local cur
    cur=$(cd "$1" 2>/dev/null && pwd) || return 1
    while [[ -n "$cur" && "$cur" != "/" ]]; do
        if is_molluscagenes_repo "$cur"; then
            echo "$cur"; return 0
        fi
        cur=$(dirname "$cur")
    done
    return 1
}

resolve_repo() {
    local candidate
    # 1. explicit --repo-dir
    if [[ -n "$repo_dir" ]]; then
        if is_molluscagenes_repo "$repo_dir"; then
            (cd "$repo_dir" && pwd); return 0
        fi
        err "not a MolluscaGenes repo: $repo_dir"
        err "expected wrappers/mg_fetch.sh + metadata/zenodo_manifest.tsv"
        return 1
    fi
    # 2. env var
    if [[ -n "${MG_REPO_DIR:-}" ]]; then
        if is_molluscagenes_repo "$MG_REPO_DIR"; then
            (cd "$MG_REPO_DIR" && pwd); return 0
        fi
        err "MG_REPO_DIR is not a MolluscaGenes repo: $MG_REPO_DIR"
        return 1
    fi
    # 3. walk up from $PWD (most natural: "update the install I'm in")
    if candidate=$(walk_up_for_repo "$PWD"); then
        echo "$candidate"; return 0
    fi
    # 4. fallback: parent of the script's own wrappers/ (for in-tree invocation
    #    from outside the install, e.g. `bash /opt/mg/wrappers/mg_update.sh`)
    local self_dir
    self_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)
    if [[ -n "$self_dir" ]]; then
        candidate=$(dirname "$self_dir")
        if is_molluscagenes_repo "$candidate"; then
            echo "$candidate"; return 0
        fi
    fi
    err "could not find a MolluscaGenes repo"
    err "pass --repo-dir <path>, set MG_REPO_DIR, or cd into an install"
    return 1
}

# --- install detection + version readers -------------------------------------

# Returns the install mode for $1: "git" if $d is inside a git work tree (so
# `.git/` directory OR gitfile pointing to a worktree), and git is on PATH;
# otherwise "tarball".
detect_install() {
    local d="$1"
    if command -v git >/dev/null 2>&1 \
            && git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "git"
    else
        echo "tarball"
    fi
}

# Best-effort read of the currently installed version. Echoes "unknown" if it
# can't be determined.
current_version() {
    local d="$1" mode="$2"
    if [[ "$mode" == "git" ]]; then
        git -C "$d" describe --tags --abbrev=0 2>/dev/null || echo "unknown"
    else
        if [[ -f "$d/.molluscagenes_version" ]]; then
            head -1 "$d/.molluscagenes_version"
        else
            echo "unknown"
        fi
    fi
}

# Discovers the latest stable release tag (excludes -rc / -alpha / -beta).
# Honors MG_UPDATE_LATEST_TAG env var for deterministic testing.
# Echoes "unknown" if probe fails (e.g. offline).
latest_version() {
    local d="$1" mode="$2"
    if [[ -n "${MG_UPDATE_LATEST_TAG:-}" ]]; then
        echo "$MG_UPDATE_LATEST_TAG"; return 0
    fi
    if [[ "$track" == "main" ]]; then
        echo "main"; return 0
    fi
    if [[ "$mode" == "git" ]]; then
        git -C "$d" fetch --tags --quiet origin 2>/dev/null || { echo "unknown"; return 0; }
        git -C "$d" tag -l 'v*' --sort=-v:refname 2>/dev/null \
            | grep -v -e '-rc' -e '-beta' -e '-alpha' \
            | head -1 \
            || echo "unknown"
    else
        # Discover via /tags rather than /releases/latest: tags don't require
        # a GitHub Release object, and this project tags without creating
        # Releases. /tags returns the tag list ordered by commit date desc.
        # Filter out pre-release markers; take the first remaining.
        local api='https://api.github.com/repos/invertome/molluscagenes/tags'
        local tag
        tag=$(curl -fsSL --max-time 15 "$api" 2>/dev/null \
            | jq -r '.[].name' 2>/dev/null \
            | grep -v -e '-rc' -e '-beta' -e '-alpha' \
            | head -1)
        [[ -n "$tag" ]] && echo "$tag" || echo "unknown"
    fi
}

# --- update routines ---------------------------------------------------------

# True if `git status --porcelain` is empty in $1.
git_tree_clean() {
    [[ -z "$(git -C "$1" status --porcelain 2>/dev/null)" ]]
}

# Move $repo to the given $tag via git checkout. Refuses if the tree is dirty
# and --force was not passed. Echoes nothing on success; writes diagnostics
# to stderr on failure.
update_code_git() {
    local d="$1" tag="$2"
    if ! git_tree_clean "$d"; then
        if [[ "$force" != "yes" ]]; then
            err "local changes in working tree (pass --force to override):"
            git -C "$d" status --short >&2
            return 4
        fi
        info "proceeding past dirty tree (--force)"
    fi
    git -C "$d" checkout --quiet "$tag"
}

# Overlay a release tarball onto $1 (tarball-mode install). $2=tag. The tarball
# path is either MG_UPDATE_TARBALL_PATH (test/local override) or downloaded
# from the GH Releases API. Excludes preserve user-local state (config.sh,
# metadata/_cache/, downloads/, runs/) and the repo's own .git/ if any.
update_code_tarball() {
    local d="$1" tag="$2"
    local tarpath tmp src
    tmp=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" RETURN

    if [[ -n "${MG_UPDATE_TARBALL_PATH:-}" ]]; then
        tarpath="$MG_UPDATE_TARBALL_PATH"
        [[ -f "$tarpath" ]] || { err "MG_UPDATE_TARBALL_PATH not a file: $tarpath"; return 4; }
    else
        # /tarball/{tag} works for any ref (tag/branch/sha) and 302s to
        # codeload — independent of whether a GitHub "Release" object exists.
        # Using /releases/tags/{tag} + .tarball_url is fragile (404s on tags
        # that were never promoted to Release objects).
        local url="https://api.github.com/repos/invertome/molluscagenes/tarball/${tag}"
        tarpath="$tmp/release.tar.gz"
        if ! curl -fsSL --max-time 600 "$url" -o "$tarpath"; then
            err "tarball download failed: $url"; return 4
        fi
    fi

    if ! tar -xzf "$tarpath" -C "$tmp"; then
        err "tarball extract failed: $tarpath"; return 4
    fi
    # The tarball contains a single top-level dir (GH names it
    # "<user>-<repo>-<short-sha>/"). Find it.
    src=$(find "$tmp" -mindepth 1 -maxdepth 1 -type d ! -name 'release*' | head -1)
    [[ -d "$src" ]] || { err "could not locate extracted tree under $tmp"; return 4; }

    # Sanity: the extracted tree should itself look like a MolluscaGenes repo
    if ! is_molluscagenes_repo "$src"; then
        err "extracted tarball doesn't look like a MolluscaGenes repo: $src"
        return 4
    fi

    if ! command -v rsync >/dev/null 2>&1; then
        err "rsync required for tarball-mode update (install rsync, or use git clone)"
        return 4
    fi

    rsync -a --delete \
        --exclude='/config.sh' \
        --exclude='/metadata/_cache/' \
        --exclude='/downloads/' \
        --exclude='/runs/' \
        --exclude='/.git/' \
        --exclude='/.molluscagenes_version' \
        "$src/" "$d/" || { err "rsync overlay failed"; return 4; }

    echo "$tag" > "$d/.molluscagenes_version"
}

# --- main --------------------------------------------------------------------
if ! repo=$(resolve_repo); then
    exit 4
fi
info "repo: $repo"

mode=$(detect_install "$repo")
info "mode: $mode"

current=$(current_version "$repo" "$mode")
info "current: $current"

latest=$(latest_version "$repo" "$mode")
info "latest: $latest"

if [[ "$current" == "$latest" && "$latest" != "unknown" ]]; then
    info "already at $latest (no code update needed)"
    already_at_latest=yes
else
    info "update available: $current -> $latest"
    already_at_latest=no
fi

if [[ "$check_only" == "yes" ]]; then
    # --check-only is read-only by design: don't run env/cache/tool/data checks
    # since some (verify_data) are slow on real installs. Users wanting full
    # status should run without --check-only.
    exit 0
fi

if [[ "$dry_run" == "yes" ]]; then
    if [[ "$already_at_latest" == "yes" ]]; then
        info "DRY RUN: already at $latest; would skip update"
    else
        info "DRY RUN: would update $mode install $current -> $latest"
    fi
    exit 0
fi

# Snapshot files we'll diff after the update (only meaningful if we update).
snap=$(mktemp -d)
trap 'rm -rf "$snap"' EXIT
[[ -f "$repo/environment.yml" ]]               && cp "$repo/environment.yml"               "$snap/environment.yml"
[[ -f "$repo/metadata/species_metadata.tsv" ]] && cp "$repo/metadata/species_metadata.tsv" "$snap/species_metadata.tsv"

if [[ "$already_at_latest" != "yes" ]]; then
    if [[ "$mode" == "git" ]]; then
        if ! update_code_git "$repo" "$latest"; then
            exit 4
        fi
    else
        if ! update_code_tarball "$repo" "$latest"; then
            exit 4
        fi
    fi
    info "updated: $current -> $latest"
fi

# --- post-update checks ------------------------------------------------------

env_status=0
data_status=0

# environment.yml diff -> advisory; status=2 only if env currently active.
if [[ -f "$snap/environment.yml" && -f "$repo/environment.yml" ]] \
        && ! cmp -s "$snap/environment.yml" "$repo/environment.yml"; then
    info "environment.yml changed:"
    diff -u "$snap/environment.yml" "$repo/environment.yml" 2>&1 | sed 's/^/  /' | head -40
    info "to refresh runtime tools:"
    info "    conda activate molluscagenes"
    info "    conda env update -f $repo/environment.yml --prune"
    if [[ "${CONDA_DEFAULT_ENV:-}" == "molluscagenes" ]]; then
        env_status=2
        info "(current shell is inside the molluscagenes env; rerun after env update)"
    fi
fi

# Tool presence + versions (advisory; status=2 if any required tool is missing).
if [[ "$verify_tools" == "yes" ]]; then
    info "tools:"
    # Default = union of dependencies pulled in by mg_blast.sh, mg_diamond.sh,
    # mg_hmmsearch.sh, mg_fetch.sh, mg_characterize.sh. Override via
    # MG_UPDATE_REQUIRED_TOOLS for testing / custom environments.
    default_tools="curl jq sha256sum tar rsync awk blastp makeblastdb blastdbcmd diamond hmmsearch hmmpress"
    read -r -a tool_list <<<"${MG_UPDATE_REQUIRED_TOOLS:-$default_tools}"
    missing=0
    for cmd in "${tool_list[@]}"; do
        if path=$(command -v "$cmd" 2>/dev/null); then
            ver=$("$cmd" --version 2>&1 | head -1 || echo '?')
            printf '  OK   %-15s  %s\n' "$cmd" "$ver"
        else
            printf '  MISS %s\n' "$cmd"
            missing=1
        fi
    done
    if [[ "$missing" -ne 0 ]]; then
        env_status=2
    fi
fi

# Data verification: delegate to verify_download.sh against $MG_BLAST_DIR.
if [[ "$verify_data" == "yes" ]]; then
    info "data:"
    if [[ -z "${MG_BLAST_DIR:-}" ]]; then
        info "  MG_BLAST_DIR not set (source config.sh); skipping data verify"
        env_status=2
    elif [[ ! -d "$MG_BLAST_DIR" ]]; then
        info "  MG_BLAST_DIR does not exist: $MG_BLAST_DIR"
        env_status=2
    elif "$repo/wrappers/verify_download.sh" "$MG_BLAST_DIR" >/dev/null 2>&1; then
        info "  data: all files match manifest"
    else
        info "  data is out of date for $latest"
        info "  to refresh:"
        info "      $repo/wrappers/mg_fetch.sh \"\$MG_BLAST_DIR\""
        data_status=1
    fi
fi

# Smart cache purge: only when species_metadata.tsv actually changed.
if [[ "$purge_cache" == "yes" && -f "$snap/species_metadata.tsv" && -f "$repo/metadata/species_metadata.tsv" ]] \
        && ! cmp -s "$snap/species_metadata.tsv" "$repo/metadata/species_metadata.tsv"; then
    cache="$repo/metadata/_cache/subset_dbs"
    if [[ -d "$cache" ]]; then
        n=$(find "$cache" -mindepth 1 -maxdepth 1 -type d | wc -l)
        info "species_metadata.tsv changed -> purging $n subset-DB cache entries"
        rm -rf "$cache"
    fi
fi

# Final exit code combines the per-section statuses.
# (data_status added in a later cycle.)
case "$env_status:$data_status" in
    0:0) exit 0 ;;
    0:1) exit 1 ;;
    2:0) exit 2 ;;
    2:1) exit 3 ;;
esac

# Stop here for now; later cycles fill in post-update verify.
exit 0
