import XCTest

@testable import MirrorDesktop

@MainActor final class AISearchTests: XCTestCase {
  private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }
  private func response() throws -> AISearchResponse {
    let movie = try JSONDecoder().decode(
      Movie.self,
      from: Data(
        #"{"id":1,"url":"https://yts.gg/movies/fixture","imdb_code":"tt0000001","title":"A catalogue movie","year":2019,"rating":8,"runtime":95,"genres":["Sci-Fi"]}"#
          .utf8))
    return AISearchResponse(
      message: "Try this movie.",
      recommendations: [.init(movie: movie, reason: "A thoughtful science fiction story.")])
  }
  private func until(_ predicate: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(5)
    while !predicate() {
      if Date() > deadline {
        XCTFail("Timed out")
        throw URLError(.timedOut)
      }
      try await Task.sleep(for: .milliseconds(10))
    }
  }
  func testConversationFollowupsWatchedExclusionsAndLocalProfileIsolation() async throws {
    let transport = FixtureAITransport(response: try response())
    let root = try folder()
    let model = AISearchModel(transport: transport, directory: root)
    model.load(scope: "user.profile-one")
    model.hideWatched = true
    model.draft = "Something thoughtful"
    model.send(excluding: [42])
    try await until { !model.searching }
    XCTAssertEqual(model.messages.count, 2)
    XCTAssertEqual(model.messages.last?.recommendations.first?.id, 1)
    model.draft = "More like the first one, but shorter"
    model.send(excluding: [42])
    try await until { !model.searching }
    XCTAssertEqual(transport.requests.last?.previous, [1])
    XCTAssertEqual(transport.requests.last?.exclude, [42])
    XCTAssertEqual(transport.requests.last?.messages.count, 3)
    let restored = AISearchModel(transport: transport, directory: root)
    restored.load(scope: "user.profile-one")
    XCTAssertEqual(restored.messages.count, 4)
    restored.load(scope: "user.profile-two")
    XCTAssertTrue(restored.messages.isEmpty)
    restored.load(scope: nil)
    XCTAssertTrue(restored.messages.isEmpty)
    let file = try XCTUnwrap(
      FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first)
    XCTAssertEqual(
      (try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?
        .intValue, 0o600)
  }
  func testFailureRetainsPromptAndRetryDoesNotDuplicateIt() async throws {
    let transport = FixtureAITransport(response: try response())
    transport.fail = true
    let model = AISearchModel(transport: transport, directory: try folder())
    model.load(scope: "retry")
    model.draft = "A funny movie"
    model.send()
    try await until { !model.searching }
    XCTAssertEqual(model.messages.count, 1)
    XCTAssertNotNil(model.error)
    transport.fail = false
    model.retry()
    try await until { !model.searching }
    XCTAssertEqual(model.messages.count, 2)
    XCTAssertNil(model.error)
  }
  func testNewChatDiscardsAnOldResponseEvenIfTransportIgnoresCancellation() async throws {
    let transport = FixtureAITransport(response: try response())
    transport.delay = true
    let model = AISearchModel(transport: transport, directory: try folder())
    model.load(scope: "cancel")
    model.draft = "A thriller"
    model.send()
    try await until { transport.continuation != nil }
    model.newChat()
    transport.continuation?.resume()
    transport.continuation = nil
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertTrue(model.messages.isEmpty)
    XCTAssertFalse(model.searching)
  }
  func testTransportAuthenticatesAndSurfacesQuotaWithoutInventedResults() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [AISearchURLProtocol.self]
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    AISearchURLProtocol.set(status: 429, body: Data(#"{"error":"Free usage limit reached."}"#.utf8))
    let service = AISearchService(
      base: URL(string: "https://fixture.example"), session: session, token: { "fixture-token" })
    do {
      _ = try await service.search(
        .init(messages: [.init(role: "user", content: "A comedy")], previous: [], exclude: []))
      XCTFail("Must surface quota failure")
    } catch { XCTAssertEqual(error.localizedDescription, "Free usage limit reached.") }
    XCTAssertEqual(
      AISearchURLProtocol.lastRequest()?.value(forHTTPHeaderField: "Authorization"),
      "Bearer fixture-token")
    XCTAssertEqual(AISearchURLProtocol.lastRequest()?.url?.path, "/v1/ai/search")
  }
}
@MainActor private final class FixtureAITransport: AISearchTransport {
  let response: AISearchResponse
  var requests: [AISearchRequest] = []
  var fail = false
  var delay = false
  var continuation: CheckedContinuation<Void, Never>?
  init(response: AISearchResponse) { self.response = response }
  func search(_ request: AISearchRequest) async throws -> AISearchResponse {
    requests.append(request)
    if delay { await withCheckedContinuation { continuation = $0 } }
    if fail { throw AISearchService.Failure("Try again later.") }
    return response
  }
}
private final class AISearchURLProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  private static var status = 200
  private static var body = Data()
  private static var captured: URLRequest?
  static func set(status: Int, body: Data) {
    lock.lock()
    defer { lock.unlock() }
    self.status = status
    self.body = body
    captured = nil
  }
  static func lastRequest() -> URLRequest? {
    lock.lock()
    defer { lock.unlock() }
    return captured
  }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.lock.lock()
    let status = Self.status
    let body = Self.body
    Self.captured = request
    Self.lock.unlock()
    client?.urlProtocol(
      self,
      didReceive: HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil,
        headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
