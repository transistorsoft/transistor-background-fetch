#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# TSBackgroundFetch iOS — Build & Publish
#
# Usage:
#   ./scripts/publish-ios.sh --version X.Y.Z --dry-run                # preview: build + package only
#   ./scripts/publish-ios.sh --version X.Y.Z [--notes "msg"]          # publish, INCLUDING the CocoaPods Trunk push
#   ./scripts/publish-ios.sh --version X.Y.Z --no-cocoapods           # publish, skip Trunk (push the podspec by hand)
#   INCLUDE_CATALYST=0 ./scripts/publish-ios.sh --version X.Y.Z
#
#   For a release, use --version (not --bump) and don't use --create-branch: see Options.
#
# Options:
#   --version X.Y.Z         Explicit version to publish/tag. Use this rather than --bump.
#   --bump (patch|minor|major)
#                          Bump from latest remote semver tag. If `git ls-remote` fails, the latest
#                          tag falls back to 0.0.0 without a warning, so --bump patch gives 0.0.1.
#   --notes "text"          Release notes (defaults to "<BINARY> <VERSION>").
#   --dry-run               Build and package only (no GitHub, no commits/tags). It does not stop
#                          --create-branch from switching branches.
#   --no-build              Skip building xcframework (use --xcframework-dir).
#   --xcframework-dir PATH  Use an existing .xcframework directory.
#   --push-cocoapods        Run `pod spec lint` + `pod trunk push` at the end. This is the DEFAULT
#                          (PUSH_COCOAPODS=1), so the flag changes nothing.
#   --no-cocoapods          Skip the CocoaPods Trunk push, and the `pod trunk me` check at startup.
#                          Then push the podspec by hand from the tagged commit, following the
#                          Trunk retry rules in WO-001.
#   --retag                 Overwrite the existing remote tag if already present.
#   --create-branch          NOT FOR RELEASES. Switches to a branch cut from origin/<base> (default
#                           name: releases/<VERSION>) AFTER the "Bump version" commit was made on
#                           the current branch, so the framework is built with the previous
#                           version. The switch happens even with --dry-run.
#   --branch-name NAME       Override the branch name used with --create-branch
#   --base BRANCH            Base branch to branch from and target PR to (auto-detects origin/HEAD)
#   --create-pr              Open a GitHub pull request from the release branch to --base
#   --auto-merge MODE        Auto-merge the PR with MODE: merge|squash|rebase (requires --create-pr)
#   --yes, -y                Skip interactive confirmation prompt (for CI/automation)
#
# Defaults:
#   PUBLIC_REPO=transistorsoft/transistor-background-fetch
#   BINARY_NAME=TSBackgroundFetch
#   PODSPEC_NAME=TSBackgroundFetch.podspec
#   INCLUDE_CATALYST=0
#
# Requirements:
#   - Xcode command-line tools
#   - zip, swift
#   - GitHub CLI (`gh`) authenticated for the PUBLIC_REPO owner
#   - CocoaPods (`pod`) with a Trunk session for the publishing account (checked at startup
#     with `pod trunk me`), unless --no-cocoapods
#
# Notes:
#   - This script operates directly on THIS repo (public).
#   - The GitHub Release is created/updated and the xcframework zip is uploaded.
#   - Package.swift and the podspec are updated in-place (commit + tag + push).
#   - Run it from an interactive terminal. It commits "Bump version to <VERSION>" (and, if it
#     opened $EDITOR on CHANGELOG-iOS.md, "Update CHANGELOG for <VERSION>") BEFORE it asks
#     "Proceed with publish? [y/N]", so answering N leaves those commits on the current branch.
#   - CocoaPods Trunk is read-only from 2026-12-02 (WO-001): from then on, pass
#     --no-cocoapods. To retry a failed Trunk push, push the podspec by hand; never re-run this
#     script for it. A re-run rebuilds the zip, whose checksum then differs from the uploaded
#     asset, and --retag would replace the asset that SwiftPM users have already resolved.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." &>/dev/null && pwd)"

PUBLIC_REPO="${PUBLIC_REPO:-transistorsoft/transistor-background-fetch}"
BINARY_NAME="${BINARY_NAME:-TSBackgroundFetch}"
INCLUDE_CATALYST="${INCLUDE_CATALYST:-0}"
PODSPEC_NAME="${PODSPEC_NAME:-TSBackgroundFetch.podspec}"

has_gh() { command -v gh >/dev/null 2>&1; }
has_pod() { command -v pod >/dev/null 2>&1; }
die() { echo "❌ $*" >&2; exit 1; }

# -------- load versioning defaults --------
VERSION_FILE="${REPO_ROOT}/versioning/${BINARY_NAME}.properties"
if [[ -f "${VERSION_FILE}" ]]; then
  MV="$(grep -E '^MARKETING_VERSION=' "${VERSION_FILE}" | cut -d'=' -f2- | tr -d '\r' || true)"
  CV="$(grep -E '^CURRENT_PROJECT_VERSION=' "${VERSION_FILE}" | cut -d'=' -f2- | tr -d '\r' || true)"
  if [[ -n "${MV}" ]]; then
    export MARKETING_VERSION="${MV}"
  fi
  if [[ -n "${CV}" ]]; then
    export CURRENT_PROJECT_VERSION="${CV}"
  fi
fi

# --- CocoaPods trunk session guard (fail-fast unless --no-cocoapods; pushing is the default) ---
require_cocoapods_trunk() {
  [[ "$PUSH_COCOAPODS" -eq 1 ]] || return 0

  has_pod || die "CocoaPods 'pod' CLI not found. Install with: sudo gem install cocoapods"

  echo "▶ Checking CocoaPods trunk session (pod trunk me)"
  set +e
  local me_out
  me_out="$(pod trunk me 2>&1)"
  local rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    echo "$me_out" | sed 's/^/    /' >&2
    die "Not logged into CocoaPods trunk. Run:\n\n    pod trunk register chris@transistorsoft.com 'Transistor Software' --description='iOS SDK publisher'\n\nThen run:\n\n    pod trunk me\n"
  fi

  # Ensure output contains the expected email (avoid publishing from wrong trunk account)
  if ! echo "$me_out" | grep -Eqi "Email:[[:space:]]*chris@transistorsoft\.com"; then
    echo "$me_out" | sed 's/^/    /' >&2
    die "CocoaPods trunk account mismatch. Expected chris@transistorsoft.com.\n\nIf you need to register this machine, run:\n\n    pod trunk register chris@transistorsoft.com 'Transistor Software' --description='iOS SDK publisher'\n"
  fi

  echo "✅ CocoaPods trunk session OK"
}

