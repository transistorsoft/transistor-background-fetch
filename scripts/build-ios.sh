#!/usr/bin/env bash

set -euo pipefail

# Resolve repo root from the location of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." &>/dev/null && pwd)"

#
# Defaults
#
VERSION="${VERSION:-}"
SCHEME="${SCHEME:-TSBackgroundFetch}"
PROJECT_NAME="${PROJECT_NAME:-TSBackgroundFetch}"
CONFIGURATION="${CONFIGURATION:-Release}"
PROJECT_PATH="${PROJECT_PATH:-${REPO_ROOT}/ios/TSBackgroundFetch/TSBackgroundFetch.xcodeproj}"

# Put artifacts under repo-level build/Release-Publish
OUTDIR="${OUTDIR:-${REPO_ROOT}/build/Release-Publish}"
INCLUDE_CATALYST="${INCLUDE_CATALYST:-0}"   # 0=skip (default for bg-fetch), 1=build

# SDK birthdate tag
SDK_BIRTHDATE=$(date -u +%Y%m%d)
XCODEFLAGS_COMMON=( GCC_PREPROCESSOR_DEFINITIONS="\$(inherited) TSL_TAG=${SDK_BIRTHDATE}" )

QUIET=0
VERBOSE=1
for arg in "$@"; do
  case "$arg" in
    --quiet)        QUIET=1; VERBOSE=0 ;;
    --verbose)      QUIET=0; VERBOSE=1 ;;
    --no-catalyst)  INCLUDE_CATALYST=0 ;;
    --catalyst)     INCLUDE_CATALYST=1 ;;
    --version)      ;; # handled below
    *)
      # handle --version VALUE (two-arg form)
      ;;
  esac
done

# Parse --version VALUE (needs index-based iteration)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)   VERSION="$2"; shift 2 ;;
    --quiet|--verbose|--no-catalyst|--catalyst) shift ;;
    *)           shift ;;
  esac
done

# --- Inject MARKETING_VERSION / CURRENT_PROJECT_VERSION from versioning file ---
VERSION_FILE="${REPO_ROOT}/versioning/${PROJECT_NAME}.properties"
if [[ -f "${VERSION_FILE}" ]]; then
  echo "Loading version info from ${VERSION_FILE}"
  MARKETING_VERSION="$(grep -E '^MARKETING_VERSION=' "${VERSION_FILE}" | cut -d'=' -f2- | tr -d '\r' || true)"
  CURRENT_PROJECT_VERSION="$(grep -E '^CURRENT_PROJECT_VERSION=' "${VERSION_FILE}" | cut -d'=' -f2- | tr -d '\r' || true)"

  if [[ -z "${MARKETING_VERSION:-}" ]]; then
    echo "ERROR: MARKETING_VERSION is missing in ${VERSION_FILE}"
    exit 1
  fi
  if [[ -z "${CURRENT_PROJECT_VERSION:-}" ]]; then
    echo "ERROR: CURRENT_PROJECT_VERSION is missing in ${VERSION_FILE}"
    exit 1
  fi

  XCODEFLAGS_COMMON+=( "MARKETING_VERSION=${MARKETING_VERSION}" )
  XCODEFLAGS_COMMON+=( "CURRENT_PROJECT_VERSION=${CURRENT_PROJECT_VERSION}" )
  echo "  MARKETING_VERSION=${MARKETING_VERSION}, CURRENT_PROJECT_VERSION=${CURRENT_PROJECT_VERSION}"

  # If caller didn't pass VERSION explicitly, default to MARKETING_VERSION for output naming.
  if [[ -z "${VERSION:-}" ]]; then
    VERSION="${MARKETING_VERSION}"
    echo "  Using MARKETING_VERSION as VERSION for output folder: ${VERSION}"
  else
    echo "  Using explicit VERSION for output folder: ${VERSION}"
  fi
else
  echo "WARNING: No versioning file found at ${VERSION_FILE}, using defaults."
  if [[ -z "${VERSION:-}" ]]; then
    VERSION="dev"
    echo "  Using default VERSION for output folder: ${VERSION}"
  fi
fi

echo ""
echo "Building ${PROJECT_NAME}.xcframework  (tag=${SDK_BIRTHDATE})"
mkdir -p "${OUTDIR}"
ROOT="${OUTDIR}/${PROJECT_NAME}_XCFramework_${VERSION}"
rm -rf "${ROOT}"
mkdir -p "${ROOT}"

SIM_ARC="${ROOT}/simulator.xcarchive"
IOS_ARC="${ROOT}/ios.xcarchive"
CAT_X86="${ROOT}/catalyst_x86.xcarchive"
CAT_ARM="${ROOT}/catalyst_arm.xcarchive"

XCFRAMEWORK_PATH="${ROOT}/${PROJECT_NAME}.xcframework"

