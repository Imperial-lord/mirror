#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
# Locally, only the user's existing iPhone 17 is selected. CI passes an explicit destination.
destination="${IOS_DESTINATION:-platform=iOS Simulator,name=iPhone 17}"
args=(-project apps/ios/Mirror.xcodeproj -scheme Mirror -destination "$destination" -parallel-testing-enabled NO)
if [[ -n "${IOS_DERIVED_DATA:-}" ]]; then args+=(-derivedDataPath "$IOS_DERIVED_DATA"); fi
if [[ -n "${IOS_PACKAGES_DIR:-}" ]]; then args+=(-clonedSourcePackagesDirPath "$IOS_PACKAGES_DIR" -disableAutomaticPackageResolution -skipPackageUpdates); fi
# Firebase starts only demo-project emulators; integration tests create a separate named app.
firebase emulators:exec --config infra/firebase/firebase.json --project demo-mirror-auth --only auth,firestore \
  "xcodebuild $(printf '%q ' "${args[@]}") test"
