import SwiftUI
import Combine

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let alwaysOnTop = "settings.alwaysOnTopEnabled"
        static let eightyTransparency = "settings.eightyTransparencyEnabled"
        static let hoverTransparency = "settings.hoverTransparencyEnabled"
    }

    @Published var alwaysOnTopEnabled: Bool = true {
        didSet {
            guard oldValue != alwaysOnTopEnabled else { return }
            defaults.set(alwaysOnTopEnabled, forKey: Keys.alwaysOnTop)
            NotificationCenter.default.post(name: .setAlwaysOnTop, object: nil, userInfo: ["enabled": alwaysOnTopEnabled])
        }
    }

    @Published var eightyTransparencyEnabled: Bool = false {
        didSet {
            guard oldValue != eightyTransparencyEnabled else { return }
            defaults.set(eightyTransparencyEnabled, forKey: Keys.eightyTransparency)
            NotificationCenter.default.post(name: .setEightyTransparency, object: nil, userInfo: ["enabled": eightyTransparencyEnabled])
        }
    }

    @Published var hoverTransparencyEnabled: Bool = true {
        didSet {
            guard oldValue != hoverTransparencyEnabled else { return }
            defaults.set(hoverTransparencyEnabled, forKey: Keys.hoverTransparency)
            NotificationCenter.default.post(name: .setHoverTransparency, object: nil, userInfo: ["enabled": hoverTransparencyEnabled])
        }
    }

    private init() {
        loadPersistedValues()
    }

    private func loadPersistedValues() {
        if defaults.object(forKey: Keys.alwaysOnTop) != nil {
            alwaysOnTopEnabled = defaults.bool(forKey: Keys.alwaysOnTop)
        }
        if defaults.object(forKey: Keys.eightyTransparency) != nil {
            eightyTransparencyEnabled = defaults.bool(forKey: Keys.eightyTransparency)
        }
        if defaults.object(forKey: Keys.hoverTransparency) != nil {
            hoverTransparencyEnabled = defaults.bool(forKey: Keys.hoverTransparency)
        }
    }
}

@main
struct YouTubePlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .sidebar) {
                Toggle("Hover Transparency", isOn: $settings.hoverTransparencyEnabled)
                    .keyboardShortcut("t", modifiers: .command)
                Toggle("Always On Top", isOn: $settings.alwaysOnTopEnabled)
                    .keyboardShortcut("l", modifiers: .command)
                Toggle("80% Transparency", isOn: $settings.eightyTransparencyEnabled)
                    .keyboardShortcut("8", modifiers: .command)
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
    private let settings = AppSettings.shared
    private var observers: [NSObjectProtocol] = []
    private var alwaysOnTopItem: NSMenuItem?
    private var eightyTransparencyItem: NSMenuItem?
    private var hoverTransparencyItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: "YouTube Player")
        }

        setupMenu()
        installObservers()
    }

    func setupMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Open URL...", action: #selector(openURL), keyEquivalent: "o"))
        menu.addItem(NSMenuItem.separator())
        let hoverTransparency = NSMenuItem(title: "Hover Transparency", action: #selector(toggleHoverTransparency), keyEquivalent: "t")
        hoverTransparency.state = settings.hoverTransparencyEnabled ? .on : .off
        menu.addItem(hoverTransparency)
        hoverTransparencyItem = hoverTransparency

        let alwaysOnTop = NSMenuItem(title: "Always On Top", action: #selector(toggleAlwaysOnTop), keyEquivalent: "l")
        alwaysOnTop.state = settings.alwaysOnTopEnabled ? .on : .off
        menu.addItem(alwaysOnTop)
        alwaysOnTopItem = alwaysOnTop

        let eightyTransparency = NSMenuItem(title: "80% Transparency", action: #selector(toggleEightyTransparency), keyEquivalent: "8")
        eightyTransparency.state = settings.eightyTransparencyEnabled ? .on : .off
        menu.addItem(eightyTransparency)
        eightyTransparencyItem = eightyTransparency

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

    @objc func toggleHoverTransparency(_ sender: NSMenuItem) {
        settings.hoverTransparencyEnabled.toggle()
    }

    @objc func toggleAlwaysOnTop(_ sender: NSMenuItem) {
        settings.alwaysOnTopEnabled.toggle()
    }

    @objc func toggleEightyTransparency(_ sender: NSMenuItem) {
        settings.eightyTransparencyEnabled.toggle()
    }

    private func installObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .setAlwaysOnTop, object: nil, queue: .main) { [weak self] notification in
            if let enabled = notification.userInfo?["enabled"] as? Bool {
                self?.alwaysOnTopItem?.state = enabled ? .on : .off
            }
        })
        observers.append(center.addObserver(forName: .setEightyTransparency, object: nil, queue: .main) { [weak self] notification in
            if let enabled = notification.userInfo?["enabled"] as? Bool {
                self?.eightyTransparencyItem?.state = enabled ? .on : .off
            }
        })
        observers.append(center.addObserver(forName: .setHoverTransparency, object: nil, queue: .main) { [weak self] notification in
            if let enabled = notification.userInfo?["enabled"] as? Bool {
                self?.hoverTransparencyItem?.state = enabled ? .on : .off
            }
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

extension Notification.Name {
    static let openURL = Notification.Name("openURL")
    static let toggleTransparency = Notification.Name("toggleTransparency")
    static let toggleOpacity = Notification.Name("toggleOpacity")
    static let setAlwaysOnTop = Notification.Name("setAlwaysOnTop")
    static let setEightyTransparency = Notification.Name("setEightyTransparency")
    static let setHoverTransparency = Notification.Name("setHoverTransparency")
}
