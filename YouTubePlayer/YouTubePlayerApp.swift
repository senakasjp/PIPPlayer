import SwiftUI
import Combine

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let alwaysOnTop = "settings.alwaysOnTopEnabled"
        static let eightyTransparency = "settings.eightyTransparencyEnabled"
        static let hoverTransparency = "settings.hoverTransparencyEnabled"
        static let fillPlayerWindow = "settings.fillPlayerWindowEnabled"
        static let lockAspectRatio16x9 = "settings.lockAspectRatio16x9Enabled"
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

    @Published var fillPlayerWindowEnabled: Bool = false {
        didSet {
            guard oldValue != fillPlayerWindowEnabled else { return }
            defaults.set(fillPlayerWindowEnabled, forKey: Keys.fillPlayerWindow)
            NotificationCenter.default.post(name: .setFillPlayerWindow, object: nil, userInfo: ["enabled": fillPlayerWindowEnabled])
        }
    }

    @Published var lockAspectRatio16x9Enabled: Bool = false {
        didSet {
            guard oldValue != lockAspectRatio16x9Enabled else { return }
            defaults.set(lockAspectRatio16x9Enabled, forKey: Keys.lockAspectRatio16x9)
            NotificationCenter.default.post(name: .setLockAspectRatio16x9, object: nil, userInfo: ["enabled": lockAspectRatio16x9Enabled])
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
        if defaults.object(forKey: Keys.fillPlayerWindow) != nil {
            fillPlayerWindowEnabled = defaults.bool(forKey: Keys.fillPlayerWindow)
        }
        if defaults.object(forKey: Keys.lockAspectRatio16x9) != nil {
            lockAspectRatio16x9Enabled = defaults.bool(forKey: Keys.lockAspectRatio16x9)
        }
    }
}

@main
struct YouTubePlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        Window("YouTube Player", id: "main-player") {
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
                Toggle("Fill Player Window", isOn: $settings.fillPlayerWindowEnabled)
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Toggle("Lock 16:9 While Resizing", isOn: $settings.lockAspectRatio16x9Enabled)
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
    private var fillPlayerWindowItem: NSMenuItem?
    private var lockAspectRatio16x9Item: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            let icon = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: "YouTube Player")
            icon?.size = NSSize(width: 14, height: 14)
            button.image = icon
            button.imageScaling = .scaleProportionallyDown
        }

        setupMenu()
        installObservers()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
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

        let fillPlayerWindow = NSMenuItem(title: "Fill Player Window", action: #selector(toggleFillPlayerWindow), keyEquivalent: "f")
        fillPlayerWindow.keyEquivalentModifierMask = [.command, .shift]
        fillPlayerWindow.state = settings.fillPlayerWindowEnabled ? .on : .off
        menu.addItem(fillPlayerWindow)
        fillPlayerWindowItem = fillPlayerWindow

        let lockAspectRatio16x9 = NSMenuItem(title: "Lock 16:9 While Resizing", action: #selector(toggleLockAspectRatio16x9), keyEquivalent: "")
        lockAspectRatio16x9.state = settings.lockAspectRatio16x9Enabled ? .on : .off
        menu.addItem(lockAspectRatio16x9)
        lockAspectRatio16x9Item = lockAspectRatio16x9

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

    @objc func toggleFillPlayerWindow(_ sender: NSMenuItem) {
        settings.fillPlayerWindowEnabled.toggle()
    }

    @objc func toggleLockAspectRatio16x9(_ sender: NSMenuItem) {
        settings.lockAspectRatio16x9Enabled.toggle()
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
        observers.append(center.addObserver(forName: .setFillPlayerWindow, object: nil, queue: .main) { [weak self] notification in
            if let enabled = notification.userInfo?["enabled"] as? Bool {
                self?.fillPlayerWindowItem?.state = enabled ? .on : .off
            }
        })
        observers.append(center.addObserver(forName: .setLockAspectRatio16x9, object: nil, queue: .main) { [weak self] notification in
            if let enabled = notification.userInfo?["enabled"] as? Bool {
                self?.lockAspectRatio16x9Item?.state = enabled ? .on : .off
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
    static let setFillPlayerWindow = Notification.Name("setFillPlayerWindow")
    static let setLockAspectRatio16x9 = Notification.Name("setLockAspectRatio16x9")
}
