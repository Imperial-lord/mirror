# macOS releases

After all five required checks on a **main push** pass, CI calls **Release macOS**, which builds the exact tested commit. The protected `macos-release` environment requires the repository owner's approval before the job can access signing secrets and publish. Pull requests, develop pushes, failed checks, and forks cannot publish. Assets include a universal ZIP, SHA256SUMS, and a signed Sparkle appcast.

This uses the [portable ad-hoc build](macos-adhoc.md), not Developer ID signing or notarization. No paid Apple account, certificate, provisioning profile, or personal GitHub token is needed. iOS is not released. Sparkle verifies signed feeds and archives before extraction and handles replacement/relaunch. Existing application data is retained.

## Version policy

Tags named `macos-vMAJOR.MINOR.PATCH` are the version source of truth. The previous untagged app was 1.0.0, so the first default release will be **1.0.1**.

| Change | PR label | Example from 1.2.3 |
| --- | --- | --- |
| Fixes, polish, maintenance (default) | `release:patch` or no label | 1.2.4 |
| New compatible features | `release:minor` | 1.3.0 |
| Breaking changes | `release:major` | 2.0.0 |

Set the label on the **develop → main PR before merging**. When multiple bump labels exist, the highest impact wins. This is an explicit reviewer decision, not a guess from commit text. Tag numbering is independent of iOS and server releases.

The workflow writes the semantic version into both `CFBundleShortVersionString` and `CFBundleVersion`. This keeps Sparkle's version comparison monotonic across automatic and manual workflows, whose run counters differ. Local development builds keep the default version in Base.xcconfig, with installation disabled to avoid replacing a developer's signed build. CI does not commit version bumps back to protected branches.

You can also run **Actions → Release macOS → Run workflow**, selecting **main** and patch/minor/major. All five required checks must already have passed for the selected main commit. A published commit is never released again under a new version or overwritten; re-running is safe. Code older than the latest macOS tag cannot be published as a newer release. A failed publishing attempt can resume its draft for the same commit and upload all assets before publishing. Releases are serialized to avoid concurrent version allocation. Main CI may show "waiting" until you approve its release deployment.

## GitHub configuration

Repository Actions secrets:

- `MACOS_FIREBASE_CONFIG_B64`: base64-encoded **Apple client** GoogleService-Info.plist for the macOS bundle ID. This is client configuration that the compiled app necessarily contains; it is not a Firebase Admin credential.
- `MACOS_PLAYBACK_SERVICE_URL`: the OCI streaming origin, with HTTP currently supported for the experimental deployment. The endpoint is included in the compiled app. HTTP does not encrypt authentication tokens in transit; use HTTPS before wider distribution.

Environment secret in **macos-release**, restricted to protected branches and owner approval:

- `MACOS_UPDATE_SIGNING_KEY`: Sparkle's private Ed25519 update-signing key. It is not an Apple signing key. The app embeds only the public `SUPublicEDKey`; neither the app nor published assets contain the private key. CI writes it to a restricted temporary file for the signing tool, never prints it, and removes that file on exit. Do not enable shell tracing for this step.

A recovery copy is in the maintainer's macOS login Keychain under the Sparkle account `com.imperiallord.mirror.updates`. Losing both copies would break trust continuity for existing ad-hoc installations. Back it up securely; never commit an export. GitHub repository secrets are not a substitute for this backup, because their values cannot be read back. Keep the public key stable between releases. A compromised signing job could steal the key, so review workflow and dependency changes before approving a release.

Never supply OCI private keys, Firebase service-account JSON, Apple private signing keys, OMDb server keys, or personal account passwords. The runner restores client configuration only for the build, does not print its values, and removes temporary files afterwards. The workflow uses GitHub's temporary GITHUB_TOKEN with release-write permission; checkout does not retain it as a Git credential.

CI runs release policy/configuration tests and the portable macOS authentication/playback suite with dummy configuration. Production configuration is available only to the main release workflow. No automatic main merge is configured: review the develop → main PR, then merge when its required checks pass.

## Install and update

Download the ZIP from [GitHub Releases](https://github.com/Imperial-lord/mirror/releases), extract it, quit an existing Mirror instance and move the new Mirror.app into Applications. macOS may require Privacy & Security → Open Anyway because this build is not notarized. Keep application data and Keychain entries. A first sign-in is required when switching from the provisioned development app to the portable flavor.

The previously published 1.0.1 app has no updater. Install the first updater-enabled release manually once. After that, Mirror checks the latest GitHub release feed on launch and about every six hours while open (unless disabled in Settings). An available update adds a small indicator to Settings. Choose **Download update**, then **Restart and update** when ready. Checks do not interrupt playback, download automatically, or quit the app. Installation may ask for normal macOS authorization if the app is not writable by the current user. Running from a read-only disk image or a translocated download can require moving Mirror into Applications first.

References: [reusable workflows](https://docs.github.com/en/actions/sharing-automations/reusing-workflows), [generated release notes](https://docs.github.com/en/repositories/releasing-projects-on-github/automatically-generated-release-notes), [Sparkle security and publishing](https://sparkle-project.org/documentation/).
