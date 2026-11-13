# Authentication and profiles

Email sign-up validates the form, then shows the four-digit verification screen. Any four ASCII digits are accepted while email delivery is pending. This screen does not mark the Firebase email address as verified. The account is created after pressing Verify Account.

Google sign-in uses the GoogleSignIn SDK, the OAuth client in GoogleService-Info.plist, and the matching callback URL scheme in Info.plist. Google is enabled in the mirror-movie-app Firebase project. Apple remains a visible icon with no action until Apple Developer setup is requested again. The Apple provider was enabled in Firebase during setup, but the app does not invoke it.

Initial profiles are created together using a Firestore batch and deterministic IDs. Subsequent loads preserve existing profiles and do not recreate a deleted Kids profile. The active profile is remembered by ID separately for each Firebase user. Profile names can be duplicated; whitespace-only names are rejected. The final profile cannot be deleted through the app.

The shared editor supports creating, renaming, changing the Kids flag, selecting/removing a photo or a preset avatar from the reference design. Selected photos are downsampled to 384 pixels and compressed to JPEG, capped at 200 KB, and stored in the profile's Firestore document. Existing profile documents without photo data remain compatible. The active avatar is used by the account tab, profile switcher, and profile selection screen. Save and delete failures keep the editor open with an error.

## Local integration tests

Requirements: Xcode, XcodeGen, Firebase CLI, Java, and a booted iPhone simulator.

Generate the project after changing project.yml:

```sh
xcodegen generate --spec apps/ios/project.yml --project apps/ios
```

Run against a demo project with local Auth and Firestore emulators:

```sh
firebase emulators:exec --config infra/firebase/firebase.json --only auth,firestore --project demo-mirror-auth \
  "xcodebuild -project apps/ios/Mirror.xcodeproj -scheme Mirror -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test"
```

Use normal simulator code signing; disabling code signing prevents Firebase Auth from accessing the simulator keychain on newer runtimes. No Apple Developer membership is needed for local simulator signing.

The tests use a separate named Firebase app and never use the production configuration. They cover profile creation, photo persistence/removal, duplicate-name preservation, deletion, last-profile protection, sign-out/sign-in restoration, failed-save state, validation, and cross-account read/write restrictions. The Firestore rules limit account documents to the authenticated owner and reviews to their author for writes.

For a UI-only check of sign-up, verification, and OAuth presentation without signing out an existing simulator session, launch a Debug build with `--auth-preview`. Do not submit account forms unless testing with a dedicated account. Relaunch normally to return to the existing session.

## Design reference

The auth and account screens follow Sasha Dobrynina’s [Mirror design](https://www.behance.net/gallery/211500071/Online-Cinema-App-Mirror), particularly the registration board and Account board 18. The 16 bundled character avatar thumbnails were extracted from the user-supplied reference board; they are not newly generated assets. Camera and gallery selection share the same compression and persistence path. The camera requires a physical device; the simulator can use gallery images and presets.
