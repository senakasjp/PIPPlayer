import SwiftUI

@main
struct YouTubePlayerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Player") {
                Button("Open URL...") {
                    NotificationCenter.default.post(name: .openURL, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let openURL = Notification.Name("openURL")
}
