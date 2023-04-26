//
//  main.swift
//  OctoCmd
//
//  Created by Huy Tran on 4/25/23.
//

import SwiftUI

@main
struct MainApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
        
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.sharedData)
                .fixedSize()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem, addition: {})
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
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
            let pressedChar = event.charactersIgnoringModifiers?.lowercased()
            print(self.sharedData.ignored)
            let matches = self.sharedData.windows
                .filter { win in
                    !self.sharedData.ignored.contains(win.pid)
                }
                .filter { win in
                    win.name.lowercased().starts(with: pressedChar!)
                }
            for window in matches {
                if self.sharedData.lastPid != window.pid {
                    let app = NSRunningApplication(processIdentifier: pid_t(window.pid))
                    app?.activate(options: .activateIgnoringOtherApps)
                    self.sharedData.lastPid = window.pid
                    break
                }
            }
            NSApp.hide(nil)
            return event
        }
        
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { event in
            if event.keyCode == 54 {
                if event.modifierFlags.contains(.command) {
                    self.sharedData.updateWindowsList()
                    // key down
                    print("Show app")
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

struct VisualEffectBackground: NSViewRepresentable {
    private let material: NSVisualEffectView.Material
    private let blendingMode: NSVisualEffectView.BlendingMode
    private let isEmphasized: Bool
    
    fileprivate init(
        material: NSVisualEffectView.Material,
        blendingMode: NSVisualEffectView.BlendingMode,
        emphasized: Bool) {
        self.material = material
        self.blendingMode = blendingMode
        self.isEmphasized = emphasized
    }
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        
        // Not certain how necessary this is
        view.autoresizingMask = [.width, .height]
        
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.isEmphasized = isEmphasized
    }
}

extension View {
    func visualEffect(
        material: NSVisualEffectView.Material,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        emphasized: Bool = false
    ) -> some View {
        background(
            VisualEffectBackground(
                material: material,
                blendingMode: blendingMode,
                emphasized: emphasized
            )
        )
    }
}
