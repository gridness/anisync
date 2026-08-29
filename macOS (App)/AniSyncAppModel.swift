import AppKit
import AuthenticationServices
import Combine
import SafariServices

@MainActor
final class AniSyncAppModel: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var snapshot = NativeState(stored: .empty, connected: false)
    @Published private(set) var extensionEnabled = false
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var showHelp = false

    private let service = AniSyncService()
    private var authenticationSession: ASWebAuthenticationSession?
    private var oauthState: String?

    var clientIDConfigured: Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "AniListClientID") as? String else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func refresh() async {
        snapshot = await service.state()
        do {
            extensionEnabled = try await SFSafariExtensionManager.stateOfSafariExtension(
                withIdentifier: AniSyncConstants.extensionBundleIdentifier
            ).isEnabled
        } catch {
            extensionEnabled = false
        }
    }

    func connect() {
        guard !isBusy else { return }
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "AniListClientID") as? String,
              !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = String(localized: "AniList connection needs a public client ID in Configuration/Local.xcconfig.")
            return
        }

        let state = UUID().uuidString
        oauthState = state
        var components = URLComponents(string: "https://anilist.co/api/v2/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "state", value: state)
        ]
        guard let url = components.url else { return }

        isBusy = true
        errorMessage = nil
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "anisync") { [weak self] callback, error in
            Task { @MainActor in
                guard let self else { return }
                self.authenticationSession = nil
                if let error {
                    self.isBusy = false
                    if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                        self.errorMessage = error.localizedDescription
                    }
                    return
                }
                do {
                    let result = try self.parseOAuthCallback(callback)
                    try await self.service.connect(token: result.token, expiresAt: result.expiresAt)
                    self.snapshot = await self.service.state()
                } catch {
                    self.errorMessage = error.localizedDescription
                }
                self.isBusy = false
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        authenticationSession = session
        if !session.start() {
            authenticationSession = nil
            isBusy = false
            errorMessage = String(localized: "AniList sign-in could not start.")
        }
    }

    func disconnect() {
        Task {
            await service.disconnect()
            snapshot = await service.state()
        }
    }

    func retry() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            await service.retryPending()
            snapshot = await service.state()
            isBusy = false
        }
    }

    func clearActivity() {
        Task {
            await service.clearActivity()
            snapshot = await service.state()
        }
    }

    func resetMappings() {
        Task {
            await service.resetMappings()
            snapshot = await service.state()
        }
    }

    func undo(_ activity: SyncActivity) {
        guard !isBusy else { return }
        isBusy = true
        Task {
            do {
                try await service.undoActivity(id: activity.id)
            } catch {
                errorMessage = error.localizedDescription
            }
            snapshot = await service.state()
            isBusy = false
        }
    }

    func dismiss(_ conflict: SyncConflict) {
        Task {
            await service.dismissConflict(id: conflict.id)
            snapshot = await service.state()
        }
    }

    func reapply(_ conflict: SyncConflict) {
        guard !isBusy else { return }
        isBusy = true
        Task {
            await service.reapplyConflict(id: conflict.id)
            snapshot = await service.state()
            isBusy = false
        }
    }

    func showSafariSettings() {
        Task {
            do {
                try await SFSafariApplication.showPreferencesForExtension(
                    withIdentifier: AniSyncConstants.extensionBundleIdentifier
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    func handle(url: URL) {
        guard url.scheme == "anisync" else { return }
        showMainWindow()
        if url.host == "connect" { connect() }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }

    private func parseOAuthCallback(_ callback: URL?) throws -> (token: String, expiresAt: Date?) {
        guard let callback,
              callback.scheme == "anisync",
              callback.host == "oauth",
              callback.path == "/callback",
              let fragment = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.fragment,
              let values = URLComponents(string: "?\(fragment)")?.queryItems else {
            throw AniSyncError.api("AniList returned an invalid callback.")
        }
        var dictionary: [String: String] = [:]
        for item in values where dictionary[item.name] == nil {
            dictionary[item.name] = item.value
        }
        guard dictionary["state"] == oauthState else {
            throw AniSyncError.api("AniList sign-in could not be validated.")
        }
        guard dictionary["token_type"]?.lowercased() == "bearer",
              let token = dictionary["access_token"],
              !token.isEmpty else {
            throw AniSyncError.api("AniList did not return an access token.")
        }
        let expiresAt = dictionary["expires_in"].flatMap(TimeInterval.init).map { Date().addingTimeInterval($0) }
        return (token, expiresAt)
    }
}
