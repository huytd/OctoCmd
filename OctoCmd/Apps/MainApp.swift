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
