//
//  SharedData.swift
//  OctoCmd
//
//  Created by Huy Tran on 4/26/23.
//

import Cocoa

/// A shared object to store data between different parts of the application.
final class SharedData: ObservableObject {
    /// An array of process IDs that should be ignored when updating the windows list.
    @Published var ignored: [Int] = (UserDefaults.standard.array(forKey: "octoCmd_Ignored") as? [Int] ?? [])

    /// An array of `WindowDef` structs representing the visible windows.
    @Published var windows: [WindowDef] = []

    /// The last process ID that was used to update the windows list.
    @Published var lastPid: Int = -1

    // MARK: Initializers

    init() {
        self.windows = self.getWindowsList()
    }

    /// Updates the `windows` array with the visible windows.
    func updateWindowsList() {
        self.windows = getWindowsList()
    }

    /// Adds or removes a process ID from the `ignored` array and saves it to UserDefaults.
    func togglePidIgnore(pid: Int) {
        if !self.ignored.contains(pid) {
            self.ignored.append(pid)
        } else {
            if let index = self.ignored.firstIndex(of: pid) {
                self.ignored.remove(at: index)
            }
        }
        UserDefaults.standard.set(self.ignored, forKey: "octoCmd_Ignored")
    }

    // MARK: Side Effects - Private

    /// Returns an array of `WindowDef` structs representing the visible windows.
    private func getWindowsList() -> [WindowDef] {
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        let windowsListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0))

        guard let infoList = windowsListInfo as? [[String: Any]] else {
            return []
        }

        let visibleWindows = infoList.filter { windowInfo in
            guard let layer = windowInfo["kCGWindowLayer"] as? Int,
                  let ownerName = windowInfo["kCGWindowOwnerName"] as? String else {
                return false
            }
            return layer == 0 && ownerName != "WindowManager"
        }

        return visibleWindows.map { windowInfo in
            guard let name = windowInfo["kCGWindowOwnerName"] as? String,
                  let wid = windowInfo["kCGWindowNumber"] as? Int,
                  let pid = windowInfo["kCGWindowOwnerPID"] as? Int else {
                fatalError("Missing window property")
            }

            // So far, Google Chrome is the only alias I want to hardcode
            var alias = String(name.first!).uppercased()
            if name == "Google Chrome" {
                alias = "C"
            }

            let matchedApp = NSWorkspace.shared.runningApplications.filter { app in
                app.processIdentifier == pid
            }.first

            guard let icon = matchedApp?.icon else {
                fatalError("Could not retrieve window icon.")
            }

            return WindowDef(
                name: name,
                wid: wid,
                pid: pid,
                alias: alias,
                icon: icon
            )
        }.uniqued()
    }
}
