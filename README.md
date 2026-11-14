# Mirror

Native SwiftUI iOS and macOS movie apps with a separately deployed Node streaming service.
Design reference: [Mirror by Sasha Dobrynina](https://www.behance.net/gallery/211500071/Online-Cinema-App-Mirror).

## Layout

```
apps/ios/             iOS app, Xcode project, configuration and tests
apps/macos/           native macOS app, desktop UI, Xcode project and tests
services/streaming/   independently deployable Node/WebTorrent service
packages/             standalone packages (legacy SwiftTorrent is not linked)
infra/firebase/       Firestore rules, indexes and emulator configuration
docs/                 feature notes, design references and asset licenses
scripts/              CI/bootstrap and repository checks
```

## iOS setup

Requires Xcode with an iOS 17+ SDK and XcodeGen (`brew install xcodegen`).

1. Download your Firebase iOS `GoogleService-Info.plist` into `apps/ios/Config/`.
2. Copy `apps/ios/Config/Local.xcconfig.example` to `Local.xcconfig` in the same directory.
   Set your registered bundle ID, development team, streaming origin and the Firebase plist's
   `REVERSED_CLIENT_ID`. URLs in xcconfig use `http:/$()/` or `https:/$()/` to avoid comment parsing.
3. Run `xcodegen generate --spec apps/ios/project.yml --project apps/ios`.
4. Open `apps/ios/Mirror.xcodeproj` and run the `Mirror` scheme.

The checked-in Xcode project and shared scheme can be opened directly after configuration.
Regenerate after changing sources or `project.yml`; commit the regenerated project and package lock.
Private configuration is ignored and stays on your machine. CI generates dummy Firebase configuration;
`python3 scripts/bootstrap-ios.py --ci` does the same on a clean checkout and refuses to replace a real file.
Dummy configuration supports builds/tests, not production sign-in.

Optional Debug-only demo autofill reads `MIRROR_DEMO_EMAIL` and `MIRROR_DEMO_PASSWORD` from the
Xcode scheme environment. Never save them in a shared scheme.

## macOS setup

See [Mirror for macOS](apps/macos/README.md) for local configuration, signing, desktop features and keyboard shortcuts. Open `apps/macos/MirrorDesktop.xcodeproj` and run the `MirrorDesktop` scheme. The Mac app uses the same Firebase data and OCI streaming service.

## Streaming service

```
cd services/streaming
cp .env.example .env
npm ci --omit=optional
npm test
npm start
```

Node 22+ reads `.env` at startup. For public hosting configure Firebase Admin credentials as described
in [the service guide](services/streaming/README.md). Docker: `docker build -t mirror-streaming services/streaming`;
pass configuration with `--env-file` and mount credentials read-only. The server code and Dockerfile
remain independent of either client UI. No CI step deploys to OCI automatically.

## Tests

```
cd services/streaming && npm test
# From the repository root, with Firebase CLI and Java installed:
bash scripts/test-ios.sh
```

Local iOS tests default to the existing iPhone 17. Set `IOS_DESTINATION` to an explicit simulator
ID if needed. Auth/profile integration tests use only the `demo-mirror-auth` emulators.
CI builds iOS and macOS in Debug and Release and runs all active client tests, server tests, a Docker build and secret/repository checks.
The old in-app torrent adapter tests are excluded because the shipping app uses the server.

## Branches and releases

- `develop`: normal integration branch; create feature/fix branches from it and target PRs here.
- `main`: stable branch; promote with a `develop` → `main` pull request after testing.

`main` requires the Security, Server tests, iOS build and tests, macOS build and tests, and Develop to main checks,
an up-to-date branch, resolved conversations and a pull request. Force pushes/deletions and admin
bypasses are disabled. No second-person approval is required for this single-maintainer project.
Merge commits preserve the develop/main history; after a promotion, merge `main` back into `develop`.
The repository defaults to `develop` for new work.

See [SECURITY.md](SECURITY.md) for configuration handling. Existing license is preserved in [LICENSE](LICENSE).
