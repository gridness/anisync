import Foundation

enum AniSyncConstants {
    static let appGroup = "group.me.heeka.anisync"
    static let keychainService = "me.heeka.anisync.anilist"
    static let keychainAccount = "access-token"
    static let keychainAccessGroupSuffix = "me.heeka.anisync.shared"
    static let extensionBundleIdentifier = "me.heeka.anisync.Extension"
    static let nativeApplicationIdentifier = "me.heeka.anisync"
    static let activityRetention: TimeInterval = 30 * 24 * 60 * 60
}

enum AniListStatus: String, Codable, CaseIterable, Sendable {
    case current = "CURRENT"
    case planning = "PLANNING"
    case completed = "COMPLETED"
    case dropped = "DROPPED"
    case paused = "PAUSED"
    case repeating = "REPEATING"
}

struct AniListAccount: Codable, Equatable, Sendable {
    let id: Int
    let name: String
    let avatarURL: String?
    var tokenExpiresAt: Date?
}

struct AniListEntrySnapshot: Codable, Equatable, Sendable {
    let id: Int
    let status: AniListStatus
    let progress: Int
    let repeatCount: Int
    let updatedAt: Int
}

struct AniListMediaSnapshot: Codable, Equatable, Sendable {
    let id: Int
    let title: String
    let episodes: Int?
    let format: String?
    let entry: AniListEntrySnapshot?
}

struct MediaSearchResult: Codable, Equatable, Sendable, Identifiable {
    let id: Int
    let title: String
    let year: Int?
    let format: String?
    let episodes: Int?
    let coverImageURL: String?
}

enum SyncKind: String, Codable, Sendable {
    case ordinary
    case rewatch
}

enum PendingState: String, Codable, Sendable {
    case queued
    case awaitingMapping
    case retrying
    case reconnect
}

struct PendingSync: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var mediaID: Int?
    let seriesKey: String
    let sourceTitle: String
    let episode: Int
    var kind: SyncKind
    var cycleID: String
    var createdAt: Date
    var state: PendingState
    var lastError: String?
    var retryAfter: Date?
    var baselineRepeat: Int?
    var force: Bool

    var logicalKey: String? {
        guard let mediaID else { return nil }
        return "\(mediaID):\(episode):\(cycleID)"
    }
}

struct SeriesMapping: Codable, Equatable, Sendable, Identifiable {
    var id: String { seriesKey }
    let seriesKey: String
    let sourceTitle: String
    let mediaID: Int
    let aniListTitle: String
    let createdAt: Date
}

struct RewatchCycle: Codable, Equatable, Sendable, Identifiable {
    var id: String { cycleID }
    let mediaID: Int
    let cycleID: String
    let startedAt: Date
    let baselineRepeat: Int
    var completedAt: Date?
}

enum ActivityOutcome: String, Codable, Sendable {
    case synced
    case alreadyUpToDate
    case undone
}

struct SyncActivity: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let logicalKey: String
    let mediaID: Int
    let title: String
    let episode: Int
    let kind: SyncKind
    let outcome: ActivityOutcome
    let occurredAt: Date
    let before: AniListEntrySnapshot?
    let after: AniListEntrySnapshot?
    var undoneAt: Date?

    var canAttemptUndo: Bool {
        outcome == .synced && undoneAt == nil && after != nil
    }
}

struct SyncConflict: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let pending: PendingSync
    let current: AniListEntrySnapshot?
    let reason: String
    let detectedAt: Date
}

struct StoredState: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var account: AniListAccount?
    var pending: [PendingSync] = []
    var activity: [SyncActivity] = []
    var conflicts: [SyncConflict] = []
    var mappings: [SeriesMapping] = []
    var rewatchCycles: [RewatchCycle] = []
    var completedKeys: [String] = []

    static let empty = StoredState()

    mutating func removeExpiredActivity(now: Date = Date()) {
        activity.removeAll { now.timeIntervalSince($0.occurredAt) > AniSyncConstants.activityRetention }
    }
}

struct NativeState: Codable, Sendable {
    let connected: Bool
    let account: AniListAccount?
    let pending: [PendingSync]
    let activity: [SyncActivity]
    let conflicts: [SyncConflict]
    let mappings: [SeriesMapping]

    init(stored: StoredState, connected: Bool) {
        self.connected = connected
        account = stored.account
        pending = stored.pending.sorted { $0.createdAt > $1.createdAt }
        activity = stored.activity.sorted { $0.occurredAt > $1.occurredAt }
        conflicts = stored.conflicts.sorted { $0.detectedAt > $1.detectedAt }
        mappings = stored.mappings.sorted { $0.sourceTitle.localizedCaseInsensitiveCompare($1.sourceTitle) == .orderedAscending }
    }
}

enum ReconciliationDecision: Equatable, Sendable {
    case noOp(String)
    case write(DesiredWrite)
    case conflict(String)
    case invalid(String)
}

struct DesiredWrite: Equatable, Sendable {
    let progress: Int
    let status: AniListStatus
    let repeatCount: Int?
}

enum AniSyncError: Error, LocalizedError, Sendable {
    case invalidMessage(String)
    case notConfigured
    case unauthorized
    case rateLimited(Int?)
    case temporary(String)
    case api(String)
    case unsafeUndo

    var errorDescription: String? {
        switch self {
        case .invalidMessage(let detail): detail
        case .notConfigured: "AniList connection is not configured."
        case .unauthorized: "AniList authorization has expired."
        case .rateLimited: "AniList is temporarily rate limiting requests."
        case .temporary(let detail): detail
        case .api(let detail): detail
        case .unsafeUndo: "AniList changed after this sync, so it cannot be undone safely."
        }
    }
}