# ----- args -----
VERSION=""
BUMP_MODE=""
RELEASE_NOTES=""
DRY_RUN=0
NO_BUILD=0
XCFRAMEWORK_DIR_OVERRIDE=""
PUSH_COCOAPODS=1
RETAG=0
CREATE_BRANCH=0
BRANCH_NAME=""
BASE_BRANCH=""
CREATE_PR=0
AUTO_MERGE=""
VERSION_SOURCE=""
SKIP_TAG_PUSH=0
AUTO_CONFIRM=0

usage() {
  cat <<USAGE
Usage:
  ./scripts/publish-ios.sh --version X.Y.Z [--notes "msg"] [--no-cocoapods] [--retag]
  ./scripts/publish-ios.sh --bump patch|minor|major [--notes "msg"]
  INCLUDE_CATALYST=0 ./scripts/publish-ios.sh --version X.Y.Z

Options:
  --version X.Y.Z           Explicit version to publish/tag
  --bump patch|minor|major  Bump from latest remote semver tag (falls back to 0.0.0 if the
                            lookup fails; prefer --version)
  --notes "text"            Release notes text
  --dry-run                 Build and package only (no Git, no tags, no GitHub release).
  --no-build                Skip building (requires --xcframework-dir)
  --xcframework-dir PATH    Use existing .xcframework directory
  --push-cocoapods          Run pod lint + trunk push at the end (default)
  --no-cocoapods            Skip CocoaPods trunk push
  --retag                   Overwrite existing remote tag if present
  --create-branch            Switch to a new branch (default: releases/<VERSION>). NOT for releases:
                             it is cut from the base after the version-bump commit, so the framework
                             reports the previous version. It switches even under --dry-run.
  --branch-name NAME         Override branch name when using --create-branch
  --base BRANCH              Base branch to branch from / PR target (auto-detected)
  --create-pr                Open a GitHub PR from the release branch to --base
  --auto-merge MODE          Auto-merge the PR (merge|squash|rebase); implies --create-pr
  --yes, -y                  Skip interactive confirmation prompt (for CI/automation)

Notes:
  If --version/--bump are omitted, the script will try to read the latest version
  heading from CHANGELOG-iOS.md (e.g., "## 4.0.2") and prompt:
    > Publish version X.Y.Z? [y/N]
USAGE
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2;;
    --bump) BUMP_MODE="${2:-}"; shift 2;;
    --notes) RELEASE_NOTES="${2:-}"; shift 2;;
    --dry-run) DRY_RUN=1; shift;;
    --no-build) NO_BUILD=1; shift;;
    --xcframework-dir) XCFRAMEWORK_DIR_OVERRIDE="${2:-}"; shift 2;;
    --push-cocoapods) PUSH_COCOAPODS=1; shift;;
    --no-cocoapods) PUSH_COCOAPODS=0; shift;;
    --retag) RETAG=1; shift;;
    --create-branch) CREATE_BRANCH=1; shift;;
    --branch-name) BRANCH_NAME="${2:-}"; shift 2;;
    --base) BASE_BRANCH="${2:-}"; shift 2;;
    --create-pr) CREATE_PR=1; shift;;
    --auto-merge) AUTO_MERGE="${2:-}"; shift 2;;
    --yes|-y) AUTO_CONFIRM=1; shift;;
    -h|--help) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

# Fail fast: check CocoaPods trunk session before doing anything
require_cocoapods_trunk

# Require gh auth
has_gh || die "GitHub CLI 'gh' not found. Install from https://cli.github.com/"
gh auth status >/dev/null 2>&1 || die "GitHub CLI is not authenticated. Run: gh auth login"

# -------- helpers --------

# Latest iOS version on the remote: "ios/X.Y.Z" tags plus bare "X.Y.Z" tags (SwiftPM
# tags, and iOS releases from before the ios/ prefix). "android/X.Y.Z" is excluded.
latest_semver_tag() {
  git ls-remote --tags --refs "https://github.com/${PUBLIC_REPO}.git" 2>/dev/null \
    | awk '{print $2}' | sed -e 's|^refs/tags/||' -e 's|^ios/||' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V | tail -1 || true
}

bump_semver() {
  local cur="$1" mode="$2"
  [[ "$cur" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || die "Cannot bump non-semver tag: $cur"
  local MA="${BASH_REMATCH[1]}" MI="${BASH_REMATCH[2]}" PA="${BASH_REMATCH[3]}"
  case "$mode" in
    patch) echo "${MA}.${MI}.$((PA+1))";;
    minor) echo "${MA}.$((MI+1)).0";;
    major) echo "$((MA+1)).0.0";;
    *) die "Unknown bump mode: $mode";;
  esac
}

