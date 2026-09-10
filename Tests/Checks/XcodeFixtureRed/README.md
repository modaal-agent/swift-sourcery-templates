# Xcode red controls

One Xcode project per control that must **fail**, each with its own
`xcodegen.yml` and no committed `.xcodeproj`. A project of its own per control,
for the reason `Tests/Checks/PluginFixtureRed`'s packages are separate: build
planning runs the plugin for every target being built, so a plan-time failure
cannot share a project with a target that has to stay green.

`Tests/Checks/run-xcode-checks.sh` generates every `*/xcodegen.yml` under this
directory and tolerates there being none.

There is none right now. `BareName/` was the one: a config naming a template
without a path, which an Xcode project could not resolve because
`XcodePluginContext` exposes no package graph. It resolves since the plugin
gained two routes that need no graph, so the control moved into
`Tests/Checks/XcodeFixture/Bare/` as the lane's green **bare name** gate
(specs/001-plugin-source-discovery/followup-xcode-lane.md §16).

To add one: a directory here holding `xcodegen.yml` and its sources, and a gate
in `run-xcode-checks.sh` that builds it, asserts the build failed, and matches
the diagnostic that explains why.
