import Foundation
import XCTest
@testable import AniSyncCore

final class ServiceTests: XCTestCase {
    func testDisconnectedPlaybackIsKeptForReconnect() async {
        let environment = makeEnvironment(token: nil)
        let state = await environment.service.qualifyPlayback(
            mediaID: 1, seriesKey: "catalog:1", sourceTitle: "Example", episode: 3
        )
        XCTAssertEqual(state.pending.count, 1)
        XCTAssertEqual(state.pending.first?.state, .reconnect)
        XCTAssertFalse(state.connected)
    }

    func testOrdinaryPlaybackWritesAndClearsPending() async {
        let environment = makeEnvironment()
        let state = await environment.service.qualifyPlayback(
            mediaID: 1, seriesKey: "catalog:1", sourceTitle: "Example", episode: 3
        )
        XCTAssertTrue(state.pending.isEmpty)
        XCTAssertEqual(state.activity.first?.after?.progress, 3)
        XCTAssertEqual(state.activity.first?.after?.status, .current)
        let saveCount = await environment.api.saveCount()
        XCTAssertEqual(saveCount, 1)
    }

    func testTemporaryFailureSurvivesAndRetries() async {
        let environment = makeEnvironment()
        await environment.api.failNextMedia(with: .temporary("Offline"))
        var state = await environment.service.qualifyPlayback(
            mediaID: 1, seriesKey: "catalog:1", sourceTitle: "Example", episode: 4
        )
        XCTAssertEqual(state.pending.first?.state, .retrying)

        await environment.service.retryPending()
        state = await environment.service.state()
        XCTAssertTrue(state.pending.isEmpty)
        XCTAssertEqual(state.activity.first?.episode, 4)
    }

    func testRateLimitRetryAfterIsHonored() async {
        let environment = makeEnvironment()
        await environment.api.failNextMedia(with: .rateLimited(120))
        _ = await environment.service.qualifyPlayback(
            mediaID: 1, seriesKey: "catalog:1", sourceTitle: "Example", episode: 4
        )
        await environment.service.retryPending()
        var state = await environment.service.state()
        XCTAssertEqual(state.pending.count, 1)

        environment.store.update { stored in
            stored.pending[0].retryAfter = Date.distantPast
        }
        await environment.service.retryPending()
        state = await environment.service.state()
        XCTAssertTrue(state.pending.isEmpty)
    }

    func testAwaitingMappingReconcilesImmediatelyAfterConfirmation() async {
        let environment = makeEnvironment()
        var state = await environment.service.qualifyPlayback(
            mediaID: nil, seriesKey: "catalog:77", sourceTitle: "Source Name", episode: 2
        )
        XCTAssertEqual(state.pending.first?.state, .awaitingMapping)

        await environment.service.confirmMapping(
            seriesKey: "catalog:77", sourceTitle: "Source Name", mediaID: 1, aniListTitle: "Example"
        )
        state = await environment.service.state()
        XCTAssertTrue(state.pending.isEmpty)
        XCTAssertEqual(state.mappings.first?.mediaID, 1)
        XCTAssertEqual(state.activity.first?.episode, 2)
    }

    func testOrdinaryPendingWorkCoalescesToHighestEpisode() async {
        let environment = makeEnvironment()
        await environment.api.failNextMedia(with: .temporary("Offline"))
        _ = await environment.service.qualifyPlayback(
            mediaID: 1, seriesKey: "catalog:1", sourceTitle: "Example", episode: 3
        )
        await environment.api.failNextMedia(with: .temporary("Offline"))
        let state = await environment.service.qualifyPlayback(
            mediaID: 1, seriesKey: "catalog:1", sourceTitle: "Example", episode: 5
        )
        XCTAssertEqual(state.pending.count, 1)
        XCTAssertEqual(state.pending.first?.episode, 5)
    }

