//
//  AppDelegate.swift
//  OctoCmd
//
//  Created by Khoa Le on 28/04/2023.
//

import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?
    let sharedData = SharedData()
    var recordingMonitor: Any?
    var recordingTimeout: DispatchWorkItem?
    var searchRecordingMonitor: Any?
    var searchRecordingTimeout: DispatchWorkItem?
    var scrollModeRecordingMonitor: Any?
    var scrollModeRecordingTimeout: DispatchWorkItem?
    var currentModifierState: NSEvent.ModifierFlags = []
    var shortcutDetectionTimer: DispatchWorkItem?
    var eventTap: CFMachPort?
    var isInCooldown: Bool = false
    var cooldownTimer: DispatchWorkItem?

    // Fallback global monitors for scroll mode (non-consuming)
    var scrollModeGlobalKeyDownMonitor: Any?
    var scrollModeGlobalKeyUpMonitor: Any?
    
    // Event tap monitoring and recovery
    var eventTapHealthTimer: Timer?
    var accessibilityCheckTimer: Timer?
    var lastEventTapTime: Date = Date()
    var eventTapFailureCount: Int = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set shared instance
        AppDelegate.shared = self
        
        // Add system event observers for debugging
        setupSystemEventObservers()
        for window in NSApplication.shared.windows {
            window.level = .floating
            window.collectionBehavior = .canJoinAllSpaces
            window.titlebarSeparatorStyle = .none
            window.isMovableByWindowBackground = true
            window.titlebarAppearsTransparent = true
            window.standardWindowButton(.closeButton)!.isHidden = true
            window.standardWindowButton(.miniaturizeButton)!.isHidden = true
            window.standardWindowButton(.zoomButton)!.isHidden = true
            window.center()
        }

        // Check accessibility permissions immediately
        let isTrusted = AXIsProcessTrusted()
        
        if !isTrusted {
            // Request accessibility permissions
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
            let _ = AXIsProcessTrustedWithOptions(options)
            
            // Start a timer to check for permission changes
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                if AXIsProcessTrusted() {
                    self.setupEventTap()
                    timer.invalidate()
                }
            }
        } else {
            // Already trusted, set up event tap immediately
            setupEventTap()
        }

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event -> NSEvent? in
            // Don't process normal key events while recording shortcuts
            if self.sharedData.isRecordingShortcut || self.sharedData.isRecordingSearchShortcut || self.sharedData.isRecordingScrollModeShortcut {
                return event
            }
            
            // Don't process shortcut matching during text input (but allow special keys like ESC and Tab)
            if self.sharedData.isTextInputActive && event.keyCode != 53 && event.keyCode != 48 {
                return event
            }
            
            // Handle Tab key to enter search mode (only if not already in search mode)
            if event.keyCode == 48 && !event.modifierFlags.contains(.command) { // Tab key
                if !self.sharedData.isSearchMode {
                    self.sharedData.enterSearchMode()
                    return nil // Consume the event
                } else {
                    // Already in search mode, let the search view handle the tab
                    return event
                }
            }
            
            // Handle ESC key to hide the app or exit modes
            if event.keyCode == 53 { // ESC key
                if self.sharedData.isScrollMode {
                    // In scroll mode, exit scroll mode
                    self.sharedData.exitScrollMode()
                    return nil // Consume the event
                } else if self.sharedData.isSearchMode {
                    // In search mode, hide the app directly
                    print("▶️ Pausing event tap for search exit")
                    if let tap = self.eventTap { CGEvent.tapEnable(tap: tap, enable: false) }

                    self.sharedData.exitSearchMode()
                    NSApp.hide(nil)
                    self.startCooldown()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        print("◀️ Resuming event tap after search exit")
                        if let tap = self.eventTap, !CGEvent.tapIsEnabled(tap: tap) {
                            CGEvent.tapEnable(tap: tap, enable: true)
                            if CGEvent.tapIsEnabled(tap: tap) {
                                print("✅ Event tap resumed successfully.")
                            } else {
                                print("❌ Failed to resume event tap, attempting recovery.")
                                self.recoverEventTap()
                            }
                        }
                    }
                    return nil // Consume the event
                } else {
                    // Normal ESC behavior - hide the app
                    NSApp.hide(nil)
                    self.startCooldown()
                    return nil
                }
            }
            
            
            // Handle page switching shortcuts (Cmd+1, Cmd+2, Cmd+3, and Cmd+4)
            if event.modifierFlags.contains(.command) {
                if event.keyCode == 18 { // Key "1"
                    self.sharedData.switchToPage(.mainApps)
                    return nil // Consume the event
                } else if event.keyCode == 19 { // Key "2"
                    self.sharedData.switchToPage(.skippedApps)
                    return nil // Consume the event
                } else if event.keyCode == 20 { // Key "3"
                    self.sharedData.switchToPage(.groups)
                    return nil // Consume the event
                } else if event.keyCode == 21 { // Key "4"
                    self.sharedData.switchToPage(.settings)
                    return nil // Consume the event
                }
            }
            
            // Note: Scroll mode keyboard events are now handled in the global event tap
            // This ensures they work even when OctoCmd is not the frontmost app
            
            // Skip normal app shortcut matching when in search mode
            if self.sharedData.isSearchMode {
                return event
            }
            
            let pressedChar = event.charactersIgnoringModifiers?.uppercased()
            let currentApps: [WindowDef]
            switch self.sharedData.currentPage {
            case .mainApps:
                currentApps = self.sharedData.mainApps
            case .skippedApps:
                currentApps = self.sharedData.skippedApps
            case .groups:
                currentApps = [] // Empty for now
            case .settings:
                currentApps = [] // Empty for settings
            }
            let matches = currentApps.filter { win in
                win.alias == pressedChar
            }
            var didHandleLetterActivation = false
            
            // Check if Alt modifier is pressed for skip functionality
            let isAltPressed = event.modifierFlags.contains(.option)
            
            for window in matches {
                if self.sharedData.lastPid != window.pid {
                    if isAltPressed {
                        // Alt + Letter pressed: Toggle skip for this app
                        print("Toggling skip for app: \(window.name)")
                        self.sharedData.togglePidIgnore(pid: window.pid)
                        didHandleLetterActivation = true
                        break
                    } else {
                        // Regular letter pressed: Activate the app
                        // Get all apps to activate (including group members)
                        let appsToActivate = self.sharedData.getAppsToActivate(for: window.name)
                        print("Activating apps: \(appsToActivate)")
                        
                        for (index, appName) in appsToActivate.enumerated() {
                            // Add a small delay between activations to ensure they work properly
                            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.1) {
                                // Find the window definition for this app
                                if let appWindow = self.sharedData.windows.first(where: { $0.name == appName }) {
                                    if appWindow.isOpen {
                                        // App is running, activate it
                                        let app = NSRunningApplication(processIdentifier: pid_t(appWindow.pid))
                                        app?.activate(options: .activateIgnoringOtherApps)
                                    } else {
                                        // App is not running, try to launch it
                                        if appWindow.bundleIdentifier != "unknown" {
                                            NSWorkspace.shared.launchApplication(withBundleIdentifier: appWindow.bundleIdentifier, 
                                                                               options: [], 
                                                                               additionalEventParamDescriptor: nil, 
                                                                               launchIdentifier: nil)
                                        } else {
                                            // Fallback: try to launch by app name
                                            NSWorkspace.shared.launchApplication(appWindow.name)
                                        }
                                    }
                                } else {
                                    // App not found in windows list, try to launch by name
                                    NSWorkspace.shared.launchApplication(appName)
                                }
                            }
                        }
                        didHandleLetterActivation = true
                        break
                    }
                }
            }
            if didHandleLetterActivation {
                NSApp.hide(nil)
                self.startCooldown()
                // Consume the event to prevent system beep
                return nil
            }
            // Pass through all events so they can be processed by other monitors
            return event
        }

        // Observer for shortcut recording
        NotificationCenter.default.addObserver(forName: NSNotification.Name("StartRecordingShortcut"), object: nil, queue: .main) { _ in
            self.startRecordingShortcut()
        }
        
        // Observer for search shortcut recording
        NotificationCenter.default.addObserver(forName: NSNotification.Name("StartRecordingSearchShortcut"), object: nil, queue: .main) { _ in
            self.startRecordingSearchShortcut()
        }
        
        // Observer for scroll mode shortcut recording
        NotificationCenter.default.addObserver(forName: NSNotification.Name("StartRecordingScrollModeShortcut"), object: nil, queue: .main) { _ in
            self.startRecordingScrollModeShortcut()
        }
    }
    
    // MARK: - CGEvent Tap for Global Keyboard Monitoring
    
    /// Safely converts CGEvent to NSEvent with validation to prevent crashes
    private func safeNSEvent(from cgEvent: CGEvent) -> NSEvent? {
        let eventType = cgEvent.type
        
        // Only convert events we know are safe to handle
        guard eventType == .keyDown || eventType == .keyUp || eventType == .flagsChanged else {
            // Log unexpected event types for debugging
            print("Warning: Skipping CGEvent with unsupported type: \(eventType.rawValue)")
            return nil
        }
        
        // Additional validation: check if the event type is within valid range
        guard eventType.rawValue > 0 && eventType.rawValue <= CGEventType.tapDisabledByUserInput.rawValue else {
            print("Warning: CGEvent has invalid type value: \(eventType.rawValue)")
            return nil
        }
        
        // Attempt the conversion and handle any potential failures gracefully
        return NSEvent(cgEvent: cgEvent)
    }
    
    func setupEventTap() {
        print("🔧 [OctoCmd] Setting up event tap...")
        
        // Double-check accessibility permissions
        let trusted = AXIsProcessTrusted()
        if !trusted {
            print("❌ [OctoCmd] Accessibility permissions not granted")
            // Show an alert to the user
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText = "OctoCmd needs accessibility permissions to monitor keyboard shortcuts.\n\nPlease grant permission in System Preferences > Security & Privacy > Privacy > Accessibility, then restart the app."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open System Preferences")
                alert.addButton(withTitle: "OK")
                
                if alert.runModal() == .alertFirstButtonReturn {
                    // Open System Preferences to the Accessibility pane
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
            return
        }
        
        // Clean up any existing event tap
        if let existingTap = self.eventTap {
            print("🔄 [OctoCmd] Cleaning up existing event tap")
            CGEvent.tapEnable(tap: existingTap, enable: false)
            CFMachPortInvalidate(existingTap)
            self.eventTap = nil
        }
        
        // Create an event tap to intercept key events
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        
        // Create the event tap
        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                // Get the AppDelegate instance from refcon
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()

                // Handle tap disabled events by re-enabling the tap
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = appDelegate.eventTap {
                        print("⚠️ Event tap disabled (type=\(type.rawValue)). Re-enabling...")
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }
                
                // Track event activity for health monitoring
                appDelegate.lastEventTapTime = Date()

                // Always handle scroll mode keys first, regardless of recording/cooldown
                if appDelegate.sharedData.isScrollMode {
                    if type == .keyDown {
                        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                        let scrollSpeed: Double = 2.0
                        print("[ScrollMode] keyDown captured, keyCode=\(keyCode)")

                        // Vertical scrolling
                        if keyCode == 38 { // J key - scroll down
                            DispatchQueue.main.async { appDelegate.sharedData.setScrollVelocity(deltaY: -scrollSpeed, deltaX: 0) }
                            return nil
                        } else if keyCode == 40 { // K key - scroll up
                            DispatchQueue.main.async { appDelegate.sharedData.setScrollVelocity(deltaY: scrollSpeed, deltaX: 0) }
                            return nil
                        } else if keyCode == 125 { // Down arrow - scroll down
                            DispatchQueue.main.async { appDelegate.sharedData.setScrollVelocity(deltaY: -scrollSpeed, deltaX: 0) }
                            return nil
                        } else if keyCode == 126 { // Up arrow - scroll up
                            DispatchQueue.main.async { appDelegate.sharedData.setScrollVelocity(deltaY: scrollSpeed, deltaX: 0) }
                            return nil
                        }
                        // Horizontal scrolling
                        else if keyCode == 4 { // H key - scroll left
                            DispatchQueue.main.async { appDelegate.sharedData.setScrollVelocity(deltaY: 0, deltaX: scrollSpeed) }
                            return nil
                        } else if keyCode == 37 { // L key - scroll right
                            DispatchQueue.main.async { appDelegate.sharedData.setScrollVelocity(deltaY: 0, deltaX: -scrollSpeed) }
                            return nil
                        } else if keyCode == 123 { // Left arrow - scroll left
                            DispatchQueue.main.async { appDelegate.sharedData.setScrollVelocity(deltaY: 0, deltaX: scrollSpeed) }
                            return nil
                        } else if keyCode == 124 { // Right arrow - scroll right
                            DispatchQueue.main.async { appDelegate.sharedData.setScrollVelocity(deltaY: 0, deltaX: -scrollSpeed) }
                            return nil
                        } else if keyCode == 48 { // Tab key - cycle scroll areas
                            DispatchQueue.main.async { appDelegate.sharedData.focusNextScrollArea() }
                            return nil
                        } else if keyCode == 53 { // ESC key
                            print("[ScrollMode] ESC pressed, exiting scroll mode")
                            DispatchQueue.main.async { appDelegate.sharedData.exitScrollMode() }
                            return nil
                        }

                        // Consume all other keyDown events in scroll mode
                        return nil
                    } else if type == .keyUp {
                        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                        print("[ScrollMode] keyUp captured, keyCode=\(keyCode)")
                        if keyCode == 38 || keyCode == 40 || // J, K keys
                           keyCode == 125 || keyCode == 126 || // Down, Up arrows
                           keyCode == 4 || keyCode == 37 || // H, L keys
                           keyCode == 123 || keyCode == 124 { // Left, Right arrows
                            DispatchQueue.main.async { appDelegate.sharedData.stopScrolling() }
                            return nil
                        }
                        // Consume keyUp in scroll mode by default
                        return nil
                    } else if type == .flagsChanged {
                        print("[ScrollMode] flagsChanged captured: \(event.flags.rawValue)")
                        // Consume modifier changes in scroll mode
                        return nil
                    }
                }

                // Don't process while recording or during cooldown
                if appDelegate.sharedData.isRecordingShortcut || appDelegate.isInCooldown {
                    return Unmanaged.passUnretained(event)
                }

                // Handle arrow keys in search mode via global event tap
                if appDelegate.sharedData.isSearchMode && type == .keyDown {
                    if let nsEvent = appDelegate.safeNSEvent(from: event) {
                        if nsEvent.keyCode == 125 { // Down arrow
                            DispatchQueue.main.async {
                                let maxIndex = appDelegate.sharedData.textSearchResults.count - 1
                                if maxIndex >= 0 {
                                    appDelegate.sharedData.selectedResultIndex = min(appDelegate.sharedData.selectedResultIndex + 1, maxIndex)
                                }
                            }
                            return nil // Consume the event
                        } else if nsEvent.keyCode == 126 { // Up arrow
                            DispatchQueue.main.async {
                                appDelegate.sharedData.selectedResultIndex = max(appDelegate.sharedData.selectedResultIndex - 1, 0)
                            }
                            return nil // Consume the event
                        }
                    }
                }
                
                // Don't process shortcut matching during text input (but allow special keys)
                if appDelegate.sharedData.isTextInputActive && type == .keyDown {
                    if let nsEvent = appDelegate.safeNSEvent(from: event) {
                        // Allow ESC, Tab in all cases
                        if nsEvent.keyCode == 53 || nsEvent.keyCode == 48 {
                            // Let these be handled by local monitor
                        } else {
                            return Unmanaged.passUnretained(event)
                        }
                    }
                }
                
                // Convert CGEvent to NSEvent for easier handling
                if let nsEvent = appDelegate.safeNSEvent(from: event) {
                    if type == .keyDown {
                        // Check if this matches our activation shortcut
                        if appDelegate.shouldActivateForKeyDownWithCurrentModifiers(nsEvent) {
                            // Check if the frontmost app is in noActivation list
                            if let frontMost = NSWorkspace.shared.frontmostApplication {
                                if appDelegate.sharedData.noActivation.contains(frontMost.bundleIdentifier ?? "unknown") {
                                    // App is in noActivation list, pass the event through
                                    return Unmanaged.passUnretained(event)
                                }
                            }
                            
                            DispatchQueue.main.async {
                                if let frontMost = NSWorkspace.shared.frontmostApplication {
                                    appDelegate.sharedData.lastPid = Int(frontMost.processIdentifier)
                                    // Search for clickable elements on the last frontmost window
                                    appDelegate.sharedData.searchClickableElements(for: Int(frontMost.processIdentifier))
                                }
                                appDelegate.sharedData.updateWindowsList()
                                NSApp.activate(ignoringOtherApps: true)
                                // Center and bring the main window to the front
                                if let window = NSApp.mainWindow ?? NSApp.windows.first {
                                    window.center()
                                    window.makeKeyAndOrderFront(nil)
                                }
                            }
                            // Consume the event to prevent it from being sent to the current app
                            return nil
                        }
                        
                        // Check if this matches our scroll mode activation shortcut
                        if appDelegate.shouldActivateScrollModeForKeyDownWithCurrentModifiers(nsEvent) {
                            DispatchQueue.main.async {
                                appDelegate.sharedData.enterScrollMode()
                            }
                            // Consume the event to prevent it from being sent to the current app
                            return nil
                        }
                        
                        // Check if this matches our search activation shortcut
                        if appDelegate.shouldActivateSearchForKeyDownWithCurrentModifiers(nsEvent) {
                            // Don't activate if already in search mode
                            if appDelegate.sharedData.isSearchMode {
                                return Unmanaged.passUnretained(event)
                            }
                            
                            // Check if the frontmost app is in noActivation list
                            if let frontMost = NSWorkspace.shared.frontmostApplication {
                                if appDelegate.sharedData.noActivation.contains(frontMost.bundleIdentifier ?? "unknown") {
                                    // App is in noActivation list, pass the event through
                                    return Unmanaged.passUnretained(event)
                                }
                            }
                            
                            print("🔍 [Search] Activating search mode via shortcut")
                            DispatchQueue.main.async {
                                if let frontMost = NSWorkspace.shared.frontmostApplication {
                                    appDelegate.sharedData.lastPid = Int(frontMost.processIdentifier)
                                    // Search for clickable elements on the last frontmost window
                                    appDelegate.sharedData.searchClickableElements(for: Int(frontMost.processIdentifier))
                                }
                                appDelegate.sharedData.updateWindowsList()
                                print("🔍 [Search] Calling enterSearchMode()")
                                appDelegate.sharedData.enterSearchMode() // Enter search mode directly
                                NSApp.activate(ignoringOtherApps: true)
                                print("🔍 [Search] App activated, search mode: \(appDelegate.sharedData.isSearchMode)")
                            }
                            // Consume the event to prevent it from being sent to the current app
                            return nil
                        }
                    } else if type == .flagsChanged {
                        // Update modifier state
                        appDelegate.currentModifierState = nsEvent.modifierFlags
                        
                        // Check if this is a modifier-only activation shortcut
                        if appDelegate.shouldActivateForEvent(nsEvent) {
                            // Check if the frontmost app is in noActivation list
                            if let frontMost = NSWorkspace.shared.frontmostApplication {
                                if appDelegate.sharedData.noActivation.contains(frontMost.bundleIdentifier ?? "unknown") {
                                    // App is in noActivation list, pass the event through
                                    return Unmanaged.passUnretained(event)
                                }
                            }
                            
                            DispatchQueue.main.async {
                                if let frontMost = NSWorkspace.shared.frontmostApplication {
                                    appDelegate.sharedData.lastPid = Int(frontMost.processIdentifier)
                                    // Search for clickable elements on the last frontmost window
                                    appDelegate.sharedData.searchClickableElements(for: Int(frontMost.processIdentifier))
                                }
                                appDelegate.sharedData.updateWindowsList()
                                NSApp.activate(ignoringOtherApps: true)
                            }
                            // Consume the event to prevent it from being sent to the current app
                            return nil
                        }
                        
                        // Check if this is a modifier-only search activation shortcut
                        if appDelegate.shouldActivateSearchForEvent(nsEvent) {
                            // Check if the frontmost app is in noActivation list
                            if let frontMost = NSWorkspace.shared.frontmostApplication {
                                if appDelegate.sharedData.noActivation.contains(frontMost.bundleIdentifier ?? "unknown") {
                                    // App is in noActivation list, pass the event through
                                    return Unmanaged.passUnretained(event)
                                }
                            }
                            
                            DispatchQueue.main.async {
                                if let frontMost = NSWorkspace.shared.frontmostApplication {
                                    appDelegate.sharedData.lastPid = Int(frontMost.processIdentifier)
                                    // Search for clickable elements on the last frontmost window
                                    appDelegate.sharedData.searchClickableElements(for: Int(frontMost.processIdentifier))
                                }
                                appDelegate.sharedData.updateWindowsList()
                                appDelegate.sharedData.enterSearchMode() // Enter search mode directly
                                NSApp.activate(ignoringOtherApps: true)
                            }
                            // Consume the event to prevent it from being sent to the current app
                            return nil
                        }
                    }
                }
                
                // Pass through all other events
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("❌ [OctoCmd] Failed to create event tap")
            return
        }
        
        print("✅ [OctoCmd] Event tap created successfully")
        self.eventTap = eventTap
        lastEventTapTime = Date()
        
        // Create a run loop source and add it to the current run loop
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        
        // Enable the event tap
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        // Verify the event tap is enabled
        if CGEvent.tapIsEnabled(tap: eventTap) {
            print("✅ [OctoCmd] Event tap enabled and ready")
        } else {
            print("❌ [OctoCmd] Event tap failed to enable")
        }
    }
    
    private func startRecordingShortcut() {
        // Remove existing monitor if any
        if let monitor = recordingMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
        // Cancel any existing timeout
        recordingTimeout?.cancel()
        
        // Reset modifier tracking for recording
        var recordingModifierState: NSEvent.ModifierFlags = []
        var modifierPressTime: TimeInterval = 0
        
        // Set a timeout to cancel recording after 10 seconds
        recordingTimeout = DispatchWorkItem {
            DispatchQueue.main.async {
                self.sharedData.isRecordingShortcut = false
            }
            if let monitor = self.recordingMonitor {
                NSEvent.removeMonitor(monitor)
                self.recordingMonitor = nil
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: recordingTimeout!)
        
        // Use local monitor to capture both key and modifier events while window is active
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .keyDown {
                // Skip ESC key to avoid closing window during recording
                if event.keyCode == 53 {
                    // Cancel recording on ESC
                    DispatchQueue.main.async {
                        self.sharedData.isRecordingShortcut = false
                    }
                    self.recordingTimeout?.cancel()
                    if let monitor = self.recordingMonitor {
                        NSEvent.removeMonitor(monitor)
                        self.recordingMonitor = nil
                    }
                    return nil
                }
                
                // Record the key combination
                self.recordKeyEvent(event)
                return nil // Consume the event
            } else if event.type == .flagsChanged {
                // Track modifier state changes
                let newModifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
                
                // Check if modifiers were pressed (more modifiers than before)
                if newModifiers.rawValue > recordingModifierState.rawValue {
                    recordingModifierState = newModifiers
                    modifierPressTime = Date().timeIntervalSince1970
                } else if newModifiers.rawValue < recordingModifierState.rawValue {
                    // Modifiers were released
                    let releaseTime = Date().timeIntervalSince1970
                    let pressDuration = releaseTime - modifierPressTime
                    
                    // If held for a short time and no other keys were pressed, record as modifier-only shortcut
                    if pressDuration > 0.1 && pressDuration < 1.0 {
                        self.recordModifierOnlyShortcut(recordingModifierState, keyCode: event.keyCode)
                    }
                    
                    recordingModifierState = newModifiers
                }
                
                return nil // Consume the event
            }
            
            return event
        }
    }
    
    private func startRecordingSearchShortcut() {
        // Remove existing monitor if any
        if let monitor = searchRecordingMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
        // Cancel any existing timeout
        searchRecordingTimeout?.cancel()
        
        // Reset modifier tracking for recording
        var recordingModifierState: NSEvent.ModifierFlags = []
        var modifierPressTime: TimeInterval = 0
        
        // Set a timeout to cancel recording after 10 seconds
        searchRecordingTimeout = DispatchWorkItem {
            DispatchQueue.main.async {
                self.sharedData.isRecordingSearchShortcut = false
            }
            if let monitor = self.searchRecordingMonitor {
                NSEvent.removeMonitor(monitor)
                self.searchRecordingMonitor = nil
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: searchRecordingTimeout!)

        // Use local monitor to capture both key and modifier events while window is active
        searchRecordingMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .keyDown {
                // Skip ESC key to avoid closing window during recording
                if event.keyCode == 53 {
                    // Cancel recording on ESC
                    DispatchQueue.main.async {
                        self.sharedData.isRecordingSearchShortcut = false
                    }
                    self.searchRecordingTimeout?.cancel()
                    if let monitor = self.searchRecordingMonitor {
                        NSEvent.removeMonitor(monitor)
                        self.searchRecordingMonitor = nil
                    }
                    return nil
                }

                // Record the key event
                self.recordSearchKeyEvent(event)
                return nil // Consume the event
            } else if event.type == .flagsChanged {
                // Handle modifier-only shortcuts
                let newModifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
                
                if !newModifiers.isEmpty && recordingModifierState.isEmpty {
                    // Started pressing modifiers
                    recordingModifierState = newModifiers
                    modifierPressTime = event.timestamp
                } else if newModifiers.isEmpty && !recordingModifierState.isEmpty {
                    // Released all modifiers
                    let pressDuration = event.timestamp - modifierPressTime
                    
                    if pressDuration < 1.0 { // If held for less than 1 second, treat as shortcut
                        self.recordSearchModifierOnlyShortcut(recordingModifierState, keyCode: UInt16(event.keyCode))
                    }
                    
                    recordingModifierState = newModifiers
                }
                
                return nil // Consume the event
            }
            
            return event
        }
    }
    
    private func startRecordingScrollModeShortcut() {
        // Remove existing monitor if any
        if let monitor = scrollModeRecordingMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
        // Cancel any existing timeout
        scrollModeRecordingTimeout?.cancel()
        
        // Reset modifier tracking for recording
        var recordingModifierState: NSEvent.ModifierFlags = []
        var modifierPressTime: TimeInterval = 0
        
        // Set a timeout to cancel recording after 10 seconds
        scrollModeRecordingTimeout = DispatchWorkItem {
            DispatchQueue.main.async {
                self.sharedData.isRecordingScrollModeShortcut = false
            }
            if let monitor = self.scrollModeRecordingMonitor {
                NSEvent.removeMonitor(monitor)
                self.scrollModeRecordingMonitor = nil
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: scrollModeRecordingTimeout!)

        // Use local monitor to capture both key and modifier events while window is active
        scrollModeRecordingMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .keyDown {
                // Skip ESC key to avoid closing window during recording
                if event.keyCode == 53 {
                    // Cancel recording on ESC
                    DispatchQueue.main.async {
                        self.sharedData.isRecordingScrollModeShortcut = false
                    }
                    self.scrollModeRecordingTimeout?.cancel()
                    if let monitor = self.scrollModeRecordingMonitor {
                        NSEvent.removeMonitor(monitor)
                        self.scrollModeRecordingMonitor = nil
                    }
                    return nil
                }

                // Record the key event
                self.recordScrollModeKeyEvent(event)
                return nil // Consume the event
            } else if event.type == .flagsChanged {
                // Handle modifier-only shortcuts
                let newModifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
                
                if !newModifiers.isEmpty && recordingModifierState.isEmpty {
                    // Started pressing modifiers
                    recordingModifierState = newModifiers
                    modifierPressTime = event.timestamp
                } else if newModifiers.isEmpty && !recordingModifierState.isEmpty {
                    // Released all modifiers
                    let pressDuration = event.timestamp - modifierPressTime
                    
                    if pressDuration < 1.0 { // If held for less than 1 second, treat as shortcut
                        self.recordScrollModeModifierOnlyShortcut(recordingModifierState, keyCode: UInt16(event.keyCode))
                    }
                    
                    recordingModifierState = newModifiers
                }
                
                return nil // Consume the event
            }
            
            return event
        }
    }
    
    private func recordKeyEvent(_ event: NSEvent) {
        let modifierFlags = event.modifierFlags
        var shortcutParts: [String] = []
        
        // Add modifiers in consistent order
        if modifierFlags.contains(.control) { shortcutParts.append("⌃") }
        if modifierFlags.contains(.option) { shortcutParts.append("⌥") }  
        if modifierFlags.contains(.shift) { shortcutParts.append("⇧") }
        if modifierFlags.contains(.command) { shortcutParts.append("⌘") }
        
        // Add the key using keyCode for consistency
        let keyName = keyCodeToName(event.keyCode)
        shortcutParts.append(keyName)
        
        let shortcut = shortcutParts.joined(separator: " + ")
        DispatchQueue.main.async {
            self.sharedData.updateActivationShortcut(shortcut)
        }
        
        // Cancel timeout and remove the monitor after recording
        self.recordingTimeout?.cancel()
        if let monitor = self.recordingMonitor {
            NSEvent.removeMonitor(monitor)
            self.recordingMonitor = nil
        }
    }
    
    private func recordModifierOnlyShortcut(_ modifiers: NSEvent.ModifierFlags, keyCode: UInt16) {
        var shortcutParts: [String] = []
        
        // For single modifier shortcuts, we want to distinguish left/right
        if modifiers == [.command] {
            // keyCode 54 = right cmd, 55 = left cmd
            if keyCode == 54 {
                shortcutParts.append("Right ⌘")
            } else if keyCode == 55 {
                shortcutParts.append("Left ⌘")
            } else {
                shortcutParts.append("⌘")
            }
        } else if modifiers == [.shift] {
            // keyCode 60 = right shift, 56 = left shift
            if keyCode == 60 {
                shortcutParts.append("Right ⇧")
            } else if keyCode == 56 {
                shortcutParts.append("Left ⇧")
            } else {
                shortcutParts.append("⇧")
            }
        } else if modifiers == [.control] {
            // keyCode 62 = right control, 59 = left control
            if keyCode == 62 {
                shortcutParts.append("Right ⌃")
            } else if keyCode == 59 {
                shortcutParts.append("Left ⌃")
            } else {
                shortcutParts.append("⌃")
            }
        } else if modifiers == [.option] {
            // keyCode 61 = right option, 58 = left option
            if keyCode == 61 {
                shortcutParts.append("Right ⌥")
            } else if keyCode == 58 {
                shortcutParts.append("Left ⌥")
            } else {
                shortcutParts.append("⌥")
            }
        } else {
            // Multiple modifiers - record them in order
            if modifiers.contains(.control) { shortcutParts.append("⌃") }
            if modifiers.contains(.option) { shortcutParts.append("⌥") }
            if modifiers.contains(.shift) { shortcutParts.append("⇧") }
            if modifiers.contains(.command) { shortcutParts.append("⌘") }
        }
        
        let shortcut = shortcutParts.joined(separator: " + ")
        DispatchQueue.main.async {
            self.sharedData.updateActivationShortcut(shortcut)
        }
        
        // Cancel timeout and remove the monitor after recording
        self.recordingTimeout?.cancel()
        if let monitor = self.recordingMonitor {
            NSEvent.removeMonitor(monitor)
            self.recordingMonitor = nil
        }
    }
    
    private func recordSearchKeyEvent(_ event: NSEvent) {
        let modifierFlags = event.modifierFlags
        var shortcutParts: [String] = []
        
        // Add modifiers in consistent order
        if modifierFlags.contains(.control) { shortcutParts.append("⌃") }
        if modifierFlags.contains(.option) { shortcutParts.append("⌥") }  
        if modifierFlags.contains(.shift) { shortcutParts.append("⇧") }
        if modifierFlags.contains(.command) { shortcutParts.append("⌘") }
        
        // Add the key using keyCode for consistency
        let keyName = keyCodeToName(event.keyCode)
        shortcutParts.append(keyName)
        
        let shortcut = shortcutParts.joined(separator: " + ")
        DispatchQueue.main.async {
            self.sharedData.updateSearchActivationShortcut(shortcut)
        }
        
        // Cancel timeout and remove the monitor after recording
        self.searchRecordingTimeout?.cancel()
        if let monitor = self.searchRecordingMonitor {
            NSEvent.removeMonitor(monitor)
            self.searchRecordingMonitor = nil
        }
    }
    
    private func recordScrollModeKeyEvent(_ event: NSEvent) {
        let modifierFlags = event.modifierFlags
        var shortcutParts: [String] = []
        
        // Add modifiers in consistent order
        if modifierFlags.contains(.control) { shortcutParts.append("⌃") }
        if modifierFlags.contains(.option) { shortcutParts.append("⌥") }  
        if modifierFlags.contains(.shift) { shortcutParts.append("⇧") }
        if modifierFlags.contains(.command) { shortcutParts.append("⌘") }
        
        // Add the key using keyCode for consistency
        let keyName = keyCodeToName(event.keyCode)
        shortcutParts.append(keyName)
        
        let shortcut = shortcutParts.joined(separator: " + ")
        DispatchQueue.main.async {
            self.sharedData.updateScrollModeShortcut(shortcut)
        }
        
        // Cancel timeout and remove the monitor after recording
        self.scrollModeRecordingTimeout?.cancel()
        if let monitor = self.scrollModeRecordingMonitor {
            NSEvent.removeMonitor(monitor)
            self.scrollModeRecordingMonitor = nil
        }
    }
    
    private func recordSearchModifierOnlyShortcut(_ modifiers: NSEvent.ModifierFlags, keyCode: UInt16) {
        var shortcutParts: [String] = []
        
        // For single modifier shortcuts, we want to distinguish left/right
        if modifiers == [.command] {
            // keyCode 54 = right cmd, 55 = left cmd
            if keyCode == 54 {
                shortcutParts.append("Right ⌘")
            } else if keyCode == 55 {
                shortcutParts.append("Left ⌘")
            } else {
                shortcutParts.append("⌘")
            }
        } else if modifiers == [.shift] {
            // keyCode 60 = right shift, 56 = left shift
            if keyCode == 60 {
                shortcutParts.append("Right ⇧")
            } else if keyCode == 56 {
                shortcutParts.append("Left ⇧")
            } else {
                shortcutParts.append("⇧")
            }
        } else if modifiers == [.control] {
            // keyCode 62 = right control, 59 = left control
            if keyCode == 62 {
                shortcutParts.append("Right ⌃")
            } else if keyCode == 59 {
                shortcutParts.append("Left ⌃")
            } else {
                shortcutParts.append("⌃")
            }
        } else if modifiers == [.option] {
            // keyCode 61 = right option, 58 = left option
            if keyCode == 61 {
                shortcutParts.append("Right ⌥")
            } else if keyCode == 58 {
                shortcutParts.append("Left ⌥")
            } else {
                shortcutParts.append("⌥")
            }
        } else {
            // Multiple modifiers - record them in order
            if modifiers.contains(.control) { shortcutParts.append("⌃") }
            if modifiers.contains(.option) { shortcutParts.append("⌥") }
            if modifiers.contains(.shift) { shortcutParts.append("⇧") }
            if modifiers.contains(.command) { shortcutParts.append("⌘") }
        }
        
        let shortcut = shortcutParts.joined(separator: " + ")
        DispatchQueue.main.async {
            self.sharedData.updateSearchActivationShortcut(shortcut)
        }
        
        // Cancel timeout and remove the monitor after recording
        self.searchRecordingTimeout?.cancel()
        if let monitor = self.searchRecordingMonitor {
            NSEvent.removeMonitor(monitor)
            self.searchRecordingMonitor = nil
        }
    }
    
    private func recordScrollModeModifierOnlyShortcut(_ modifiers: NSEvent.ModifierFlags, keyCode: UInt16) {
        var shortcutParts: [String] = []
        
        // For single modifier shortcuts, we want to distinguish left/right
        if modifiers == [.command] {
            // keyCode 54 = right cmd, 55 = left cmd
            if keyCode == 54 {
                shortcutParts.append("Right ⌘")
            } else if keyCode == 55 {
                shortcutParts.append("Left ⌘")
            } else {
                shortcutParts.append("⌘")
            }
        } else if modifiers == [.shift] {
            // keyCode 60 = right shift, 56 = left shift
            if keyCode == 60 {
                shortcutParts.append("Right ⇧")
            } else if keyCode == 56 {
                shortcutParts.append("Left ⇧")
            } else {
                shortcutParts.append("⇧")
            }
        } else if modifiers == [.control] {
            // keyCode 62 = right control, 59 = left control
            if keyCode == 62 {
                shortcutParts.append("Right ⌃")
            } else if keyCode == 59 {
                shortcutParts.append("Left ⌃")
            } else {
                shortcutParts.append("⌃")
            }
        } else if modifiers == [.option] {
            // keyCode 61 = right option, 58 = left option
            if keyCode == 61 {
                shortcutParts.append("Right ⌥")
            } else if keyCode == 58 {
                shortcutParts.append("Left ⌥")
            } else {
                shortcutParts.append("⌥")
            }
        } else {
            // Multiple modifiers - record them in order
            if modifiers.contains(.control) { shortcutParts.append("⌃") }
            if modifiers.contains(.option) { shortcutParts.append("⌥") }
            if modifiers.contains(.shift) { shortcutParts.append("⇧") }
            if modifiers.contains(.command) { shortcutParts.append("⌘") }
        }
        
        let shortcut = shortcutParts.joined(separator: " + ")
        DispatchQueue.main.async {
            self.sharedData.updateScrollModeShortcut(shortcut)
        }
        
        // Cancel timeout and remove the monitor after recording
        self.scrollModeRecordingTimeout?.cancel()
        if let monitor = self.scrollModeRecordingMonitor {
            NSEvent.removeMonitor(monitor)
            self.scrollModeRecordingMonitor = nil
        }
    }
    
    private func keyCodeToName(_ keyCode: UInt16) -> String {
        switch keyCode {
        // Letters
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        
        // Numbers
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        case 29: return "0"
        
        // Punctuation and symbols
        case 24: return "="
        case 27: return "-"
        case 30: return "]"
        case 33: return "["
        case 39: return "'"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 47: return "."
        case 50: return "`"
        
        // Special keys
        case 36: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Escape"
        case 123: return "Left"
        case 124: return "Right"
        case 125: return "Down"
        case 126: return "Up"
        
        default: return "Key\(keyCode)"
        }
    }
    
    private func shouldActivateForKeyDownWithCurrentModifiers(_ event: NSEvent) -> Bool {
        let shortcut = sharedData.activationShortcut
        let parts = shortcut.split(separator: " + ").map { String($0) }
        
        // Check if this is a modifier+key shortcut (not modifier-only)
        let hasRegularKey = parts.contains { part in
            !["⌃", "⌥", "⇧", "⌘", "Left ⌃", "Right ⌃", "Left ⌥", "Right ⌥", "Left ⇧", "Right ⇧", "Left ⌘", "Right ⌘"].contains(part)
        }
        
        if !hasRegularKey {
            return false // This is a modifier-only shortcut, not handled here
        }
        
        // Check if the key matches
        let requiredKey = extractRequiredKey(from: parts)
        if !keyMatches(required: requiredKey, event: event) {
            return false
        }
        
        // Check if the modifiers match (use the event's modifiers, not currentModifierState)
        let requiredModifiers = extractRequiredModifiers(from: parts)
        let modifiersMatch = modifiersMatch(required: requiredModifiers, current: event.modifierFlags)
        
        return modifiersMatch
    }
    
    private func shouldActivateForEvent(_ event: NSEvent) -> Bool {
        let shortcut = sharedData.activationShortcut
        
        // Parse the shortcut string
        let parts = shortcut.split(separator: " + ").map { String($0) }
        
        // Check if this is a key event we should handle
        // For flagsChanged events, we only handle modifier-only shortcuts
        if event.type == .flagsChanged {
            return shouldActivateForModifierOnlyShortcut(parts: parts, event: event)
        } else if event.type == .keyDown {
            return shouldActivateForKeyDownShortcut(parts: parts, event: event)
        }
        
        return false
    }
    
    private func shouldActivateForModifierOnlyShortcut(parts: [String], event: NSEvent) -> Bool {
        // Check if this is a modifier-only shortcut (no regular key)
        let hasRegularKey = parts.contains { part in
            !["⌃", "⌥", "⇧", "⌘", "Left ⌃", "Right ⌃", "Left ⌥", "Right ⌥", "Left ⇧", "Right ⇧", "Left ⌘", "Right ⌘"].contains(part)
        }
        
        if hasRegularKey {
            return false // Not a modifier-only shortcut
        }
        
        // For single left/right modifier shortcuts
        if parts.count == 1 {
            let part = parts[0]
            switch part {
            case "Left ⌘":
                return event.keyCode == 55 && event.modifierFlags.contains(.command)
            case "Right ⌘":
                return event.keyCode == 54 && event.modifierFlags.contains(.command)
            case "Left ⇧":
                return event.keyCode == 56 && event.modifierFlags.contains(.shift)
            case "Right ⇧":
                return event.keyCode == 60 && event.modifierFlags.contains(.shift)
            case "Left ⌃":
                return event.keyCode == 59 && event.modifierFlags.contains(.control)
            case "Right ⌃":
                return event.keyCode == 62 && event.modifierFlags.contains(.control)
            case "Left ⌥":
                return event.keyCode == 58 && event.modifierFlags.contains(.option)
            case "Right ⌥":
                return event.keyCode == 61 && event.modifierFlags.contains(.option)
            case "⌘":
                return (event.keyCode == 54 || event.keyCode == 55) && event.modifierFlags.contains(.command)
            case "⇧":
                return (event.keyCode == 56 || event.keyCode == 60) && event.modifierFlags.contains(.shift)
            case "⌃":
                return (event.keyCode == 59 || event.keyCode == 62) && event.modifierFlags.contains(.control)
            case "⌥":
                return (event.keyCode == 58 || event.keyCode == 61) && event.modifierFlags.contains(.option)
            default:
                break
            }
        }
        
        // For modifier-only shortcuts (multiple modifiers), we need to check if ALL required modifiers are present
        let requiredModifiers = extractRequiredModifiers(from: parts)
        let currentModifiers = event.modifierFlags
        
        // Check if the required modifiers match
        if !modifiersMatch(required: requiredModifiers, current: currentModifiers) {
            return false
        }
        
        // For multi-modifier shortcuts, we just check if any of the modifier keys was pressed
        if requiredModifiers.contains(.command) && (event.keyCode == 54 || event.keyCode == 55) {
            return true
        }
        if requiredModifiers.contains(.shift) && (event.keyCode == 56 || event.keyCode == 60) {
            return true
        }
        if requiredModifiers.contains(.control) && (event.keyCode == 59 || event.keyCode == 62) {
            return true
        }
        if requiredModifiers.contains(.option) && (event.keyCode == 58 || event.keyCode == 61) {
            return true
        }
        
        return false
    }
    
    private func shouldActivateForKeyDownShortcut(parts: [String], event: NSEvent) -> Bool {
        // Check modifiers match
        let requiredModifiers = extractRequiredModifiers(from: parts)
        let currentModifiers = event.modifierFlags
        
        if !modifiersMatch(required: requiredModifiers, current: currentModifiers) {
            return false
        }
        
        // Check if key matches
        let requiredKey = extractRequiredKey(from: parts)
        return keyMatches(required: requiredKey, event: event)
    }
    
    private func startCooldown() {
        // Cancel any existing cooldown timer
        cooldownTimer?.cancel()
        
        // Set cooldown state
        isInCooldown = true
        
        // Create new cooldown timer for 1 second
        cooldownTimer = DispatchWorkItem {
            DispatchQueue.main.async {
                self.isInCooldown = false
            }
        }
        
        // Execute the cooldown timer after 1 second
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: cooldownTimer!)
    }
    
    private func extractRequiredModifiers(from parts: [String]) -> NSEvent.ModifierFlags {
        var modifiers: NSEvent.ModifierFlags = []
        
        for part in parts {
            switch part {
            case "⌃": modifiers.insert(.control)
            case "⌥": modifiers.insert(.option)
            case "⇧": modifiers.insert(.shift)
            case "⌘": modifiers.insert(.command)
            default: break
            }
        }
        
        return modifiers
    }
    
    private func extractRequiredKey(from parts: [String]) -> String? {
        return parts.first { part in
            !["⌃", "⌥", "⇧", "⌘", "Left ⌃", "Right ⌃", "Left ⌥", "Right ⌥", "Left ⇧", "Right ⇧", "Left ⌘", "Right ⌘"].contains(part)
        }
    }
    
    private func modifiersMatch(required: NSEvent.ModifierFlags, current: NSEvent.ModifierFlags) -> Bool {
        // For activation, we want exact matching of the relevant modifiers
        // Filter out system flags that we don't care about
        let relevantFlags: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        let requiredRelevant = required.intersection(relevantFlags)
        let currentRelevant = current.intersection(relevantFlags)
        
        return requiredRelevant == currentRelevant
    }
    
    private func keyMatches(required: String?, event: NSEvent) -> Bool {
        guard let requiredKey = required else {
            return false // No key specified
        }
        
        // Convert event keyCode to key name and compare
        let eventKeyName = keyCodeToName(event.keyCode)
        return eventKeyName == requiredKey
    }
    
    // MARK: - Search Activation Shortcut Detection
    
    private func shouldActivateSearchForEvent(_ event: NSEvent) -> Bool {
        let shortcut = sharedData.searchActivationShortcut
        
        // Parse the shortcut string
        let parts = shortcut.split(separator: " + ").map { String($0) }
        
        // Check if this is a key event we should handle
        // For flagsChanged events, we only handle modifier-only shortcuts
        if event.type == .flagsChanged {
            return shouldActivateSearchForModifierOnlyShortcut(parts: parts, event: event)
        } else if event.type == .keyDown {
            return shouldActivateSearchForKeyDownShortcut(parts: parts, event: event)
        }
        
        return false
    }
    
    private func shouldActivateSearchForKeyDownWithCurrentModifiers(_ event: NSEvent) -> Bool {
        let shortcut = sharedData.searchActivationShortcut
        let parts = shortcut.split(separator: " + ").map { String($0) }
        
        // Check if this is a modifier+key shortcut (not modifier-only)
        let hasRegularKey = parts.contains { part in
            !["⌃", "⌥", "⇧", "⌘", "Left ⌃", "Right ⌃", "Left ⌥", "Right ⌥", "Left ⇧", "Right ⇧", "Left ⌘", "Right ⌘"].contains(part)
        }
        
        if !hasRegularKey {
            return false // This is a modifier-only shortcut, not handled here
        }
        
        // Check if the key matches
        let requiredKey = extractRequiredKey(from: parts)
        if !keyMatches(required: requiredKey, event: event) {
            return false
        }
        
        // Check if the modifiers match (use the event's modifiers, not currentModifierState)
        let requiredModifiers = extractRequiredModifiers(from: parts)
        let modifiersMatch = modifiersMatch(required: requiredModifiers, current: event.modifierFlags)
        
        return modifiersMatch
    }
    
    private func shouldActivateScrollModeForKeyDownWithCurrentModifiers(_ event: NSEvent) -> Bool {
        let shortcut = sharedData.scrollModeShortcut
        let parts = shortcut.split(separator: " + ").map { String($0) }
        
        // Check if this is a modifier+key shortcut (not modifier-only)
        let hasRegularKey = parts.contains { part in
            !["⌃", "⌥", "⇧", "⌘", "Left ⌃", "Right ⌃", "Left ⌥", "Right ⌥", "Left ⇧", "Right ⇧", "Left ⌘", "Right ⌘"].contains(part)
        }
        
        if !hasRegularKey {
            return false // This is a modifier-only shortcut, not handled here
        }
        
        // Check if the key matches
        let requiredKey = extractRequiredKey(from: parts)
        if !keyMatches(required: requiredKey, event: event) {
            return false
        }
        
        // Check if the modifiers match (use the event's modifiers, not currentModifierState)
        let requiredModifiers = extractRequiredModifiers(from: parts)
        let modifiersMatch = modifiersMatch(required: requiredModifiers, current: event.modifierFlags)
        
        return modifiersMatch
    }
    
    private func shouldActivateSearchForModifierOnlyShortcut(parts: [String], event: NSEvent) -> Bool {
        // Check if this is a modifier-only shortcut (no regular key)
        let hasRegularKey = parts.contains { part in
            !["⌃", "⌥", "⇧", "⌘", "Left ⌃", "Right ⌃", "Left ⌥", "Right ⌥", "Left ⇧", "Right ⇧", "Left ⌘", "Right ⌘"].contains(part)
        }
        
        if hasRegularKey {
            return false // Not a modifier-only shortcut
        }
        
        // For single left/right modifier shortcuts
        if parts.count == 1 {
            let part = parts[0]
            switch part {
            case "Left ⌘":
                return event.keyCode == 55 && event.modifierFlags.contains(.command)
            case "Right ⌘":
                return event.keyCode == 54 && event.modifierFlags.contains(.command)
            case "Left ⇧":
                return event.keyCode == 56 && event.modifierFlags.contains(.shift)
            case "Right ⇧":
                return event.keyCode == 60 && event.modifierFlags.contains(.shift)
            case "Left ⌃":
                return event.keyCode == 59 && event.modifierFlags.contains(.control)
            case "Right ⌃":
                return event.keyCode == 62 && event.modifierFlags.contains(.control)
            case "Left ⌥":
                return event.keyCode == 58 && event.modifierFlags.contains(.option)
            case "Right ⌥":
                return event.keyCode == 61 && event.modifierFlags.contains(.option)
            case "⌘":
                return (event.keyCode == 54 || event.keyCode == 55) && event.modifierFlags.contains(.command)
            case "⇧":
                return (event.keyCode == 56 || event.keyCode == 60) && event.modifierFlags.contains(.shift)
            case "⌃":
                return (event.keyCode == 59 || event.keyCode == 62) && event.modifierFlags.contains(.control)
            case "⌥":
                return (event.keyCode == 58 || event.keyCode == 61) && event.modifierFlags.contains(.option)
            default:
                return false
            }
        }
        
        // For multiple modifier shortcuts
        return modifiersMatch(required: extractRequiredModifiers(from: parts), current: event.modifierFlags)
    }
    
    private func shouldActivateSearchForKeyDownShortcut(parts: [String], event: NSEvent) -> Bool {
        // Check if this is a modifier+key shortcut (not modifier-only)
        let hasRegularKey = parts.contains { part in
            !["⌃", "⌥", "⇧", "⌘", "Left ⌃", "Right ⌃", "Left ⌥", "Right ⌥", "Left ⇧", "Right ⇧", "Left ⌘", "Right ⌘"].contains(part)
        }
        
        if !hasRegularKey {
            return false // This is a modifier-only shortcut, not handled here
        }
        
        // Check if the key matches
        let requiredKey = extractRequiredKey(from: parts)
        if !keyMatches(required: requiredKey, event: event) {
            return false
        }
        
        // Check if the modifiers match
        let requiredModifiers = extractRequiredModifiers(from: parts)
        let modifiersMatch = modifiersMatch(required: requiredModifiers, current: event.modifierFlags)
        
        return modifiersMatch
    }
    
    // MARK: - Debugging and Recovery System
    
    private func setupSystemEventObservers() {
        print("🔧 [OctoCmd] Setting up system event observers for debugging")
        
        // Observe system sleep/wake events
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        // Observe screen lock/unlock events
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidLock),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidUnlock),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
        
        // Start periodic health checks
        startEventTapHealthMonitoring()
        startAccessibilityMonitoring()
    }
    
    @objc private func systemWillSleep() {
        print("💤 [OctoCmd] System going to sleep - event tap may be disabled")
        eventTapHealthTimer?.invalidate()
        accessibilityCheckTimer?.invalidate()
    }
    
    @objc private func systemDidWake() {
        print("🌅 [OctoCmd] System woke up - checking event tap status")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.checkAndRecoverEventTap()
            self.startEventTapHealthMonitoring()
            self.startAccessibilityMonitoring()
        }
    }
    
    @objc private func screenDidLock() {
        print("🔒 [OctoCmd] Screen locked - event tap may be affected")
    }
    
    @objc private func screenDidUnlock() {
        print("🔓 [OctoCmd] Screen unlocked - checking event tap status")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.checkAndRecoverEventTap()
        }
    }
    
    private func startEventTapHealthMonitoring() {
        eventTapHealthTimer?.invalidate()
        eventTapHealthTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            self.checkEventTapHealth()
        }
        print("🩺 [OctoCmd] Started event tap health monitoring (30s intervals)")
    }
    
    private func startAccessibilityMonitoring() {
        accessibilityCheckTimer?.invalidate()
        accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
            self.checkAccessibilityPermissions()
        }
        print("♿ [OctoCmd] Started accessibility permission monitoring (60s intervals)")
    }
    
    private func checkEventTapHealth() {
        guard let eventTap = self.eventTap else {
            print("❌ [OctoCmd] Event tap is nil - attempting recovery")
            self.recoverEventTap()
            return
        }
        
        // Skip health check if we're in active modes to prevent interference
        if self.sharedData.isSearchMode || self.sharedData.isScrollMode {
            print("⏸️ [OctoCmd] Skipping event tap health check - app is in active mode")
            return
        }
        
        // Check if event tap is enabled
        let isEnabled = CGEvent.tapIsEnabled(tap: eventTap)
        if !isEnabled {
            print("❌ [OctoCmd] Event tap is disabled - attempting recovery")
            self.recoverEventTap()
            return
        }
        
        // Check if we've received events recently (indicates event tap is working)
        let timeSinceLastEvent = Date().timeIntervalSince(lastEventTapTime)
        if timeSinceLastEvent > 300 { // 5 minutes without any events
            print("⚠️ [OctoCmd] No events received for \(Int(timeSinceLastEvent))s - event tap may be stale")
            // Don't recover immediately as user might just not be using keyboard
            // But log the warning for debugging
        } else {
            print("✅ [OctoCmd] Event tap health check passed")
        }
    }
    
    private func checkAccessibilityPermissions() {
        let isTrusted = AXIsProcessTrusted()
        if !isTrusted {
            print("❌ [OctoCmd] Accessibility permissions lost!")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permissions Lost"
                alert.informativeText = "OctoCmd has lost accessibility permissions. Keyboard shortcuts will not work until permissions are restored."
                alert.alertStyle = .critical
                alert.addButton(withTitle: "Open System Preferences")
                alert.addButton(withTitle: "OK")
                
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        } else {
            print("✅ [OctoCmd] Accessibility permissions check passed")
        }
    }
    
    private func checkAndRecoverEventTap() {
        let isTrusted = AXIsProcessTrusted()
        if !isTrusted {
            print("❌ [OctoCmd] Cannot recover - accessibility permissions not granted")
            return
        }
        
        if let eventTap = self.eventTap {
            let isEnabled = CGEvent.tapIsEnabled(tap: eventTap)
            if !isEnabled {
                print("🔄 [OctoCmd] Event tap disabled - attempting to re-enable")
                CGEvent.tapEnable(tap: eventTap, enable: true)
                
                // Verify it was re-enabled
                if CGEvent.tapIsEnabled(tap: eventTap) {
                    print("✅ [OctoCmd] Event tap successfully re-enabled")
                    eventTapFailureCount = 0
                } else {
                    print("❌ [OctoCmd] Failed to re-enable event tap - recreating")
                    recoverEventTap()
                }
            }
        } else {
            print("🔄 [OctoCmd] Event tap is nil - recreating")
            recoverEventTap()
        }
    }
    
    func recoverEventTap() {
        eventTapFailureCount += 1
        print("🚨 [OctoCmd] Attempting event tap recovery (attempt \(eventTapFailureCount))")
        
        if eventTapFailureCount > 5 {
            print("💀 [OctoCmd] Too many recovery attempts - showing error to user")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Keyboard Shortcut System Failed"
                alert.informativeText = "OctoCmd's keyboard monitoring system has failed multiple times. Please restart the application."
                alert.alertStyle = .critical
                alert.addButton(withTitle: "Restart OctoCmd")
                alert.addButton(withTitle: "Continue")
                
                if alert.runModal() == .alertFirstButtonReturn {
                    NSApp.terminate(nil)
                }
            }
            return
        }
        
        // Clean up existing event tap
        if let existingTap = self.eventTap {
            CGEvent.tapEnable(tap: existingTap, enable: false)
            CFMachPortInvalidate(existingTap)
            self.eventTap = nil
        }
        
        // Wait a moment then recreate
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.setupEventTap()
            if self.eventTap != nil {
                print("✅ [OctoCmd] Event tap recovery successful")
                self.eventTapFailureCount = 0
            } else {
                print("❌ [OctoCmd] Event tap recovery failed")
            }
        }
    }
    
    // MARK: - Scroll Mode Global Monitors (Fallback)
    func startScrollModeGlobalMonitors() {
        // Avoid duplicate monitors
        if scrollModeGlobalKeyDownMonitor != nil || scrollModeGlobalKeyUpMonitor != nil {
            return
        }
        print("[ScrollMode] Starting global monitors (fallback)")
        scrollModeGlobalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self, self.sharedData.isScrollMode else { return }
            let keyCode = event.keyCode
            let scrollSpeed: Double = 2.0
            print("[ScrollMode][Global] keyDown keyCode=\(keyCode)")
            switch keyCode {
            case 38: // J
                self.sharedData.setScrollVelocity(deltaY: -scrollSpeed, deltaX: 0)
            case 40: // K
                self.sharedData.setScrollVelocity(deltaY: scrollSpeed, deltaX: 0)
            case 125: // Down
                self.sharedData.setScrollVelocity(deltaY: -scrollSpeed, deltaX: 0)
            case 126: // Up
                self.sharedData.setScrollVelocity(deltaY: scrollSpeed, deltaX: 0)
            case 4, 123: // H or Left
                self.sharedData.setScrollVelocity(deltaY: 0, deltaX: scrollSpeed)
            case 37, 124: // L or Right
                self.sharedData.setScrollVelocity(deltaY: 0, deltaX: -scrollSpeed)
            case 48: // Tab
                self.sharedData.focusNextScrollArea()
            case 53: // ESC
                self.sharedData.exitScrollMode()
            default:
                break
            }
        }
        scrollModeGlobalKeyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyUp]) { [weak self] event in
            guard let self = self, self.sharedData.isScrollMode else { return }
            let keyCode = event.keyCode
            print("[ScrollMode][Global] keyUp keyCode=\(keyCode)")
            switch keyCode {
            case 38, 40, 125, 126, 4, 37, 123, 124:
                self.sharedData.stopScrolling()
            default:
                break
            }
        }
    }

    func stopScrollModeGlobalMonitors() {
        if let m = scrollModeGlobalKeyDownMonitor { NSEvent.removeMonitor(m); scrollModeGlobalKeyDownMonitor = nil }
        if let m = scrollModeGlobalKeyUpMonitor { NSEvent.removeMonitor(m); scrollModeGlobalKeyUpMonitor = nil }
        print("[ScrollMode] Stopped global monitors (fallback)")
    }

    deinit {
        // Clean up observers and timers
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default.removeObserver(self)
        eventTapHealthTimer?.invalidate()
        accessibilityCheckTimer?.invalidate()
        
        // Clean up event tap
        if let eventTap = self.eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
    }
} 
