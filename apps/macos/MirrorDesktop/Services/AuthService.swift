import AppKit
import AuthenticationServices
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import GoogleSignIn

public struct MirrorUserProfile: Identifiable, Codable, Hashable {
  public var id: String
  public var name: String
  public var isKid: Bool
  public var avatarColor: String
  // Small, compressed JPEG stored with the profile; no Storage bucket is required.
  public var avatarImage: String?

  public init(
    id: String = UUID().uuidString, name: String, isKid: Bool = false,
    avatarColor: String = "222226", avatarImage: String? = nil
  ) {
    self.id = id
    self.name = name
    self.isKid = isKid
    self.avatarColor = avatarColor
    self.avatarImage = avatarImage
  }
}

public enum ProfileError: LocalizedError {
  case signedOut, invalidName, lastProfile, missingProfile, invalidImage

  public var errorDescription: String? {
    switch self {
    case .signedOut: return "Please sign in again."
    case .invalidName: return "Enter a profile name between 1 and 30 characters."
    case .lastProfile: return "Keep at least one profile on your account."
    case .missingProfile: return "This profile no longer exists. Please choose another."
    case .invalidImage: return "This photo could not be loaded. Please choose another."
    }
  }
}

@MainActor
@Observable
public final class AuthService {
  public static let shared = AuthService()
  public private(set) var currentUser: User?
  public private(set) var currentProfile: MirrorUserProfile?
  public private(set) var profiles: [MirrorUserProfile] = []
  public private(set) var isLoadingProfiles = false
  public private(set) var profileError: String?
  private let auth: Auth
  private let db: Firestore
  private var isAuthenticating = false
  private var revision = 0

  init(auth: Auth = Auth.auth(), db: Firestore = Firestore.firestore()) {
    self.auth = auth
    self.db = db
    currentUser = auth.currentUser
    auth.addStateDidChangeListener { [weak self] _, user in
      Task { @MainActor in
        guard let self, !self.isAuthenticating else { return }
        // Ignore queued notifications belonging to a previous session.
        guard self.auth.currentUser?.uid == user?.uid else { return }
        if self.currentUser?.uid != user?.uid {
          self.revision += 1
          self.profiles = []
          self.currentProfile = nil
        }
        self.currentUser = user
        if let user {
          await self.loadProfiles(for: user.uid)
        } else {
          self.profiles = []
          self.currentProfile = nil
          self.profileError = nil
        }
      }
    }
  }

  public var isAuthenticated: Bool { currentUser != nil }

  public func signUp(email: String, password: String, username: String) async throws {
    isAuthenticating = true
    defer { isAuthenticating = false }
    let name = try validatedName(username)
    // A failed profile write must be retryable without creating another account.
    let user: User
    if let existing = auth.currentUser, existing.email?.lowercased() == email.lowercased() {
      user = existing
    } else {
      user = try await auth.createUser(withEmail: email, password: password).user
    }
    if currentUser?.uid != user.uid {
      profiles = []
      currentProfile = nil
    }
    currentUser = user
    let change = user.createProfileChangeRequest()
    change.displayName = name
    try await change.commitChanges()
    // Deterministic document IDs make provisioning safe to retry.
    try await fetchProfiles(for: user.uid, initialName: name)
  }

  public func signIn(email: String, password: String) async throws {
    isAuthenticating = true
    defer { isAuthenticating = false }
    let result = try await auth.signIn(withEmail: email, password: password)
    if currentUser?.uid != result.user.uid {
      profiles = []
      currentProfile = nil
    }
    currentUser = result.user
    try await fetchProfiles(for: result.user.uid)
  }

