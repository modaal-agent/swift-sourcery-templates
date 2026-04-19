#!/bin/bash

xcodebuild test \
    -scheme ExampleProjectSpm \
    -destination 'platform=iOS Simulator,OS=26.4,name=iPhone 17 Pro' \
    -configuration "Debug" \
    -sdk "iphonesimulator" \
    -skipPackagePluginValidation \
    | xcbeautify
