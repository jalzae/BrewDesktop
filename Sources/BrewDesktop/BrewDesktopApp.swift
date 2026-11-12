import SwiftUI

@main
struct BrewDesktopApp: App {
    @StateObject private var store = BrewStore()

    var body: some Scene {
        WindowGroup("BrewDesktop") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 880, minHeight: 560)
                .task { store.refreshAll() }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Install Package…") {
                    NotificationCenter.default.post(name: .openInstallSheet, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command])
                Divider()
                Button("Refresh") {
                    NotificationCenter.default.post(name: .refreshAll, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            EmptyView()
        }
    }
}

extension Notification.Name {
    static let openInstallSheet = Notification.Name("openInstallSheet")
    static let refreshAll = Notification.Name("refreshAll")
}
