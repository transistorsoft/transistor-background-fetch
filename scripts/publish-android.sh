#!/usr/bin/env bash
set -euo pipefail

# publish-android.sh — Bump, changelog, build, and publish TSBackgroundFetch (Android).
#
# Usage:
#   ./scripts/publish-android.sh --bump patch          # bump version, stamp changelog, publish to Maven Central
#   ./scripts/publish-android.sh --bump minor
#   ./scripts/publish-android.sh --bump major
#   ./scripts/publish-android.sh --snapshot            # publish current version as -SNAPSHOT
#   ./scripts/publish-android.sh --dry-run --bump patch # preview without writing or publishing
#
# Options:
#   --bump [patch|minor|major]   Bump version via Gradle task, stamp changelog, publish release
#   --snapshot                   Append -SNAPSHOT to current version and publish to snapshots repo
#   --dry-run                    Preview all steps without executing
#   --skip-tests                 Skip unit tests before publishing
#   --local                      Publish to mavenLocal instead of Central (for testing)
#   --no-bump                    Publish at current version without bumping

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GRADLE_DIR="${REPO_ROOT}/android"
CHANGELOG="${REPO_ROOT}/CHANGELOG.md"
VERSION_FILE="${GRADLE_DIR}/versioning/tsbackgroundfetch.properties"
TODAY="$(date +%Y-%m-%d)"

DRY_RUN=false
BUMP_MODE=""
SNAPSHOT=false
SKIP_TESTS=false
LOCAL=false
EXPLICIT_VERSION=""

# ---- Parse arguments ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bump)
      BUMP_MODE="${2:?--bump requires patch|minor|major}"
      shift 2
      ;;
    --no-bump)
      BUMP_MODE="none"
      shift
      ;;
    --snapshot)
      SNAPSHOT=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --skip-tests)
      SKIP_TESTS=true
      shift
      ;;
    --local)
      LOCAL=true
      shift
      ;;
    --version)
      EXPLICIT_VERSION="${2:?--version requires a version string (e.g. 4.1.0)}"
      shift 2
      ;;
    *)
      echo "❌ Unknown option: $1" >&2
      echo "Usage: $0 --bump [patch|minor|major] | --snapshot [--version X.Y.Z] [--dry-run] [--skip-tests] [--local]" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$BUMP_MODE" ]] && ! $SNAPSHOT && [[ -z "$EXPLICIT_VERSION" ]]; then
  echo "❌ Must specify --bump [patch|minor|major], --no-bump, --version X.Y.Z, or --snapshot" >&2
  exit 1
fi

# --version alone implies --no-bump
if [[ -z "$BUMP_MODE" ]] && [[ -n "$EXPLICIT_VERSION" ]] && ! $SNAPSHOT; then
  BUMP_MODE="none"
fi

if [[ -n "$BUMP_MODE" ]] && [[ "$BUMP_MODE" != "none" ]] && $SNAPSHOT; then
  echo "❌ --bump and --snapshot are mutually exclusive" >&2
  exit 1
fi

die() { echo "❌ $*" >&2; exit 1; }
run() {
  echo "  \$ $*"
  if ! $DRY_RUN; then
    "$@"
  fi
}

read_version() {
  grep '^VERSION_NAME=' "$VERSION_FILE" | cut -d= -f2 | tr -d '[:space:]'
}

