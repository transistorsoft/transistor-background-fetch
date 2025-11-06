#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# TSBackgroundFetch iOS: Build + Publish (single script)
#
# Usage:
#   ./scripts/publish-ios.sh --version 4.0.0
#   ./scripts/publish-ios.sh --bump patch
#   INCLUDE_CATALYST=1 ./scripts/publish-ios.sh --version 4.0.0
#
# Flags:
#   --version X.Y.Z
#   --bump [patch|minor|major]
#   --notes "text"
#   --dry-run
#   --no-build
#   --xcframework-dir PATH
#   --push-cocoapods
#
# Defaults for Background Fetch:
#   PUBLIC_REPO=transistorsoft/transistor-background-fetch
#   BINARY_NAME=TSBackgroundFetch
#   INCLUDE_CATALYST=1
#   PODSPEC_NAME=TSBackgroundFetch.podspec
#
# Auth:
#   Prefer gh CLI; otherwise set GITHUB_TOKEN
# ------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." &>/dev/null && pwd)"

PUBLIC_REPO="${PUBLIC_REPO:-transistorsoft/transistor-background-fetch}"
BINARY_NAME="${BINARY_NAME:-TSBackgroundFetch}"
INCLUDE_CATALYST="${INCLUDE_CATALYST:-1}"
PODSPEC_NAME="${PODSPEC_NAME:-TSBackgroundFetch.podspec}"

: "${GITHUB_TOKEN:=${GITHUB_TOKEN_IOS_PUBLISHING:-}}"

has_gh() { command -v gh >/dev/null 2>&1; }
die() { echo "❌ $*" >&2; exit 1; }

VERSION=""
BUMP_MODE=""
RELEASE_NOTES=""
DRY_RUN=0
NO_BUILD=0
XCFRAMEWORK_DIR_OVERRIDE=""
PUSH_COCOAPODS=0

usage() { sed -n '1,120p' "$0" | sed 's/^  //'; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2;;
    --bump) BUMP_MODE="${2:-}"; shift 2;;
    --notes) RELEASE_NOTES="${2:-}"; shift 2;;
    --dry-run) DRY_RUN=1; shift;;
    --no-build) NO_BUILD=1; shift;;
    --xcframework-dir) XCFRAMEWORK_DIR_OVERRIDE="${2:-}"; shift 2;;
    --push-cocoapods) PUSH_COCOAPODS=1; shift;;
    -h|--help) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

latest_public_tag() {
  git ls-remote --tags --refs "https://github.com/${PUBLIC_REPO}.git" 2>/dev/null \
    | awk -F/ '{print $NF}' | sed 's/\^{}//' | sort -V | tail -1
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
    local latest; latest="$(latest_public_tag)"
    [[ -n "$latest" ]] || die "No tags in ${PUBLIC_REPO}. Use --version to set the first one."
    bump_semver "$latest" "$BUMP_MODE"; return
  fi
  if [[ -n "${MARKETING_VERSION:-}" ]]; then echo "$MARKETING_VERSION"; return; fi
  local latest; latest="$(latest_public_tag)"; if [[ -n "$latest" ]]; then echo "$latest"; return; fi
  echo "dev"
}

VERSION="$(resolve_version)"
echo "ℹ️  Version: ${VERSION}"
echo "ℹ️  Public repo: ${PUBLIC_REPO}"
echo "ℹ️  Catalyst: $( [[ "$INCLUDE_CATALYST" == "1" ]] && echo ENABLED || echo DISABLED )"

OUT_ROOT="${REPO_ROOT}/build/Release-Publish/${BINARY_NAME}_XCFramework_${VERSION}"
XCFRAMEWORK_DIR_DEFAULT="${OUT_ROOT}/${BINARY_NAME}.xcframework"
ZIP_DEFAULT="${OUT_ROOT}/${BINARY_NAME}.xcframework.zip"

if [[ "$NO_BUILD" -eq 0 ]]; then
  echo "▶ Building XCFramework..."
  VERSION="$VERSION" INCLUDE_CATALYST="$INCLUDE_CATALYST" "${SCRIPT_DIR}/build-ios.sh"
else
  echo "↷ Skipping build (--no-build set)"
fi

if [[ -n "$XCFRAMEWORK_DIR_OVERRIDE" ]]; then
  XC_DIR="$XCFRAMEWORK_DIR_OVERRIDE"
else
  XC_DIR="$XCFRAMEWORK_DIR_DEFAULT"
fi
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

if has_gh; then
  echo "ℹ️  Using gh CLI authentication."
elif [[ -n "${GITHUB_TOKEN}" ]]; then
  echo "ℹ️  Using GITHUB_TOKEN."
else
  echo "ℹ️  No gh auth detected and no GITHUB_TOKEN set; API calls will fail."
fi

echo "▶ Create/Update GitHub Release + upload asset"
if has_gh; then
  gh release view "$VERSION" --repo "$PUBLIC_REPO" >/dev/null 2>&1 || \
    gh release create "$VERSION" --repo "$PUBLIC_REPO" --title "$VERSION" --notes "${RELEASE_NOTES:-${BINARY_NAME} ${VERSION}}"
  gh release upload "$VERSION" "$ZIP_PATH" --repo "$PUBLIC_REPO" --clobber
