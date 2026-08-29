import SwiftUI

struct AniSyncContentView: View {
    @ObservedObject var model: AniSyncAppModel
    @State private var confirmDisconnect = false
    @State private var confirmResetMappings = false

    private let sites = ["smotret-anime.org", "smotret-anime.app", "anime-365.ru"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                readiness
                account
                supportedSites
                if !model.snapshot.conflicts.isEmpty { conflicts }
                if !model.snapshot.pending.isEmpty { pending }
                activity
                privacy
            }
            .padding(24)
            .frame(maxWidth: 720)
        }
        .frame(minWidth: 520, minHeight: 560)
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refresh() }
        }
        .alert("Disconnect AniList?", isPresented: $confirmDisconnect) {
            Button("Disconnect", role: .destructive) { model.disconnect() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the token, pending syncs, activity, conflicts, and rewatch state from this Mac. Saved title mappings remain.")
        }
        .alert("Reset title mappings?", isPresented: $confirmResetMappings) {
            Button("Reset Mappings", role: .destructive) { model.resetMappings() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Anime365 titles without a direct AniList link will need confirmation again.")
        }
        .alert("AniSync Needs Attention", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(isPresented: $model.showHelp) { helpSheet }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("AniSync").font(.title2.weight(.semibold))
                Text("Anime365 progress, quietly kept in sync with AniList.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isBusy { ProgressView().controlSize(.small).accessibilityLabel("Working") }
        }
    }

    private var readiness: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: readinessSymbol)
                    .font(.title2)
                    .foregroundStyle(readinessColor)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(readinessTitle).font(.headline)
                    Text(readinessDetail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                readinessAction
            }
            .padding(4)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var readinessAction: some View {
        if !model.snapshot.connected {
            Button("Connect AniList") { model.connect() }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
        } else if !model.extensionEnabled {
            Button("Open Safari Settings") { model.showSafariSettings() }
                .buttonStyle(.borderedProminent)
        } else if !model.snapshot.pending.isEmpty {
            Button("Retry Now") { model.retry() }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
        }
    }

    private var account: some View {
        section("AniList Account") {
            HStack(spacing: 12) {
                AsyncImage(url: model.snapshot.account?.avatarURL.flatMap(URL.init(string:))) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.snapshot.account?.name ?? "Not connected").fontWeight(.medium)
                    Text(model.snapshot.connected ? "Connected securely with Keychain" : "Required before an episode can reach AniList")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.snapshot.connected {
                    Button("Disconnect") { confirmDisconnect = true }
                } else {
                    Button("Connect") { model.connect() }.disabled(model.isBusy)
                }
            }
        }
    }

    private var supportedSites: some View {
        section("Safari Extension") {
            VStack(spacing: 0) {
                ForEach(sites, id: \.self) { site in
                    HStack {
                        Label(site, systemImage: "safari")
                        Spacer()
                        Text("Supported").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    if site != sites.last { Divider() }
                }
            }
            Divider().padding(.vertical, 4)
            HStack(alignment: .firstTextBaseline) {
                Label(
                    model.extensionEnabled ? "Enabled in Safari" : "Enable AniSync in Safari Settings",
                    systemImage: model.extensionEnabled ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                .foregroundStyle(model.extensionEnabled ? Color.primary : Color.orange)
                Spacer()
                Button("Safari Settings…") { model.showSafariSettings() }
            }
        }
    }

    private var pending: some View {
        section("Pending Sync") {
            ForEach(model.snapshot.pending) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: pendingSymbol(item.state)).foregroundStyle(.orange).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(item.sourceTitle) · Episode \(item.episode)").fontWeight(.medium)
                        Text(pendingDetail(item)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 3)
            }
        }
    }

    private var conflicts: some View {
        section("Sync Conflicts") {
            ForEach(model.snapshot.conflicts) { conflict in
                VStack(alignment: .leading, spacing: 8) {
                    Label("\(conflict.pending.sourceTitle) · Episode \(conflict.pending.episode)", systemImage: "exclamationmark.triangle.fill")
                        .fontWeight(.medium)
                        .foregroundStyle(.red)
                    Text(conflict.reason).foregroundStyle(.secondary)
                    if let current = conflict.current {
                        Text("AniList now has \(statusName(current.status)) at episode \(current.progress).")
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    HStack {
                        Button("Reapply After Checking") { model.reapply(conflict) }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isBusy)
                        Link("Open AniList", destination: URL(string: "https://anilist.co/anime/\(conflict.pending.mediaID ?? 0)")!)
                        Button("Dismiss") { model.dismiss(conflict) }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var activity: some View {
        section("Activity") {
            if model.snapshot.activity.isEmpty {
                ContentUnavailableView(
                    "No Sync Activity Yet",
                    systemImage: "clock",
                    description: Text("Qualified episodes will appear here for 30 days.")
                )
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ForEach(model.snapshot.activity.prefix(20)) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.undoneAt == nil ? "checkmark.circle.fill" : "arrow.uturn.backward.circle")
                            .foregroundStyle(item.undoneAt == nil ? .green : .secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(item.title) · Episode \(item.episode)").fontWeight(.medium)
                            Text(activityDetail(item)).foregroundStyle(.secondary)
                            Text(item.occurredAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if item.canAttemptUndo {
                            Button("Undo…") { model.undo(item) }.disabled(model.isBusy)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Divider()
                HStack {
                    Button("Clear Activity") { model.clearActivity() }
                    Spacer()
                    Text("Stored locally for 30 days").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var privacy: some View {
        section("Privacy & Help") {
            VStack(alignment: .leading, spacing: 10) {
                Label("Your AniList token stays in Keychain. AniSync has no server, analytics, or telemetry.", systemImage: "lock.shield")
                Text("AniSync observes only supported Anime365 pages you open and sends AniList only the title and episode needed to sync.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Privacy & Help…") { model.showHelp = true }
                    Button("Reset Title Mappings…") { confirmResetMappings = true }
                    Spacer()
                    Link("Report a Problem", destination: URL(string: "https://github.com/gridness/anisync/issues")!)
                }
                Text("AniSync is an unofficial companion and is not affiliated with AniList or Anime365.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var helpSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Privacy & Help").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { model.showHelp = false }.keyboardShortcut(.defaultAction)
            }
            Divider()
            Text("How AniSync works").font(.headline)
            Text("Watch a normal episode on a supported Anime365 site. While it is actively playing, AniSync qualifies it at 80%, checks AniList again, and only then makes a safe update.")
            Text("What stays on this Mac").font(.headline)
            Text("The access token is stored in Keychain. Title mappings, saved retries, conflicts, and 30 days of activity are stored locally. Explicitly disconnecting removes account-specific state.")
            Text("AniSync never collects analytics, telemetry, cookies, credentials, video addresses, or a remote viewing history.")
            Divider()
            HStack {
                Link("AniList", destination: URL(string: "https://anilist.co")!)
                Link("Source & Support", destination: URL(string: "https://github.com/gridness/anisync")!)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            GroupBox { content().padding(4) }
        }
    }

    private var readinessTitle: LocalizedStringKey {
        if !model.snapshot.connected { return "Connect AniList" }
        if !model.extensionEnabled { return "Enable the Safari extension" }
        if !model.snapshot.conflicts.isEmpty { return "Review a sync conflict" }
        if !model.snapshot.pending.isEmpty { return "A saved sync needs attention" }
        return "Ready"
    }

    private var readinessDetail: LocalizedStringKey {
        if !model.snapshot.connected { return "Connect one AniList account. Your access token stays in Keychain." }
        if !model.extensionEnabled { return "Enable AniSync and allow its three supported Anime365 sites in Safari Settings." }
        if !model.snapshot.conflicts.isEmpty { return "AniList changed after an episode was saved, so AniSync did not overwrite it." }
        if !model.snapshot.pending.isEmpty { return "Your episode is preserved on this Mac. Retry now or follow the action below." }
        return "AniSync will save an eligible episode when active playback reaches 80%. You can close this app."
    }

    private var readinessSymbol: String {
        if !model.snapshot.connected { return "person.crop.circle.badge.plus" }
        if !model.extensionEnabled { return "safari" }
        if !model.snapshot.conflicts.isEmpty { return "exclamationmark.triangle.fill" }
        if !model.snapshot.pending.isEmpty { return "clock.badge.exclamationmark" }
        return "checkmark.circle.fill"
    }

    private var readinessColor: Color {
        if !model.snapshot.conflicts.isEmpty { return .red }
        if !model.snapshot.connected || !model.extensionEnabled || !model.snapshot.pending.isEmpty { return .orange }
        return .green
    }

    private func pendingSymbol(_ state: PendingState) -> String {
        switch state {
        case .awaitingMapping: "questionmark.circle"
        case .reconnect: "person.crop.circle.badge.exclamationmark"
        case .retrying: "arrow.clockwise.circle"
        case .queued: "clock"
        }
    }

    private func pendingDetail(_ item: PendingSync) -> String {
        if let error = item.lastError { return error }
        switch item.state {
        case .awaitingMapping: return String(localized: "Confirm this title from the Safari toolbar.")
        case .reconnect: return String(localized: "Reconnect AniList to finish this saved sync.")
        case .retrying: return String(localized: "Saved locally and waiting to retry.")
        case .queued: return String(localized: "Waiting to reconcile with AniList.")
        }
    }

    private func activityDetail(_ item: SyncActivity) -> String {
        if item.undoneAt != nil { return String(localized: "Undone safely") }
        if item.outcome == .alreadyUpToDate { return String(localized: "AniList was already up to date") }
        if item.kind == .rewatch { return String(localized: "Rewatch progress saved to AniList") }
        return String(localized: "Progress saved to AniList")
    }

    private func statusName(_ status: AniListStatus) -> String {
        switch status {
        case .current: String(localized: "current")
        case .planning: String(localized: "planning")
        case .completed: String(localized: "completed")
        case .dropped: String(localized: "dropped")
        case .paused: String(localized: "paused")
        case .repeating: String(localized: "repeating")
        }
    }
}
