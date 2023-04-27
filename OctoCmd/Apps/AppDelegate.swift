//
//  AppDelegate.swift
//  OctoCmd
//
//  Created by Khoa Le on 28/04/2023.
//

import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    let sharedData = SharedData()

    func applicationDidFinishLaunching(_ notification: Notification) {
        for window in NSApplication.shared.windows {
            window.level = .floating
            window.titlebarSeparatorStyle = .none
            window.isMovableByWindowBackground = true
            window.titlebarAppearsTransparent = true
            window.standardWindowButton(.closeButton)!.isHidden = true
            window.standardWindowButton(.miniaturizeButton)!.isHidden = true
            window.standardWindowButton(.zoomButton)!.isHidden = true
            window.center()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let isTrusted = AXIsProcessTrusted()
            print("Is trusted", isTrusted)
            if !isTrusted {
                let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
                let enabled = AXIsProcessTrustedWithOptions(options)
            }
        }

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let pressedChar = event.charactersIgnoringModifiers?.uppercased()
            let matches = self.sharedData.windows
                .filter { win in
                    !self.sharedData.ignored.contains(win.pid)
                }
                .filter { win in
                    win.alias == pressedChar
                }
            for window in matches {
                print("Compare \(self.sharedData.lastPid) with \(window.pid)")
                if self.sharedData.lastPid != window.pid {
                    let app = NSRunningApplication(processIdentifier: pid_t(window.pid))
                    app?.activate(options: .activateIgnoringOtherApps)
                    break
                }
            }
            NSApp.hide(nil)
            // Send Cmd + Q or Nil event
            return event.keyCode == 12 && event.modifierFlags.contains(.command) ? event : nil
        }

        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { event in
            if event.keyCode == 54 {
                if event.modifierFlags.contains(.command) {
                    if let frontMost = NSWorkspace.shared.frontmostApplication {
                        self.sharedData.lastPid = Int(frontMost.processIdentifier)
                    }
                    self.sharedData.updateWindowsList()
                    // key down
                    print("Show app from", self.sharedData.lastPid)
                    NSApp.activate(ignoringOtherApps: true)
                } else {
                    // key up
                    print("Hide app")
                    NSApp.hide(nil)
                }
            }
        })
    }
}
