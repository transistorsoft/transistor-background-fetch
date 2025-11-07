#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# TSBackgroundFetch iOS — Build & Publish
#
# Usage:
#   ./scripts/publish-ios.sh --version 4.0.1 [--notes "msg"] [--push-cocoapods]
#   ./scripts/publish-ios.sh --bump patch|minor|major [--notes "msg"]
#   INCLUDE_CATALYST=0 ./scripts/publish-ios.sh --version 4.0.1
#   ./scripts/publish-ios.sh --version 4.0.1 --dry-run
#   ./scripts/publish-ios.sh --version 4.0.2 --create-branch --create-pr
#   ./scripts/publish-ios.sh --version 4.0.2 --create-branch --branch-name releases/4.0.2 --base main --create-pr --auto-merge squash
#
# Options:
#   --version X.Y.Z         Explicit version to publish/tag.
#   --bump (patch|minor|major)
#                          Bump from latest remote semver tag.
#   --notes "text"          Release notes (defaults to "<BINARY> <VERSION>").
#   --dry-run               Build and package only (no GitHub, no commits/tags).
#   --no-build              Skip building xcframework (use --xcframework-dir).
#   --xcframework-dir PATH  Use an existing .xcframework directory.
#   --push-cocoapods        Run `pod spec lint` + `pod trunk push` at the end.
#   --retag                 Overwrite the existing remote tag if already present.
#   --create-branch          Create and switch to a release branch before making edits (default name: releases/<VERSION>)
#   --branch-name NAME       Override the branch name used with --create-branch
#   --base BRANCH            Base branch to branch from and target PR to (auto-detects origin/HEAD)
#   --create-pr              Open a GitHub pull request from the release branch to --base
#   --auto-merge MODE        Auto-merge the PR with MODE: merge|squash|rebase (requires --create-pr)
#
# Defaults:
#   PUBLIC_REPO=transistorsoft/transistor-background-fetch
#   BINARY_NAME=TSBackgroundFetch
#   PODSPEC_NAME=TSBackgroundFetch.podspec
#   INCLUDE_CATALYST=1
#
# Requirements:
#   - Xcode command-line tools
#   - zip, swift
#   - GitHub CLI (`gh`) authenticated for the PUBLIC_REPO owner
#   - CocoaPods (`pod`) if using --push-cocoapods
#
# Notes:
#   - This script operates directly on THIS repo (public).
#   - The GitHub Release is created/updated and the xcframework zip is uploaded.
#   - Package.swift and the podspec are updated in-place (commit + tag + push).
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." &>/dev/null && pwd)"

PUBLIC_REPO="${PUBLIC_REPO:-transistorsoft/transistor-background-fetch}"
BINARY_NAME="${BINARY_NAME:-TSBackgroundFetch}"
INCLUDE_CATALYST="${INCLUDE_CATALYST:-1}"
PODSPEC_NAME="${PODSPEC_NAME:-TSBackgroundFetch.podspec}"

has_gh() { command -v gh >/dev/null 2>&1; }
die() { echo "❌ $*" >&2; exit 1; }

# ----- args -----
VERSION=""
BUMP_MODE=""
RELEASE_NOTES=""
DRY_RUN=0
NO_BUILD=0
XCFRAMEWORK_DIR_OVERRIDE=""
PUSH_COCOAPODS=0
RETAG=0
CREATE_BRANCH=0
BRANCH_NAME=""
BASE_BRANCH=""
CREATE_PR=0
AUTO_MERGE=""
VERSION_SOURCE=""
SKIP_TAG_PUSH=0

