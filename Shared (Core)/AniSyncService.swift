import Foundation

actor AniSyncService {
    private let store: AniSyncStateStore
    private let tokenStore: any AniListTokenStoring
    private let api: any AniListAPI
    private var processingMediaIDs: Set<Int> = []

    init(
        store: AniSyncStateStore = AniSyncStateStore(),
        tokenStore: any AniListTokenStoring = AniListTokenStore(),
        api: any AniListAPI = HTTPAniListAPI()
    ) {
        self.store = store
        self.tokenStore = tokenStore
        self.api = api
    }

    func state() -> NativeState {
        NativeState(stored: store.read(), connected: tokenStore.read() != nil)
    }

    func connect(token: String, expiresAt: Date?) async throws {
        var account = try await api.viewer(token: token)
        account.tokenExpiresAt = expiresAt
        try tokenStore.save(token)
        store.update { state in
            state.account = account
            for index in state.pending.indices where state.pending[index].state == .reconnect {
                state.pending[index].state = .queued
                state.pending[index].lastError = nil
                state.pending[index].retryAfter = nil
            }
        }
        await retryPending()
    }

    func disconnect() {
        tokenStore.delete()
        store.update { state in
            state.account = nil
            state.pending.removeAll()
            state.activity.removeAll()
            state.conflicts.removeAll()
            state.rewatchCycles.removeAll()
            state.completedKeys.removeAll()
        }
    }

    @discardableResult
    func qualifyPlayback(
        mediaID directMediaID: Int?,
        seriesKey: String,
        sourceTitle: String,
        episode: Int
    ) async -> NativeState {
        guard episode > 0, !seriesKey.isEmpty else { return state() }

        var pendingID: UUID?
        store.update { state in
            let mappedID = state.mappings.first { $0.seriesKey == seriesKey }?.mediaID
            let mediaID = directMediaID.flatMap { $0 > 0 ? $0 : nil } ?? mappedID
            let activeCycle = mediaID.flatMap { id in
                state.rewatchCycles.first { $0.mediaID == id && $0.completedAt == nil }
            }
            let kind: SyncKind = activeCycle == nil ? .ordinary : .rewatch
            let cycleID = activeCycle?.cycleID ?? "ordinary"
            let logicalKey = mediaID.map { "\($0):\(episode):\(cycleID)" }

            if let logicalKey,
               state.completedKeys.contains(logicalKey) || state.pending.contains(where: { $0.logicalKey == logicalKey }) {
                return
            }

            if kind == .ordinary,
               let index = state.pending.firstIndex(where: {
                   $0.kind == .ordinary &&
                   (($0.mediaID != nil && $0.mediaID == mediaID) || ($0.mediaID == nil && $0.seriesKey == seriesKey))
               }) {
                if state.pending[index].episode >= episode {
                    pendingID = state.pending[index].id
                    return
                }
                state.pending.remove(at: index)
            }

            let pending = PendingSync(
                id: UUID(),
                mediaID: mediaID,
                seriesKey: seriesKey,
                sourceTitle: sourceTitle,
                episode: episode,
                kind: kind,
                cycleID: cycleID,
                createdAt: Date(),
                state: mediaID == nil ? .awaitingMapping : .queued,
                lastError: nil,
                retryAfter: nil,
                baselineRepeat: activeCycle?.baselineRepeat,
                force: false
            )
            state.pending.append(pending)
            pendingID = pending.id
        }

        if let pendingID {
            await processPending(id: pendingID)
        }
        return state()
    }

    func searchMedia(_ query: String) async throws -> [MediaSearchResult] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 2 else { return [] }
        return try await api.search(clean, token: tokenStore.read())
    }

    func confirmMapping(
        seriesKey: String,
        sourceTitle: String,
        mediaID: Int,
        aniListTitle: String
    ) async {
        var pendingIDs: [UUID] = []
        store.update { state in
            state.mappings.removeAll { $0.seriesKey == seriesKey }
            state.mappings.append(SeriesMapping(
                seriesKey: seriesKey,
                sourceTitle: sourceTitle,
                mediaID: mediaID,
                aniListTitle: aniListTitle,
                createdAt: Date()
            ))
            for index in state.pending.indices where state.pending[index].seriesKey == seriesKey {
                state.pending[index].mediaID = mediaID
                state.pending[index].state = .queued
                state.pending[index].retryAfter = nil
                pendingIDs.append(state.pending[index].id)
            }
        }
        for id in pendingIDs {
            await processPending(id: id)
        }
    }

    func startRewatch(mediaID: Int) async throws {
        guard let token = tokenStore.read() else { throw AniSyncError.unauthorized }
        let media = try await api.media(id: mediaID, token: token)
        let baseline = media.entry?.repeatCount ?? 0
        if media.entry?.status != .repeating {
            _ = try await api.save(
                mediaID: mediaID,
                write: DesiredWrite(progress: 0, status: .repeating, repeatCount: nil),
                token: token
            )
        }
        store.update { state in
            state.rewatchCycles.removeAll { $0.mediaID == mediaID && $0.completedAt == nil }
            state.rewatchCycles.append(RewatchCycle(
                mediaID: mediaID,
                cycleID: UUID().uuidString,
                startedAt: Date(),
                baselineRepeat: baseline,
                completedAt: nil
            ))
        }
    }

    func retryPending() async {
        let ids = store.read().pending
            .filter {
                $0.mediaID != nil &&
                $0.state != .awaitingMapping &&
                ($0.retryAfter == nil || $0.retryAfter! <= Date())
            }
            .prefix(10)
            .map(\.id)
        for id in ids {
            await processPending(id: id)
        }
    }

    func clearActivity() {
        store.update { $0.activity.removeAll() }
    }

    func resetMappings() {
        store.update { $0.mappings.removeAll() }
    }

    func dismissConflict(id: UUID) {
        store.update { $0.conflicts.removeAll { $0.id == id } }
    }

    func reapplyConflict(id: UUID) async {
        var pendingID: UUID?
        store.update { state in
            guard let index = state.conflicts.firstIndex(where: { $0.id == id }) else { return }
            var pending = state.conflicts[index].pending
            pending.id = UUID()
            pending.createdAt = Date()
            pending.state = .queued
            pending.lastError = nil
            pending.retryAfter = nil
            pending.force = true
            state.conflicts.remove(at: index)
            state.pending.append(pending)
            pendingID = pending.id
        }
        if let pendingID { await processPending(id: pendingID) }
    }

    func undoActivity(id: UUID) async throws {
        let currentState = store.read()
        guard let activity = currentState.activity.first(where: { $0.id == id }),
              activity.canAttemptUndo,
              let expected = activity.after,
              let token = tokenStore.read() else { throw AniSyncError.unsafeUndo }

        let media = try await api.media(id: activity.mediaID, token: token)
        guard media.entry == expected else { throw AniSyncError.unsafeUndo }

        if let before = activity.before {
            _ = try await api.save(
                mediaID: activity.mediaID,
                write: DesiredWrite(
                    progress: before.progress,
                    status: before.status,
                    repeatCount: before.repeatCount
                ),
                token: token
            )
        } else {
            try await api.delete(listEntryID: expected.id, token: token)
        }

        store.update { state in
            guard let index = state.activity.firstIndex(where: { $0.id == id }) else { return }
            state.activity[index].undoneAt = Date()
            state.completedKeys.removeAll { $0 == activity.logicalKey }
        }
    }

    func handleNativeMessage(_ message: [String: Any]) async -> [String: Any] {
        do {
            guard let command = message["command"] as? String else {
                throw AniSyncError.invalidMessage("The extension sent a message without a command.")
            }
            switch command {
            case "getState":
                return success(state: state())
            case "retryPending":
                await retryPending()
                return success(state: state())
            case "qualifyPlayback":
                guard let seriesKey = message["seriesKey"] as? String,
                      let sourceTitle = message["sourceTitle"] as? String,
                      let episode = integer(message["episode"]) else {
                    throw AniSyncError.invalidMessage("The qualified episode was incomplete.")
                }
                let result = await qualifyPlayback(
                    mediaID: integer(message["mediaID"]),
                    seriesKey: seriesKey,
                    sourceTitle: sourceTitle,
                    episode: episode
                )
                return success(state: result)
            case "searchMedia":
                guard let query = message["query"] as? String else {
                    throw AniSyncError.invalidMessage("Enter a title to search AniList.")
                }
                return ["ok": true, "results": NativeMessageCodec.dictionary(SearchEnvelope(results: try await searchMedia(query)))["results"] ?? []]
            case "confirmMapping":
                guard let seriesKey = message["seriesKey"] as? String,
                      let sourceTitle = message["sourceTitle"] as? String,
                      let mediaID = integer(message["mediaID"]),
                      let title = message["aniListTitle"] as? String else {
                    throw AniSyncError.invalidMessage("The selected title was incomplete.")
                }
                await confirmMapping(seriesKey: seriesKey, sourceTitle: sourceTitle, mediaID: mediaID, aniListTitle: title)
                return success(state: state())
            case "startRewatch":
                guard let mediaID = integer(message["mediaID"]) else {
                    throw AniSyncError.invalidMessage("Open a mapped anime before starting a rewatch.")
                }
                try await startRewatch(mediaID: mediaID)
                return success(state: state())
            case "clearActivity":
                clearActivity()
                return success(state: state())
            case "resetMappings":
                resetMappings()
                return success(state: state())
            case "disconnect":
                disconnect()
                return success(state: state())
            case "dismissConflict":
                guard let raw = message["id"] as? String, let id = UUID(uuidString: raw) else {
                    throw AniSyncError.invalidMessage("The conflict identifier was invalid.")
                }
                dismissConflict(id: id)
                return success(state: state())
            case "reapplyConflict":
                guard let raw = message["id"] as? String, let id = UUID(uuidString: raw) else {
                    throw AniSyncError.invalidMessage("The conflict identifier was invalid.")
                }
                await reapplyConflict(id: id)
                return success(state: state())
            case "undoActivity":
                guard let raw = message["id"] as? String, let id = UUID(uuidString: raw) else {
                    throw AniSyncError.invalidMessage("The activity identifier was invalid.")
                }
                try await undoActivity(id: id)
                return success(state: state())
            default:
                throw AniSyncError.invalidMessage("AniSync does not recognize the command “\(command)”.")
            }
        } catch {
            return ["ok": false, "error": error.localizedDescription, "state": NativeMessageCodec.dictionary(state())]
        }
    }

    private func processPending(id: UUID) async {
        guard let item = store.read().pending.first(where: { $0.id == id }),
              let mediaID = item.mediaID else { return }
        guard processingMediaIDs.insert(mediaID).inserted else { return }
        await performPending(id: id)
        processingMediaIDs.remove(mediaID)

        if let next = store.read().pending.first(where: {
            $0.id != id && $0.mediaID == mediaID && $0.state == .queued
        }) {
            await processPending(id: next.id)
        }
    }

    private func performPending(id: UUID) async {
        guard var pending = store.read().pending.first(where: { $0.id == id }),
              let mediaID = pending.mediaID else { return }
        guard let token = tokenStore.read() else {
            mark(id: id, state: .reconnect, error: "Connect AniList to finish this saved sync.")
            return
        }

        do {
            var media = try await api.media(id: mediaID, token: token)
            if pending.kind == .ordinary,
               media.entry?.status == .repeating || activeCycle(mediaID: mediaID) != nil {
                pending = promoteToRewatch(pending, media: media)
                store.update { state in
                    guard let index = state.pending.firstIndex(where: { $0.id == id }) else { return }
                    state.pending[index] = pending
                }
            }

            let decision = Reconciler.decide(pending: pending, media: media)
            switch decision {
            case .noOp:
                finish(pending: pending, title: media.title, before: media.entry, after: media.entry, outcome: .alreadyUpToDate)
            case .write(let desired):
                let before = media.entry
                let after = try await api.save(mediaID: mediaID, write: desired, token: token)
                media = AniListMediaSnapshot(id: media.id, title: media.title, episodes: media.episodes, format: media.format, entry: after)
                finish(pending: pending, title: media.title, before: before, after: after, outcome: .synced)
                if pending.kind == .rewatch,
                   media.episodes == pending.episode,
                   after.status == .completed {
                    store.update { state in
                        if let index = state.rewatchCycles.firstIndex(where: { $0.cycleID == pending.cycleID }) {
                            state.rewatchCycles[index].completedAt = Date()
                        }
                    }
                }
            case .conflict(let reason):
                store.update { state in
                    state.pending.removeAll { $0.id == id }
                    state.conflicts.append(SyncConflict(
                        id: UUID(),
                        pending: pending,
                        current: media.entry,
                        reason: reason,
                        detectedAt: Date()
                    ))
                }
            case .invalid(let reason):
                store.update { state in
                    state.pending.removeAll { $0.id == id }
                    state.conflicts.append(SyncConflict(
                        id: UUID(),
                        pending: pending,
                        current: media.entry,
                        reason: reason,
                        detectedAt: Date()
                    ))
                }
            }
        } catch AniSyncError.unauthorized {
            tokenStore.delete()
            mark(id: id, state: .reconnect, error: AniSyncError.unauthorized.localizedDescription)
        } catch AniSyncError.rateLimited(let seconds) {
            mark(
                id: id,
                state: .retrying,
                error: AniSyncError.rateLimited(seconds).localizedDescription,
                retryAfter: Date().addingTimeInterval(TimeInterval(seconds ?? 60))
            )
        } catch {
            mark(id: id, state: .retrying, error: error.localizedDescription)
        }
    }

    private func promoteToRewatch(_ pending: PendingSync, media: AniListMediaSnapshot) -> PendingSync {
        var pending = pending
        let cycle: RewatchCycle
        if let active = activeCycle(mediaID: media.id) {
            cycle = active
        } else {
            cycle = RewatchCycle(
                mediaID: media.id,
                cycleID: UUID().uuidString,
                startedAt: Date(),
                baselineRepeat: media.entry?.repeatCount ?? 0,
                completedAt: nil
            )
            store.update { $0.rewatchCycles.append(cycle) }
        }
        pending.kind = .rewatch
        pending.cycleID = cycle.cycleID
        pending.baselineRepeat = cycle.baselineRepeat
        return pending
    }

    private func activeCycle(mediaID: Int) -> RewatchCycle? {
        store.read().rewatchCycles.first { $0.mediaID == mediaID && $0.completedAt == nil }
    }

    private func finish(
        pending: PendingSync,
        title: String,
        before: AniListEntrySnapshot?,
        after: AniListEntrySnapshot?,
        outcome: ActivityOutcome
    ) {
        guard let mediaID = pending.mediaID, let logicalKey = pending.logicalKey else { return }
        store.update { state in
            state.pending.removeAll { $0.id == pending.id }
            if !state.completedKeys.contains(logicalKey) { state.completedKeys.append(logicalKey) }
            state.activity.append(SyncActivity(
                id: UUID(),
                logicalKey: logicalKey,
                mediaID: mediaID,
                title: title,
                episode: pending.episode,
                kind: pending.kind,
                outcome: outcome,
                occurredAt: Date(),
                before: before,
                after: after,
                undoneAt: nil
            ))
        }
    }

    private func mark(
        id: UUID,
        state pendingState: PendingState,
        error: String,
        retryAfter: Date? = nil
    ) {
        store.update { state in
            guard let index = state.pending.firstIndex(where: { $0.id == id }) else { return }
            state.pending[index].state = pendingState
            state.pending[index].lastError = error
            state.pending[index].retryAfter = retryAfter
        }
    }

    private func success(state: NativeState) -> [String: Any] {
        ["ok": true, "state": NativeMessageCodec.dictionary(state)]
    }

    private func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }
}

private struct SearchEnvelope: Codable {
    let results: [MediaSearchResult]
}
