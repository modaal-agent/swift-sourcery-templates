# Sourced, not executed: provisions the pinned Sourcery into .build/ and sets
# $SOURCERY. Both check lanes (run-checks.sh, run-cli-checks.sh) share this
# file so the pin and the download path live once. Requires $GIT_ROOT.
#
# Set SOURCERY=/path/to/sourcery to use your own build instead.

# The pin is Scripts/engine-pin.sh, which Scripts/assemble-release.sh reads too.
. "$GIT_ROOT/Scripts/engine-pin.sh"

if [ -z "$SOURCERY" ]; then
  BUNDLE_DIR="$GIT_ROOT/.build/sourcery-${SOURCERY_ENGINE_VERSION}"
  SOURCERY="$BUNDLE_DIR/sourcery-${SOURCERY_ENGINE_VERSION}.artifactbundle/sourcery/bin/sourcery"
  if [ ! -x "$SOURCERY" ]; then
    echo "Downloading Sourcery ${SOURCERY_ENGINE_VERSION}..."
    mkdir -p "$BUNDLE_DIR"
    curl -sSL -o "$BUNDLE_DIR/sourcery.zip" "$SOURCERY_ENGINE_URL"
    unzip -q -o "$BUNDLE_DIR/sourcery.zip" -d "$BUNDLE_DIR"
    # Some releases nest the executable one level deeper.
    [ -x "$SOURCERY" ] || SOURCERY="$(find "$BUNDLE_DIR" -type f -name sourcery -perm +111 | head -1)"
  fi
fi
[ -x "$SOURCERY" ] || { echo "FAIL: no sourcery executable at '$SOURCERY'"; exit 1; }
echo "Sourcery: $("$SOURCERY" --version)"