  public func signInWithGoogle() async throws -> Bool {
    guard let clientID = FirebaseApp.app()?.options.clientID else {
      throw NSError(
        domain: "GoogleSignIn", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Google sign-in needs an updated Firebase configuration. Please try again after setup."
        ])
    }
    guard let window = NSApp.keyWindow ?? NSApp.windows.first else {
      throw NSError(
        domain: "GoogleSignIn", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Open the Mirror window and try again."])
    }
    GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    let googleResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: window)
    guard let idToken = googleResult.user.idToken?.tokenString else {
      throw NSError(
        domain: "GoogleSignIn", code: 3,
        userInfo: [
          NSLocalizedDescriptionKey: "Google did not return an identity token. Please try again."
        ])
    }
    isAuthenticating = true
    defer { isAuthenticating = false }
    let credential = GoogleAuthProvider.credential(
      withIDToken: idToken, accessToken: googleResult.user.accessToken.tokenString)
    let result = try await auth.signIn(with: credential)
    if currentUser?.uid != result.user.uid {
      profiles = []
      currentProfile = nil
    }
    currentUser = result.user
    try await fetchProfiles(for: result.user.uid)
    return result.additionalUserInfo?.isNewUser ?? false
  }

  public func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?)
    async throws -> Bool
  {
    isAuthenticating = true
    defer { isAuthenticating = false }
    let credential = OAuthProvider.appleCredential(
      withIDToken: idToken, rawNonce: rawNonce, fullName: fullName)
    let result = try await auth.signIn(with: credential)
    if currentUser?.uid != result.user.uid {
      profiles = []
      currentProfile = nil
    }
    currentUser = result.user
    if let fullName {
      let name = PersonNameComponentsFormatter().string(from: fullName)
      if !name.isEmpty {
        let change = result.user.createProfileChangeRequest()
        change.displayName = name
        try await change.commitChanges()
      }
    }
    try await fetchProfiles(for: result.user.uid)
    return result.additionalUserInfo?.isNewUser ?? false
  }

  public func sendPasswordReset(email: String) async throws {
    try await auth.sendPasswordReset(
      withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  public func signOut() throws {
    try auth.signOut()
    GIDSignIn.sharedInstance.signOut()
    revision += 1
    currentUser = nil
    currentProfile = nil
    profiles = []
    profileError = nil
    isLoadingProfiles = false
    UserDefaults.standard.removeObject(forKey: "activeProfile")
  }

  public func loadProfiles(for userId: String) async {
    guard !isLoadingProfiles, !isAuthenticating else { return }
    do { try await fetchProfiles(for: userId) } catch {
      if currentUser?.uid == userId { profileError = error.localizedDescription }
    }
  }

  private func fetchProfiles(for userId: String, initialName: String? = nil) async throws {
    guard currentUser?.uid == userId else { return }
    revision += 1
    let requestRevision = revision
    isLoadingProfiles = true
    profileError = nil
    defer { if revision == requestRevision { isLoadingProfiles = false } }
    let userRef = db.collection("users").document(userId)
    let collection = userRef.collection("profiles")
    let snapshot = try await collection.getDocuments()
    guard currentUser?.uid == userId, revision == requestRevision else { return }
    var loaded = snapshot.documents.map { doc -> MirrorUserProfile in
      let data = doc.data()
      return MirrorUserProfile(
        id: doc.documentID, name: data["name"] as? String ?? "User",
        isKid: data["isKid"] as? Bool ?? false,
        avatarColor: data["avatarColor"] as? String ?? "222226",
        avatarImage: data["avatarImage"] as? String)
    }
    if loaded.isEmpty {
      let name =
        initialName ?? currentUser?.displayName ?? currentUser?.email?.components(separatedBy: "@")
        .first ?? "User"
      loaded = [
        MirrorUserProfile(id: "primary", name: name),
        MirrorUserProfile(id: "kids", name: "Kids", isKid: true),
      ]
      let batch = db.batch()
      batch.setData(
        [
          "uid": userId, "email": currentUser?.email ?? "", "displayName": name,
          "createdAt": FieldValue.serverTimestamp(),
        ], forDocument: userRef, merge: true)
      for profile in loaded {
        batch.setData(profileData(profile), forDocument: collection.document(profile.id))
      }
      try await batch.commit()
    }
    guard currentUser?.uid == userId, revision == requestRevision else { return }
    loaded.sort { lhs, rhs in
      if lhs.id == "primary" { return rhs.id != "primary" }
      if rhs.id == "primary" { return false }
      if lhs.isKid != rhs.isKid { return !lhs.isKid }
      return lhs.id < rhs.id
    }
    profiles = loaded
    let savedID = UserDefaults.standard.string(forKey: activeProfileKey(userId))
    let selected = loaded.first { $0.id == (currentProfile?.id ?? savedID) } ?? loaded.first
    if let selected { selectProfile(selected) }
  }

  public func addProfile(
    name: String, isKid: Bool, avatarColor: String = "222226", avatarImage: String? = nil
  ) async throws {
    guard let userId = currentUser?.uid else { throw ProfileError.signedOut }
    let profile = MirrorUserProfile(
      name: try validatedName(name), isKid: isKid, avatarColor: avatarColor,
      avatarImage: avatarImage)
    revision += 1
    defer { isLoadingProfiles = false }
    try await db.collection("users").document(userId).collection("profiles").document(profile.id)
      .setData(profileData(profile))
    guard currentUser?.uid == userId else { return }
    profiles.append(profile)
  }

  public func updateProfile(
    id: String, name: String, isKid: Bool, avatarColor: String, avatarImage: String?
  ) async throws {
    guard let userId = currentUser?.uid else { throw ProfileError.signedOut }
    guard var profile = profiles.first(where: { $0.id == id }) else {
      throw ProfileError.missingProfile
    }
    profile.name = try validatedName(name)
    profile.isKid = isKid
    profile.avatarColor = avatarColor
    profile.avatarImage = avatarImage
    revision += 1
    defer { isLoadingProfiles = false }
    try await db.collection("users").document(userId).collection("profiles").document(id)
      .updateData(profileData(profile))
    guard currentUser?.uid == userId, let index = profiles.firstIndex(where: { $0.id == id }) else {
      return
    }
    profiles[index] = profile
    if currentProfile?.id == id { selectProfile(profile) }
  }

  public func deleteProfile(id: String) async throws {
    guard let userId = currentUser?.uid else { throw ProfileError.signedOut }
    guard profiles.count > 1 else { throw ProfileError.lastProfile }
    guard profiles.contains(where: { $0.id == id }) else { throw ProfileError.missingProfile }
    revision += 1
    defer { isLoadingProfiles = false }
    try await db.collection("users").document(userId).collection("profiles").document(id).delete()
    guard currentUser?.uid == userId else { return }
    profiles.removeAll { $0.id == id }
    if currentProfile?.id == id, let first = profiles.first { selectProfile(first) }
  }

  public func selectProfile(_ profile: MirrorUserProfile) {
    guard let userId = currentUser?.uid, let stored = profiles.first(where: { $0.id == profile.id })
    else { return }
    currentProfile = stored
    UserDefaults.standard.set(stored.id, forKey: activeProfileKey(userId))
    UserDefaults.standard.set(stored.name, forKey: "activeProfile")
  }

  private func activeProfileKey(_ userId: String) -> String { "activeProfileID.\(userId)" }
  private func validatedName(_ name: String) throws -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...30).contains(trimmed.count) else { throw ProfileError.invalidName }
    return trimmed
  }
  private func profileData(_ profile: MirrorUserProfile) -> [String: Any] {
    [
      "id": profile.id, "name": profile.name, "isKid": profile.isKid,
      "avatarColor": profile.avatarColor, "avatarImage": profile.avatarImage as Any? ?? NSNull(),
    ]
  }
}