# Write an explicit version into the properties file.
# Computes VERSION_CODE as MA*1000 + MI*100 + PA.
write_version() {
  local ver="$1"
  if [[ ! "$ver" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    die "Invalid version format: ${ver} (expected X.Y.Z)"
  fi
  local ma="${BASH_REMATCH[1]}" mi="${BASH_REMATCH[2]}" pa="${BASH_REMATCH[3]}"
  local code=$(( ma * 1000 + mi * 100 + pa ))
  if $DRY_RUN; then
    echo "  Would update ${VERSION_FILE}: VERSION_NAME=${ver}, VERSION_CODE=${code}"
  else
    sed -i '' "s/^VERSION_NAME=.*/VERSION_NAME=${ver}/" "$VERSION_FILE"
    sed -i '' "s/^VERSION_CODE=.*/VERSION_CODE=${code}/" "$VERSION_FILE"
    echo "▶ Updated ${VERSION_FILE}: VERSION_NAME=${ver}, VERSION_CODE=${code}"
  fi
}

# ---- Snapshot path ----
if $SNAPSHOT; then
  BASE_VERSION="$(read_version)"
  if [[ -n "$EXPLICIT_VERSION" ]]; then
    # Explicit version: publish exactly <version>-SNAPSHOT
    VERSION="${EXPLICIT_VERSION}-SNAPSHOT"
  else
    # Auto-bump patch so snapshot is newer than the last release.
    # e.g. 4.0.6 → 4.0.7-SNAPSHOT (properties file is NOT modified).
    if [[ "$BASE_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
      NEXT_PATCH=$(( ${BASH_REMATCH[3]} + 1 ))
      VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${NEXT_PATCH}-SNAPSHOT"
    else
      VERSION="${BASE_VERSION}-SNAPSHOT"
    fi
  fi
  echo "═══════════════════════════════════════════════════"
  echo "  Snapshot publish: ${VERSION}"
  echo "  (properties file unchanged at ${BASE_VERSION})"
  echo "═══════════════════════════════════════════════════"

  if ! $DRY_RUN; then
    cd "$GRADLE_DIR"
    ./gradlew :tsbackgroundfetch:publishSnapshotToSonatype \
      -PTS_BACKGROUND_FETCH_VERSION_NAME="$VERSION"
  else
    echo "  Would publish ${VERSION} to Central snapshots repo"
  fi

  echo "✅ Snapshot ${VERSION} published."
  exit 0
fi

# ════════════════════════════════════════════════════════════
#  Release path: bump → changelog → test → build → publish
# ════════════════════════════════════════════════════════════

OLD_VERSION="$(read_version)"
echo "▶ Current version: ${OLD_VERSION}"

# ---- 1. Bump version ----
echo ""
if [[ "$BUMP_MODE" == "none" ]] && [[ -n "$EXPLICIT_VERSION" ]]; then
  echo "── Step 1: Set explicit version (${EXPLICIT_VERSION}) ───────────────"
  write_version "$EXPLICIT_VERSION"
  VERSION="$EXPLICIT_VERSION"
  echo "▶ Publishing at explicit version: ${VERSION}"
elif [[ "$BUMP_MODE" == "none" ]]; then
  echo "── Step 1: Bump version skipped (--no-bump) ─────────────────"
  VERSION="$(read_version)"
  echo "▶ Publishing at current version: ${VERSION}"
else
  echo "── Step 1: Bump version (${BUMP_MODE}) ──────────────────────────"
  case "$BUMP_MODE" in
    patch) GRADLE_BUMP="bumpVersionPatch" ;;
    minor) GRADLE_BUMP="bumpVersionMinor" ;;
    major) GRADLE_BUMP="bumpVersionMajor" ;;
    *) die "Unknown bump mode: ${BUMP_MODE} (use patch|minor|major)" ;;
  esac

  if ! $DRY_RUN; then
    bash -c "cd '$GRADLE_DIR' && ./gradlew :tsbackgroundfetch:${GRADLE_BUMP} --quiet"
    VERSION="$(read_version)"
  else
    # Compute bumped version locally for preview.
    cur="$OLD_VERSION"
    IFS='.' read -ra parts <<< "$cur"
    while [[ ${#parts[@]} -lt 3 ]]; do parts+=(0); done
    case "$BUMP_MODE" in
      patch) parts[2]=$(( parts[2] + 1 )) ;;
      minor) parts[1]=$(( parts[1] + 1 )); parts[2]=0 ;;
      major) parts[0]=$(( parts[0] + 1 )); parts[1]=0; parts[2]=0 ;;
    esac
    VERSION="${parts[0]}.${parts[1]}.${parts[2]}"
    echo "  (dry-run: would run ./gradlew :tsbackgroundfetch:${GRADLE_BUMP})"
  fi
  echo "▶ New version: ${VERSION}"
fi

# ---- 2. Generate & stamp changelog ----
echo ""
echo "── Step 2: Stamp changelog ──────────────────────────────────"
generate_changelog_entries() {
  # Find the most recent local tag that is an ancestor of HEAD
  local prev_tag=""
  local tag
  while IFS= read -r tag; do
    if git -C "$REPO_ROOT" merge-base --is-ancestor "$tag" HEAD 2>/dev/null; then
      prev_tag="$tag"
    fi
  done < <(git -C "$REPO_ROOT" tag -l | grep -E '^[0-9]+\.[0-9]+' | sort -V)

  if [[ -z "$prev_tag" ]]; then
    echo "⚠️  No reachable tag found — skipping entry generation"
    return
  fi

  # If this version is already stamped in the changelog, nothing to do
  if [[ -f "$CHANGELOG" ]] && grep -q "^## ${VERSION}" "$CHANGELOG" 2>/dev/null; then
    echo "ℹ️  CHANGELOG.md already has a '## ${VERSION}' heading — skipping generation"
    return
  fi

  # If there's already an Unreleased section with content, don't overwrite
  if [[ -f "$CHANGELOG" ]] && grep -q '^## Unreleased' "$CHANGELOG" 2>/dev/null; then
    local entry_count
    entry_count="$(awk '/^## Unreleased/{found=1;next} /^##/{exit} found && /^- /{c++} END{print c+0}' "$CHANGELOG")"
    if [[ "$entry_count" -gt 0 ]]; then
      echo "ℹ️  CHANGELOG.md already has ${entry_count} entries under '## Unreleased' — skipping generation"
      return
    fi
  fi

  # Collect commit subjects since last tag, filtering out noise
  local commits_file
  commits_file="$(mktemp)"
  git -C "$REPO_ROOT" log "${prev_tag}..HEAD" --pretty=format:'%s' --no-merges \
    | { grep -Eiv '^(fix(up)?|changelog|bump|\[release\]|#|merge)' || true; } \
    | sed '/^\[iOS\]/!{/^\[Android\]/!s/^/[Android] /;}' \
    | sed 's/^/- /' \
    > "$commits_file"

  if [[ ! -s "$commits_file" ]]; then
    echo "ℹ️  No new commits since ${prev_tag}"
    rm -f "$commits_file"
    return
  fi

  echo "▶ Entries from commits since ${prev_tag}:"
  sed 's/^/    /' "$commits_file"

  # Insert under ## Unreleased
  local tmpfile
  tmpfile="$(mktemp)"

  if [[ -f "$CHANGELOG" ]] && grep -q '^## Unreleased' "$CHANGELOG"; then
    while IFS= read -r line; do
      printf '%s\n' "$line"
      if [[ "$line" == "## Unreleased"* ]]; then
        cat "$commits_file"
      fi
    done < "$CHANGELOG" > "$tmpfile"
  elif [[ -f "$CHANGELOG" ]]; then
    while IFS= read -r line; do
      printf '%s\n' "$line"
      if [[ "$line" == "# CHANGELOG"* ]]; then
        echo ""
        echo "## Unreleased"
        cat "$commits_file"
      fi
    done < "$CHANGELOG" > "$tmpfile"
  else
    { echo "# CHANGELOG"; echo ""; echo "## Unreleased"; cat "$commits_file"; } > "$tmpfile"
  fi

  rm -f "$commits_file"
  mv "$tmpfile" "$CHANGELOG"

  # Open in editor for curation
  local editor="${EDITOR:-vim}"
  echo "▶ Opening CHANGELOG.md in ${editor} for review..."
  if ! $DRY_RUN; then
    "$editor" "$CHANGELOG"
  fi
}