# Compute CURRENT_PROJECT_VERSION from semver (e.g. 4.0.6 -> 4006)
semver_to_project_version() {
  local v="$1"
  [[ "$v" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || { echo ""; return; }
  echo "$(( BASH_REMATCH[1] * 1000 + BASH_REMATCH[2] * 100 + BASH_REMATCH[3] ))"
}

# Write version back to properties file and export for the rest of the script
update_version_file() {
  local version="$1"
  local project_version
  project_version="$(semver_to_project_version "$version")"
  [[ -z "$project_version" ]] && return

  mkdir -p "$(dirname "${VERSION_FILE}")"

  echo "▶ Updating ${VERSION_FILE}:"
  echo "    MARKETING_VERSION=${version}"
  echo "    CURRENT_PROJECT_VERSION=${project_version}"

  cat > "${VERSION_FILE}" <<EOF
MARKETING_VERSION=${version}
CURRENT_PROJECT_VERSION=${project_version}
EOF

  export MARKETING_VERSION="$version"
  export CURRENT_PROJECT_VERSION="$project_version"

  git -C "$REPO_ROOT" add "${VERSION_FILE}"
  if ! git -C "$REPO_ROOT" diff --cached --quiet -- "${VERSION_FILE}"; then
    git -C "$REPO_ROOT" commit -m "Bump version to ${version}"
  fi
}

# Read top version from CHANGELOG-iOS.md
version_from_changelog() {
  local changelog="${REPO_ROOT}/CHANGELOG-iOS.md"
  if [[ -f "$changelog" ]]; then
    local v
    v="$(grep -E '^\s*##\s*v?[0-9]+\.[0-9]+\.[0-9]+' "$changelog" | head -1 | sed -E 's/^\s*##\s*v?([0-9]+\.[0-9]+\.[0-9]+).*$/\1/')"
    [[ -n "$v" ]] && echo "$v"
  fi
}

# Extract release notes for a specific version heading from CHANGELOG-iOS.md
changelog_notes_for_version() {
  local v="$1"
  local f="${REPO_ROOT}/CHANGELOG-iOS.md"
  [[ -f "$f" ]] || return 0
  awk -v ver="$v" '
    BEGIN{found=0}
    /^##[[:space:]]+/{
      if(found) exit
      gsub(/\r/,"")
      if(index($0,ver)>0){found=1; next}
    }
    found{print}
  ' "$f" | sed 's/^[[:space:]]*\* /- /' | sed 's/^[[:space:]]*$//'
}

# Release notes for VERSION. Before publish, this release's entries still sit under
# "## Unreleased" (renamed to "## VERSION" later in this script), so fall back to it.
release_notes_from_changelog() {
  local notes
  notes="$(changelog_notes_for_version "$VERSION" | sed '/^$/d')"
  if [[ -z "$notes" ]]; then
    notes="$(changelog_notes_for_version "Unreleased" | sed '/^$/d')"
  fi
  echo "$notes"
}

resolve_version() {
  if [[ -n "$VERSION" && -n "$BUMP_MODE" ]]; then die "--version and --bump are mutually exclusive"; fi

  if [[ -n "$VERSION" ]]; then
    VERSION_SOURCE="arg"
    echo "$VERSION"
    return
  fi

  if [[ -n "$BUMP_MODE" ]]; then
    local latest; latest="$(latest_semver_tag)"; [[ -n "$latest" ]] || latest='0.0.0'
    VERSION_SOURCE="bump"
    bump_semver "$latest" "$BUMP_MODE"
    return
  fi

  if [[ -n "${MARKETING_VERSION:-}" ]]; then
    VERSION_SOURCE="marketing"
    echo "$MARKETING_VERSION"
    return
  fi

  # Try CHANGELOG-iOS.md as an interactive suggestion
  local from_changelog; from_changelog="$(version_from_changelog || true)"
  if [[ -n "$from_changelog" ]]; then
    VERSION_SOURCE="changelog"
    echo "$from_changelog"
    return
  fi

  # Fallback to latest remote semver tag
  local latest; latest="$(latest_semver_tag)"
  if [[ -n "$latest" ]]; then
    VERSION_SOURCE="remote"
    echo "$latest"
    return
  fi

  VERSION_SOURCE="dev"
  echo "dev"
}

# ---- Generate CHANGELOG-iOS.md from git log since last tag ----
generate_changelog() {
  local changelog="${REPO_ROOT}/CHANGELOG-iOS.md"

  # Find the most recent local tag that is an ancestor of HEAD
  local prev_tag=""
  local tag
  while IFS= read -r tag; do
    if git -C "$REPO_ROOT" merge-base --is-ancestor "$tag" HEAD 2>/dev/null; then
      prev_tag="$tag"
    fi
  done < <(git -C "$REPO_ROOT" tag -l 'ios/*' | sed 's|^ios/||' | sort -V)

  if [[ -z "$prev_tag" ]]; then
    echo "⚠️  No reachable tag found on current branch — skipping changelog generation"
    return
  fi

  # If there's already an Unreleased section with content, don't overwrite
  if grep -q '^## Unreleased' "$changelog" 2>/dev/null; then
    local entry_count
    entry_count="$(awk '/^## Unreleased/{found=1;next} /^##/{exit} found && /^\* /{c++} END{print c+0}' "$changelog")"
    if [[ "$entry_count" -gt 0 ]]; then
      echo "ℹ️  CHANGELOG-iOS.md already has ${entry_count} entries under '## Unreleased' — skipping generation"
      return
    fi
  fi

  # Collect commit subjects since last tag, filtering out noise
  local commits_file
  commits_file="$(mktemp)"
  git -C "$REPO_ROOT" log "${prev_tag}..HEAD" --pretty=format:'%s' --no-merges \
    | { grep -Eiv '^(fix(up)?|changelog|bump|\[release\]|#)' || true; } \
    | sed '/^\[iOS\]/!{/^\[Android\]/!s/^/[iOS] /;}' \
    | sed 's/^/* /' \
    > "$commits_file"

  if [[ ! -s "$commits_file" ]]; then
    echo "ℹ️  No new commits since ${prev_tag} — nothing to add to CHANGELOG-iOS.md"
    rm -f "$commits_file"
    return
  fi

  echo "▶ Generating CHANGELOG-iOS.md entries from commits since ${prev_tag}:"
  sed 's/^/    /' "$commits_file"

  # Build new changelog with commits inserted under ## Unreleased
  local tmpfile
  tmpfile="$(mktemp)"

  if grep -q '^## Unreleased' "$changelog" 2>/dev/null; then
    # Insert commits after existing ## Unreleased heading
    while IFS= read -r line; do
      printf '%s\n' "$line"
      if [[ "$line" == "## Unreleased"* ]]; then
        cat "$commits_file"
      fi
    done < "$changelog" > "$tmpfile"
  elif [[ -f "$changelog" ]]; then
    # Insert ## Unreleased section after # CHANGELOG heading
    while IFS= read -r line; do
      printf '%s\n' "$line"
      if [[ "$line" == "# CHANGELOG"* ]]; then
        echo ""
        echo "## Unreleased"
        cat "$commits_file"
      fi
    done < "$changelog" > "$tmpfile"
  else
    { echo "# CHANGELOG"; echo ""; echo "## Unreleased"; cat "$commits_file"; } > "$tmpfile"
  fi

  rm -f "$commits_file"
  mv "$tmpfile" "$changelog"

  # Open in editor for curation
  local editor="${EDITOR:-vim}"
  echo "▶ Opening CHANGELOG-iOS.md in ${editor} for review..."
  "$editor" "$changelog"

  # Stage the updated changelog
  git -C "$REPO_ROOT" add CHANGELOG-iOS.md
  if ! git -C "$REPO_ROOT" diff --cached --quiet -- CHANGELOG-iOS.md; then
    git -C "$REPO_ROOT" commit -m "Update CHANGELOG for ${VERSION}"
  fi
}

VERSION="$(resolve_version)"

# Coerce VERSION to pure semver (e.g., "## 4.0.2 — 2025-11-07" -> "4.0.2")
if [[ -n "${VERSION:-}" ]]; then
  if [[ "$VERSION" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
    VERSION="${BASH_REMATCH[1]}"
  fi
fi

# If version was inferred from CHANGELOG, prompt for confirmation
if [[ "$VERSION_SOURCE" == "changelog" && "$AUTO_CONFIRM" -eq 0 ]]; then
  echo "⚙️  Detected version ${VERSION} from CHANGELOG-iOS.md"
  read -r -p "> Publish version ${VERSION}? [y/N] " _ans
  case "${_ans:-}" in
    y|Y|yes|YES)
      ;;
    *)
      die "Aborted. Provide --version X.Y.Z or use --bump patch|minor|major."
      ;;
  esac
fi

# Update versioning file (skip in dry-run mode)
if [[ "$DRY_RUN" -eq 0 ]]; then
  update_version_file "$VERSION"
fi

echo "ℹ️  Version: ${VERSION}"
echo "ℹ️  Public repo: ${PUBLIC_REPO}"
echo "ℹ️  Catalyst: $( [[ "$INCLUDE_CATALYST" == "1" ]] && echo ENABLED || echo DISABLED )"

# Generate changelog interactively (skip when --yes or dry-run)
if [[ "$AUTO_CONFIRM" -eq 0 && "$DRY_RUN" -eq 0 ]]; then
  generate_changelog
fi

# Determine default base branch if not provided
detect_default_branch() {
  local head
  head="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -n "$head" ]]; then
    echo "${head#origin/}"
    return
  fi
  if git show-ref --verify --quiet refs/remotes/origin/main; then echo "main"; return; fi
  if git show-ref --verify --quiet refs/remotes/origin/master; then echo "master"; return; fi
  git rev-parse --abbrev-ref HEAD
}

if [[ -z "$BASE_BRANCH" ]]; then
  BASE_BRANCH="$(detect_default_branch)"
fi
echo "ℹ️  Base branch: ${BASE_BRANCH}"

# Optionally create and switch to a release branch. This runs AFTER the "Bump version" commit
# above and is not skipped by --dry-run, so it is not for releases (see --create-branch in the header).
if [[ "$CREATE_BRANCH" -eq 1 ]]; then
  if [[ -z "$BRANCH_NAME" ]]; then
    _ver_for_branch="$VERSION"
    _ver_for_branch="$(echo "$_ver_for_branch" | sed -E 's/[^A-Za-z0-9._-]+/-/g')"
    BRANCH_NAME="releases/${_ver_for_branch}"
  fi
  echo "▶ Creating release branch '${BRANCH_NAME}' from '${BASE_BRANCH}'"
  pushd "${REPO_ROOT}" >/dev/null
  git fetch origin "${BASE_BRANCH}" --quiet || true
  if git rev-parse --verify --quiet "refs/heads/${BRANCH_NAME}"; then
    git switch "${BRANCH_NAME}"
  else
    git switch -c "${BRANCH_NAME}" "origin/${BASE_BRANCH}"
  fi
  popd >/dev/null
fi

IOS_TAG="ios/${VERSION}"
# SwiftPM reads versions only from bare semver tags (X.Y.Z / vX.Y.Z) and ignores
# "ios/X.Y.Z", so the release commit also gets a bare tag; without it, SPM consumers
# (`from: "4.1.0"`) never see this version. The ios/ tag stays the GitHub Release tag
# and the asset URL. The bare tag is pushed last, once the asset checksum is verified,
# so SPM never resolves a version whose binary isn't downloadable yet.
SPM_TAG="${VERSION}"
SKIP_SPM_TAG_PUSH=0
remote_tag_exists() {
  git ls-remote --tags "https://github.com/${PUBLIC_REPO}.git" "refs/tags/${IOS_TAG}" | grep -q "refs/tags/${IOS_TAG}"
}
if remote_tag_exists; then
  if [[ "$RETAG" -ne 1 ]]; then
    remote_sha="$(git ls-remote --tags "https://github.com/${PUBLIC_REPO}.git" "refs/tags/${IOS_TAG}" | awk '{print $1}')"
    local_sha=""
    if git rev-parse -q --verify "refs/tags/${IOS_TAG}" >/dev/null 2>&1; then
      local_sha="$(git rev-parse -q "${IOS_TAG}^{}" 2>/dev/null || true)"
    fi

    if [[ -n "$local_sha" && "$local_sha" != "$remote_sha" ]]; then
      echo "❌ Tag '${IOS_TAG}' already exists on remote and points to a different commit."
      echo "   remote: ${remote_sha}"
      echo "   local : ${local_sha}"
      echo "   Use --retag to overwrite the remote tag, or bump with --bump patch|minor|major."
      exit 1
    fi

    echo "ℹ️  Tag '${IOS_TAG}' already exists on remote and matches; will skip re-pushing this tag."
    SKIP_TAG_PUSH=1
  fi
fi

# The bare SPM tag must point at the same commit as the ios/ tag.
REMOTE_SPM_SHA="$(git ls-remote --tags --refs "https://github.com/${PUBLIC_REPO}.git" "refs/tags/${SPM_TAG}" | awk '{print $1}' | head -1)"
if [[ -n "$REMOTE_SPM_SHA" && "$RETAG" -ne 1 ]]; then
  REMOTE_IOS_SHA="$(git ls-remote --tags --refs "https://github.com/${PUBLIC_REPO}.git" "refs/tags/${IOS_TAG}" | awk '{print $1}' | head -1)"
  if [[ "$REMOTE_SPM_SHA" == "$REMOTE_IOS_SHA" ]]; then
    echo "ℹ️  Tag '${SPM_TAG}' already exists on remote and matches '${IOS_TAG}'; will skip re-pushing it."
    SKIP_SPM_TAG_PUSH=1
  else
    echo "❌ Tag '${SPM_TAG}' already exists on remote but does not point at '${IOS_TAG}'."
    echo "   ${SPM_TAG}: ${REMOTE_SPM_SHA}"
    echo "   ${IOS_TAG}: ${REMOTE_IOS_SHA:-(not on remote)}"
    echo "   Use --retag to overwrite the remote tags, or bump with --bump patch|minor|major."
    exit 1
  fi
fi

# Resolve release notes from CHANGELOG-iOS.md if not provided
if [[ -z "$RELEASE_NOTES" ]]; then
  notes="$(release_notes_from_changelog)"
  if [[ -n "$notes" ]]; then
    RELEASE_NOTES="$notes"
    echo "ℹ️  Notes (from CHANGELOG-iOS.md):"
    echo "$RELEASE_NOTES" | sed 's/^/    /'
  fi
fi

OUT_ROOT="${REPO_ROOT}/build/Release-Publish/${BINARY_NAME}_XCFramework_${VERSION}"
XCFRAMEWORK_DIR_DEFAULT="${OUT_ROOT}/${BINARY_NAME}.xcframework"

if [[ "$NO_BUILD" -eq 0 ]]; then
  echo "▶ Building XCFramework..."
  VERSION="$VERSION" INCLUDE_CATALYST="$INCLUDE_CATALYST" "${SCRIPT_DIR}/build-ios.sh" --version "$VERSION"
else
  echo "↷ Skipping build (--no-build)"
fi

XC_DIR="${XCFRAMEWORK_DIR_OVERRIDE:-$XCFRAMEWORK_DIR_DEFAULT}"
[[ -d "$XC_DIR" ]] || die "XCFramework not found at: $XC_DIR (use --xcframework-dir to override)"
echo "ℹ️  XCFramework: $XC_DIR"

# ---- DRY RUN (simulate publish with local zip/checksum; no network or git changes) ----
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "🧪 Dry run: build complete — simulating publish steps (no network or git changes)."

  ZIP_NAME="${BINARY_NAME}.xcframework.zip"
  DRY_TMPDIR="$(mktemp -d)"
  ZIP_PATH="${DRY_TMPDIR}/${ZIP_NAME}"

  echo "▶ (dry-run) Packaging XCFramework → ${ZIP_PATH}"
  cp "${REPO_ROOT}/LICENSE" "$(dirname "$XC_DIR")/LICENSE" 2>/dev/null || true
  ( cd "$(dirname "$XC_DIR")" && /usr/bin/zip -yr "$ZIP_PATH" "$(basename "$XC_DIR")" LICENSE ) >/dev/null

  echo "▶ (dry-run) Computing SPM checksum"
  CHECKSUM="$(swift package compute-checksum "$ZIP_PATH")"
  echo "   checksum: $CHECKSUM"

  ASSET_URL="https://github.com/${PUBLIC_REPO}/releases/download/${IOS_TAG}/${ZIP_NAME}"

  # Preview release notes
  if [[ -z "$RELEASE_NOTES" ]]; then
    notes="$(release_notes_from_changelog)"
    [[ -n "$notes" ]] && RELEASE_NOTES="$notes"
  fi

  echo
  echo "– Would update versioning/${BINARY_NAME}.properties:"
  echo "    MARKETING_VERSION=${VERSION}"
  echo "    CURRENT_PROJECT_VERSION=$(semver_to_project_version "$VERSION")"

  if grep -q '^## Unreleased' "${REPO_ROOT}/CHANGELOG-iOS.md" 2>/dev/null; then
    echo "– Would rename '## Unreleased' → '## ${VERSION} &mdash; $(date +%Y-%m-%d)' in CHANGELOG-iOS.md"
  fi

  echo
  echo "– Would create/update GitHub Release:"
  echo "    tag:        ${IOS_TAG}"
  echo "    prerelease: $([[ "$VERSION" == *-* ]] && echo true || echo false)"
  echo "    asset:      ${ZIP_NAME}"
  echo "    url:        ${ASSET_URL}"
  if [[ -n "$RELEASE_NOTES" ]]; then
    echo "    notes:"
    echo "$RELEASE_NOTES" | sed 's/^/      /'
  else
    echo "    notes:      ${BINARY_NAME} ${VERSION}"
  fi
  echo
  echo "– Would update Package.swift url + checksum"
  echo "– Would update ${PODSPEC_NAME} version + source url"

  if [[ "$CREATE_BRANCH" -eq 1 ]]; then
    echo "– Would create branch: releases/${VERSION} (base: ${BASE_BRANCH})"
    [[ "$CREATE_PR" -eq 1 ]] && echo "– Would open PR: releases/${VERSION} → ${BASE_BRANCH}"
  else
    echo "– Would commit on ${BASE_BRANCH}"
  fi
  echo "– Would tag: ${IOS_TAG}"
  echo "– Would push branch/tag to origin for ${PUBLIC_REPO}"
  if [[ "$SKIP_SPM_TAG_PUSH" -eq 1 ]]; then
    echo "– Would skip SwiftPM tag ${SPM_TAG} (already on remote, matches ${IOS_TAG})"
  else
    echo "– Would tag ${SPM_TAG} (SwiftPM version) at ${IOS_TAG}'s commit and push it after the asset checksum verifies"
  fi

  if [[ "$PUSH_COCOAPODS" -eq 1 ]]; then
    echo
    echo "– Would run CocoaPods validation & publish:"
    echo "    pod spec lint ${PODSPEC_NAME} --skip-import-validation --allow-warnings"
    echo "    pod trunk push ${PODSPEC_NAME} --skip-import-validation --allow-warnings"
  fi

  echo
  echo "🧪 Dry run finished. No changes were made."
  rm -rf "$DRY_TMPDIR"
  exit 0
fi

# ---- Publish confirmation prompt ----
echo ""
echo "┌─────────────────────────────────────────────┐"
echo "│            PUBLISH CONFIRMATION             │"
echo "└─────────────────────────────────────────────┘"
echo ""
echo "  Version:        ${VERSION}"
echo "  Public repo:    ${PUBLIC_REPO}"
echo "  Catalyst:       $( [[ "$INCLUDE_CATALYST" == "1" ]] && echo ENABLED || echo DISABLED )"
echo "  CocoaPods push: $( [[ "$PUSH_COCOAPODS" -eq 1 ]] && echo YES || echo "NO (--no-cocoapods)" )"
echo "  Verify tag:     $( [[ "$SKIP_TAG_PUSH" -eq 1 ]] && echo "SKIP (tag exists)" || echo YES )"
echo "  SwiftPM tag:    ${SPM_TAG}$( [[ "$SKIP_SPM_TAG_PUSH" -eq 1 ]] && echo " (SKIP, tag exists)" || echo " (pushed after checksum verify)" )"
if [[ "$CREATE_BRANCH" -eq 1 ]]; then
  echo "  Branch:         ${BRANCH_NAME:-releases/${VERSION}}"
  [[ "$CREATE_PR" -eq 1 ]] && echo "  Pull request:   ${BRANCH_NAME:-releases/${VERSION}} → ${BASE_BRANCH}"
  [[ -n "$AUTO_MERGE" ]] && echo "  Auto-merge:     ${AUTO_MERGE}"
else
  echo "  Commit target:  ${BASE_BRANCH} (direct push)"
fi
if [[ -n "$RELEASE_NOTES" ]]; then
  echo ""
  echo "  Release notes:"
  echo "$RELEASE_NOTES" | sed 's/^/    /'
fi
echo ""

if [[ "$AUTO_CONFIRM" -eq 0 ]]; then
  read -rp "Proceed with publish? [y/N] " answer
  case "$answer" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Aborted."; exit 0;;
  esac
fi

# ---------------- Publish ----------------

ZIP_NAME="${BINARY_NAME}.xcframework.zip"
PUBLISH_TMPDIR="$(mktemp -d)"
ZIP_PATH="${PUBLISH_TMPDIR}/${ZIP_NAME}"

echo "▶ Packaging XCFramework → ${ZIP_PATH}"
cp "${REPO_ROOT}/LICENSE" "$(dirname "$XC_DIR")/LICENSE" 2>/dev/null || true
( cd "$(dirname "$XC_DIR")" && /usr/bin/zip -yr "$ZIP_PATH" "$(basename "$XC_DIR")" LICENSE )

echo "▶ Computing SPM checksum"
CHECKSUM="$(swift package compute-checksum "$ZIP_PATH")"
echo "   checksum: $CHECKSUM"

# Fallback release notes
if [[ -z "${RELEASE_NOTES}" ]]; then
  RELEASE_NOTES="${BINARY_NAME} ${VERSION}"
fi

ASSET_URL="https://github.com/${PUBLIC_REPO}/releases/download/${IOS_TAG}/${ZIP_NAME}"

# ---- Preflight asset guard ----
SKIP_UPLOAD=0
if gh release view "$IOS_TAG" --repo "$PUBLIC_REPO" >/dev/null 2>&1; then
  # Does an asset with this exact name already exist?
  existing_asset="$(gh release view "$IOS_TAG" --repo "$PUBLIC_REPO" --json assets --jq '.assets[]? | select(.name=="'"$ZIP_NAME"'") | .name' 2>/dev/null || true)"
  if [[ -n "$existing_asset" ]]; then
    echo "ℹ️  Found existing asset '${ZIP_NAME}' on release ${VERSION}. Verifying it matches local build…"
    REMOTE_TMP="$(mktemp -d)"
    REMOTE_ZIP="${REMOTE_TMP}/${ZIP_NAME}"
    if ! curl -fsSL -o "$REMOTE_ZIP" "$ASSET_URL"; then
      rm -rf "$REMOTE_TMP"
      die "Failed to download existing remote asset for comparison."
    fi
    REMOTE_CHECKSUM="$(swift package compute-checksum "$REMOTE_ZIP")"
    if [[ "$REMOTE_CHECKSUM" != "$CHECKSUM" ]]; then
      if [[ "$RETAG" -ne 1 ]]; then
        rm -rf "$REMOTE_TMP"
        die "Remote asset differs from local but tag ${VERSION} already has an asset. Bump the version or re-run with --retag to intentionally replace."
      else
        echo "↺ Remote asset differs and --retag provided; will replace after retag."
      fi
    else
      echo "✓ Remote asset matches local; will skip re-upload."
      SKIP_UPLOAD=1
    fi
    rm -rf "$REMOTE_TMP"
  fi
fi

# ---- Rename Unreleased heading in CHANGELOG-iOS.md ----
CHANGELOG_PATH="${REPO_ROOT}/CHANGELOG-iOS.md"
TODAY="$(date +%Y-%m-%d)"
if [[ -f "$CHANGELOG_PATH" ]] && grep -q '^## Unreleased' "$CHANGELOG_PATH"; then
  echo "▶ Renaming '## Unreleased' → '## ${VERSION} &mdash; ${TODAY}' in CHANGELOG-iOS.md"
  sed -i '' "s/^## Unreleased/## ${VERSION} \&mdash; ${TODAY}/" "$CHANGELOG_PATH"
  git -C "$REPO_ROOT" add CHANGELOG-iOS.md
  if ! git -C "$REPO_ROOT" diff --cached --quiet -- CHANGELOG-iOS.md; then
    git -C "$REPO_ROOT" commit -m "Bump changelog: ${VERSION}"
  fi
fi

echo "▶ Update Package.swift + ${PODSPEC_NAME}, commit, tag, push"

PACKAGE_SWIFT="${REPO_ROOT}/Package.swift"
PODSPEC_PATH="${REPO_ROOT}/${PODSPEC_NAME}"

# Initialize Package.swift if missing
if [[ ! -f "${PACKAGE_SWIFT}" ]]; then
  cat > "${PACKAGE_SWIFT}" <<SWIFT
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "${BINARY_NAME}",
    // iOS 13 required by the Swift overlay (async/await + BGTaskScheduler).
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "${BINARY_NAME}", targets: ["${BINARY_NAME}"]),
        .library(name: "BackgroundFetch", targets: ["BackgroundFetch"])
    ],
    targets: [
        .binaryTarget(
            name: "${BINARY_NAME}",
            url: "${ASSET_URL}",
            checksum: "${CHECKSUM}"
        ),
        .target(
            name: "BackgroundFetch",
            dependencies: ["${BINARY_NAME}"],
            path: "ios/TSBackgroundFetch/SwiftInterface"
        )
    ]
)
SWIFT
fi

