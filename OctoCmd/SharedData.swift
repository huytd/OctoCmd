//
//  SharedData.swift
//  OctoCmd
//
//  Created by Huy Tran on 4/26/23.
//

import Foundation
import Cocoa

extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var set = Set<Element>()
        return filter { set.insert($0).inserted }
    }
}

struct WindowDef: Identifiable, Hashable {
    let id = UUID()
    var name = ""
    var wid = -1
    var pid = -1
    var alias = ""
    var icon: NSImage

    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
    }
}

func ==(left: WindowDef, right: WindowDef) -> Bool {
    return left.pid == right.pid
}

func getWindowsList() -> [WindowDef] {
    let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
    let windowsListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0))
    let infoList = windowsListInfo as! [[String: Any]]
    let visibleWindows = infoList.filter { $0["kCGWindowLayer"] as! Int == 0 && $0["kCGWindowOwnerName"] as! String != "WindowManager" }
    return visibleWindows.map { (dict) -> WindowDef in
        let name = dict["kCGWindowOwnerName"] as! String
        let wid = dict["kCGWindowNumber"] as! Int
        let pid = dict["kCGWindowOwnerPID"] as! Int
        // So far, Google Chrome is the only alias I want to hardcode
        var alias = String(name.first!).uppercased()
        if name == "Google Chrome" {
            alias = "C"
        }
        let matchedApp = NSWorkspace.shared.runningApplications.filter { app in
            app.processIdentifier == pid
        }.first
        let icon = matchedApp?.icon
        return WindowDef(
            name: name,
            wid: wid,
            pid: pid,
            alias: alias,
            icon: icon!
        )
    }.uniqued()
}

final class SharedData: ObservableObject {
    @Published var ignored: [Int] = (UserDefaults.standard.array(forKey: "octoCmd_Ignored") as? [Int] ?? [])
    @Published var windows: [WindowDef] = getWindowsList()
    @Published var lastPid = -1
    
    public func updateWindowsList() {
        self.windows = getWindowsList()
    }
    
    public func togglePidIgnore(pid: Int) {
        if !self.ignored.contains(pid) {
            self.ignored.append(pid)
        } else {
            if let index = self.ignored.firstIndex(of: pid) {
                self.ignored.remove(at: index)
            }
        }
        UserDefaults.standard.set(self.ignored, forKey: "octoCmd_Ignored")
    }
}

