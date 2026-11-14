#!/usr/bin/env bash
# Opt-in portable build: no Apple identity or provisioning profile is used.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
mode="${1:-build}"
if [[ "$mode" != build && "$mode" != test ]]; then
  echo 'Usage: bash scripts/build-macos-adhoc.sh [build|test]' >&2; exit 2
fi
output="$repo_root/build/macos-adhoc"
packages="$output/SourcePackages"
mkdir -p "$output"
if [[ ! -d "$packages/checkouts" ]]; then
  if [[ -n "${MIRROR_ADHOC_PACKAGES_SEED:-}" ]]; then
    # APFS copy-on-write clone; the normal dependency cache remains untouched.
    cp -cR "$MIRROR_ADHOC_PACKAGES_SEED" "$packages"
  else
    xcodebuild -resolvePackageDependencies -project apps/macos/MirrorDesktop.xcodeproj \
      -scheme MirrorDesktop -clonedSourcePackagesDirPath "$packages" \
      -onlyUsePackageVersionsFromResolvedFile
  fi
fi
python3 scripts/prepare-macos-adhoc.py
args=(-project apps/macos/MirrorDesktop.xcodeproj -scheme MirrorDesktop
      -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$output/DerivedData"
      -clonedSourcePackagesDirPath "$packages" -disableAutomaticPackageResolution -skipPackageUpdates
      CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS=
      PROVISIONING_PROFILE_SPECIFIER=)
if [[ -n "${MIRROR_RELEASE_VERSION:-}${MIRROR_RELEASE_BUILD:-}" ]]; then
  if [[ ! "${MIRROR_RELEASE_VERSION:-}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] ||
     [[ ! "${MIRROR_RELEASE_BUILD:-}" =~ ^[1-9][0-9]*$ ]]; then
    echo 'Supply a valid MIRROR_RELEASE_VERSION and positive MIRROR_RELEASE_BUILD together.' >&2; exit 2
  fi
  args+=("MARKETING_VERSION=$MIRROR_RELEASE_VERSION" "CURRENT_PROJECT_VERSION=$MIRROR_RELEASE_BUILD")
fi
if [[ "$mode" == test ]]; then
  firebase emulators:exec --config infra/firebase/firebase.json --project demo-mirror-auth --only auth,firestore \
    "xcodebuild $(printf '%q ' "${args[@]}") -configuration Debug -parallel-testing-enabled NO test"
  exit 0
fi
# Universal binary for Apple silicon and Intel Macs. No global Gatekeeper changes.
xcodebuild "${args[@]}" -configuration Release ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  DEBUG_INFORMATION_FORMAT=dwarf COMPILER_INDEX_STORE_ENABLE=NO build
app="$output/DerivedData/Build/Products/Release/Mirror.app"
if [[ -e "$app/Contents/embedded.provisionprofile" ]]; then
  echo 'Refusing to package a device-provisioned app as portable.' >&2; exit 1
fi
notices="$app/Contents/Resources/PortableBuildNotices"
mkdir -p "$notices"
cp "$output/keychain-patch-manifest.json" "$notices/"
install -m 644 "$packages/checkouts/firebase-ios-sdk/LICENSE" "$notices/Firebase-LICENSE.txt"
install -m 644 "$packages/checkouts/GoogleUtilities/LICENSE" "$notices/GoogleUtilities-LICENSE.txt"
cat > "$notices/README.txt" <<'EOF'
Mirror portable ad-hoc build

This build has no Apple-verified publisher identity and is not notarized.
FirebaseAuth and GoogleUtilities have macOS-only login-Keychain compatibility
changes described by the included patch manifest and the project build script.
The SDK licenses and copyright notices are retained. Credentials remain in the
OS-encrypted login Keychain, in a separate .mirror.adhoc service namespace.
Provisioned cross-app Keychain groups are not supported by this flavor.
EOF
# Only the outer resource seal changed; embedded frameworks were signed by Xcode.
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
python3 - "$app" <<'PY'
import plistlib, subprocess,sys
p=subprocess.run(['codesign','-d','--entitlements',':-',sys.argv[1]],capture_output=True,check=True)
if p.stdout.strip():
    entitlements=plistlib.loads(p.stdout)
    for restricted in ['keychain-access-groups','com.apple.application-identifier','com.apple.developer.team-identifier']:
        if restricted in entitlements: raise SystemExit('Portable build contains a provisioned entitlement: '+restricted)
PY
archive="$output/Mirror-macOS-adhoc.zip"
ditto -c -k --keepParent "$app" "$archive"
(cd "$output" && shasum -a 256 Mirror-macOS-adhoc.zip > SHA256SUMS)
echo "Portable build: $archive"
