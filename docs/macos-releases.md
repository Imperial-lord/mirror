# macOS releases

Every successful **push CI run on main** triggers **Release macOS**, which builds the exact tested commit and publishes a GitHub Release containing a universal ZIP and SHA256SUMS. Pull requests, develop pushes, failed CI, and forks cannot publish. The release scripts must first be merged into main; the first successful main CI run containing them can then publish.

This uses the [portable ad-hoc build](macos-adhoc.md), not Developer ID signing or notarization. No paid Apple account, certificate, provisioning profile, or personal GitHub token is needed. iOS is not released. Downloads can be installed manually; there is no in-app updater. Existing application data is retained when replacing the app.

## Version policy

Tags named `macos-vMAJOR.MINOR.PATCH` are the version source of truth. The previous untagged app was 1.0.0, so the first default release will be **1.0.1**.

| Change | PR label | Example from 1.2.3 |
| --- | --- | --- |
| Fixes, polish, maintenance (default) | `release:patch` or no label | 1.2.4 |
| New compatible features | `release:minor` | 1.3.0 |
| Breaking changes | `release:major` | 2.0.0 |

Set the label on the **develop → main PR before merging**. When multiple bump labels exist, the highest impact wins. This is an explicit reviewer decision, not a guess from commit text. Tag numbering is independent of iOS and server releases.

The workflow writes the chosen version into `CFBundleShortVersionString` and uses its monotonically increasing run number as `CFBundleVersion`. Local development builds keep the default version in the macOS Base.xcconfig. CI does not commit version bumps back to protected branches.

You can also run **Actions → Release macOS → Run workflow**, selecting **main** and patch/minor/major. The selected main commit must already have a successful push CI run. A published commit is never released again under a new version or overwritten; re-running is safe. Code older than the latest macOS tag cannot be published as a newer release. A failed publishing attempt can resume its draft for the same commit and upload both assets before publishing. Releases are serialized to avoid concurrent version allocation.

## GitHub configuration

Repository Actions secrets:

- `MACOS_FIREBASE_CONFIG_B64`: base64-encoded **Apple client** GoogleService-Info.plist for the macOS bundle ID. This is client configuration that the compiled app necessarily contains; it is not a Firebase Admin credential.
- `MACOS_PLAYBACK_SERVICE_URL`: the OCI streaming origin, with HTTP currently supported for the experimental deployment. The endpoint is included in the compiled app. HTTP does not encrypt authentication tokens in transit; use HTTPS before wider distribution.

Never supply OCI private keys, Firebase service-account JSON, Apple private signing keys, OMDb server keys, or personal account passwords. The runner restores the client configuration only for the build, does not print its values, and removes the temporary files afterwards. Release assets contain the app and checksums only. The workflow uses GitHub's temporary GITHUB_TOKEN with release-write permission; checkout does not retain it as a Git credential.

CI runs release policy/configuration tests and the portable macOS authentication/playback suite with dummy configuration. Production configuration is available only to the main release workflow. No automatic main merge is configured: review the develop → main PR, then merge when its required checks pass.

## Install and update

Download the ZIP from [GitHub Releases](https://github.com/Imperial-lord/mirror/releases), extract it, quit an existing Mirror instance and move the new Mirror.app into Applications. macOS may require Privacy & Security → Open Anyway because this build is not notarized. Keep application data and Keychain entries. A first sign-in is required when switching from the provisioned development app to the portable flavor.

GitHub references: [workflow_run and manual triggers](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows), [generated release notes](https://docs.github.com/en/repositories/releasing-projects-on-github/automatically-generated-release-notes).
