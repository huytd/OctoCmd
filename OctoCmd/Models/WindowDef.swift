//
//  WindowDef.swift
//  OctoCmd
//
//  Created by Khoa Le on 28/04/2023.
//

import Cocoa

struct WindowDef: Identifiable, Hashable {
    let id = UUID()

    /// Name of the window.
    let name: String

    /// ID of the window.
    let wid: Int

    /// Process ID owning the window.
    let pid: Int

    /// Alias name for the window.
    let alias: String

    /// Icon image for the window.
    let icon: NSImage

    // MARK: Initialize

    /// Initialize a new window definition.
    ///
    /// - Parameters:
    ///   - name: Name of the window.
    ///   - wid: ID of the window.
    ///   - pid: ID of the process owning the window.
    ///   - alias: Alias name for the window.
    ///   - icon: Icon image for the window.
    init(
        name: String = "",
        wid: Int = -1,
        pid: Int = -1,
        alias: String = "",
        icon: NSImage
    ) {
        self.name = name
        self.wid = wid
        self.pid = pid
        self.alias = alias
        self.icon = icon
    }

    // MARK: Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
    }

    static func ==(left: WindowDef, right: WindowDef) -> Bool {
        return left.pid == right.pid
    }
}
