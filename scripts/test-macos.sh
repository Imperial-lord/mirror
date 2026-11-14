#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
args=(-project apps/macos/MirrorDesktop.xcodeproj -scheme MirrorDesktop -destination 'platform=macOS' -parallel-testing-enabled NO)
if [[ -n "${MAC_DERIVED_DATA:-}" ]]; then args+=(-derivedDataPath "$MAC_DERIVED_DATA"); fi
if [[ -n "${MAC_PACKAGES_DIR:-}" ]]; then args+=(-clonedSourcePackagesDirPath "$MAC_PACKAGES_DIR" -disableAutomaticPackageResolution -skipPackageUpdates); fi
if [[ "${CI:-}" == true ]]; then
  # GitHub runners have no Apple development identity. Build the real application,
  # but run only tests that do not write to the protected authentication keychain.
  # The signed local suite includes the authentication integration tests.
  args+=(CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS= -skip-testing:MirrorDesktopTests/DesktopAuthIntegrationTests)
else
  args+=(-allowProvisioningUpdates)
fi
firebase emulators:exec --config infra/firebase/firebase.json --project demo-mirror-auth --only auth,firestore \
  "xcodebuild $(printf '%q ' "${args[@]}") test"
