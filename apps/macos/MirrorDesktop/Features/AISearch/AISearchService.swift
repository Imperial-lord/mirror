import CryptoKit
import FirebaseAuth
import Foundation
import Observation

struct AIChatMessage: Codable, Identifiable {
  var id = UUID()
  let role: String
  let content: String
  var recommendations: [AIRecommendation] = []
}
struct AIRecommendation: Codable, Identifiable {
  var id: Int { movie.id }
  let movie: Movie
  let reason: String
}
struct AISearchRequest: Encodable {
  struct Message: Encodable {
    let role: String
    let content: String
  }
  let messages: [Message]
  let previous: [Int]
  let exclude: [Int]
}
struct AISearchResponse: Decodable {
  let message: String
  let recommendations: [AIRecommendation]
}
@MainActor protocol AISearchTransport {
  func search(_ request: AISearchRequest) async throws -> AISearchResponse
}
@MainActor final class AISearchService: AISearchTransport {
  private let base: URL?
  private let session: URLSession
  private let token: () async throws -> String
  init(
    base: URL? = nil, session: URLSession = .shared,
    token: @escaping () async throws -> String = {
      guard let user = Auth.auth().currentUser else { throw Failure("Sign in to use AI search.") }
      return try await user.getIDToken()
    }
  ) {
    let configuredURL =
      (Bundle.main.object(forInfoDictionaryKey: "AISearchServiceURL") as? String)
      ?? (Bundle.main.object(forInfoDictionaryKey: "PlaybackServiceURL") as? String)
    self.base =
      base ?? configuredURL.flatMap(URL.init(string:))
    self.session = session
    self.token = token
  }
  func search(_ body: AISearchRequest) async throws -> AISearchResponse {
    guard let base, ["http", "https"].contains(base.scheme) else {
      throw Failure("AI search isn’t available yet.")
    }
    var request = URLRequest(url: base.appendingPathComponent("v1/ai/search"))
    request.httpMethod = "POST"
    request.timeoutInterval = 110
    request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
    try Task.checkCancellation()
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(body)
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse, data.count < 2 * 1024 * 1024 else {
      throw Failure("AI search couldn’t finish that request.")
    }
    if response.statusCode == 401 { throw Failure("Please sign in again to use AI search.") }
    guard response.statusCode == 200 else {
      let message = (try? JSONDecoder().decode(ServiceError.self, from: data))?.error
      throw Failure(message ?? "AI search isn’t available right now. Please try again later.")
    }
    return try JSONDecoder().decode(AISearchResponse.self, from: data)
  }
  private struct ServiceError: Decodable { let error: String }
  struct Failure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
  }
}

@MainActor @Observable final class AISearchModel {
  var draft = ""
  private(set) var messages: [AIChatMessage] = []
  private(set) var searching = false
  var error: String?
  var hideWatched = false
  private let transport: any AISearchTransport
  private let directory: URL
  private var file: URL?
  private var task: Task<Void, Never>?
  private var generation = UUID()
  init(transport: (any AISearchTransport)? = nil, directory: URL? = nil) {
    self.transport = transport ?? AISearchService()
    self.directory =
      directory
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("MirrorAIChats", isDirectory: true)
  }
  func load(scope: String?) {
    cancel()
    messages = []
    draft = ""
    error = nil
    hideWatched = false
    file = nil
    guard let scope else { return }
    let name = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
    file = directory.appendingPathComponent(name + ".json")
    guard let file, FileManager.default.fileExists(atPath: file.path) else { return }
    do {
      let data = try Data(contentsOf: file)
      guard data.count <= 2 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
      messages = Array(try JSONDecoder().decode([AIChatMessage].self, from: data).suffix(20))
      if messages.last?.role == "user" {
        error = "Your last search wasn’t completed. You can try it again."
      }
    } catch { self.error = "Couldn’t restore this chat. Start a new chat to continue." }
  }
  func send(excluding: [Int] = []) {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !searching else { return }
    guard text.count <= 1500 else {
      error = "Please keep your message under 1,500 characters."
      return
    }
    messages.append(AIChatMessage(role: "user", content: text))
    draft = ""
    messages = Array(messages.suffix(20))
    persist()
    run(excluding: excluding)
  }
  func retry(excluding: [Int] = []) {
    guard messages.last?.role == "user", !searching else { return }
    run(excluding: excluding)
  }
  func cancel() {
    generation = UUID()
    task?.cancel()
    task = nil
    searching = false
  }
  func newChat() {
    cancel()
    messages = []
    draft = ""
    error = nil
    persist()
  }
  private func run(excluding: [Int]) {
    error = nil
    searching = true
    let requestID = UUID()
    generation = requestID
    let previous =
      messages.last(where: { !$0.recommendations.isEmpty })?.recommendations.map(\.id) ?? []
    let request = AISearchRequest(
      messages: messages.suffix(8).map { .init(role: $0.role, content: $0.content) },
      previous: previous, exclude: hideWatched ? Array(excluding.prefix(500)) : [])
    task = Task {
      do {
        let response = try await transport.search(request)
        guard !Task.isCancelled, generation == requestID else { return }
        messages.append(
          AIChatMessage(
            role: "assistant", content: response.message, recommendations: response.recommendations)
        )
        messages = Array(messages.suffix(20))
        searching = false
        persist()
      } catch {
        guard !Task.isCancelled, generation == requestID else { return }
        searching = false
        self.error =
          (error as? AISearchService.Failure)?.message
          ?? "Couldn’t finish your search. Check your connection and try again."
      }
    }
  }
  private func persist() {
    guard let file else { return }
    do {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      var root = directory
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try root.setResourceValues(values)
      try JSONEncoder().encode(messages).write(to: file, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    } catch { self.error = "Couldn’t save this chat on your Mac." }
  }
}