stamp_changelog() {
  if [[ ! -f "$CHANGELOG" ]]; then
    die "CHANGELOG.md not found at ${CHANGELOG}"
  fi

  if grep -q "^## ${VERSION}" "$CHANGELOG" 2>/dev/null; then
    echo "ℹ️  '## ${VERSION}' already stamped — skipping"
    return
  fi

  if ! grep -q '^## Unreleased' "$CHANGELOG"; then
    echo "ℹ️  No '## Unreleased' section — nothing to stamp"
    return
  fi

  local stamped="## ${VERSION} \&mdash; ${TODAY}"

  if $DRY_RUN; then
    echo "  Would rename '## Unreleased' → '${stamped}'"
    return
  fi

  sed -i '' "s/^## Unreleased/${stamped}/" "$CHANGELOG"
  echo "▶ Stamped: ${stamped}"

  git -C "$REPO_ROOT" add CHANGELOG.md
  git -C "$REPO_ROOT" add android/versioning/tsbackgroundfetch.properties
  if ! git -C "$REPO_ROOT" diff --cached --quiet; then
    git -C "$REPO_ROOT" commit -m "Release ${VERSION}"
  fi
}

generate_changelog_entries
stamp_changelog

# ---- 3. Run tests ----
if ! $SKIP_TESTS; then
  echo ""
  echo "── Step 3: Run tests ──────────────────────────────────────"
  run bash -c "cd '$GRADLE_DIR' && ./gradlew :tsbackgroundfetch:testDebugUnitTest"
else
  echo ""
  echo "── Step 3: Tests skipped (--skip-tests) ───────────────────"
fi

# ---- 4. Build ----
echo ""
echo "── Step 4: Build release ────────────────────────────────────"
run bash -c "cd '$GRADLE_DIR' && ./gradlew :tsbackgroundfetch:assembleRelease"

# ---- 5. Publish ----
echo ""
echo "── Step 5: Publish ──────────────────────────────────────────"
if $LOCAL; then
  echo "▶ Publishing to mavenLocal..."
  run bash -c "cd '$GRADLE_DIR' && ./gradlew :tsbackgroundfetch:publishToMavenLocal"
else
  echo "▶ Publishing to Maven Central (Sonatype)..."
  run bash -c "cd '$GRADLE_DIR' && ./gradlew :tsbackgroundfetch:publishToSonatype closeAndReleaseSonatypeStagingRepository"
fi

# ---- 6. Tag ----
echo ""
echo "── Step 6: Tag ──────────────────────────────────────────────"
if $DRY_RUN; then
  echo "  Would tag: ${VERSION}"
else
  git -C "$REPO_ROOT" tag -a "$VERSION" -m "Release ${VERSION}"
  echo "▶ Tagged: ${VERSION}"
fi

echo ""
echo "═══════════════════════════════════════════════════"
echo "  ✅ ${VERSION} published successfully"
echo "═══════════════════════════════════════════════════"
echo ""
echo "  Artifacts will appear at:"
echo "    https://repo1.maven.org/maven2/com/transistorsoft/tsbackgroundfetch/${VERSION}/"
echo ""
echo "  Don't forget to push:"
echo "    git push && git push --tags"
