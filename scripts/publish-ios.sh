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
  --dry-run                 Build + package only; no Git/tag/release
  --no-build                Skip building (requires --xcframework-dir)
  --xcframework-dir PATH    Use existing .xcframework directory
  --push-cocoapods          Run pod lint + trunk push at the end
  --retag                   Overwrite existing remote tag if present
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
resolve_version() {
  if [[ -n "$VERSION" && -n "$BUMP_MODE" ]]; then die "--version and --bump are mutually exclusive"; fi
  if [[ -n "$VERSION" ]]; then echo "$VERSION"; return; fi
  if [[ -n "$BUMP_MODE" ]]; then
    local latest; latest="$(latest_semver_tag)"; [[ -n "$latest" ]] || latest='0.0.0'
    bump_semver "$latest" "$BUMP_MODE"; return
  fi
  if [[ -n "${MARKETING_VERSION:-}" ]]; then echo "$MARKETING_VERSION"; return; fi
  local latest; latest="$(latest_semver_tag)"; [[ -n "$latest" ]] && { echo "$latest"; return; }
  echo "dev"
}

# Require gh auth
has_gh || die "GitHub CLI 'gh' not found. Install from https://cli.github.com/"
gh auth status >/dev/null 2>&1 || die "GitHub CLI is not authenticated. Run: gh auth login"

VERSION="$(resolve_version)"
echo "ℹ️  Version: ${VERSION}"
echo "ℹ️  Public repo: ${PUBLIC_REPO}"
echo "ℹ️  Catalyst: $( [[ "$INCLUDE_CATALYST" == "1" ]] && echo ENABLED || echo DISABLED )"

remote_tag_exists() {
  git ls-remote --tags "https://github.com/${PUBLIC_REPO}.git" "refs/tags/${VERSION}" | grep -q "refs/tags/${VERSION}"
}
if remote_tag_exists && [[ "$RETAG" -ne 1 ]]; then
  echo "❌ Tag '${VERSION}' already exists on remote ${PUBLIC_REPO}."
  echo "   Use --bump (e.g., --bump patch) or pass --retag to overwrite."
  exit 1
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

ASSET_URL="https://github.com/${PUBLIC_REPO}/releases/download/${VERSION}/${ZIP_NAME}"

echo "▶ Create/Update GitHub Release + upload asset"
gh release view "$VERSION" --repo "$PUBLIC_REPO" >/dev/null 2>&1 || \
  gh release create "$VERSION" --repo "$PUBLIC_REPO" --title "$VERSION" --notes "${RELEASE_NOTES:-${BINARY_NAME} ${VERSION}}"
gh release upload "$VERSION" "$ZIP_PATH" --repo "$PUBLIC_REPO" --clobber
gh release edit "$VERSION" --repo "$PUBLIC_REPO" --draft=false >/dev/null 2>&1 || true

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
popd >/dev/null

if [[ "${PUSH_COCOAPODS}" -eq 1 ]]; then
  echo "▶ Pushing to CocoaPods Trunk..."
  command -v pod >/dev/null 2>&1 || die "CocoaPods CLI not found. Install with: sudo gem install cocoapods"
  [[ -f "${PODSPEC_PATH}" ]] || die "Podspec '${PODSPEC_NAME}' not found."
  pod spec lint "${PODSPEC_PATH}" --skip-import-validation --allow-warnings
  pod trunk push "${PODSPEC_PATH}" --skip-import-validation --allow-warnings
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

EOF