# Initialize podspec if missing
if [[ -n "${PODSPEC_NAME}" && ! -f "${PODSPEC_PATH}" ]]; then
  cat > "${PODSPEC_PATH}" <<POD
Pod::Spec.new do |s|
  s.name                = '${BINARY_NAME}'
  s.version             = '${VERSION}'
  s.summary             = 'Background fetch & periodic background tasks for iOS.'
  s.description         = 'Lightweight, open-source Background Fetch that wraps BGTaskScheduler / background fetch to deliver reliable periodic callbacks.'
  s.homepage            = 'https://github.com/transistorsoft/transistor-background-fetch'
  s.documentation_url   = 'https://fetch.transistorsoft.com'
  s.license             = { :type => 'MIT', :file => 'LICENSE' }
  s.author              = { 'Transistor Software' => 'info@transistorsoft.com' }
  s.source              = { :http => '${ASSET_URL}' }
  s.ios.deployment_target = '15.0'
  s.vendored_frameworks = '${BINARY_NAME}.xcframework'
  s.static_framework    = true
  s.frameworks          = 'UIKit'
  s.weak_frameworks     = 'BackgroundTasks'
  s.pod_target_xcconfig = { 'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'YES' }
end
POD
fi

# Update Package.swift url + checksum
sed -i '' "s|url: \".*\"|url: \"${ASSET_URL}\"|g" "${PACKAGE_SWIFT}"
sed -i '' "s|checksum: \".*\"|checksum: \"${CHECKSUM}\"|g" "${PACKAGE_SWIFT}"

# Update Podspec key fields (keep open-source license/homepage/docs)
if [[ -n "${PODSPEC_NAME}" && -f "${PODSPEC_PATH}" ]]; then
  ruby - "${PODSPEC_PATH}" "${VERSION}" "${ASSET_URL}" <<'RUBY'
path, version, url = ARGV
zip = File.basename(url)
xc_base = zip.sub(/\.xcframework\.zip\z/, '')
vendored = "#{xc_base}.xcframework"
txt = File.read(path)
replacements = {
  /^\s*s\.version\s*=.*$/i            => "  s.version             = '#{version}'",
  /^\s*s\.source\s*=.*$/i             => "  s.source              = { :http => '#{url}' }",
  /^\s*s\.homepage\s*=.*$/i           => "  s.homepage            = 'https://github.com/transistorsoft/transistor-background-fetch'",
  /^\s*s\.documentation_url\s*=.*$/i  => "  s.documentation_url   = 'https://fetch.transistorsoft.com'",
  /^\s*s\.license\s*=.*$/i            => "  s.license             = { :type => 'MIT', :file => 'LICENSE' }",
  /^\s*s\.frameworks\s*=.*$/i         => "  s.frameworks          = 'UIKit'",
  /^\s*s\.weak_frameworks\s*=.*$/i    => "  s.weak_frameworks     = 'BackgroundTasks'",
  /^\s*s\.vendored_frameworks\s*=.*$/i=> "  s.vendored_frameworks = '#{vendored}'",
  /^\s*s\.summary\s*=.*$/i            => "  s.summary             = 'Background fetch & periodic background tasks for iOS.'",
  /^\s*s\.description\s*=.*$/i        => "  s.description         = 'Lightweight, open-source Background Fetch that wraps BGTaskScheduler / background fetch to deliver reliable periodic callbacks.'",
  /^\s*s\.author\s*=.*$/i             => "  s.author              = { 'Transistor Software' => 'info@transistorsoft.com' }",
  /^\s*s\.ios\.deployment_target\s*=.*$/i => "  s.ios.deployment_target = '15.0'",
  /^\s*s\.static_framework\s*=.*$/i   => "  s.static_framework    = true",
  /^\s*s\.pod_target_xcconfig\s*=.*$/i => "  s.pod_target_xcconfig = { 'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'YES' }",
}
replacements.each do |pattern, replacement|
  if txt =~ pattern
    txt.gsub!(pattern, replacement)
  else
    txt.sub!(/\nend\s*\z/m) { "\n#{replacement}\nend" }
  end
end
txt.gsub!(/^\s*s\.source_files\s*=.*$/i, '')
txt.gsub!(/\n{2,}/, "\n")
File.write(path, txt)
RUBY
fi

# Commit, tag, push
pushd "${REPO_ROOT}" >/dev/null
git add "${PACKAGE_SWIFT}" || true
[[ -n "${PODSPEC_NAME}" && -f "${PODSPEC_PATH}" ]] && git add "${PODSPEC_PATH}" || true
git commit -m "chore: ${BINARY_NAME} ${VERSION} (url + checksum)" || echo "No file changes"

# Push branch if created
if [[ "$CREATE_BRANCH" -eq 1 ]]; then
  echo "▶ Pushing branch ${BRANCH_NAME} to origin"
  git push -u origin "${BRANCH_NAME}" || true
fi

if [[ "$SKIP_TAG_PUSH" -eq 1 ]]; then
  echo "↷ Skipping tag creation/push; remote '${IOS_TAG}' already exists and matches."
else
  if [[ "$RETAG" -eq 1 ]]; then
    echo "↺ Retagging ${IOS_TAG} (deleting remote tag if present)…"
    git tag -f "${IOS_TAG}"
    git push --delete origin "${IOS_TAG}" >/dev/null 2>&1 || true
    git push origin "${IOS_TAG}"
  else
    if ! git rev-parse -q --verify "refs/tags/${IOS_TAG}" >/dev/null; then
      git tag "${IOS_TAG}"
    fi
    git push origin "${IOS_TAG}" || true
  fi
fi
popd >/dev/null

# Create/Update GitHub Release + upload asset (after tag/branch push)
echo "▶ Create/Update GitHub Release + upload asset (post-tag)"
if ! gh release view "$IOS_TAG" --repo "$PUBLIC_REPO" >/dev/null 2>&1; then
  gh release create "$IOS_TAG" \
    --repo "$PUBLIC_REPO" \
    --title "$VERSION" \
    --notes "$RELEASE_NOTES" \
    --verify-tag
else
  gh release edit "$IOS_TAG" --repo "$PUBLIC_REPO" --verify-tag >/dev/null 2>&1 || true
fi

# Upload asset (unless identical asset already present)
if [[ "$SKIP_UPLOAD" -ne 1 ]]; then
  gh release upload "$IOS_TAG" "$ZIP_PATH" --repo "$PUBLIC_REPO" --clobber
else
  echo "↷ Skipping asset upload; remote asset already matches."
fi

# ---- Post-upload asset checksum verification (with retry for CDN propagation) ----
echo "▶ Verifying uploaded asset checksum matches Package.swift"
VERIFY_TMP="$(mktemp -d)"
VERIFY_ZIP="${VERIFY_TMP}/${ZIP_NAME}"
_MAX_ATTEMPTS=10
_downloaded=0
for _attempt in $(seq 1 $_MAX_ATTEMPTS); do
  if curl -sSfL -o "$VERIFY_ZIP" "$ASSET_URL" 2>/dev/null; then
    _downloaded=1
    break
  fi
  if [[ $_attempt -lt $_MAX_ATTEMPTS ]]; then
    echo "   Asset not yet available (attempt ${_attempt}/${_MAX_ATTEMPTS}), waiting 10s..."
    sleep 10
  fi
done

if [[ $_downloaded -eq 0 ]]; then
  rm -rf "$VERIFY_TMP"
  die "Failed to download uploaded asset for verification after ${_MAX_ATTEMPTS} attempts."
fi

UPLOADED_CHECKSUM="$(swift package compute-checksum "$VERIFY_ZIP")"
rm -rf "$VERIFY_TMP"
if [[ "$UPLOADED_CHECKSUM" != "$CHECKSUM" ]]; then
  echo "❌ Uploaded asset checksum mismatch."
  echo "   expected: $CHECKSUM"
  echo "   actual  : $UPLOADED_CHECKSUM"
  echo "   Leaving the GitHub Release in DRAFT state. Investigate and retry."
  gh release edit "$IOS_TAG" --repo "$PUBLIC_REPO" --draft=true >/dev/null 2>&1 || true
  exit 1
fi

# All good: publish the bare SwiftPM version tag on the ios/ tag's commit.
if [[ "$SKIP_SPM_TAG_PUSH" -eq 1 ]]; then
  echo "↷ Skipping SwiftPM tag '${SPM_TAG}'; remote tag already exists and matches '${IOS_TAG}'."
else
  pushd "${REPO_ROOT}" >/dev/null
  # When the ios/ tag push was skipped it may exist only on the remote.
  if ! git rev-parse -q --verify "refs/tags/${IOS_TAG}" >/dev/null; then
    git fetch origin "refs/tags/${IOS_TAG}:refs/tags/${IOS_TAG}" --quiet
  fi
  IOS_TAG_COMMIT="$(git rev-parse "${IOS_TAG}^{commit}")"
  echo "▶ Tagging ${SPM_TAG} (SwiftPM version) at ${IOS_TAG} (${IOS_TAG_COMMIT:0:7})"
  git tag -f "${SPM_TAG}" "${IOS_TAG_COMMIT}" >/dev/null
  if [[ "$RETAG" -eq 1 ]]; then
    git push --delete origin "${SPM_TAG}" >/dev/null 2>&1 || true
  fi
  # No `|| true`: if this push fails, SPM consumers never see the release, so stop here.
  git push origin "${SPM_TAG}"
  popd >/dev/null
fi

# Undraft the release
gh release edit "$IOS_TAG" --repo "$PUBLIC_REPO" --draft=false >/dev/null 2>&1 || true

# Optionally create PR and auto-merge
if [[ "$CREATE_PR" -eq 1 || -n "$AUTO_MERGE" ]]; then
  if [[ "$CREATE_BRANCH" -ne 1 && -z "$BRANCH_NAME" ]]; then
    BRANCH_NAME="$(git -C "${REPO_ROOT}" rev-parse --abbrev-ref HEAD)"
  fi
  echo "▶ Creating PR from '${BRANCH_NAME}' → '${BASE_BRANCH}'"
  gh pr create --repo "$PUBLIC_REPO" --base "$BASE_BRANCH" --head "$BRANCH_NAME" --title "release: ${VERSION}" --body "$RELEASE_NOTES" || true
  if [[ -n "$AUTO_MERGE" ]]; then
    case "$AUTO_MERGE" in
      merge|squash|rebase) ;;
      *) echo "⚠️  Invalid --auto-merge mode: $AUTO_MERGE (use merge|squash|rebase)"; AUTO_MERGE="";;
    esac
    if [[ -n "$AUTO_MERGE" ]]; then
      echo "▶ Enabling auto-merge (${AUTO_MERGE})"
      gh pr merge --repo "$PUBLIC_REPO" --auto --"$AUTO_MERGE" || true
    fi
  fi