usage() {
  cat <<USAGE
Usage:
  ./scripts/publish-ios.sh --version X.Y.Z [--notes "msg"] [--push-cocoapods] [--retag]
  ./scripts/publish-ios.sh --bump patch|minor|major [--notes "msg"]
  INCLUDE_CATALYST=0 ./scripts/publish-ios.sh --version X.Y.Z

Options:
  --version X.Y.Z           Explicit version to publish/tag
  --bump patch|minor|major  Bump from latest remote semver tag
  --notes "text"            Release notes text
  --dry-run                 Build and package only (no Git, no tags, no GitHub release).
  --no-build                Skip building (requires --xcframework-dir)
  --xcframework-dir PATH    Use existing .xcframework directory
  --push-cocoapods          Run pod lint + trunk push at the end
  --retag                   Overwrite existing remote tag if present
  --create-branch            Create and switch to a release branch (default: releases/<VERSION>)
  --branch-name NAME         Override branch name when using --create-branch
  --base BRANCH              Base branch to branch from / PR target (auto-detected)
  --create-pr                Open a GitHub PR from the release branch to --base
  --auto-merge MODE          Auto-merge the PR (merge|squash|rebase); implies --create-pr

Notes:
  If --version/--bump are omitted, the script will try to read the latest version
  heading from CHANGELOG.md (e.g., "## 4.0.2") and prompt:
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
    --retag) RETAG=1; shift;;
    --create-branch) CREATE_BRANCH=1; shift;;
    --branch-name) BRANCH_NAME="${2:-}"; shift 2;;
    --base) BASE_BRANCH="${2:-}"; shift 2;;
    --create-pr) CREATE_PR=1; shift;;
    --auto-merge) AUTO_MERGE="${2:-}"; shift 2;;
    -h|--help) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

