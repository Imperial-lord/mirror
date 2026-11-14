# Portable macOS build

This opt-in build is for sharing Mirror directly with trusted friends. It supports macOS 14 or newer on Apple silicon and Intel. It is ad-hoc signed, without an Apple-verified publisher identity, notarization, a development provisioning profile, or a paid Apple account. [GitHub Releases](macos-releases.md) automate packaging/versioning and provide signed updates through Settings. The first updater-enabled release must be installed manually over older versions.

## Build and test

Configure the ordinary macOS app first using [the macOS setup guide](../apps/macos/README.md), including the Firebase **client** configuration and streaming URL. No signing certificate, private signing key, or provisioning profile is needed for this flavor. Never package Firebase service-account credentials or server environment files.

From the repository root:

```sh
bash scripts/build-macos-adhoc.sh test
bash scripts/build-macos-adhoc.sh build
```

The script resolves locked dependencies into `build/macos-adhoc/SourcePackages`, applies the compatibility changes there, and builds with a separate DerivedData directory. It does not modify the normal dependency cache, iOS build, or normal macOS signing settings. Tests use the local Firebase emulators, not production accounts. Xcode, Python 3, Firebase CLI, and the emulator's Java runtime must be installed.

An optional `MIRROR_ADHOC_PACKAGES_SEED` can point to an existing Xcode SourcePackages directory; the script makes an APFS copy-on-write clone before applying changes. Otherwise it downloads dependencies normally.

Outputs:

- `build/macos-adhoc/Mirror-macOS-adhoc.zip`
- `build/macos-adhoc/SHA256SUMS`
- `build/macos-adhoc/DerivedData/Build/Products/Release/Mirror.app`

The build checks signatures and rejects device provisioning profiles and protected signing entitlements. The bundle includes dependency licenses and a manifest recording the original and modified source hashes.

## Authentication and existing data

The normal Firebase Apple SDK uses the Data Protection Keychain, which requires signing entitlements authorized by a provisioning profile. Ad-hoc signing alone cannot authorize those entitlements.

This flavor modifies three files in isolated, pinned FirebaseAuth and GoogleUtilities sources to use the macOS encrypted **login Keychain** for their default, non-sharing credential storage. Tokens remain in Keychain, not plaintext preferences or files. Explicit shared-Keychain access groups remain unsupported. The patch checks SDK versions, lockfile revisions, and expected source text, and refuses unexpected edits; SDK upgrades require reviewing it again.

The portable build uses a separate `.mirror.adhoc` Keychain service namespace. It does not migrate, overwrite, or delete the signed build's credentials. You must sign in once in the portable build. Firestore accounts, profiles, playlists, favorites and watch history are unchanged. Existing local downloads and settings are not reset. Switching back to the development build keeps its original credential storage.

Login Keychain access follows macOS access controls. Because ad-hoc builds have no stable verified publisher identity, replacing the app can cause another Keychain access prompt or require signing in again. Google consent and production-account sign-in should be checked manually before wider sharing. Emulator authentication tests cover sign-up, sign-in, profiles, and restoring a session after recreating the Firebase app; they do not establish behavior on every recipient's Mac.

## Share and install

Share the ZIP through a trusted channel and supply the checksum separately when possible. A checksum helps detect a changed download; it does not establish publisher identity when distributed beside a tampered file.

1. Your friend extracts the ZIP and moves `Mirror.app` into Applications.
2. They try to open it. If macOS blocks it, they can use **System Settings → Privacy & Security → Open Anyway**, then confirm only if they trust the copy. The exact warning depends on the macOS version and download source.
3. They sign into their own Mirror account.

Do not disable Gatekeeper or other system protections. See [Apple's instructions for opening an app from an unidentified developer](https://support.apple.com/en-us/102445).

For manual updates, quit Mirror and replace the app with the new copy. For in-app updates, use Settings → Download update → Restart and update. Do not delete application data or Keychain entries. Keep a backup of any local downloads that matter.

Developer ID signing and notarization require the paid Apple Developer Program; a free Personal Team cannot issue a Developer ID certificate. This build is an experimental alternative, not equivalent to notarized distribution. See [Apple Developer Program capabilities](https://developer.apple.com/programs/whats-included/).