fi


if [[ "${PUSH_COCOAPODS}" -eq 1 ]]; then
  echo "▶ Pushing to CocoaPods Trunk..."
  command -v pod >/dev/null 2>&1 || die "CocoaPods CLI not found. Install with: sudo gem install cocoapods"
  [[ -f "${PODSPEC_PATH}" ]] || die "Podspec '${PODSPEC_NAME}' not found."
  pod repo update
  pod spec lint "${PODSPEC_PATH}" --skip-import-validation --allow-warnings
  pod trunk push "${PODSPEC_PATH}" --skip-import-validation --allow-warnings
fi

# Remind about CocoaPods if we didn't push it this run
if [[ "${PUSH_COCOAPODS}" -eq 0 ]]; then
  if [[ -n "${PODSPEC_NAME}" && -f "${PODSPEC_PATH}" ]]; then
    echo ""
    echo "ℹ️  CocoaPods push skipped (--no-cocoapods)."
    echo "    If you intend to publish ${BINARY_NAME} ${VERSION} to CocoaPods, run:"
    echo "      pod spec lint \"${PODSPEC_PATH}\" --skip-import-validation --allow-warnings"
    echo "      pod trunk push \"${PODSPEC_PATH}\" --skip-import-validation --allow-warnings"
    echo "    Follow the Trunk retry rules in WO-001; don't re-run this script to push."
    echo ""
  else
    echo ""
    echo "ℹ️  CocoaPods push skipped, and no podspec was found at '${PODSPEC_PATH}'."
    echo "    If you plan to publish to CocoaPods, ensure the podspec exists and push it by hand (pod trunk push)."
    echo ""
  fi
fi

cat <<EOF

✅ Published ${BINARY_NAME} ${VERSION}

SPM (Package.swift):
  .binaryTarget(
      name: "${BINARY_NAME}",
      url: "${ASSET_URL}",
      checksum: "${CHECKSUM}"
  )

CocoaPods:
  pod '${BINARY_NAME}', '~> ${VERSION}'

Git:
  Branch (optional): ${BRANCH_NAME:-<not created>}
  Base: ${BASE_BRANCH}
  PR: $( [[ "$CREATE_PR" -eq 1 ]] && echo "requested" || echo "not created" )

EOF

echo ""
echo "📌 SPM troubleshooting (for users): If Xcode reports 'checksum does not match', ask them to:"
echo "    1) Xcode → File → Packages → Reset Package Caches, then Resolve Package Versions"
echo "    2) Or run:"
echo "       rm -rf ~/Library/Caches/org.swift.swiftpm"
echo "       rm -rf ~/Library/Developer/Xcode/DerivedData"
echo ""
