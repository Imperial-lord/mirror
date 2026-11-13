import XCTest
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import UIKit
@testable import Mirror

/// Runs against local emulators only. Never uses the production Firebase app.
@MainActor
final class AuthProfileIntegrationTests: XCTestCase {
    private var service: AuthService!
    private var auth: Auth!
    private var db: Firestore!

    private func configureEmulator() throws {
        let options = FirebaseOptions(googleAppID: "1:123456789:ios:1234567890abcdef", gcmSenderID: "123456789")
        options.apiKey = "emulator-api-key"
        options.projectID = "demo-mirror-auth"
        let name = "Tests-\(UUID().uuidString)"
        FirebaseApp.configure(name: name, options: options)
        let app = try XCTUnwrap(FirebaseApp.app(name: name))
        auth = Auth.auth(app: app)
        auth.useEmulator(withHost: "127.0.0.1", port: 9099)
        db = Firestore.firestore(app: app)
        let settings = db.settings
        settings.host = "127.0.0.1:8080"
        settings.isSSLEnabled = false
        settings.cacheSettings = MemoryCacheSettings()
        db.settings = settings
        service = AuthService(auth: auth, db: db)
    }

    func testProfileLifecycleAndSessionRestoration() async throws {
        try configureEmulator()
        let email = "lifecycle-\(UUID().uuidString)@example.test"
        try await service.signUp(email: email, password: "TestPassword123!", username: "Jerome Bell")
        XCTAssertEqual(service.profiles.count, 2)
        let userID = try XCTUnwrap(service.currentUser?.uid)
        let primary = try XCTUnwrap(service.profiles.first { !$0.isKid })
        let kids = try XCTUnwrap(service.profiles.first { $0.isKid })
        service.selectProfile(primary)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512))
        let image = renderer.image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
        }
        let photo = try AvatarPhotoEncoder.encode(image)
        let encodedData = try XCTUnwrap(Data(base64Encoded: photo))
        let decodedPhoto = try XCTUnwrap(UIImage(data: encodedData))
        XCTAssertLessThanOrEqual(max(decodedPhoto.size.width, decodedPhoto.size.height), 384)
        XCTAssertLessThanOrEqual(encodedData.count, 200_000)
        XCTAssertThrowsError(try AvatarPhotoEncoder.encode(Data("invalid image".utf8)))
        try await service.updateProfile(id: primary.id, name: "  Updated  ", isKid: false, avatarColor: "222226", avatarImage: photo)
        XCTAssertEqual(service.currentProfile?.name, "Updated")
        XCTAssertEqual(service.currentProfile?.avatarImage, photo)
        try await service.addProfile(name: "Updated", isKid: false)
        await service.loadProfiles(for: userID)
        XCTAssertEqual(service.profiles.filter { $0.name == "Updated" }.count, 2, "Loading must preserve namesakes")
        try await service.deleteProfile(id: kids.id)
        await service.loadProfiles(for: userID)
        XCTAssertFalse(service.profiles.contains { $0.isKid }, "Deleted Kids profile must stay deleted")
        let remaining = try XCTUnwrap(service.profiles.first { $0.id != primary.id })
        try await service.deleteProfile(id: remaining.id)
        do {
            try await service.deleteProfile(id: primary.id)
            XCTFail("Last profile deletion must fail")
        } catch ProfileError.lastProfile { }
        try service.signOut()
        XCTAssertNil(service.currentProfile)
        XCTAssertTrue(service.profiles.isEmpty)
        try await service.signIn(email: email, password: "TestPassword123!")
        XCTAssertEqual(service.currentProfile?.id, primary.id)
        XCTAssertEqual(service.currentProfile?.avatarImage, photo)
        XCTAssertEqual(service.currentProfile?.avatarColor, "222226")
        XCTAssertEqual(service.profiles.count, 1)
        try await service.updateProfile(id: primary.id, name: "Updated", isKid: false, avatarColor: "222226", avatarImage: nil)
        await service.loadProfiles(for: userID)
        XCTAssertNil(service.currentProfile?.avatarImage)
    }

    func testReloadDoesNotDeleteProfilesNamedJerome() async throws {
        try configureEmulator()
        try await service.signUp(email: "jerome-\(UUID().uuidString)@example.test", password: "TestPassword123!", username: "Jerome Bell")
        let userID = try XCTUnwrap(service.currentUser?.uid)
        let id = try XCTUnwrap(service.profiles.first { $0.name == "Jerome Bell" }?.id)
        await service.loadProfiles(for: userID)
        XCTAssertTrue(service.profiles.contains { $0.id == id })
    }

    func testFailedWritesAndAccountIsolation() async throws {
        try configureEmulator()
        let email = "isolation-\(UUID().uuidString)@example.test"
        try await service.signUp(email: email, password: "TestPassword123!", username: "First")
        let firstID = try XCTUnwrap(service.currentUser?.uid)
        let firstProfile = try XCTUnwrap(service.currentProfile)
        try service.signOut()
        try await service.signUp(email: "second-\(UUID().uuidString)@example.test", password: "TestPassword123!", username: "Second")
        XCTAssertNotEqual(service.currentUser?.uid, firstID)
        XCTAssertEqual(service.currentProfile?.name, "Second")
        service.selectProfile(firstProfile)
        XCTAssertEqual(service.currentProfile?.name, "Second", "Cannot select another account's profile")
        do {
            _ = try await db.collection("users").document(firstID).collection("profiles").getDocuments()
            XCTFail("Cross-account reads must fail")
        } catch { }
        let count = service.profiles.count
        do {
            try await service.addProfile(name: " \n ", isKid: false)
            XCTFail("Whitespace-only name must fail")
        } catch ProfileError.invalidName { }
        XCTAssertEqual(service.profiles.count, count)
        let profile = try XCTUnwrap(service.currentProfile)
        let otherRef = db.collection("users").document(firstID).collection("profiles").document(profile.id)
        do {
            try await otherRef.setData(["name": "Forbidden"])
            XCTFail("Cross-account writes must fail")
        } catch { }
        XCTAssertEqual(service.currentProfile?.name, "Second")
        let userID = try XCTUnwrap(service.currentUser?.uid)
        try await db.collection("users").document(userID).collection("profiles").document(profile.id).delete()
        do {
            try await service.updateProfile(id: profile.id, name: "Should not save", isKid: true, avatarColor: "222226", avatarImage: nil)
            XCTFail("Updating a removed server document must fail")
        } catch { }
        XCTAssertEqual(service.currentProfile?.name, "Second", "Failed save must not modify local state")
    }
}
