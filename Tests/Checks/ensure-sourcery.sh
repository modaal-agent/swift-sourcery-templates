# Sourced, not executed: provisions the pinned Sourcery into .build/ and sets
# $SOURCERY. Both check lanes (run-checks.sh, run-cli-checks.sh) share this
# file so the pin and the download path live once. Requires $GIT_ROOT.
#
# Set SOURCERY=/path/to/sourcery to use your own build instead.

# Keep in step with Package.swift's binary target.
SOURCERY_VERSION="2.3.0"
SOURCERY_URL="https://github.com/krzysztofzablocki/Sourcery/releases/download/${SOURCERY_VERSION}/sourcery-${SOURCERY_VERSION}.artifactbundle.zip"

if [ -z "$SOURCERY" ]; then
  BUNDLE_DIR="$GIT_ROOT/.build/sourcery-${SOURCERY_VERSION}"
  SOURCERY="$BUNDLE_DIR/sourcery-${SOURCERY_VERSION}.artifactbundle/sourcery/bin/sourcery"
  if [ ! -x "$SOURCERY" ]; then
    echo "Downloading Sourcery ${SOURCERY_VERSION}..."
    mkdir -p "$BUNDLE_DIR"
    curl -sSL -o "$BUNDLE_DIR/sourcery.zip" "$SOURCERY_URL"
    unzip -q -o "$BUNDLE_DIR/sourcery.zip" -d "$BUNDLE_DIR"
    # Some releases nest the executable one level deeper.
    [ -x "$SOURCERY" ] || SOURCERY="$(find "$BUNDLE_DIR" -type f -name sourcery -perm +111 | head -1)"
  fi
fi
[ -x "$SOURCERY" ] || { echo "FAIL: no sourcery executable at '$SOURCERY'"; exit 1; }
echo "Sourcery: $("$SOURCERY" --version)"
