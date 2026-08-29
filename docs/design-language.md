# AniSync Design Language

Status: Confirmed for macOS v1  
Confirmed: 2026-08-29  
Apple guidance reviewed: 2026-08-29  
Minimum platform: macOS 26  
Distribution: Mac App Store

## Product

AniSync is a quiet Safari companion for people who watch anime on Anime365 and keep their viewing history on AniList. When an eligible episode crosses 80% while actively playing, AniSync safely advances the corresponding AniList entry. It supports ordinary viewing and explicit rewatches without silently overwriting a newer decision made on AniList.

Version 1 supports these origins only:

- `https://smotret-anime.org`
- `https://smotret-anime.app`
- `https://anime-365.ru`

The product is free and has no AniSync account, server, analytics, telemetry, advertisements, in-app purchases, or subscription. It is an unofficial companion and must present clear privacy, support, and attribution information.

## People and jobs

The primary user already uses Safari, Anime365, and AniList. Their main job is not to manage a tracker; it is to watch an episode and trust that the tracker will be correct afterward. Secondary jobs are connecting AniList, resolving a title that lacks a direct identifier, inspecting a rare failure, explicitly starting a rewatch, and correcting a safe-to-undo sync.

Users may work in English or Russian, use keyboard navigation or VoiceOver, prefer increased contrast or reduced motion, watch in a background tab, or temporarily lose connectivity. Routine viewing must not require the containing app to remain open.

## Domain language

Interface copy and implementation names use the terms defined in [`CONTEXT.md`](../CONTEXT.md). In particular, the interface distinguishes a Pending Sync from a Sync Conflict and an Awaiting Mapping state. “Rewatch” is reserved for an explicit Rewatch Cycle, not merely opening an old episode.

## Experience principles

### Quiet assurance

Routine success is visible but never interruptive: a brief toolbar checkmark and a compact activity record. There are no video overlays, confetti, mascots, celebratory animation, or notification noise.

### The viewer remains in control

AniSync never guesses a title and mutates AniList. Missing identity requires one explicit mapping confirmation. A newer AniList state wins automatically only when it is safely compatible; otherwise AniSync presents a conflict for inspection.

### Native and familiar

The containing app behaves like a small macOS settings utility. It uses standard windows, controls, menus, focus behavior, keyboard commands, semantic colors, system type, and platform materials. It does not imitate a website or create custom window chrome.

### Explain only when needed

The normal state is terse. Errors state what happened, what AniSync preserved, and the single next action. Technical details are available as selectable diagnostics rather than appearing in primary copy.

### Least privilege and local trust

Safari access is requested only for the three supported origins. The AniList access token remains in Keychain and is never exposed to extension JavaScript. Account-specific pending work and rewatch state are erased on explicit disconnect.

## macOS experience architecture

AniSync has two surfaces.

### Safari toolbar popover

This is the routine surface. It shows:

- the connected AniList username;
- the current supported title and episode, when available;
- the threshold explanation, “Syncs at 80%”;
- a brief success state;
- the three most recent activity items;
- focused actions for Start Rewatch, reconnecting, resolving a mapping, inspecting a conflict, and opening the AniSync app.

The popover stays one level deep. It does not open nested popovers or turn into a miniature dashboard. Title mapping uses a search field, concise result list, preview, and one confirmation in this surface.

### Containing app

The app is a single standard, resizable SwiftUI window. It contains:

- overall readiness and AniList account state;
- supported-site permission state;
- recent sync activity retained for 30 days;
- Pending Sync and Sync Conflict details;
- Clear Activity, Disconnect, and Reset Mappings controls;
- privacy, help, support, and unofficial-companion information.

It has no sidebar, inspector, document model, library browser, full-screen experience, multiple-window workflow, or menu-bar extra.

### Menu structure

The app supplies the standard application menu with About AniSync, Settings (Command-comma), Hide, and Quit; standard Edit clipboard commands; the standard Window menu; and Help links. Automatic sync correction is row-specific and conditional, so it is not represented as a global Command-Z action.

## Design language

### Layout

Use readable, content-sized forms and grouped sections with native spacing. Keep the primary window comfortably compact instead of filling the display. Align labels, values, and controls to a consistent grid. Use leading and trailing alignment so localization and future right-to-left work do not require structural rewrites.

### Type

Use the system typeface and semantic SwiftUI text styles. Body copy should normally be at least 13 points on macOS. Use weight and spacing to establish hierarchy; do not use all-caps labels or decorative display typography.

### Color and materials

Use semantic system colors and the user’s accent color. Success, warning, and error colors always have an accompanying symbol and text. Support light mode, dark mode, increased contrast, and reduced transparency. Use macOS 26 system materials only where they clarify grouping; never layer decorative glass or gradients behind ordinary controls.

### Icons and brand