    func testRewatchCompletionIncrementsOnlyOnce() async {
        let entry = AniListEntrySnapshot(id: 9, status: .repeating, progress: 11, repeatCount: 2, updatedAt: 100)
        let environment = makeEnvironment(entry: entry)
        _ = await environment.service.qualifyPlayback(
            mediaID: 1, seriesKey: "catalog:1", sourceTitle: "Example", episode: 12
        )
        _ = await environment.service.qualifyPlayback(
            mediaID: 1, seriesKey: "catalog:1", sourceTitle: "Example", episode: 12
        )
        let media = try? await environment.api.media(id: 1, token: "token")
        XCTAssertEqual(media?.entry?.repeatCount, 3)
        XCTAssertEqual(media?.entry?.status, .completed)
        let saveCount = await environment.api.saveCount()
        XCTAssertEqual(saveCount, 1)
    }

    func testUndoDeletesEntryCreatedByAniSyncWhenStillUnchanged() async throws {
        let environment = makeEnvironment()
        let synced = await environment.service.qualifyPlayback(
            mediaID: 1, seriesKey: "catalog:1", sourceTitle: "Example", episode: 3
        )
        let activity = try XCTUnwrap(synced.activity.first)
        try await environment.service.undoActivity(id: activity.id)
        let state = await environment.service.state()
        XCTAssertNotNil(state.activity.first?.undoneAt)
        let deleteCount = await environment.api.deleteCount()
        XCTAssertEqual(deleteCount, 1)
    }

    private func makeEnvironment(
        token: String? = "token",
        entry: AniListEntrySnapshot? = nil
    ) -> (service: AniSyncService, api: FakeAniListAPI, store: AniSyncStateStore) {
        let suite = "me.heeka.anisync.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = AniSyncStateStore(defaults: defaults)
        let tokenStore = InMemoryTokenStore(token: token)
        let api = FakeAniListAPI(entry: entry)
        return (AniSyncService(store: store, tokenStore: tokenStore, api: api), api, store)
    }
}

private final class InMemoryTokenStore: AniListTokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    init(token: String?) { self.token = token }
    func read() -> String? { lock.withLock { token } }
    func save(_ token: String) { lock.withLock { self.token = token } }
    func delete() { lock.withLock { token = nil } }
}

private actor FakeAniListAPI: AniListAPI {
    private var snapshot: AniListMediaSnapshot
    private var nextMediaError: AniSyncError?
    private var saves = 0
    private var deletes = 0

    init(entry: AniListEntrySnapshot?) {
        snapshot = AniListMediaSnapshot(id: 1, title: "Example", episodes: 12, format: "TV", entry: entry)
    }

    func viewer(token: String) async throws -> AniListAccount {
        AniListAccount(id: 1, name: "viewer", avatarURL: nil, tokenExpiresAt: nil)
    }

    func media(id: Int, token: String) async throws -> AniListMediaSnapshot {
        if let error = nextMediaError {
            nextMediaError = nil
            throw error
        }
        return snapshot
    }

    func save(mediaID: Int, write: DesiredWrite, token: String) async throws -> AniListEntrySnapshot {
        saves += 1
        let previous = snapshot.entry
        let entry = AniListEntrySnapshot(
            id: previous?.id ?? 9,
            status: write.status,
            progress: write.progress,
            repeatCount: write.repeatCount ?? previous?.repeatCount ?? 0,
            updatedAt: max(previous?.updatedAt ?? 0, Int(Date().timeIntervalSince1970))
        )
        snapshot = AniListMediaSnapshot(
            id: snapshot.id, title: snapshot.title, episodes: snapshot.episodes,
            format: snapshot.format, entry: entry
        )
        return entry
    }

    func delete(listEntryID: Int, token: String) async throws {
        deletes += 1
        snapshot = AniListMediaSnapshot(
            id: snapshot.id, title: snapshot.title, episodes: snapshot.episodes,
            format: snapshot.format, entry: nil
        )
    }

    func search(_ query: String, token: String?) async throws -> [MediaSearchResult] { [] }

    func failNextMedia(with error: AniSyncError) { nextMediaError = error }
    func saveCount() -> Int { saves }
    func deleteCount() -> Int { deletes }
}