latest_semver_tag() {
  git ls-remote --tags --refs "https://github.com/${PUBLIC_REPO}.git" 2>/dev/null \
    | awk -F/ '{print $NF}' | sed 's/\^{}//' \
    | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^v//' \
    | sort -V | tail -1
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

# Read top version from CHANGELOG.md
version_from_changelog() {
  local changelog="${REPO_ROOT}/CHANGELOG.md"
  if [[ -f "$changelog" ]]; then
    # Find the first heading like "## 4.0.2" or "## v4.0.2"
    local v
    v="$(grep -E '^\s*##\s*v?[0-9]+\.[0-9]+\.[0-9]+' "$changelog" | head -1 | sed -E 's/^\s*##\s*v?([0-9]+\.[0-9]+\.[0-9]+).*$/\1/')"
    [[ -n "$v" ]] && echo "$v"
  fi
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

  # Try CHANGELOG.md as an interactive suggestion
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

# Require gh auth
has_gh || die "GitHub CLI 'gh' not found. Install from https://cli.github.com/"
gh auth status >/dev/null 2>&1 || die "GitHub CLI is not authenticated. Run: gh auth login"


VERSION="$(resolve_version)"

# Coerce VERSION to pure semver (e.g., "## 4.0.2 — 2025-11-07" -> "4.0.2")
if [[ -n "${VERSION:-}" ]]; then
  if [[ "$VERSION" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
    VERSION="${BASH_REMATCH[1]}"
  fi
fi

# If version was inferred from CHANGELOG, prompt for confirmation
if [[ "$VERSION_SOURCE" == "changelog" ]]; then
  echo "⚙️  Detected version ${VERSION} from CHANGELOG.md"
  read -r -p "> Publish version ${VERSION}? [y/N] " _ans
  case "${_ans:-}" in
    y|Y|yes|YES)
      ;;
    *)
      die "Aborted. Provide --version X.Y.Z or use --bump patch|minor|major."
      ;;
  esac
fi

echo "ℹ️  Version: ${VERSION}"
echo "ℹ️  Public repo: ${PUBLIC_REPO}"
echo "ℹ️  Catalyst: $( [[ "$INCLUDE_CATALYST" == "1" ]] && echo ENABLED || echo DISABLED )"

# Determine default base branch if not provided
detect_default_branch() {
  # Try to read origin/HEAD first
  local head
  head="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -n "$head" ]]; then
    echo "${head#origin/}"
    return
  fi
  # Fallbacks
  if git show-ref --verify --quiet refs/remotes/origin/main; then echo "main"; return; fi
  if git show-ref --verify --quiet refs/remotes/origin/master; then echo "master"; return; fi
  # Last resort: current branch
  git rev-parse --abbrev-ref HEAD
}

if [[ -z "$BASE_BRANCH" ]]; then
  BASE_BRANCH="$(detect_default_branch)"
fi
echo "ℹ️  Base branch: ${BASE_BRANCH}"

# Optionally create and switch to a release branch before making edits
if [[ "$CREATE_BRANCH" -eq 1 ]]; then
  # Default branch name derived from VERSION; ensure it's safe for git
  if [[ -z "$BRANCH_NAME" ]]; then
    _ver_for_branch="$VERSION"
    # Keep only [A-Za-z0-9._-] in the branch suffix; replace others with '-'
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

remote_tag_exists() {
  git ls-remote --tags "https://github.com/${PUBLIC_REPO}.git" "refs/tags/${VERSION}" | grep -q "refs/tags/${VERSION}"
}
if remote_tag_exists; then
  if [[ "$RETAG" -ne 1 ]]; then
    # Compare remote tag target with local (if present). If they differ, abort with guidance.
    remote_sha="$(git ls-remote --tags "https://github.com/${PUBLIC_REPO}.git" "refs/tags/${VERSION}" | awk '{print $1}')"
    local_sha=""
    if git rev-parse -q --verify "refs/tags/${VERSION}" >/dev/null 2>&1; then
      # Peel annotated tags to the commit object
      local_sha="$(git rev-parse -q "${VERSION}^{}" 2>/dev/null || true)"
    fi

    if [[ -n "$local_sha" && "$local_sha" != "$remote_sha" ]]; then
      echo "❌ Tag '${VERSION}' already exists on remote and points to a different commit."
      echo "   remote: ${remote_sha}"
      echo "   local : ${local_sha}"
      echo "   Use --retag to overwrite the remote tag, or bump with --bump patch|minor|major."
      exit 1
    fi

    # If remote exists and matches local (or local tag absent), skip tag push silently.
    echo "ℹ️  Tag '${VERSION}' already exists on remote and matches; will skip re-pushing this tag."
    SKIP_TAG_PUSH=1
  fi
fi

OUT_ROOT="${REPO_ROOT}/build/Release-Publish/${BINARY_NAME}_XCFramework_${VERSION}"
XCFRAMEWORK_DIR_DEFAULT="${OUT_ROOT}/${BINARY_NAME}.xcframework"

if [[ "$NO_BUILD" -eq 0 ]]; then
  echo "▶ Building XCFramework..."
  VERSION="$VERSION" INCLUDE_CATALYST="$INCLUDE_CATALYST" "${SCRIPT_DIR}/build-ios.sh"
else
  echo "↷ Skipping build (--no-build)"
fi

XC_DIR="${XCFRAMEWORK_DIR_OVERRIDE:-$XCFRAMEWORK_DIR_DEFAULT}"
[[ -d "$XC_DIR" ]] || die "XCFramework not found at: $XC_DIR (use --xcframework-dir to override)"
echo "ℹ️  XCFramework: $XC_DIR"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "🧪 Dry run complete. Skipping publish."
  exit 0
fi

ZIP_NAME="${BINARY_NAME}.xcframework.zip"
TMPDIR="$(mktemp -d)"
ZIP_PATH="${TMPDIR}/${ZIP_NAME}"

echo "▶ Packaging XCFramework → ${ZIP_PATH}"
( cd "$(dirname "$XC_DIR")" && /usr/bin/zip -yr "$ZIP_PATH" "$(basename "$XC_DIR")" )

echo "▶ Computing SPM checksum"
CHECKSUM="$(swift package compute-checksum "$ZIP_PATH")"
echo "   checksum: $CHECKSUM"

# ▶ Derive release notes from CHANGELOG.md if not provided
if [[ -z "${RELEASE_NOTES}" && -f "${REPO_ROOT}/CHANGELOG.md" ]]; then
  RELEASE_NOTES="$(ruby - "${REPO_ROOT}/CHANGELOG.md" "${VERSION}" <<'RUBY'
path, version = ARGV
text = File.read(path)
# Match headings like: "## 4.0.2 — 2025-11-07" or "## 4.0.2 &mdash; 2025-11-07" or just "## 4.0.2"
heading_regex = /^##\s*v?#{Regexp.escape(version)}\b.*$/i
lines = text.lines
start = lines.index { |l| l =~ heading_regex }
if start
  # Find next heading starting with '## '
  nxt = (start + 1 ... lines.length).find { |i| lines[i].start_with?("## ") } || lines.length
  body = lines[(start + 1)...nxt].join.strip
  puts body unless body.empty?
end
RUBY
)"
fi

# Fallback if no notes resolved
if [[ -z "${RELEASE_NOTES}" ]]; then
  RELEASE_NOTES="${BINARY_NAME} ${VERSION}"
fi


ASSET_URL="https://github.com/${PUBLIC_REPO}/releases/download/${VERSION}/${ZIP_NAME}"

# Preflight: guard against mutating an existing asset at the same tag (checksum-aware)
SKIP_UPLOAD=0
if gh release view "$VERSION" --repo "$PUBLIC_REPO" >/dev/null 2>&1; then
  # Does an asset with this exact name already exist?
  if gh release view "$VERSION" --repo "$PUBLIC_REPO" --json assets --jq \
     '.assets[]? | select(.name=="'"$ZIP_NAME"'") | .name' >/dev/null 2>&1; then
    echo "ℹ️  Found existing asset '${ZIP_NAME}' on release ${VERSION}. Verifying it matches local build…"
    # Download remote asset and compute its checksum
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
    platforms: [.iOS(.v12)],
    products: [.library(name: "${BINARY_NAME}", targets: ["${BINARY_NAME}"])],
    targets: [
        .binaryTarget(
            name: "${BINARY_NAME}",
            url: "${ASSET_URL}",
            checksum: "${CHECKSUM}"
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
  s.documentation_url   = 'https://github.com/transistorsoft/transistor-background-fetch/docs/ios'
  s.license             = { :type => 'MIT', :file => 'LICENSE' }
  s.author              = { 'Transistor Software' => 'info@transistorsoft.com' }
  s.source              = { :http => '${ASSET_URL}' }
  s.ios.deployment_target = '12.0'
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
  /^\s*s\.documentation_url\s*=.*$/i  => "  s.documentation_url   = 'https://github.com/transistorsoft/transistor-background-fetch/docs/ios'",
  /^\s*s\.license\s*=.*$/i            => "  s.license             = { :type => 'MIT', :file => 'LICENSE' }",
  /^\s*s\.frameworks\s*=.*$/i         => "  s.frameworks          = 'UIKit'",
  /^\s*s\.weak_frameworks\s*=.*$/i    => "  s.weak_frameworks     = 'BackgroundTasks'",
  /^\s*s\.vendored_frameworks\s*=.*$/i=> "  s.vendored_frameworks = '#{vendored}'",
  /^\s*s\.summary\s*=.*$/i            => "  s.summary             = 'Background fetch & periodic background tasks for iOS.'",
  /^\s*s\.description\s*=.*$/i        => "  s.description         = 'Lightweight, open-source Background Fetch that wraps BGTaskScheduler / background fetch to deliver reliable periodic callbacks.'",
  /^\s*s\.author\s*=.*$/i             => "  s.author              = { 'Transistor Software' => 'info@transistorsoft.com' }",
  /^\s*s\.ios\.deployment_target\s*=.*$/i => "  s.ios.deployment_target = '12.0'",
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
  echo "↷ Skipping tag creation/push; remote '${VERSION}' already exists and matches."
else
  if [[ "$RETAG" -eq 1 ]]; then
    echo "↺ Retagging ${VERSION} (deleting remote tag if present)…"
    git tag -f "${VERSION}"
    git push --delete origin "${VERSION}" >/dev/null 2>&1 || true
    git push origin "${VERSION}"
  else
    if ! git rev-parse -q --verify "refs/tags/${VERSION}" >/dev/null; then
      git tag "${VERSION}"
    fi
    git push origin "${VERSION}" || true
  fi
fi
popd >/dev/null

# Create/Update GitHub Release + upload asset (after tag/branch push)
echo "▶ Create/Update GitHub Release + upload asset (post-tag)"
# Ensure the tag exists on origin before creating the release; --verify-tag enforces this.
if ! gh release view "$VERSION" --repo "$PUBLIC_REPO" >/dev/null 2>&1; then
  gh release create "$VERSION" \
    --repo "$PUBLIC_REPO" \
    --title "$VERSION" \
    --notes "$RELEASE_NOTES" \
    --verify-tag
else
  # If a release already exists (possibly draft), make sure it refers to this tag and proceed.
  gh release edit "$VERSION" --repo "$PUBLIC_REPO" --verify-tag >/dev/null 2>&1 || true
fi

# Upload asset (unless identical asset already present)
if [[ "$SKIP_UPLOAD" -ne 1 ]]; then
  gh release upload "$VERSION" "$ZIP_PATH" --repo "$PUBLIC_REPO" --clobber
else
  echo "↷ Skipping asset upload; remote asset already matches."
fi

# Post-upload verification: ensure the asset at the release URL matches the manifest checksum.
echo "▶ Verifying uploaded asset checksum matches Package.swift"
VERIFY_TMP="$(mktemp -d)"
VERIFY_ZIP="${VERIFY_TMP}/${ZIP_NAME}"
if ! curl -fsSL -o "$VERIFY_ZIP" "$ASSET_URL"; then
  rm -rf "$VERIFY_TMP"
  die "Failed to download uploaded asset for verification."
fi
UPLOADED_CHECKSUM="$(swift package compute-checksum "$VERIFY_ZIP")"
rm -rf "$VERIFY_TMP"
if [[ "$UPLOADED_CHECKSUM" != "$CHECKSUM" ]]; then
  echo "❌ Uploaded asset checksum mismatch."
  echo "   expected: $CHECKSUM"
  echo "   actual  : $UPLOADED_CHECKSUM"
  echo "   Leaving the GitHub Release in DRAFT state. Investigate and retry."
  gh release edit "$VERSION" --repo "$PUBLIC_REPO" --draft=true >/dev/null 2>&1 || true
  exit 1
fi

# All good: undraft the release
gh release edit "$VERSION" --repo "$PUBLIC_REPO" --draft=false >/dev/null 2>&1 || true

 # Optionally create PR and auto-merge
if [[ "$CREATE_PR" -eq 1 || -n "$AUTO_MERGE" ]]; then
  if [[ "$CREATE_BRANCH" -ne 1 && -z "$BRANCH_NAME" ]]; then
    # Use current branch name if user didn't create a branch explicitly
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
  pod spec lint "${PODSPEC_PATH}" --skip-import-validation --allow-warnings
  pod trunk push "${PODSPEC_PATH}" --skip-import-validation --allow-warnings
fi

# Remind about CocoaPods if we didn't push it this run
if [[ "${PUSH_COCOAPODS}" -eq 0 ]]; then
  if [[ -n "${PODSPEC_NAME}" && -f "${PODSPEC_PATH}" ]]; then
    echo ""
    echo "ℹ️  CocoaPods push skipped (no --push-cocoapods)."
    echo "    If you intend to publish ${BINARY_NAME} ${VERSION} to CocoaPods, run:"
    echo "      pod spec lint \"${PODSPEC_PATH}\" --skip-import-validation --allow-warnings"
    echo "      pod trunk push \"${PODSPEC_PATH}\" --skip-import-validation --allow-warnings"
    echo "    (Or rerun this script with --push-cocoapods to automate these steps.)"
    echo ""
  else
    echo ""
    echo "ℹ️  CocoaPods push skipped, and no podspec was found at '${PODSPEC_PATH}'."
    echo "    If you plan to publish to CocoaPods, ensure the podspec exists and rerun with --push-cocoapods."
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