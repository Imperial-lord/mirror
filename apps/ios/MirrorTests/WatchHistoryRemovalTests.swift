import FirebaseFirestore
import SwiftData
import XCTest

@testable import Mirror

@MainActor final class WatchHistoryRemovalTests: XCTestCase {
  private func container() throws -> ModelContainer {
    try ModelContainer(
      for: WatchHistoryItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
  }
  private func item(_ id: Int, user: String = "viewer", progress: Double = 60) -> WatchHistoryItem {
    WatchHistoryItem(
      movieId: id, title: "Movie", posterURL: nil, runtime: 10, progressSeconds: progress,
      lastWatched: Date(timeIntervalSince1970: 10), userId: user)
  }
  func testRemovalDeletesContinuingAndWatchedWithoutTouchingAnotherAccount() async throws {
    let db = try container()
    let context = db.mainContext
    for value in [item(1), item(2, progress: 590), item(1, user: "other"), item(3)] {
      context.insert(value)
    }
    try context.save()
    var remote: [Int] = []
    var offline: [Int] = []
    for id in [1, 2] {
      try await WatchHistorySync.remove(
        movieId: id, userId: "viewer", context: context,
        deleteRemote: { id, user in
          XCTAssertEqual(user, "viewer")
          remote.append(id)
        },
        resetOffline: { id, user in
          XCTAssertEqual(user, "viewer")
          offline.append(id)
        })
    }
    let rows = try ModelContext(db).fetch(FetchDescriptor<WatchHistoryItem>())
    XCTAssertEqual(Set(rows.filter { $0.userId == "viewer" }.map(\.movieId)), [3])
    XCTAssertEqual(rows.filter { $0.userId == "other" }.map(\.movieId), [1])
    XCTAssertEqual(remote, [1, 2])
    XCTAssertEqual(offline, [1, 2])
  }
  func testCloudFailureKeepsLocalHistoryAndOfflineCheckpointForRetry() async throws {
    let db = try container()
    let context = db.mainContext
    context.insert(item(1))
    try context.save()
    var reset = false
    do {
      try await WatchHistorySync.remove(
        movieId: 1, userId: "viewer", context: context,
        deleteRemote: { _, _ in throw URLError(.notConnectedToInternet) },
        resetOffline: { _, _ in reset = true })
      XCTFail("Must report the failed deletion")
    } catch {}
    XCTAssertFalse(reset)
    XCTAssertEqual(try context.fetch(FetchDescriptor<WatchHistoryItem>()).count, 1)
  }
  func testStorageFailureKeepsRowSoUserCanRetryCleanupAfterCloudDeletion() async throws {
    let db = try container()
    let context = db.mainContext
    context.insert(item(1))
    try context.save()
    do {
      try await WatchHistorySync.remove(
        movieId: 1, userId: "viewer", context: context,
        deleteRemote: { _, _ in }, resetOffline: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
      XCTFail("Must report the incomplete cleanup")
    } catch {}
    XCTAssertEqual(try context.fetch(FetchDescriptor<WatchHistoryItem>()).count, 1)
  }
  func testServerDeletionPrunesOnlyMissingOwnedRowsAndPreservesInFlightPlayback() throws {
    let db = try container()
    let context = db.mainContext
    let current = item(3)
    current.lastWatched = Date(timeIntervalSince1970: 30)
    for row in [item(1), item(2), current, item(1, user: "other")] { context.insert(row) }
    try context.save()
    var reset: [Int] = []
    try WatchHistorySync.pruneMissing(
      rows: [["movieId": 2]], userId: "viewer",
      before: Date(timeIntervalSince1970: 20), context: context,
      resetOffline: { id, _ in reset.append(id) })
    XCTAssertEqual(reset, [1])
    let remaining = try context.fetch(FetchDescriptor<WatchHistoryItem>())
    XCTAssertEqual(Set(remaining.filter { $0.userId == "viewer" }.map(\.movieId)), [2, 3])
    XCTAssertEqual(remaining.filter { $0.userId == "other" }.count, 1)
  }
  func testInFlightRefreshCannotRestoreARecordRemovedWhileItWasLoading() async throws {
    let db = try container()
    let context = db.mainContext
    context.insert(item(1))
    try context.save()
    let gate = SnapshotGate()
    let refresh = Task {
      await WatchHistorySync.sync(
        context: context, account: { "viewer" }, fetchHistory: { _ in try await gate.fetch() })
    }
    while gate.continuation == nil { await Task.yield() }
    try await WatchHistorySync.remove(
      movieId: 1, userId: "viewer", context: context,
      deleteRemote: { _, _ in }, resetOffline: { _, _ in })
    gate.continuation?.resume(
      returning: (
        rows: [
          [
            "movieId": 1, "title": "Stale", "positionSeconds": 60.0,
            "durationSeconds": 600.0, "updatedAt": Timestamp(date: Date()),
          ]
        ], authoritative: true
      ))
    let error = await refresh.value
    XCTAssertNil(error)
    XCTAssertTrue(try context.fetch(FetchDescriptor<WatchHistoryItem>()).isEmpty)
  }
  func testNonAuthoritativeSnapshotDoesNotEraseCachedHistory() async throws {
    let db = try container(), context = db.mainContext
    let cached = item(1)
    cached.year = 2020
    cached.metadataLoaded = true
    context.insert(cached)
    try context.save()
    let error = await WatchHistorySync.sync(context: context, account: { "viewer" },
      fetchHistory: { _ in (rows: [], authoritative: false) })
    XCTAssertNil(error)
    XCTAssertEqual(try context.fetch(FetchDescriptor<WatchHistoryItem>()).count, 1)
  }
  func testAccountSwitchWhileRefreshingDoesNotApplyTheOldSnapshot() async throws {
    let db = try container(), context = db.mainContext
    context.insert(item(1))
    try context.save()
    var account = "viewer"
    let gate = SnapshotGate()
    let refresh = Task {
      await WatchHistorySync.sync(context: context, account: { account }, fetchHistory: { _ in try await gate.fetch() })
    }
    while gate.continuation == nil { await Task.yield() }
    account = "other"
    gate.continuation?.resume(returning: (rows: [], authoritative: true))
    let error = await refresh.value
    XCTAssertNil(error)
    XCTAssertEqual(try context.fetch(FetchDescriptor<WatchHistoryItem>()).count, 1)
  }
}
@MainActor private final class SnapshotGate {
  var continuation: CheckedContinuation<(rows: [[String: Any]], authoritative: Bool), Error>?
  func fetch() async throws -> (rows: [[String: Any]], authoritative: Bool) {
    try await withCheckedThrowingContinuation { continuation = $0 }
  }
}