# Fast-fail sanity check for project path
if [[ ! -d "${PROJECT_PATH}" ]]; then
  echo "ERROR: Project not found at: ${PROJECT_PATH}"
  echo "  Override with: PROJECT_PATH=/custom/path ${SCRIPT_DIR}/build-ios.sh"
  exit 1
fi

echo "  Using PROJECT_PATH: ${PROJECT_PATH}"
echo "  Output directory:   ${OUTDIR}"

if [[ "${INCLUDE_CATALYST}" == "1" ]]; then
  echo "  Mac Catalyst: ENABLED"
else
  echo "  Mac Catalyst: DISABLED (pass --catalyst or INCLUDE_CATALYST=1 to enable)"
fi

# ---------------------------------------------------------------------------
# xcodebuild wrapper: suppresses output in --quiet mode
# ---------------------------------------------------------------------------
run_xcodebuild() {
  if [[ "$QUIET" -eq 1 ]]; then
    xcodebuild "$@" > /dev/null
  else
    xcodebuild "$@"
  fi
}

# ---------------------------------------------------------------------------
# Archive: iOS Simulator
# ---------------------------------------------------------------------------
echo ""
echo "Archiving (iOS Simulator)..."
run_xcodebuild archive \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "generic/platform=iOS Simulator" \
  -archivePath "${SIM_ARC}" -sdk iphonesimulator \
  SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  "${XCODEFLAGS_COMMON[@]}"

# ---------------------------------------------------------------------------
# Archive: iOS Device
# ---------------------------------------------------------------------------
echo ""
echo "Archiving (iOS Device)..."
run_xcodebuild archive \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "generic/platform=iOS" \
  -archivePath "${IOS_ARC}" -sdk iphoneos \
  SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  "${XCODEFLAGS_COMMON[@]}"

# ---------------------------------------------------------------------------
# Archive: Mac Catalyst (dual-arch, if enabled)
# ---------------------------------------------------------------------------
if [[ "${INCLUDE_CATALYST}" == "1" ]]; then
  echo ""
  echo "Archiving (Mac Catalyst x86_64)..."
  run_xcodebuild archive \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -destination "generic/platform=macOS,variant=Mac Catalyst" \
    -archivePath "${CAT_X86}" -sdk macosx \
    SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    ENABLE_USER_SCRIPT_SANDBOXING=NO \
    ARCHS=x86_64 \
    EXCLUDED_ARCHS= \
    ONLY_ACTIVE_ARCH=NO \
    "${XCODEFLAGS_COMMON[@]}"

  echo ""
  echo "Archiving (Mac Catalyst arm64)..."
  run_xcodebuild archive \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -destination "generic/platform=macOS,variant=Mac Catalyst" \
    -archivePath "${CAT_ARM}" -sdk macosx \
    SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    ENABLE_USER_SCRIPT_SANDBOXING=NO \
    ARCHS=arm64 \
    EXCLUDED_ARCHS= \
    ONLY_ACTIVE_ARCH=NO \
    "${XCODEFLAGS_COMMON[@]}"
fi

# ---------------------------------------------------------------------------
# Catalyst: verify slices and lipo-merge into universal framework
# ---------------------------------------------------------------------------
CAT_FRAME_X86="${CAT_X86}/Products/Library/Frameworks/${PROJECT_NAME}.framework"
CAT_FRAME_ARM="${CAT_ARM}/Products/Library/Frameworks/${PROJECT_NAME}.framework"
CAT_UNIV="${ROOT}/${PROJECT_NAME}.framework"

if [[ "${INCLUDE_CATALYST}" == "1" ]]; then
  echo ""
  echo "Catalyst x86_64 slice info:"
  lipo -info "${CAT_FRAME_X86}/${PROJECT_NAME}" || true
  echo "Catalyst arm64 slice info:"
  lipo -info "${CAT_FRAME_ARM}/${PROJECT_NAME}" || true

  # Confirm both slices exist before lipo
  if [[ ! -f "${CAT_FRAME_X86}/${PROJECT_NAME}" ]]; then
    echo "ERROR: Catalyst x86_64 slice missing at ${CAT_FRAME_X86}/${PROJECT_NAME}"
    exit 1
  fi
  if [[ ! -f "${CAT_FRAME_ARM}/${PROJECT_NAME}" ]]; then
    echo "ERROR: Catalyst arm64 slice missing at ${CAT_FRAME_ARM}/${PROJECT_NAME}"
    exit 1
  fi

  # Validate arch content
  ARM_INFO="$(lipo -info "${CAT_FRAME_ARM}/${PROJECT_NAME}" 2>/dev/null || true)"
  X86_INFO="$(lipo -info "${CAT_FRAME_X86}/${PROJECT_NAME}" 2>/dev/null || true)"
  if [[ "$ARM_INFO" != *"arm64"* ]]; then
    echo "ERROR: Expected arm64 in Catalyst ARM slice but got: $ARM_INFO"
    exit 1
  fi
  if [[ "$X86_INFO" != *"x86_64"* ]]; then
    echo "ERROR: Expected x86_64 in Catalyst x86 slice but got: $X86_INFO"
    exit 1
  fi

  rm -rf "${CAT_UNIV}"
  cp -R "${CAT_FRAME_ARM}" "${CAT_UNIV}"
  lipo -create \
    "${CAT_FRAME_ARM}/${PROJECT_NAME}" \
    "${CAT_FRAME_X86}/${PROJECT_NAME}" \
    -output "${CAT_UNIV}/${PROJECT_NAME}"
