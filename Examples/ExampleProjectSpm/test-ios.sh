#!/bin/bash
#
# The slow lane: builds the example package through the SPM prebuild plugin and
# runs the Quick specs on an iOS Simulator. This is what covers RxSwift smart
# defaults, RIBs external-protocol annotation, type erasure and the plugin
# itself. For template edits, start with ../../Checks/run-checks.sh — it needs
# no simulator and runs in seconds.
#
# Destination, in order of precedence:
#   DESTINATION="platform=iOS Simulator,id=..."   use it verbatim
#   OS_VERSION=26.5 [DEVICE_NAME="iPhone 17 Pro"] pin the runtime
#   (default)                                     newest installed iOS runtime
#                                                 that has DEVICE_NAME
#
# The default resolves a concrete simulator UDID rather than naming a device:
# an OS version pinned in this script ages out of the machine, and a bare
# `name=` is ambiguous when the same device exists under several runtimes —
# xcodebuild then reports "Unable to find a device matching the provided
# destination specifier".

set -eo pipefail

DEVICE_NAME="${DEVICE_NAME:-iPhone 17 Pro}"

if [ -z "$DESTINATION" ]; then
  if [ -n "$OS_VERSION" ]; then
    DESTINATION="platform=iOS Simulator,OS=$OS_VERSION,name=$DEVICE_NAME"
  else
    UDID=$(xcrun simctl list devices available | awk -v name="$DEVICE_NAME" '
      /^-- /  { ios = (index($0, "-- iOS ") == 1); next }
      ios == 1 {
        line = $0
        sub(/^ +/, "", line)
        p = index(line, " (")
        if (p == 0) next
        dev = substr(line, 1, p - 1)
        rest = substr(line, p + 2)
        q = index(rest, ")")
        if (q == 0) next
        if (dev == name) udid = substr(rest, 1, q - 1)
      }
      END { print udid }')
    if [ -z "$UDID" ]; then
      echo "No available iOS simulator named '$DEVICE_NAME'."
      echo "Set DEVICE_NAME, OS_VERSION or DESTINATION. Available devices:"
      xcrun simctl list devices available
      exit 1
    fi
    DESTINATION="platform=iOS Simulator,id=$UDID"
  fi
fi

echo "Destination: $DESTINATION"

if command -v xcbeautify > /dev/null; then
  FORMATTER=(xcbeautify)
else
  FORMATTER=(cat)
fi

xcodebuild test \
    -scheme ExampleProjectSpm \
    -destination "$DESTINATION" \
    -configuration "Debug" \
    -sdk "iphonesimulator" \
    -skipPackagePluginValidation \
    | "${FORMATTER[@]}"
