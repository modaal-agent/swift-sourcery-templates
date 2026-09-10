# Sourced, not executed: the upstream Sourcery engine this repository vendors —
# its version, its zip and that zip's SHA-256. Requires nothing; sets three
# variables and returns.
#
# Read by name in two places:
#
#   Scripts/assemble-release.sh       downloads the zip, verifies it against
#                                     SOURCERY_ENGINE_CHECKSUM, and vendors
#                                     bin/sourcery into the release bundle
#   Tests/Checks/ensure-sourcery.sh   provisions the same engine for the fast
#                                     and CLI check lanes
#
# It has its own file because a pin has to be readable by name.
# `Scripts/assemble-release.sh` used to take the *first* `artifactbundle.zip` URL
# in `Package.swift` and parse the version out of its path, which selects by
# position: a manifest naming a second artifact bundle would vendor that one as
# "the engine", with a version parsed from the wrong URL, and the release smoke
# test would still pass. `Tests/Checks/ensure-sourcery.sh` carried a second copy
# of the version under "keep in step with Package.swift", which is not a check
# anything runs. See specs/001-plugin-source-discovery/followup-xcode-lane.md,
# F12.
#
# Bumping the engine: change all three values together, then run
# `Tests/Checks/run-checks.sh` and `Tests/Checks/run-cli-checks.sh` — the
# snapshot diff is what an engine bump shows up as.

SOURCERY_ENGINE_VERSION="2.3.0"
SOURCERY_ENGINE_URL="https://github.com/krzysztofzablocki/Sourcery/releases/download/${SOURCERY_ENGINE_VERSION}/sourcery-${SOURCERY_ENGINE_VERSION}.artifactbundle.zip"
SOURCERY_ENGINE_CHECKSUM="2fb2ae820c4d12f77232bacba5ee719fff9d61c71c3e8c6067691b2e90aa4ba7"
