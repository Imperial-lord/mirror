import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import XCTest

@testable import MirrorDesktop

@MainActor final class DesktopAuthIntegrationTests: XCTestCase {
  private func service() -> AuthService {
    let options = FirebaseOptions(
      googleAppID: "1:123456789:ios:1234567890abcdef", gcmSenderID: "123456789")
    options.apiKey = "emulator-api-key"
    options.projectID = "demo-mirror-auth"
    let name = "MacTests-\(UUID().uuidString)"
    FirebaseApp.configure(name: name, options: options)
    let app = FirebaseApp.app(name: name)!
    let auth = Auth.auth(app: app)
    auth.useEmulator(withHost: "127.0.0.1", port: 9099)
    let db = Firestore.firestore(app: app)
    let settings = db.settings
    settings.host = "127.0.0.1:8080"
    settings.isSSLEnabled = false
    settings.cacheSettings = MemoryCacheSettings()
    db.settings = settings
    return AuthService(auth: auth, db: db)
  }
  func testDesktopSignInPersistsSessionAndProfiles() async throws {
    let service = service()
    let email = "mac-\(UUID().uuidString)@example.test"
    try await service.signUp(email: email, password: "EmulatorOnly123!", username: "Mac Viewer")
    defer { try? service.signOut() }
    let uid = try XCTUnwrap(service.currentUser?.uid)
    XCTAssertEqual(service.profiles.count, 2)
    let primary = try XCTUnwrap(service.profiles.first)
    try await service.updateProfile(
      id: primary.id, name: "Updated Mac", isKid: false, avatarColor: "222226", avatarImage: nil)
    try service.signOut()
    try await service.signIn(email: email, password: "EmulatorOnly123!")
    XCTAssertEqual(service.currentUser?.uid, uid)
    XCTAssertEqual(service.profiles.first(where: { $0.id == primary.id })?.name, "Updated Mac")
  }
  func testProfileCreationAndFinalProfileProtection() async throws {
    let service = service()
    try await service.signUp(
      email: "profiles-\(UUID().uuidString)@example.test", password: "EmulatorOnly123!",
      username: "Viewer")
    defer { try? service.signOut() }
    try await service.addProfile(name: "Cinema", isKid: false)
    XCTAssertEqual(service.profiles.count, 3)
    for id in service.profiles.dropFirst().map(\.id) { try await service.deleteProfile(id: id) }
    do {
      try await service.deleteProfile(id: service.profiles[0].id)
      XCTFail("Must preserve the last profile")
    } catch { XCTAssertEqual(service.profiles.count, 1) }
  }
}
