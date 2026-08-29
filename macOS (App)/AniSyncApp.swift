import AppKit
import SwiftUI

@main
struct AniSyncApp: App {
    @NSApplicationDelegateAdaptor(AniSyncAppDelegate.self) private var appDelegate
    @StateObject private var model = AniSyncAppModel()

    var body: some Scene {
        Window("AniSync", id: "main") {
            AniSyncContentView(model: model)
                .background(AniSyncWindowConfiguration())
                .onOpenURL { url in
                    model.handle(url: url)
                }
        }
        .defaultSize(width: 620, height: 700)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.showMainWindow() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("AniSync Help") { model.showHelp = true }
                    .keyboardShortcut("?", modifiers: .command)
                Link("Report a Problem", destination: URL(string: "https://github.com/gridness/anisync/issues")!)
            }
        }
    }
}

final class AniSyncAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

private struct AniSyncWindowConfiguration: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.collectionBehavior.insert(.fullScreenNone)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.collectionBehavior.insert(.fullScreenNone)
    }
}
