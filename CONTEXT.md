# AniSync

AniSync keeps an AniList user's anime-list state aligned with episodes watched on supported streaming sites.

## Language

**AniList Entry**:
The user's AniList record for one anime, including its viewing status and episode progress.
_Avoid_: Anime, item, list item

**AniList Connection**:
The authorization linking AniSync to one AniList account. An interrupted or expired connection preserves unfinished work for reconnection, while an explicit disconnect removes account-specific state.
_Avoid_: Login, profile, token

**Episode Progress**:
The highest episode the user has completed for an AniList Entry.
_Avoid_: Watch position, timestamp

**Qualified Playback**:
An identified episode whose actively playing video first reaches or passes 80% of its duration. Seeking, resuming beyond the threshold, muted playback, and background-tab playback still qualify; loading a paused video does not.
_Avoid_: Video view, page visit, elapsed watch time

**Syncable Episode**:
An episode with an exact AniList identity, normal episode type, and positive integer episode number. A known episode count is an upper bound, while an unknown count permits progress but not automatic completion; a movie may be represented as episode 1, while fractional specials, recaps, and other ambiguous releases are excluded.
_Avoid_: Any video, special case

**Progress Sync**:
A reconciliation that advances an AniList Entry after an episode qualifies as watched, without reducing Episode Progress or repeating an already-applied change.
_Avoid_: Check-in, scrobble

**Pending Sync**:
A Progress Sync that qualified locally but has not yet been reconciled with AniList. It remains pending across application and Safari restarts until it succeeds, is safely superseded, or the connected account is removed.
_Avoid_: Retry, failed request

**Sync Activity**:
A local record of a Progress Sync's intended change, outcome, and relevant before-and-after AniList state. It supports explanation and correction without serving as an independent anime library.
_Avoid_: Watch history, tracking library, audit log

**Sync Conflict**:
A Pending Sync that cannot be applied automatically because AniList contains a newer, deliberate change. The remote AniList Entry remains authoritative until the user explicitly resolves the conflict.
_Avoid_: Failed request, overwrite

**Series Mapping**:
The user's saved association between a series on a supported streaming site and its corresponding AniList Entry.
_Avoid_: Guess, search result

**Awaiting Mapping**:
A Qualified Playback retained because its series lacks an exact AniList identity. It can become a Pending Sync only after the user confirms and saves a Series Mapping.
_Avoid_: Failed match, guessed match

**Supported Anime365 Origin**:
One of the explicitly trusted Anime365 website origins where AniSync may observe playback: `smotret-anime.org`, `smotret-anime.app`, or `anime-365.ru`.
_Avoid_: Mirror, any website

**Rewatch Cycle**:
An explicitly started repeat viewing of an AniList Entry, with Episode Progress distinct from its earlier completed viewing. It begins from AniList's repeating state or a user action and ends after the final known episode qualifies.
_Avoid_: Rerun, replay, old episode
