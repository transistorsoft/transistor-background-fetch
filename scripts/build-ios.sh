#!/usr/bin/env bash
set -euo pipefail

VERSION=""
INCLUDE_CATALYST="${INCLUDE_CATALYST:-1}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"; shift 2 ;;
    --no-catalyst)
      INCLUDE_CATALYST=0; shift ;;
    *)
      echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# ------------------------------------------------------------
# TSBackgroundFetch iOS: Build XCFramework
#
# Env (optional):
#   BINARY_NAME        (default: TSBackgroundFetch)
#   SCHEME             (default: TSBackgroundFetch) — must be shared
#   CONFIGURATION      (default: Release)
#   INCLUDE_CATALYST   (default: 1) — set 0 to skip Mac Catalyst
#   VERSION            (optional) used only for output folder name if provided
# ------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." &>/dev/null && pwd)"

PROJECT_PATH="${REPO_ROOT}/ios/TSBackgroundFetch/TSBackgroundFetch.xcodeproj"

BINARY_NAME="${BINARY_NAME:-TSBackgroundFetch}"
SCHEME="${SCHEME:-TSBackgroundFetch}"
CONFIGURATION="${CONFIGURATION:-Release}"

OUT_ROOT="${REPO_ROOT}/build/Release-Publish/${BINARY_NAME}_XCFramework${VERSION:+_${VERSION}}"
IOS_ARCHIVE="${OUT_ROOT}/iOS.xcarchive"
SIM_ARCHIVE="${OUT_ROOT}/iOS_Sim.xcarchive"
CAT_ARCHIVE="${OUT_ROOT}/MacCatalyst.xcarchive"
XCFRAMEWORK_PATH="${OUT_ROOT}/${BINARY_NAME}.xcframework"

echo "— Building ${BINARY_NAME}.xcframework —"
rm -rf "${OUT_ROOT}"
mkdir -p "${OUT_ROOT}"

echo "Archiving (iOS device)…"
xcodebuild archive \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "generic/platform=iOS" \
  -archivePath "${IOS_ARCHIVE}" \
  SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES

echo "Archiving (iOS Simulator)…"
xcodebuild archive \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "generic/platform=iOS Simulator" \
  -archivePath "${SIM_ARCHIVE}" \
  SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES

XC_ARGS=(
  -framework "${IOS_ARCHIVE}/Products/Library/Frameworks/${BINARY_NAME}.framework"
  -framework "${SIM_ARCHIVE}/Products/Library/Frameworks/${BINARY_NAME}.framework"
)

if [[ "${INCLUDE_CATALYST}" == "1" ]]; then
  echo "Archiving (Mac Catalyst)…"
  xcodebuild archive \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -destination "platform=macOS,arch=x86_64,variant=Mac Catalyst" \
    -archivePath "${CAT_ARCHIVE}" \
    SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES
  XC_ARGS+=( -framework "${CAT_ARCHIVE}/Products/Library/Frameworks/${BINARY_NAME}.framework" )
else
  echo "Skipping Mac Catalyst (INCLUDE_CATALYST=0)"
fi

echo "Creating xcframework…"
xcodebuild -create-xcframework "${XC_ARGS[@]}" -output "${XCFRAMEWORK_PATH}"

echo "✅ Created: ${XCFRAMEWORK_PATH}"

echo "🧹 Cleaning intermediates…"
rm -rf "${IOS_ARCHIVE}" "${SIM_ARCHIVE}" "${CAT_ARCHIVE}"