import AppKit
import Foundation

/// Remembers which native window belongs to the player.
///
/// AppKit's `windowNumber` is the same identifier AeroSpace reports as
/// `window-id`, so the follower can ask AeroSpace to move exactly this window
/// and never one of the app's auxiliary windows.
final class PlayerWindowRegistry {
    static let shared = PlayerWindowRegistry()

    private(set) var playerWindowNumber: Int?

    private init() {}

    func register(_ window: NSWindow) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                self.register(window)
            }
            return
        }
        guard window.windowNumber > 0 else { return }
        playerWindowNumber = window.windowNumber
    }

    func clear() {
        playerWindowNumber = nil
    }
}

/// Keeps the player visible while AeroSpace switches workspaces.
///
/// AeroSpace emulates workspaces by moving the windows of inactive workspaces
/// off screen. A window level such as `.statusBar` cannot prevent that, so
/// "Always On Top" alone is not enough. The follower subscribes to AeroSpace
/// workspace changes and moves the player to whatever workspace its own monitor
/// is showing. It never moves the app's other windows, never focuses the player,
/// and gives up quietly when AeroSpace is not installed or not running.
final class AeroSpaceWorkspaceFollower {
    static let shared = AeroSpaceWorkspaceFollower()

    private static let aeroSpaceBundleIdentifier = "bobko.aerospace"
    private static let binaryPaths = [
        "/opt/homebrew/bin/aerospace",
        "/usr/local/bin/aerospace",
        "/Applications/AeroSpace.app/Contents/MacOS/aerospace"
    ]

    private let queue = DispatchQueue(label: "com.example.YouTubePlayer.aerospace-follower")
    private let queueKey = DispatchSpecificKey<Void>()
    private let processIdentifier = getpid()

    private var process: Process?
    private var outputPipe: Pipe?
    private var lineBuffer = Data()
    private var pendingReconcile: DispatchWorkItem?
    private var pendingRestart: DispatchWorkItem?
    private var restartDelay: TimeInterval = 2
    private var wantsFollowing = false

    private init() {
        queue.setSpecific(key: queueKey, value: ())
    }

    /// Starts following. Safe to call repeatedly.
    func start() {
        queue.async {
            guard !self.wantsFollowing else { return }
            self.wantsFollowing = true
            self.restartDelay = 2
            self.launch()
        }
    }

    /// Stops following and releases the subscription process. Runs
    /// synchronously so the child process is gone before the app exits.
    func stop() {
        let teardown = {
            self.wantsFollowing = false
            self.pendingRestart?.cancel()
            self.pendingRestart = nil
            self.pendingReconcile?.cancel()
            self.pendingReconcile = nil
            self.outputPipe?.fileHandleForReading.readabilityHandler = nil
            self.process?.terminate()
            self.process = nil
            self.outputPipe = nil
            self.lineBuffer.removeAll()
        }
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            teardown()
        } else {
            queue.sync(execute: teardown)
        }
    }

    /// Re-checks the player against the visible workspace, for example after
    /// the player window is created or a setting changes.
    func reconcileNow() {
        queue.async {
            self.scheduleReconcile(after: 0.2)
        }
    }

    // MARK: - Subscription process

    private func launch() {
        guard wantsFollowing else { return }
        guard let binary = Self.aerospaceBinary(), Self.aeroSpaceIsRunning() else {
            scheduleRestart()
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["subscribe", "focused-workspace-changed", "--no-send-initial"]
        process.standardError = FileHandle.nullDevice

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            self.queue.async { self.consume(data) }
        }

        process.terminationHandler = { [weak self] _ in
            self?.queue.async { self?.handleProcessExit() }
        }

        do {
            try process.run()
        } catch {
            scheduleRestart()
            return
        }

        self.process = process
        self.outputPipe = outputPipe
        restartDelay = 2
        scheduleReconcile(after: 0.4)
    }

    private func handleProcessExit() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        process = nil
        lineBuffer.removeAll()
        guard wantsFollowing else { return }
        scheduleRestart()
    }

    private func scheduleRestart() {
        pendingRestart?.cancel()
        let delay = restartDelay
        restartDelay = min(restartDelay * 2, 30)
        let work = DispatchWorkItem { [weak self] in self?.launch() }
        pendingRestart = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Events

    private func consume(_ data: Data) {
        lineBuffer.append(data)
        while let newline = lineBuffer.firstIndex(of: 0x0A) {
            let lineData = lineBuffer[lineBuffer.startIndex..<newline]
            lineBuffer.removeSubrange(lineBuffer.startIndex...newline)
            if let line = String(data: lineData, encoding: .utf8) {
                handleEvent(line)
            }
        }
    }

    private func handleEvent(_ line: String) {
        guard Self.isWorkspaceChangeEvent(line) else { return }
        scheduleReconcile(after: 0.15)
    }

    private func scheduleReconcile(after delay: TimeInterval) {
        pendingReconcile?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reconcile() }
        pendingReconcile = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func reconcile() {
        guard wantsFollowing else { return }
        guard let windowNumber = PlayerWindowRegistry.shared.playerWindowNumber else { return }
        guard let snapshot = windowSnapshot(for: windowNumber) else { return }
        guard let visible = visibleWorkspace(onMonitor: snapshot.monitorID) else { return }
        guard visible != snapshot.workspace else { return }
        moveWindow(windowNumber, to: visible)
    }

    // MARK: - AeroSpace queries

    private func windowSnapshot(for windowNumber: Int) -> WindowSnapshot? {
        let result = run(arguments: [
            "list-windows", "--monitor", "all", "--pid", String(processIdentifier),
            "--format", "%{window-id}\t%{monitor-id}\t%{workspace}"
        ])
        guard result.status == 0 else { return nil }
        return Self.parseWindowSnapshot(result.output, windowNumber: windowNumber)
    }

    private func visibleWorkspace(onMonitor monitorID: String) -> String? {
        let result = run(arguments: [
            "list-workspaces", "--monitor", monitorID, "--visible", "--format", "%{workspace}"
        ])
        guard result.status == 0 else { return nil }
        return Self.firstWorkspaceName(result.output)
    }

    private func moveWindow(_ windowNumber: Int, to workspace: String) {
        _ = run(arguments: [
            "move-node-to-workspace", "--window-id", String(windowNumber),
            "--fail-if-noop", "--", workspace
        ])
    }

    private func run(arguments: [String]) -> (status: Int32, output: String) {
        guard let binary = Self.aerospaceBinary() else { return (-1, "") }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
        } catch {
            return (-1, "")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    // MARK: - Pure helpers (covered by regression checks)

    static func aerospaceBinary() -> String? {
        binaryPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func aeroSpaceIsRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: aeroSpaceBundleIdentifier).isEmpty
    }

    static func isWorkspaceChangeEvent(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let event = object as? [String: Any],
              let name = event["_event"] as? String else { return false }
        return name == "focused-workspace-changed"
    }

    static func parseWindowSnapshot(
        _ output: String,
        windowNumber: Int
    ) -> WindowSnapshot? {
        let wanted = String(windowNumber)
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line
                .split(separator: "\t", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 3, fields[0] == wanted else { continue }
            let monitorID = fields[1]
            let workspace = fields[2]
            guard !monitorID.isEmpty, !workspace.isEmpty else { continue }
            return WindowSnapshot(monitorID: monitorID, workspace: workspace)
        }
        return nil
    }

    static func firstWorkspaceName(_ output: String) -> String? {
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let name = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        return nil
    }
}

struct WindowSnapshot: Equatable {
    let monitorID: String
    let workspace: String
}
