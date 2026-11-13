# Configuration and secrets

Never commit `.env`, `Config/Local.xcconfig`, a real `GoogleService-Info.plist`,
Firebase Admin service-account JSON, signing certificates, private keys or tokens.
Examples contain placeholders only. Git ignores these files; CI also scans tracked files and history.

Firebase iOS configuration identifies the client and is embedded in a built app; it is not
an authorization boundary. Keep the project-specific file local anyway. Firestore rules and
server-side token verification enforce access. Restrict client keys in the Firebase/Google console.
Server credentials and OMDb keys belong in deployment environment variables or mounted secret files.
Mobile apps cannot keep server-side secrets in an `.env` or their compiled bundle.

If a credential is accidentally published, revoke/rotate it at its issuer before cleaning Git history.
Report security issues privately through GitHub's private vulnerability reporting when enabled.