else
  [[ -n "${GITHUB_TOKEN}" ]] || die "No gh CLI and no GITHUB_TOKEN"
  rel_json=$(curl -sSf -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${PUBLIC_REPO}/releases/tags/${VERSION}" || true)
  if echo "$rel_json" | grep -q '"message": "Not Found"'; then
    rel_json=$(curl -sSf -X POST -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${PUBLIC_REPO}/releases" \
      -d "{\"tag_name\":\"${VERSION}\",\"name\":\"${VERSION}\",\"prerelease\":$( [[ "$VERSION" == *-* ]] && echo true || echo false ),\"body\":\"${RELEASE_NOTES:-${BINARY_NAME} ${VERSION}}\"}")
  fi
  upload_url=$(echo "$rel_json" | python3 - "$ZIP_NAME" <<'PY'
import sys, json; j=json.load(sys.stdin); print(j["upload_url"].split("{")[0])
PY
)
  curl -sSf -X POST -H "Authorization: Bearer $GITHUB_TOKEN" -H "Content-Type: application/zip" \
    --data-binary @"$ZIP_PATH" "${upload_url}?name=${ZIP_NAME}" >/dev/null
fi

echo "▶ Clone/update ${PUBLIC_REPO}: Package.swift + podspec, tag, push"
CLONE_DIR="$(mktemp -d)"
if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
  git clone "git@github.com:${PUBLIC_REPO}.git" "$CLONE_DIR"
else
  git clone "https://github.com/${PUBLIC_REPO}.git" "$CLONE_DIR"
fi
pushd "$CLONE_DIR" >/dev/null

# Initialize Package.swift if missing
if [[ ! -f Package.swift ]]; then
  cat > Package.swift <<SWIFT
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
if [[ -n "$PODSPEC_NAME" && ! -f "$PODSPEC_NAME" ]]; then
  cat > "$PODSPEC_NAME" <<POD
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
sed -i '' "s|url: \".*\"|url: \"${ASSET_URL}\"|g" Package.swift
sed -i '' "s|checksum: \".*\"|checksum: \"${CHECKSUM}\"|g" Package.swift

# Update Podspec key fields (keep open-source license/homepage/docs)
if [[ -n "$PODSPEC_NAME" && -f "$PODSPEC_NAME" ]]; then
  ruby - "$PODSPEC_NAME" "$VERSION" "$ASSET_URL" <<'RUBY'
path, version, url = ARGV
txt = File.read(path)
replacements = {
  /^\s*s\.version\s*=.*$/i            => "  s.version             = '#{version}'",
  /^\s*s\.source\s*=.*$/i             => "  s.source              = { :http => '#{url}' }",
  /^\s*s\.homepage\s*=.*$/i           => "  s.homepage            = 'https://github.com/transistorsoft/transistor-background-fetch'",
  /^\s*s\.documentation_url\s*=.*$/i  => "  s.documentation_url   = 'https://github.com/transistorsoft/transistor-background-fetch/docs/ios'",
  # License stays open-source (MIT) for this project
  /^\s*s\.license\s*=.*$/i            => "  s.license             = { :type => 'MIT', :file => 'LICENSE' }",
  # Ensure frameworks are correct for BF (no sqlite/z/c++)
  /^\s*s\.frameworks\s*=.*$/i         => "  s.frameworks          = 'UIKit'",
  /^\s*s\.weak_frameworks\s*=.*$/i    => "  s.weak_frameworks     = 'BackgroundTasks'",
  /^\s*s\.vendored_frameworks\s*=.*$/i=> "  s.vendored_frameworks = '#{File.basename(url,'.zip')}.xcframework'",
}
replacements.each do |pattern, replacement|
  if txt =~ pattern
    txt.gsub!(pattern, replacement)
  else
    txt.sub!(/\nend\s*\z/m) { "\n#{replacement}\nend" }
  end
end
File.write(path, txt)
RUBY
fi

git add Package.swift || true
[[ -n "$PODSPEC_NAME" && -f "$PODSPEC_NAME" ]] && git add "$PODSPEC_NAME" || true
git commit -m "chore: ${BINARY_NAME} ${VERSION} (url + checksum)" || echo "No file changes"
git tag -f "${VERSION}"
git push
git push --force --tags
if [[ "$PUSH_COCOAPODS" -eq 1 ]]; then
  echo "▶ Pushing to CocoaPods Trunk..."
  if ! command -v pod >/dev/null 2>&1; then
    echo "❌ CocoaPods 'pod' CLI not found. Install with: sudo gem install cocoapods"
    exit 1
  fi
  if [[ -z "$PODSPEC_NAME" || ! -f "$PODSPEC_NAME" ]]; then
    echo "❌ Podspec '${PODSPEC_NAME}' not found in the public repo checkout; cannot push."
    exit 1
  fi
  pod spec lint "$PODSPEC_NAME" --skip-import-validation --allow-warnings
  pod trunk push "$PODSPEC_NAME" --skip-import-validation --allow-warnings
fi
popd >/dev/null

cat <<EOF

✅ Published ${BINARY_NAME} ${VERSION}

SPM (Package.swift):
  .binaryTarget(
      name: "${BINARY_NAME}",
      url: "${ASSET_URL}",
      checksum: "${CHECKSUM}"
  )

CocoaPods (if pushing to trunk):
  pod spec lint ${PODSPEC_NAME:-TSBackgroundFetch.podspec} --skip-import-validation --allow-warnings
  pod trunk push ${PODSPEC_NAME:-TSBackgroundFetch.podspec} --skip-import-validation --allow-warnings

EOF