The app icon is a custom layered Icon Composer asset: two interlocking arcs resolving into a checkmark on a restrained indigo field. The toolbar icon is a simple monochrome derivative that remains legible at Safari toolbar sizes. SF Symbols may support interface actions but do not serve as the product trademark.

### Motion

Motion is functional and brief: state replacement, progress disclosure, or a short success transition. Nothing bounces, loops, or competes with the video. When Reduce Motion is enabled, use an immediate or cross-faded state change.

### Writing

Copy is concise, literal, and calm. Prefer “Saved episode 8 to AniList” over branded or emotional language. State preservation explicitly in failures, for example: “You’re offline. Episode 8 is saved and will retry.” English and Russian ship together. Avoid idioms, jargon, and direction-specific language.

## Components

### Readiness card

The first section in the app summarizes whether AniSync is Ready, Needs AniList, Needs Safari Access, or Needs Attention. It uses a symbol, title, one-sentence explanation, and at most one primary action.

### Account row

Shows the AniList avatar when available, username, connection state, and a Connect or Disconnect action. Disconnect requires confirmation because it erases the token, Pending Sync items, and account-specific rewatch state while preserving site configuration.

### Supported sites list

Lists the three supported origins with accessible permission status. A missing permission provides a single action that explains how to enable the extension in Safari Settings.

### Activity list

Uses a native list with timestamp, title, episode, resulting AniList state, and outcome. Entries may disclose selectable details. Successful activity expires after 30 days and can be cleared. Persistent failures remain represented by Pending Sync or Sync Conflict state rather than disappearing with activity history.

### State callout

Pending, reconnect, mapping, permission, and conflict states share one restrained callout pattern: semantic symbol, plain-language title, preservation statement, and one primary action. Secondary actions appear only when necessary.

### Search and mapping

Search starts only after a qualified episode lacks an exact AniList identifier. Results show title, year, format, and artwork if available. Confirmation displays both the Anime365 title and selected AniList title. The mapping is stored locally and the retained qualified episode reconciles immediately.

### Progress

Indeterminate progress appears only during a user-initiated operation such as connection or mapping search. Passive playback does not create an app progress bar; Safari and the video player already communicate playback.

## State model and behavior

### First launch

Present a short checklist: connect AniList, enable AniSync in Safari, allow the three supported sites, then watch normally. Each step explains its reason at the moment it is needed. Do not request unrelated permissions.

### Ready

Show the connected account, all supported sites, and “AniSync will save an episode when playback reaches 80%.” The app can be closed afterward.

### Qualified playback

A positive-integer normal episode qualifies when an actively playing video has a finite duration and reaches at least 80%. Seeking or resuming beyond the threshold qualifies; merely loading a paused video does not. Muted video and a background tab remain eligible. Movies are episode 1. Specials, recaps, and fractional episodes are out of scope.

The logical completion key is `(AniList media ID, episode number, viewing cycle)`, independent of Anime365 origin, translation, or tab. Duplicates are no-ops. A later ordinary episode supersedes an earlier pending ordinary episode for the same title.

### Ordinary reconciliation

AniSync re-reads AniList before a mutation. It never lowers progress. A missing entry or one in PLANNING, PAUSED, or DROPPED becomes CURRENT at the qualified episode. If the known final episode is reached, the entry becomes COMPLETED. When the total is unknown, progress can advance but completion is not inferred.

If AniList contains a newer deliberate status or lower-progress edit that conflicts with the queued intent, AniSync creates a Sync Conflict instead of overwriting it.

### Rewatch

A Rewatch Cycle exists only when AniList is already REPEATING or the user explicitly starts it in AniSync. Progress advances within that cycle. Reaching the known final episode completes the entry and increments the repeat count exactly once. An unknown total remains REPEATING. Opening an old episode alone never starts a rewatch.

### Success

Safari briefly displays a checkmark on the toolbar and the activity list records the outcome. No overlay appears over the video.

### Awaiting mapping

The qualified episode is retained. The popover explains that AniSync needs the corresponding AniList title and offers search. One confirmed mapping is saved locally and immediately triggers reconciliation.

### Offline, rate limit, or temporary failure

Create a durable Pending Sync that survives app and browser restarts. Retry after re-reading AniList. Ordinary work coalesces to the highest safe progress. Rewatch completion remains an exactly-once intent. Copy confirms that the episode is saved locally.

### Expired or revoked authorization

Keep Pending Sync work and ask the user to reconnect. A successful reconnect resumes reconciliation. Explicit Disconnect is different: it erases the token and account-specific pending state.

### Conflict

Show the queued intent beside the current AniList value and timestamp when available. The user can dismiss the intent, open AniList, or deliberately reapply after another read. AniList is the source of truth for newer manual choices.

### Permission denied

Explain which supported site lacks Safari access and guide the user to Safari Settings. Do not repeatedly prompt or broaden the requested origins.

### Private Browsing

Version 1 does not operate in Private Browsing. State this directly without implying that watching failed or that private data was captured.

### Safe correction

