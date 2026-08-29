import Foundation

enum Reconciler {
    static func decide(pending: PendingSync, media: AniListMediaSnapshot) -> ReconciliationDecision {
        guard pending.episode > 0 else {
            return .invalid("Only positive, whole-number episodes can be synced.")
        }
        if let total = media.episodes, pending.episode > total {
            return .invalid("Episode \(pending.episode) is beyond AniList’s known episode count of \(total).")
        }

        switch pending.kind {
        case .ordinary:
            return ordinaryDecision(pending: pending, media: media)
        case .rewatch:
            return rewatchDecision(pending: pending, media: media)
        }
    }

    private static func ordinaryDecision(pending: PendingSync, media: AniListMediaSnapshot) -> ReconciliationDecision {
        guard let entry = media.entry else {
            return .write(DesiredWrite(
                progress: pending.episode,
                status: finalStatus(for: pending.episode, total: media.episodes, otherwise: .current),
                repeatCount: nil
            ))
        }

        if entry.status == .repeating {
            return .invalid("The entry is already repeating and must be reconciled as a rewatch.")
        }
        if entry.status == .completed {
            return .noOp("AniList already marks this title complete.")
        }
        if entry.progress >= pending.episode {
            return .noOp("AniList progress is already at or beyond this episode.")
        }

        let queuedAt = Int(pending.createdAt.timeIntervalSince1970)
        if !pending.force && entry.updatedAt > queuedAt {
            return .conflict("AniList was changed after this episode was queued.")
        }

        return .write(DesiredWrite(
            progress: pending.episode,
            status: finalStatus(for: pending.episode, total: media.episodes, otherwise: .current),
            repeatCount: nil
        ))
    }

    private static func rewatchDecision(pending: PendingSync, media: AniListMediaSnapshot) -> ReconciliationDecision {
        let entry = media.entry
        let baseline = pending.baselineRepeat ?? entry?.repeatCount ?? 0
        let isFinal = media.episodes == pending.episode

        if isFinal,
           let entry,
           entry.status == .completed,
           entry.repeatCount >= baseline + 1 {
            return .noOp("This rewatch cycle is already complete.")
        }

        if !pending.force,
           let entry,
           entry.updatedAt > Int(pending.createdAt.timeIntervalSince1970),
           entry.status != .repeating,
           !(isFinal && entry.status == .completed && entry.repeatCount == baseline) {
            return .conflict("AniList changed after this rewatch episode was queued.")
        }

        if isFinal {
            return .write(DesiredWrite(
                progress: pending.episode,
                status: .completed,
                repeatCount: baseline + 1
            ))
        }

        let progress = max(entry?.progress ?? 0, pending.episode)
        return .write(DesiredWrite(progress: progress, status: .repeating, repeatCount: nil))
    }

    private static func finalStatus(
        for episode: Int,
        total: Int?,
        otherwise status: AniListStatus
    ) -> AniListStatus {
        guard let total, episode == total else { return status }
        return .completed
    }
}

