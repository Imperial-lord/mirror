# Mirror for macOS

Native SwiftUI/AppKit app for macOS 14+, with its own desktop UI and a separately deployed OCI playback service. It does not run a torrent engine on the Mac.

## Build

1. Install Xcode and XcodeGen.
2. Register a separate Apple-platform app/bundle ID in the existing Firebase project. Use its downloaded configuration as `Config/GoogleService-Info.plist`.
3. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`; set the same bundle ID, Apple development team, streaming origin and reversed Google client ID.
4. Run `xcodegen generate --spec apps/macos/project.yml --project apps/macos` from the repository root.
5. Open `apps/macos/MirrorDesktop.xcodeproj` and run the `MirrorDesktop` scheme.

Firebase Authentication uses the macOS Data Protection keychain. The app must be signed with the checked-in entitlements; a development identity and matching provisioning profile are required for a normal local build. Xcode can manage these automatically. Do not remove keychain entitlements to bypass a signing error. CI uses ad-hoc signing without protected keychain entitlements and skips the two authentication integration tests; run the full signed local suite to verify authentication persistence.

The existing local configuration has been set up for this Mac. Credentials, Firebase client configuration and signing overrides remain ignored by Git. The current developer build can be found at `build/macos/Mirror.app` after building/copying it locally.

## Features

- Desktop sidebar, resizable layouts, keyboard navigation and macOS sharing menus.
- Sign-in, sign-up with the same temporary four-digit verification step as iOS, password reset, Google sign-in, session persistence and profile management. Apple remains the existing placeholder.
- Live home collections and watch-history recommendations; catalog search, partial-title matching, genres, country, studio, year, rating and sorting.
- Movie details, trailers, Wikimedia-only credits/biographies and filmography navigation.
- Firestore Favorites and playlists, editing membership, renaming/removing folders, and history shared with iOS. Watched means strictly more than 95% of the movie duration.
- OCI HTTP-range playback, fullscreen by default, seeking, volume/speed/quality controls, subtitles and watch progress synchronization.
- Local resumable downloads with quality replacement and multiple saved subtitle languages; offline playback restricts choices to what is saved on this Mac. Keep the app running to continue the download queue; interrupted work can be resumed after relaunch.
- Functional dark/light/system appearance, autoplay, real disk usage and download removal.

The native desktop UI lives only under `MirrorDesktop/`. Portable catalog/history/library/metadata code, models and the established artwork/icon assets are referenced by the Mac target from the existing iOS implementation. AppKit authentication presentation, desktop download file permissions and the player/window lifecycle are platform-specific. The iOS UI and OCI deployment are unchanged.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| Command-1 / 2 / 3 / 4 | Home / Catalog / Library / Downloads |
| Command-F | Search movies |
| Command-comma | Settings |
| Space | Play / pause |
| Left / Right | Skip backward / forward 10 seconds |
| F | Enter / exit fullscreen |
| Escape | Leave fullscreen, then return to the movie page |

## Tests

From the repository root, `bash scripts/test-macos.sh` runs the suite with only local Firebase emulators (`demo-mirror-auth`). The suite covers account/profile persistence, strict watch completion, account-scoped history, real HTTP video/seek behavior, download resume/replacement, saved subtitle choices and playback cleanup. Generated clips are local fixtures; tests do not fetch a public movie torrent or use production accounts.

CI bootstraps dummy configuration with `python3 scripts/bootstrap-ios.py --ci --platform macos`. CI runs unit, HTTP playback, download and history tests plus a Release build without production credentials. Authentication integration tests run in the locally signed suite because GitHub runners do not have an Apple development identity. Distribution signing/notarization is separate from this local development build.
