import XCTest
@testable import AniSyncCore

final class ReconciliationTests: XCTestCase {
    func testMissingEntryBecomesCurrent() {
        let decision = Reconciler.decide(pending: pending(episode: 3), media: media(total: 12))
        XCTAssertEqual(decision, .write(DesiredWrite(progress: 3, status: .current, repeatCount: nil)))
    }

    func testKnownFinalEpisodeCompletes() {
        let decision = Reconciler.decide(pending: pending(episode: 12), media: media(total: 12))
        XCTAssertEqual(decision, .write(DesiredWrite(progress: 12, status: .completed, repeatCount: nil)))
    }

    func testUnknownTotalDoesNotComplete() {
        let decision = Reconciler.decide(pending: pending(episode: 24), media: media(total: nil))
        XCTAssertEqual(decision, .write(DesiredWrite(progress: 24, status: .current, repeatCount: nil)))
    }

    func testProgressNeverRegresses() {
        let existing = entry(status: .current, progress: 8, updatedAt: 900)
        let decision = Reconciler.decide(pending: pending(episode: 7), media: media(total: 12, entry: existing))
        XCTAssertEqual(decision, .noOp("AniList progress is already at or beyond this episode."))
    }

    func testCompletedEntryIsPreservedOutsideRewatch() {
        let existing = entry(status: .completed, progress: 12, updatedAt: 900)
        let decision = Reconciler.decide(pending: pending(episode: 4), media: media(total: 12, entry: existing))
        XCTAssertEqual(decision, .noOp("AniList already marks this title complete."))
    }

    func testNewerAniListChangeCreatesConflict() {
        let existing = entry(status: .paused, progress: 2, updatedAt: 1_100)
        let decision = Reconciler.decide(pending: pending(episode: 3), media: media(total: 12, entry: existing))
        XCTAssertEqual(decision, .conflict("AniList was changed after this episode was queued."))
    }

    func testExplicitReapplyCanAdvanceAfterConflict() {
        let existing = entry(status: .paused, progress: 2, updatedAt: 1_100)
        var item = pending(episode: 3)
        item.force = true
        let decision = Reconciler.decide(pending: item, media: media(total: 12, entry: existing))
        XCTAssertEqual(decision, .write(DesiredWrite(progress: 3, status: .current, repeatCount: nil)))
    }

    func testRewatchFinalIncrementsRepeatExactlyOnce() {
        let existing = entry(status: .repeating, progress: 11, repeatCount: 2, updatedAt: 900)
        let item = pending(episode: 12, kind: .rewatch, baselineRepeat: 2)
        let decision = Reconciler.decide(pending: item, media: media(total: 12, entry: existing))
        XCTAssertEqual(decision, .write(DesiredWrite(progress: 12, status: .completed, repeatCount: 3)))
    }

    func testCompletedRewatchDoesNotIncrementAgain() {
        let existing = entry(status: .completed, progress: 12, repeatCount: 3, updatedAt: 1_100)
        let item = pending(episode: 12, kind: .rewatch, baselineRepeat: 2)
        let decision = Reconciler.decide(pending: item, media: media(total: 12, entry: existing))
        XCTAssertEqual(decision, .noOp("This rewatch cycle is already complete."))
    }

    func testUnknownRewatchTotalRemainsRepeating() {
        let existing = entry(status: .repeating, progress: 4, repeatCount: 1, updatedAt: 900)
        let item = pending(episode: 5, kind: .rewatch, baselineRepeat: 1)
        let decision = Reconciler.decide(pending: item, media: media(total: nil, entry: existing))
        XCTAssertEqual(decision, .write(DesiredWrite(progress: 5, status: .repeating, repeatCount: nil)))
    }

    func testEpisodeBeyondKnownTotalIsRejected() {
        let decision = Reconciler.decide(pending: pending(episode: 13), media: media(total: 12))
        XCTAssertEqual(decision, .invalid("Episode 13 is beyond AniList’s known episode count of 12."))
    }

    private func pending(
        episode: Int,
        kind: SyncKind = .ordinary,
        baselineRepeat: Int? = nil
    ) -> PendingSync {
        PendingSync(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            mediaID: 1,
            seriesKey: "catalog:1",
            sourceTitle: "Example",
            episode: episode,
            kind: kind,
            cycleID: kind == .ordinary ? "ordinary" : "rewatch-1",
            createdAt: Date(timeIntervalSince1970: 1_000),
            state: .queued,
            lastError: nil,
            retryAfter: nil,
            baselineRepeat: baselineRepeat,
            force: false
        )
    }

    private func media(total: Int?, entry: AniListEntrySnapshot? = nil) -> AniListMediaSnapshot {
        AniListMediaSnapshot(id: 1, title: "Example", episodes: total, format: "TV", entry: entry)
    }

    private func entry(
        status: AniListStatus,
        progress: Int,
        repeatCount: Int = 0,
        updatedAt: Int
    ) -> AniListEntrySnapshot {
        AniListEntrySnapshot(id: 10, status: status, progress: progress, repeatCount: repeatCount, updatedAt: updatedAt)
    }
}