fi

# ---------------------------------------------------------------------------
# Create XCFramework
# ---------------------------------------------------------------------------
echo ""
echo "Creating xcframework..."
CREATE=( -create-xcframework
  -framework "${SIM_ARC}/Products/Library/Frameworks/${PROJECT_NAME}.framework"
  -framework "${IOS_ARC}/Products/Library/Frameworks/${PROJECT_NAME}.framework"
  -output "${XCFRAMEWORK_PATH}"
)
if [[ "${INCLUDE_CATALYST}" == "1" ]]; then
  CREATE+=( -framework "${CAT_UNIV}" )
fi
run_xcodebuild "${CREATE[@]}"

# ---------------------------------------------------------------------------
# Clean intermediate archives
# ---------------------------------------------------------------------------
echo ""
echo "Cleaning intermediates..."
rm -rf "${SIM_ARC}" "${IOS_ARC}"
if [[ "${INCLUDE_CATALYST}" == "1" ]]; then
  rm -rf "${CAT_X86}" "${CAT_ARM}" "${CAT_UNIV}"
fi

# ---------------------------------------------------------------------------
# Sign XCFramework
# ---------------------------------------------------------------------------
SIGN_IDENTITY="${SIGN_IDENTITY:-Apple Distribution: 9224-2932 Quebec Inc (32A636YFGZ)}"
echo ""
echo "Signing XCFramework with: ${SIGN_IDENTITY}"
codesign --force --sign "${SIGN_IDENTITY}" --timestamp "${XCFRAMEWORK_PATH}"

# ---------------------------------------------------------------------------
# Zip + SPM checksum
# ---------------------------------------------------------------------------
echo ""
echo "Creating zip for SPM distribution..."
cp "${REPO_ROOT}/LICENSE" "${ROOT}/LICENSE" 2>/dev/null || true
( cd "${ROOT}" && /usr/bin/zip -yr "${PROJECT_NAME}.xcframework.zip" "${PROJECT_NAME}.xcframework" LICENSE )
echo ""
echo "SPM checksum:"
swift package compute-checksum "${ROOT}/${PROJECT_NAME}.xcframework.zip" || true

# ---------------------------------------------------------------------------
# Info.plist version sanity check
# ---------------------------------------------------------------------------
print_plist_versions() {
  local plist_path="$1"
  if [[ -f "$plist_path" ]]; then
    local shortver ver
    shortver=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist_path" 2>/dev/null || echo "N/A")
    ver=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist_path" 2>/dev/null || echo "N/A")
    echo "   CFBundleShortVersionString=${shortver}, CFBundleVersion=${ver}"
  else
    echo "   Info.plist not found at $plist_path"
  fi
}

echo ""
echo "Built framework Info.plist versions:"
XC_PLISTS=()
if [[ -f "${XCFRAMEWORK_PATH}/ios-arm64/${PROJECT_NAME}.framework/Info.plist" ]]; then
  XC_PLISTS+=("${XCFRAMEWORK_PATH}/ios-arm64/${PROJECT_NAME}.framework/Info.plist")
fi
if [[ -f "${XCFRAMEWORK_PATH}/ios-arm64_x86_64-simulator/${PROJECT_NAME}.framework/Info.plist" ]]; then
  XC_PLISTS+=("${XCFRAMEWORK_PATH}/ios-arm64_x86_64-simulator/${PROJECT_NAME}.framework/Info.plist")
fi
if [[ -f "${XCFRAMEWORK_PATH}/ios-arm64_x86_64-maccatalyst/${PROJECT_NAME}.framework/Info.plist" ]]; then
  XC_PLISTS+=("${XCFRAMEWORK_PATH}/ios-arm64_x86_64-maccatalyst/${PROJECT_NAME}.framework/Info.plist")
fi
if [[ ${#XC_PLISTS[@]} -eq 0 ]]; then
  echo "   (no Info.plist files found in ${XCFRAMEWORK_PATH})"
else
  for FW_PLIST in "${XC_PLISTS[@]}"; do
    echo " - $(dirname "$(dirname "$FW_PLIST")")"
    print_plist_versions "$FW_PLIST"
  done
fi

echo ""
echo "Done. XCFramework at: ${XCFRAMEWORK_PATH}"
echo "     ZIP: ${ROOT}/${PROJECT_NAME}.xcframework.zip"
