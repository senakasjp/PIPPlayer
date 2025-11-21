import SwiftUI

@main
struct YouTubePlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("View") {
                Button("Toggle Opacity") {
                    NotificationCenter.default.post(name: .toggleOpacity, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)
            }
            CommandMenu("Player") {
                Button("Open URL...") {
                    NotificationCenter.default.post(name: .openURL, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: "YouTube Player")
        }

        setupMenu()
    }

    func setupMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Open URL...", action: #selector(openURL), keyEquivalent: "o"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Toggle Transparency", action: #selector(toggleTransparency), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "Toggle Always On Top", action: #selector(toggleLayer), keyEquivalent: "l"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc func openURL() {
        NotificationCenter.default.post(name: .openURL, object: nil)
    }

    @objc func toggleTransparency() {
        NotificationCenter.default.post(name: .toggleTransparency, object: nil)
    }

    @objc func toggleLayer() {
        NotificationCenter.default.post(name: .toggleLayer, object: nil)
    }
}

extension Notification.Name {
    static let openURL = Notification.Name("openURL")
    static let toggleTransparency = Notification.Name("toggleTransparency")
    static let toggleLayer = Notification.Name("toggleLayer")
    static let toggleOpacity = Notification.Name("toggleOpacity")
}