An activity row may offer Undo only when AniList still exactly matches AniSync’s recorded write. AniSync re-reads first. If the value changed, Undo is replaced by Open AniList.

## Accessibility and input

All controls participate in logical keyboard traversal and display a visible focus ring. Standard shortcuts and clipboard behavior remain intact. VoiceOver labels name both the control and current state. Status is never communicated by color alone. Controls use native hit targets, body text remains comfortably readable, and diagnostics are selectable.

The app is verified in light and dark appearance, Increase Contrast, Reduce Transparency, Reduce Motion, keyboard-only use, and VoiceOver. Pointer interactions use standard cursors and do not depend on hover-only disclosure.

## Ecosystem and implementation boundaries

The Safari content script observes only DOM already present on a user-opened supported page. It does not crawl Anime365 or use an Anime365 API. Frame observations travel to the extension background page, then through Safari native messaging to the containing extension. The native layer owns Keychain access, local durable state, OAuth validation, and AniList GraphQL calls. JavaScript never receives the AniList token.

Authentication uses `ASWebAuthenticationSession` with callback `anisync://oauth/callback`, validates the callback, and stores only a public AniList client ID in local build configuration. A checked-in example configuration is provided; no client secret exists in the app.

App Groups hold nonsecret state shared by the containing app and extension. Keychain Sharing holds credentials. App Sandbox permits only the outbound network access needed for AniList. The extension declares the three exact website origins and native messaging permission.

There is one AniList account per macOS user, shared across standard Safari profiles. iOS, Private Browsing, other streaming sites, notifications, widgets, App Intents, Siri, Spotlight, iCloud synchronization, Handoff, SharePlay, StoreKit, a local library, and a proprietary service are deferred.

## Delivery and verification

Implementation proceeds in correctness-first vertical slices without an artificial deadline. Deterministic tests use sanitized captured Anime365 markup and a fake AniList service. Fixtures and logs must never contain cookies, credentials, viewing URLs, or other account data. A real AniList mutation is performed only as an explicit smoke test against an entry chosen by the user.

The v1 acceptance bar includes onboarding; all three supported origins; exact matching and confirmed mappings; non-regression and deduplication; ordinary status transitions; explicit rewatch semantics; durable offline retry; rate limiting; expired authorization; conflict handling; safe correction; English and Russian localization; accessibility; and Mac App Store-ready privacy and support presentation.

## Evidence

The design follows Apple’s current guidance for [design principles](https://developer.apple.com/design/human-interface-guidelines/design-principles/), [designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/), [accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility/), [privacy](https://developer.apple.com/design/human-interface-guidelines/privacy/), [feedback](https://developer.apple.com/design/human-interface-guidelines/feedback/), [onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding/), [settings](https://developer.apple.com/design/human-interface-guidelines/settings/), [windows](https://developer.apple.com/design/human-interface-guidelines/windows/), [popovers](https://developer.apple.com/design/human-interface-guidelines/popovers/), [keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards/), and [VoiceOver](https://developer.apple.com/design/human-interface-guidelines/voiceover/).

The architecture also follows Apple’s guidance for [Safari web extension permissions](https://developer.apple.com/documentation/safariservices/managing-safari-web-extension-permissions), [messaging between an app and extension JavaScript](https://developer.apple.com/documentation/safariservices/messaging-between-the-app-and-javascript-in-a-safari-web-extension), [`ASWebAuthenticationSession`](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession), [Keychain Sharing](https://developer.apple.com/documentation/xcode/configuring-keychain-sharing), and [Safari web extension distribution](https://developer.apple.com/documentation/safariservices/distributing-your-safari-web-extension).

## Decision ledger

| Decision | Rationale | Status |
| --- | --- | --- |
| macOS 26 minimum | User-selected v1 platform; permits a focused modern SwiftUI implementation | Confirmed |
| Mac App Store distribution | Matches the intended consumer installation and Safari extension workflow | Confirmed |
| Toolbar popover plus small containing app | Keeps routine work beside Safari while preserving a native place for setup and recovery | Confirmed |
| Native layer owns AniList token and calls | Prevents credential exposure to page-adjacent JavaScript | Confirmed |
| Exact identity or one confirmed mapping | Prevents a plausible but harmful wrong-title mutation | Confirmed |
| 80% while actively playing | Supports seeks and resumed playback while excluding a paused preloaded page | Confirmed |
| Explicit rewatch cycle | Prevents old-episode playback from altering completed history | Confirmed |
| Durable local retry with re-read | Handles offline and rate-limit conditions without blind mutation | Confirmed |
| Newer AniList choice wins conflicts | Respects user agency at the system of record | Confirmed |
| No proprietary service or telemetry | Keeps scope, privacy promise, and trust model simple | Confirmed |
| English and Russian in v1 | Matches the intended audience and confirmed requirement | Confirmed |
| No artificial deadline | Allows correctness-first handling of account mutations | Confirmed |

