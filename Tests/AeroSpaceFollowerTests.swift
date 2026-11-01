import Foundation

/// Checks the pure parsing helpers used by the AeroSpace workspace follower.
/// These helpers decide which window and workspace the app acts on, so a wrong
/// answer would move the wrong window.
@main
struct AeroSpaceFollowerTests {
    static func main() {
        var failures = 0

        func check(_ condition: Bool, _ message: String) {
            if condition {
                print("PASS  \(message)")
            } else {
                print("FAIL  \(message)")
                failures += 1
            }
        }

        // Only the exact player window is selected, even when the app owns
        // several windows and AeroSpace prints them on separate lines.
        let windows = """
        10513\t1\tT
        10512\t1\tT
        """
        let snapshot = AeroSpaceWorkspaceFollower.parseWindowSnapshot(windows, windowNumber: 10512)
        check(snapshot?.workspace == "T", "selects the row for the exact window number")
        check(snapshot?.monitorID == "1", "reads the monitor of the matching row")

        // A missing window must not produce a snapshot at all. Falling back to
        // the first row is what moved the wrong window in the old workaround.
        let missing = AeroSpaceWorkspaceFollower.parseWindowSnapshot(windows, windowNumber: 99999)
        check(missing == nil, "refuses to guess when the window number is absent")

        // Malformed or truncated output must not be trusted.
        let partial = "10512\t\n"
        check(AeroSpaceWorkspaceFollower.parseWindowSnapshot(partial, windowNumber: 10512) == nil,
              "ignores rows with a missing workspace")

        // Window numbers that merely share a prefix must not match.
        let prefixed = "105121\t1\tT\n"
        check(AeroSpaceWorkspaceFollower.parseWindowSnapshot(prefixed, windowNumber: 10512) == nil,
              "does not match a window number by prefix")

        // Only workspace change events trigger a move.
        check(AeroSpaceWorkspaceFollower.isWorkspaceChangeEvent(#"{"_event":"focused-workspace-changed","workspace":"T"}"#),
              "accepts a focused workspace change event")
        check(!AeroSpaceWorkspaceFollower.isWorkspaceChangeEvent(#"{"_event":"mode-changed","mode":"main"}"#),
              "ignores unrelated AeroSpace events")
        check(!AeroSpaceWorkspaceFollower.isWorkspaceChangeEvent("workspace-changed"),
              "ignores non-JSON output")

        // The visible workspace lookup returns one trimmed name.
        check(AeroSpaceWorkspaceFollower.firstWorkspaceName("  T \n") == "T",
              "trims the visible workspace name")
        check(AeroSpaceWorkspaceFollower.firstWorkspaceName("\n\n") == nil,
              "reports no workspace when the output is empty")

        // The binary lookup must point at an executable when AeroSpace is
        // installed, and must not pretend it exists otherwise.
        if let binary = AeroSpaceWorkspaceFollower.aerospaceBinary() {
            check(FileManager.default.isExecutableFile(atPath: binary), "finds an executable aerospace binary")
        } else {
            check(true, "no aerospace binary on this machine")
        }

        if failures > 0 {
            print("\n\(failures) check(s) failed")
            exit(1)
        }
        print("\nAll AeroSpace follower checks passed")
    }
}
