//
//  SharedData.swift
//  OctoCmd
//
//  Created by Huy Tran on 4/26/23.
//

import Cocoa
import Accessibility

// Overlay window to visualize found elements
class ElementOverlayWindow: NSWindow {
    var elementRects: [CGRect] = []
    var elementTexts: [String] = []

    init() {
        super.init(
            contentRect: NSScreen.main?.frame ?? CGRect.zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = NSWindow.Level.screenSaver
        self.backgroundColor = NSColor.clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let overlayView = ElementOverlayView()
        self.contentView = overlayView
    }

    func showElements(_ rects: [CGRect], texts: [String]) {
        self.elementRects = rects
        self.elementTexts = texts

        if let overlayView = self.contentView as? ElementOverlayView {
            overlayView.elementRects = rects
            overlayView.elementTexts = texts
            overlayView.needsDisplay = true
        }

        self.orderFrontRegardless()

        // Auto-hide after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.orderOut(nil)
        }
    }
}

// Clickable Elements Overlay Window
class ClickableElementsOverlayWindow: NSWindow {
    var clickableElements: [DesktopTextSearcher.AccessibilityTextElement] = []
    var highlightedLabel: String? = nil
    var filterPrefix: String? = nil

    // Don't accept key events - let the main search window handle them
    override var canBecomeKey: Bool { false }

    init() {
        let screenFrame = NSScreen.main?.frame ?? CGRect.zero
        print("Creating clickable elements overlay window with frame: \(screenFrame)")

        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = NSWindow.Level.floating
        self.backgroundColor = NSColor.clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let overlayView = ClickableElementsOverlayView()
        overlayView.frame = screenFrame
        self.contentView = overlayView

        print("Clickable elements overlay window created at level: \(self.level.rawValue)")
    }

    func showClickableElements(_ elements: [DesktopTextSearcher.AccessibilityTextElement], highlightedLabel: String? = nil) {
        self.clickableElements = elements
        self.highlightedLabel = highlightedLabel

        if let overlayView = self.contentView as? ClickableElementsOverlayView {
            overlayView.clickableElements = elements
            overlayView.highlightedLabel = highlightedLabel
            overlayView.needsDisplay = true
        }

        self.orderFrontRegardless()
        self.makeKeyAndOrderFront(nil)
        print("Clickable elements overlay window shown with \(elements.count) elements")
    }

    func updateHighlight(_ label: String?) {
        self.highlightedLabel = label
        if let overlayView = self.contentView as? ClickableElementsOverlayView {
            overlayView.highlightedLabel = label
            overlayView.needsDisplay = true
        }
    }

    func updateFilter(_ prefix: String?) {
        self.filterPrefix = prefix
        if let overlayView = self.contentView as? ClickableElementsOverlayView {
            overlayView.filterPrefix = prefix
            overlayView.needsDisplay = true
        }
    }

    func hideOverlay() {
        self.orderOut(nil)
        print("Clickable elements overlay window hidden")
    }
}

class ClickableElementsOverlayView: NSView {
    var clickableElements: [DesktopTextSearcher.AccessibilityTextElement] = []
    var highlightedLabel: String? = nil
    var filterPrefix: String? = nil
    let labelPadding: CGFloat = 2.0
    let fontSize: CGFloat = 9.0 // Smaller font size

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Clear the view
        NSColor.clear.setFill()
        dirtyRect.fill()

        let screenHeight = NSScreen.main?.frame.height ?? 1440

        // Draw labels for each clickable element
        for element in clickableElements {
            guard let label = element.label else { continue }

            if let prefix = filterPrefix?.lowercased(), !label.lowercased().hasPrefix(prefix) {
                continue
            }

            let rect = element.boundingRect
            let isHighlighted = (highlightedLabel?.lowercased() == label.lowercased())

            // Convert screen coordinates to NSView coordinates (flip Y-axis)
            // Position hint at top-left corner of element rectangle
            let labelPosition = CGPoint(
                x: rect.origin.x, // Position at left edge of element
                y: screenHeight - rect.origin.y // Position at top of element
            )

            // Create smaller label background
            let labelSize = CGSize(width: 18, height: 14) // Smaller size for labels
            let labelRect = CGRect(
                x: labelPosition.x,
                y: labelPosition.y - labelPadding/2,
                width: labelSize.width,
                height: labelSize.height
            )

            // Create rounded rectangle path
            let cornerRadius: CGFloat = 3.0
            let roundedRect = NSBezierPath(roundedRect: labelRect, xRadius: cornerRadius, yRadius: cornerRadius)
            
            // Save graphics state for shadow
            NSGraphicsContext.saveGraphicsState()
            
            // Add shadow
            let shadow = NSShadow()
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.shadowBlurRadius = 3.0
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
            shadow.set()

            // Draw gradient background
            if isHighlighted {
                // Red gradient for highlighted
                let gradient = NSGradient(colors: [
                    NSColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 0.9),
                    NSColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 0.9)
                ])
                gradient?.draw(in: roundedRect, angle: 90)
            } else {
                // Yellow gradient for normal labels
                let gradient = NSGradient(colors: [
                    NSColor(red: 1.0, green: 1.0, blue: 0.4, alpha: 0.9),
                    NSColor(red: 0.9, green: 0.8, blue: 0.2, alpha: 0.9)
                ])
                gradient?.draw(in: roundedRect, angle: 90)
            }
            
            // Restore graphics state
            NSGraphicsContext.restoreGraphicsState()

            // Draw subtle border
            if isHighlighted {
                NSColor(red: 0.6, green: 0.1, blue: 0.1, alpha: 0.8).setStroke()
            } else {
                NSColor(red: 0.7, green: 0.6, blue: 0.1, alpha: 0.6).setStroke()
            }
            roundedRect.lineWidth = 0.5
            roundedRect.stroke()



            // Draw label text with better positioning
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: fontSize),
                .foregroundColor: NSColor.black
            ]

            let attributedLabel = NSAttributedString(string: label, attributes: attributes)
            let textSize = attributedLabel.size()
            let textRect = CGRect(
                x: labelRect.midX - textSize.width/2,
                y: labelRect.midY - textSize.height/2,
                width: textSize.width,
                height: textSize.height
            )
            attributedLabel.draw(in: textRect)
        }
    }
}

// Text Search Overlay Window
class TextSearchOverlayWindow: NSWindow {
    var searchMatches: [DesktopTextSearcher.TextMatch] = []
    var selectedIndex: Int = 0

    // Don't accept key events - let the main search window handle them
    override var canBecomeKey: Bool { false }

    init() {
        let screenFrame = NSScreen.main?.frame ?? CGRect.zero
        print("Creating full-screen overlay window with frame: \(screenFrame)")

        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = NSWindow.Level.floating // Try floating level first, then we can escalate if needed
        self.backgroundColor = NSColor.clear // Transparent background
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let overlayView = TextSearchOverlayView()
        overlayView.frame = screenFrame
        self.contentView = overlayView

        print("Overlay window created at level: \(self.level.rawValue)")
    }

    func showSearchResults(_ matches: [DesktopTextSearcher.TextMatch], selectedIndex: Int = 0) {
        self.searchMatches = matches
        self.selectedIndex = selectedIndex

        if let overlayView = self.contentView as? TextSearchOverlayView {
            overlayView.searchMatches = matches
            overlayView.selectedIndex = selectedIndex
            overlayView.needsDisplay = true
        }

        self.orderFrontRegardless()
        self.makeKeyAndOrderFront(nil)
        print("Overlay window shown with \(matches.count) matches")
        print("Window is visible: \(self.isVisible)")
        print("Window frame: \(self.frame)")
        print("Window level: \(self.level.rawValue)")
    }

    func updateSelection(_ newIndex: Int) {
        print("🔄 updateSelection called with newIndex: \(newIndex)")
        self.selectedIndex = newIndex
        if let overlayView = self.contentView as? TextSearchOverlayView {
            print("🎯 Setting overlayView.selectedIndex to \(newIndex)")
            overlayView.selectedIndex = newIndex

            // Force redraw immediately with multiple methods
            overlayView.needsDisplay = true
            overlayView.setNeedsDisplay(overlayView.bounds)

            DispatchQueue.main.async {
                print("🖼️ Forcing display() call")
                overlayView.display()
            }
        } else {
            print("❌ overlayView is nil or wrong type!")
        }
    }

    func hideOverlay() {
        self.orderOut(nil)
        print("Overlay window hidden")
    }
}

class TextSearchOverlayView: NSView {
    var searchMatches: [DesktopTextSearcher.TextMatch] = []
    var selectedIndex: Int = 0
    var overlayPadding = 4.0

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let timestamp = Date().timeIntervalSince1970
        print("🎨 DRAW called at \(timestamp) - \(searchMatches.count) matches, selected: \(selectedIndex)")
        print("Overlay view frame: \(self.frame)")
        print("Dirty rect: \(dirtyRect)")

        // Clear the view
        NSColor.clear.setFill()
        dirtyRect.fill()


        // Draw rectangles for each text match
        for (index, match) in searchMatches.enumerated() {
            let rect = match.screenPosition

            // Convert screen coordinates to NSView coordinates (flip Y-axis for drawing)
            let screenHeight = NSScreen.main?.frame.height ?? 1440
            let overlayRect = CGRect(
                x: rect.origin.x - overlayPadding,
                y: screenHeight - rect.origin.y - rect.height - overlayPadding,
                width: rect.width + overlayPadding * 2,
                height: rect.height + overlayPadding * 2
            )

            let isSelected = (index == selectedIndex)
            print("🔲 Drawing match \(index + 1): '\(match.text)' - isSelected: \(isSelected) (selectedIndex: \(selectedIndex))")

            // Draw background
            if isSelected {
                print("🟢 Drawing GREEN rectangle for selected match")
                NSColor.red.withAlphaComponent(0.4).setFill()  // Selected = green
            } else {
                print("🔵 Drawing BLUE rectangle for regular match")
                NSColor.purple.withAlphaComponent(0.3).setFill()   // Regular = blue
            }
            overlayRect.fill()

            // Draw border
            if isSelected {
                NSColor.red.withAlphaComponent(0.9).setStroke()  // Selected = green
            } else {
                NSColor.purple.withAlphaComponent(0.8).setStroke()   // Regular = blue
            }
            let borderPath = NSBezierPath(rect: overlayRect)
            borderPath.lineWidth = isSelected ? 2.0 : 1.0
            borderPath.stroke()
        }
    }
}

class ElementOverlayView: NSView {
    var elementRects: [CGRect] = []
    var elementTexts: [String] = []

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Clear the view
        NSColor.clear.setFill()
        dirtyRect.fill()

        // Draw rectangles for each found element
        for (index, rect) in elementRects.enumerated() {
            // Convert screen coordinates to view coordinates
            let viewRect = self.convert(rect, from: nil)

            // Draw semi-transparent red rectangle
            NSColor.red.withAlphaComponent(0.3).setFill()
            viewRect.fill()

            // Draw border
            NSColor.red.withAlphaComponent(0.8).setStroke()
            let borderPath = NSBezierPath(rect: viewRect)
            borderPath.lineWidth = 1.0
            borderPath.stroke()

            // Draw text label if we have one
            if index < elementTexts.count && !elementTexts[index].isEmpty {
                let text = elementTexts[index]
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: 12),
                    .foregroundColor: NSColor.white,
                    .backgroundColor: NSColor.black.withAlphaComponent(0.7)
                ]

                let attributedText = NSAttributedString(string: text, attributes: attributes)
                let textRect = CGRect(x: viewRect.minX, y: viewRect.maxY + 2, width: 200, height: 20)
                attributedText.draw(in: textRect)
            }
        }
    }
}

// Scroll Mode Overlay Window
class ScrollModeOverlayWindow: NSWindow {

    // Don't accept key events - let the main app handle them
    override var canBecomeKey: Bool { false }

    init() {
        // Use union of all screens so overlay exists even when app isn't active
        let screens = NSScreen.screens
        let screenFrame = screens.reduce(CGRect.null) { $0.union($1.frame) }
        print("Creating scroll mode overlay window with frame: \(screenFrame)")

        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // Use a high window level so border renders above apps
        self.level = NSWindow.Level.screenSaver
        self.backgroundColor = NSColor.clear // Transparent background
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let overlayView = ScrollModeOverlayView()
        overlayView.frame = screenFrame
        overlayView.wantsLayer = true
        self.contentView = overlayView

        print("Scroll mode overlay window created at level: \(self.level.rawValue)")
    }

    func showScrollModeIndicator(_ rect: CGRect) {
        if let overlayView = self.contentView as? ScrollModeOverlayView {
            overlayView.highlightedBounds = rect
            overlayView.needsDisplay = true
        }

        self.orderFrontRegardless()
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        print("Scroll mode overlay window shown")
    }

    func hideOverlay() {
        self.orderOut(nil)
        print("Scroll mode overlay window hidden")
    }
}

class ScrollModeOverlayView: NSView {
    var highlightedBounds: CGRect?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        print("🎨 SCROLL MODE OVERLAY DRAW called")

        // Clear the view
        NSColor.clear.setFill()
        dirtyRect.fill()

        // Only draw if we have bounds to highlight
        guard let windowBounds = highlightedBounds else {
            print("No highlighted bounds available")
            return
        }

        // Accessibility coordinates are top-left-origin. Convert to bottom-left-origin first,
        // then convert from screen to this window's coordinate space.
        guard let window = self.window else { return }
        let globalMaxY = NSScreen.screens.map { $0.frame.maxY }.max() ?? (NSScreen.main?.frame.maxY ?? 0)
        let flippedScreenRect = NSRect(
            x: windowBounds.origin.x,
            y: globalMaxY - windowBounds.origin.y - windowBounds.height,
            width: windowBounds.width,
            height: windowBounds.height
        )
        let viewWindowBounds = window.convertFromScreen(flippedScreenRect)

        // Draw blue rounded border around the scroll area
        let borderInset: CGFloat = -6.0 // Negative inset to draw outside the window
        let borderRect = viewWindowBounds.insetBy(dx: borderInset, dy: borderInset)
        let cornerRadius: CGFloat = 5.0
        let lineWidth: CGFloat = 4.0

        // Create the rounded border path
        let borderPath = NSBezierPath(roundedRect: borderRect, xRadius: cornerRadius, yRadius: cornerRadius)
        borderPath.lineWidth = lineWidth

        // Set blue color and draw the border
        NSColor.systemBlue.withAlphaComponent(0.95).setStroke()
        borderPath.stroke()

        print("Drew border around area at: \(viewWindowBounds)")
    }
}

enum PageType {
    case mainApps
    case skippedApps
    case groups
    case settings
}

struct AppGroup: Codable, Identifiable {
    let id = UUID()
    var name: String
    var appNames: [String]

    init(name: String, appNames: [String] = []) {
        self.name = name
        self.appNames = appNames
    }
}

/// A shared object to store data between different parts of the application.
final class SharedData: ObservableObject {
    /// An array of process IDs that should be ignored when updating the windows list.
    @Published var ignored: [Int] = (UserDefaults.standard.array(forKey: "tentacle_Ignored") as? [Int] ?? [])
    @Published var noActivation: [String] = (UserDefaults.standard.array(forKey: "tentacle_NoActivation") as? [String] ?? [])
    @Published var activationShortcut: String = (UserDefaults.standard.string(forKey: "tentacle_ActivationShortcut") ?? "⌃ + ⌥")
    @Published var isRecordingShortcut: Bool = false
    @Published var searchActivationShortcut: String = (UserDefaults.standard.string(forKey: "tentacle_SearchActivationShortcut") ?? "⇧ + Space")
    @Published var isRecordingSearchShortcut: Bool = false
    @Published var currentPage: PageType = .mainApps
    @Published var isTextInputActive: Bool = false
    @Published var isSearchMode: Bool = false
    @Published var isScrollMode: Bool = false
    @Published var scrollModeShortcut: String = (UserDefaults.standard.string(forKey: "tentacle_ScrollModeShortcut") ?? "⌃ + S")
    @Published var isRecordingScrollModeShortcut: Bool = false

    // Smooth scrolling properties
    private var scrollTimer: Timer?
    private var currentScrollVelocityY: Double = 0.0
    private var currentScrollVelocityX: Double = 0.0
    private var targetScrollVelocityY: Double = 0.0
    private var targetScrollVelocityX: Double = 0.0
    private let baseScrollSpeed: Double = 3.0
    private let maxScrollSpeed: Double = 15.0
    private let acceleration: Double = 1.2
    private let deceleration: Double = 0.85
    @Published var searchQuery: String = ""
    @Published var textSearchResults: [DesktopTextSearcher.TextMatch] = []
    @Published var isSearching: Bool = false
    @Published var selectedResultIndex: Int = 0 {
        didSet {
            // Update overlay whenever selection changes
            if selectedResultIndex != oldValue {
                print("📍 selectedResultIndex changed from \(oldValue) to \(selectedResultIndex)")
                updateTextSearchSelection()
            }
        }
    }

    /// An array of `WindowDef` structs representing the visible windows.
    @Published var windows: [WindowDef] = []

    @Published var isAccessibilityEnabled: Bool = false
    private var accessibilityCheckTimer: Timer?

    /// The last process ID that was used to update the windows list.
    @Published var lastPid: Int = -1

    /// Cache for app name to letter assignments to ensure deterministic letter assignment
    private var appLetterCache: [String: String] = {
        if let data = UserDefaults.standard.data(forKey: "tentacle_AppLetterCache"),
           let cache = try? JSONDecoder().decode([String: String].self, from: data) {
            return cache
        }
        return [:]
    }()

    /// Set of pinned app names that should always be shown even when not open
    @Published var pinnedApps: Set<String> = Set<String>()

    /// Array of app groups created by the user
    @Published var appGroups: [AppGroup] = []

    // Overlay window for visualizing found elements
    private var overlayWindow: ElementOverlayWindow?

    // Text search overlay window
    private var textSearchOverlay: TextSearchOverlayWindow?

    // Clickable elements overlay window
    private var clickableElementsOverlay: ClickableElementsOverlayWindow?

    // Scroll mode overlay window
    private var scrollModeOverlay: ScrollModeOverlayWindow?
    private var scrollAreas: [CGRect] = []
    private var currentScrollAreaIndex: Int = 0

    /// Cache for app name to bundle identifier mapping for pinned apps
    private var appBundleIdentifierCache: [String: String] = {
        if let data = UserDefaults.standard.data(forKey: "tentacle_AppBundleIdentifierCache"),
           let cache = try? JSONDecoder().decode([String: String].self, from: data) {
            return cache
        }
        return [:]
    }()

    // MARK: Initializers

    init() {
        // Load pinned apps from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "tentacle_PinnedApps"),
           let pinned = try? JSONDecoder().decode(Set<String>.self, from: data) {
            self.pinnedApps = pinned
        }

        // Load app groups from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "tentacle_AppGroups"),
           let groups = try? JSONDecoder().decode([AppGroup].self, from: data) {
            self.appGroups = groups
        }

        self.windows = self.getWindowsList()

        // Check for accessibility permissions
        checkAccessibilityPermissions()

        // Periodically check for accessibility permissions
        accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.checkAccessibilityPermissions()
        }
    }

    func checkAccessibilityPermissions() {
        // This is a direct check, but it doesn't prompt the user.
        // The user must grant permissions in System Settings.
        let isEnabled = AXIsProcessTrusted()
        DispatchQueue.main.async {
            self.isAccessibilityEnabled = isEnabled
        }
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
        UserDefaults.standard.set(self.ignored, forKey: "tentacle_Ignored")
    }

    /// Adds or removes app name from the `noActivation` array and saves it to UserDefaults.
    func toggleWindowActivation(bundlerIdentifier: String) {
        if !self.noActivation.contains(bundlerIdentifier) {
            self.noActivation.append(bundlerIdentifier)
        } else {
            if let index = self.noActivation.firstIndex(of: bundlerIdentifier) {
                self.noActivation.remove(at: index)
            }
        }
        UserDefaults.standard.set(self.noActivation, forKey: "tentacle_NoActivation")
    }

    func startRecordingShortcut() {
        self.isRecordingShortcut = true
        NotificationCenter.default.post(name: NSNotification.Name("StartRecordingShortcut"), object: nil)
    }

    func updateActivationShortcut(_ shortcut: String) {
        self.activationShortcut = shortcut
        self.isRecordingShortcut = false
        UserDefaults.standard.set(shortcut, forKey: "tentacle_ActivationShortcut")
    }

    func startRecordingSearchShortcut() {
        self.isRecordingSearchShortcut = true
        NotificationCenter.default.post(name: NSNotification.Name("StartRecordingSearchShortcut"), object: nil)
    }

    func updateSearchActivationShortcut(_ shortcut: String) {
        self.searchActivationShortcut = shortcut
        self.isRecordingSearchShortcut = false
        UserDefaults.standard.set(shortcut, forKey: "tentacle_SearchActivationShortcut")
    }

    func startRecordingScrollModeShortcut() {
        self.isRecordingScrollModeShortcut = true
        NotificationCenter.default.post(name: NSNotification.Name("StartRecordingScrollModeShortcut"), object: nil)
    }

    func updateScrollModeShortcut(_ shortcut: String) {
        self.scrollModeShortcut = shortcut
        self.isRecordingScrollModeShortcut = false
        UserDefaults.standard.set(shortcut, forKey: "tentacle_ScrollModeShortcut")
    }

    func switchToPage(_ page: PageType) {
        self.currentPage = page
    }

    func enterSearchMode() {
        print("🔍 [SharedData] Entering search mode")
        self.isSearchMode = true
        self.isTextInputActive = true
        self.searchQuery = ""
        self.textSearchResults = []
        self.isSearching = false
        self.selectedResultIndex = 0

        // Position the window at bottom center when entering search mode
        DispatchQueue.main.async {
            if let window = NSApp.mainWindow ?? NSApp.windows.first {
                if let screen = NSScreen.main {
                    let screenFrame = screen.visibleFrame
                    let windowFrame = window.frame

                    // Calculate bottom center position
                    let x = screenFrame.midX - 160
                    let y = screenFrame.minY + 40 // 40px from bottom of screen

                    window.setFrameOrigin(NSPoint(x: x, y: y))
                }
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func exitSearchMode() {
        guard self.isSearchMode else { return }
        
        print("🔍 [SharedData] Exiting search mode")
        self.isSearchMode = false
        self.isTextInputActive = false
        self.searchQuery = ""
        self.textSearchResults = []
        self.isSearching = false
        self.selectedResultIndex = 0
        hideTextSearchOverlay()
        hideClickableElementsOverlay()

        // Restore window to center position when exiting search mode
        DispatchQueue.main.async {
            if let window = NSApp.mainWindow ?? NSApp.windows.first {
                window.center()
            }
        }
    }

    func enterScrollMode() {
        self.isScrollMode = true

        // Ensure global event tap is active in scroll mode and start fallback monitors
        if let appDelegate = AppDelegate.shared {
            var shouldUseFallback = false
            if let tap = appDelegate.eventTap {
                if !CGEvent.tapIsEnabled(tap: tap) {
                    print("[ScrollMode] Event tap disabled; enabling now")
                    CGEvent.tapEnable(tap: tap, enable: true)
                    // Check again after attempting to enable
                    if !CGEvent.tapIsEnabled(tap: tap) {
                        print("[ScrollMode] Event tap still disabled after enable attempt; will use fallback monitors")
                        shouldUseFallback = true
                    } else {
                        print("[ScrollMode] Event tap is enabled")
                    }
                } else {
                    print("[ScrollMode] Event tap is enabled")
                }
            } else {
                print("[ScrollMode] Event tap missing; setting up")
                appDelegate.setupEventTap()
                shouldUseFallback = appDelegate.eventTap == nil
            }

            // Start fallback global monitors ONLY if the event tap is unavailable/disabled
            if shouldUseFallback {
                appDelegate.startScrollModeGlobalMonitors()
            } else {
                appDelegate.stopScrollModeGlobalMonitors()
            }
        } else {
            print("[ScrollMode] AppDelegate.shared is nil; cannot verify event tap")
        }

        // Hide the main app window in scroll mode
        if let mainWindow = NSApp.mainWindow ?? NSApp.windows.first {
            mainWindow.orderOut(nil)
        }

        // Find all scrollable areas in the active window
        scrollAreas = getScrollableAreas()
        if let (index, rect) = nearestScrollAreaToMouse() {
            // Found a scrollable area near the mouse; focus and highlight it
            focusScrollArea(at: index)
        } else if let windowRect = getFocusedWindowBounds() {
            // No scrollable area found; fall back to highlighting the active window
            moveMouseToCenter(of: windowRect)
            showScrollModeOverlay(windowRect)
        }

        // Start smooth scrolling timer
        startSmoothScrolling()

        print("🖱️ Scroll mode activated - use j/k or arrow keys to scroll, ESC to exit")
    }

    func exitScrollMode() {
        self.isScrollMode = false
        hideScrollModeOverlay()

        // Stop smooth scrolling timer
        stopSmoothScrolling()

        // Stop fallback monitors if running
        if let appDelegate = AppDelegate.shared {
            appDelegate.stopScrollModeGlobalMonitors()
        }

        // Clear scroll area state
        scrollAreas.removeAll()
        currentScrollAreaIndex = 0

        // Hide the app entirely when exiting scroll mode, like search mode
        NSApp.hide(nil)

        print("🖱️ Exited scroll mode")
    }

    // MARK: - Smooth Scrolling Methods

    private func startSmoothScrolling() {
        scrollTimer?.invalidate()
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
            self.updateSmoothScrolling()
        }
    }

    private func stopSmoothScrolling() {
        scrollTimer?.invalidate()
        scrollTimer = nil
        currentScrollVelocityY = 0.0
        currentScrollVelocityX = 0.0
        targetScrollVelocityY = 0.0
        targetScrollVelocityX = 0.0
    }

    private func updateSmoothScrolling() {
        // Directly use target velocity - no momentum or deceleration
        currentScrollVelocityY = targetScrollVelocityY
        currentScrollVelocityX = targetScrollVelocityX

        // Send scroll events if velocity is significant
        let threshold = 0.1
        if abs(currentScrollVelocityY) > threshold || abs(currentScrollVelocityX) > threshold {
            let deltaY = Int32(currentScrollVelocityY)
            let deltaX = Int32(currentScrollVelocityX)
            sendScrollEvent(deltaY: deltaY, deltaX: deltaX)
        }
    }

    func setScrollVelocity(deltaY: Double, deltaX: Double) {
        targetScrollVelocityY = deltaY
        targetScrollVelocityX = deltaX
    }

    func stopScrolling() {
        targetScrollVelocityY = 0.0
        targetScrollVelocityX = 0.0
        currentScrollVelocityY = 0.0  // Immediately stop current velocity
        currentScrollVelocityX = 0.0  // Immediately stop current velocity
    }

    private func sendScrollEvent(deltaY: Int32, deltaX: Int32) {
        // Create scroll event using line units for more natural scrolling
        // wheel1 = vertical scroll (deltaY), wheel2 = horizontal scroll (deltaX)
        if let scrollEvent = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: deltaY, wheel2: deltaX, wheel3: 0) {
            scrollEvent.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Text Search Overlay Methods

    func showTextSearchOverlay() {
        if textSearchOverlay == nil {
            textSearchOverlay = TextSearchOverlayWindow()
        }

        if !textSearchResults.isEmpty {
            textSearchOverlay?.showSearchResults(textSearchResults, selectedIndex: selectedResultIndex)
        }
    }

    func updateTextSearchOverlay() {
        if !textSearchResults.isEmpty {
            // Create overlay if it doesn't exist
            if textSearchOverlay == nil {
                print("Creating new text search overlay")
                textSearchOverlay = TextSearchOverlayWindow()
            }
            textSearchOverlay?.showSearchResults(textSearchResults, selectedIndex: selectedResultIndex)
        } else {
            hideTextSearchOverlay()
        }
    }

    func updateTextSearchSelection() {
        textSearchOverlay?.updateSelection(selectedResultIndex)
    }

    func hideTextSearchOverlay() {
        textSearchOverlay?.hideOverlay()
    }

    // MARK: - Scroll Mode Overlay Methods

    func showScrollModeOverlay(_ rect: CGRect) {
        if scrollModeOverlay == nil {
            scrollModeOverlay = ScrollModeOverlayWindow()
        }

        scrollModeOverlay?.showScrollModeIndicator(rect)
    }

    func hideScrollModeOverlay() {
        scrollModeOverlay?.hideOverlay()
    }

    // MARK: - Scroll Area Navigation

    private func getScrollableAreas() -> [CGRect] {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return [] }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRefUnwrapped = windowRef,
              CFGetTypeID(windowRefUnwrapped) == AXUIElementGetTypeID() else { return [] }
        let windowElement = windowRefUnwrapped as! AXUIElement
        var areas = collectScrollAreas(from: windowElement)
        // Always include the full focused window area as a scrollable target
        if let windowRect = getFocusedWindowBounds() {
            areas.append(windowRect)
        }
        return areas
    }

    private func collectScrollAreas(from element: AXUIElement) -> [CGRect] {
        var results: [CGRect] = []

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        
        // Determine if this element should be considered a scrollable area
        var isScrollableCandidate = false
        if let role = roleRef as? String, role == kAXScrollAreaRole || role == kAXListRole {
            isScrollableCandidate = true
        } else {
            // Check Orientation == AXVerticalOrientation
            var orientationRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXOrientationAttribute as CFString, &orientationRef) == .success,
               let orientation = orientationRef as? String,
               orientation == kAXVerticalOrientationValue {
                isScrollableCandidate = true
            }

            // Check Rows attribute count > 5
            if !isScrollableCandidate {
                var rowsRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXRowsAttribute as CFString, &rowsRef) == .success,
                   let rows = rowsRef as? [AXUIElement], rows.count > 5 {
                    isScrollableCandidate = true
                }
            }

            // Check Children attribute count > 5
            if !isScrollableCandidate {
                var childrenAttrRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenAttrRef) == .success,
                   let children = childrenAttrRef as? [AXUIElement], children.count > 5 {
                    isScrollableCandidate = true
                }
            }

            // Check Type attribute equals "code"
            if !isScrollableCandidate {
                var typeRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, "Type" as CFString, &typeRef) == .success,
                   let type = typeRef as? String, type.lowercased() == "code" {
                    isScrollableCandidate = true
                }
            }
        }

        if isScrollableCandidate {
            var positionRef: CFTypeRef?
            var sizeRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
               AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
               let posRefUnwrapped = positionRef,
               CFGetTypeID(posRefUnwrapped) == AXValueGetTypeID(),
               let sizeRefUnwrapped = sizeRef,
               CFGetTypeID(sizeRefUnwrapped) == AXValueGetTypeID() {
                var position = CGPoint.zero
                var size = CGSize.zero
                AXValueGetValue(posRefUnwrapped as! AXValue, .cgPoint, &position)
                AXValueGetValue(sizeRefUnwrapped as! AXValue, .cgSize, &size)
                // Only accept reasonably sized areas
                if size.width >  200.0 && size.height >= 300.0 {
                    results.append(CGRect(origin: position, size: size))
                }
            }
        }

        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                results.append(contentsOf: collectScrollAreas(from: child))
            }
        }

        return results
    }

    private func getFocusedWindowBounds() -> CGRect? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRefUnwrapped = windowRef,
              CFGetTypeID(windowRefUnwrapped) == AXUIElementGetTypeID() else { return nil }
        let windowElement = windowRefUnwrapped as! AXUIElement

        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRefUnwrapped = positionRef,
              CFGetTypeID(posRefUnwrapped) == AXValueGetTypeID(),
              let sizeRefUnwrapped = sizeRef,
              CFGetTypeID(sizeRefUnwrapped) == AXValueGetTypeID() else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRefUnwrapped as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeRefUnwrapped as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    private func nearestScrollAreaToMouse() -> (Int, CGRect)? {
        let mouse = NSEvent.mouseLocation
        var bestIndex = -1
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, rect) in scrollAreas.enumerated() {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let dx = center.x - mouse.x
            let dy = center.y - mouse.y
            let distance = sqrt(dx * dx + dy * dy)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        if bestIndex >= 0 {
            return (bestIndex, scrollAreas[bestIndex])
        }
        return nil
    }

    private func focusScrollArea(at index: Int) {
        guard index >= 0 && index < scrollAreas.count else { return }
        currentScrollAreaIndex = index
        let rect = scrollAreas[index]
        moveMouseToCenter(of: rect)
        showScrollModeOverlay(rect)
    }

    func focusNextScrollArea() {
        guard !scrollAreas.isEmpty else { return }
        let nextIndex = (currentScrollAreaIndex + 1) % scrollAreas.count
        focusScrollArea(at: nextIndex)
    }

    private func moveMouseToCenter(of rect: CGRect) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        CGWarpMouseCursorPosition(center)
    }

    // MARK: - Clickable Elements Overlay Methods

    func showClickableElementsOverlay(_ elements: [DesktopTextSearcher.AccessibilityTextElement], highlightedLabel: String? = nil) {
        if clickableElementsOverlay == nil {
            clickableElementsOverlay = ClickableElementsOverlayWindow()
        }

        clickableElementsOverlay?.showClickableElements(elements, highlightedLabel: highlightedLabel)
    }

    func updateClickableElementsHighlight(_ label: String?) {
        clickableElementsOverlay?.updateHighlight(label)
    }

    func updateClickableElementsFilter(_ prefix: String?) {
        clickableElementsOverlay?.updateFilter(prefix)
    }

    func hideClickableElementsOverlay() {
        clickableElementsOverlay?.hideOverlay()
    }

    private func saveAppLetterCache() {
        if let data = try? JSONEncoder().encode(appLetterCache) {
            UserDefaults.standard.set(data, forKey: "tentacle_AppLetterCache")
        }
    }

    private func savePinnedApps() {
        if let data = try? JSONEncoder().encode(pinnedApps) {
            UserDefaults.standard.set(data, forKey: "tentacle_PinnedApps")
        }
    }

    private func saveAppBundleIdentifierCache() {
        if let data = try? JSONEncoder().encode(appBundleIdentifierCache) {
            UserDefaults.standard.set(data, forKey: "tentacle_AppBundleIdentifierCache")
        }
    }

    private func saveAppGroups() {
        if let data = try? JSONEncoder().encode(appGroups) {
            UserDefaults.standard.set(data, forKey: "tentacle_AppGroups")
        }
    }

    func toggleAppPin(appName: String) {
        if pinnedApps.contains(appName) {
            pinnedApps.remove(appName)
        } else {
            pinnedApps.insert(appName)
        }
        savePinnedApps()
    }

    // MARK: - Group Management

    func createGroup(name: String) {
        let newGroup = AppGroup(name: name)
        self.appGroups.append(newGroup)
        saveAppGroups()
    }

    func deleteGroup(id: UUID) {
        self.appGroups.removeAll { $0.id == id }
        saveAppGroups()
    }

    func updateGroup(id: UUID, name: String? = nil, appNames: [String]? = nil) {
        if let index = self.appGroups.firstIndex(where: { $0.id == id }) {
            if let name = name {
                self.appGroups[index].name = name
            }
            if let appNames = appNames {
                self.appGroups[index].appNames = appNames
            }
            saveAppGroups()
        }
    }

    func addAppToGroup(groupId: UUID, appName: String) {
        if let index = self.appGroups.firstIndex(where: { $0.id == groupId }),
           !self.appGroups[index].appNames.contains(appName) {
            self.appGroups[index].appNames.append(appName)
            saveAppGroups()
        }
    }

    func removeAppFromGroup(groupId: UUID, appName: String) {
        if let index = self.appGroups.firstIndex(where: { $0.id == groupId }) {
            self.appGroups[index].appNames.removeAll { $0 == appName }
            saveAppGroups()
        }
    }

    var availableApps: [String] {
        return Array(Set(windows.map { $0.name })).sorted()
    }

    // MARK: - Group Activation Helpers

    func findGroupContaining(appName: String) -> AppGroup? {
        return appGroups.first { group in
            group.appNames.contains(appName)
        }
    }

    func getAppsToActivate(for appName: String) -> [String] {
        if let group = findGroupContaining(appName: appName) {
            // Return all apps in the group, with the selected app last
            var appsToActivate = group.appNames.filter { $0 != appName }
            appsToActivate.append(appName)
            return appsToActivate
        } else {
            // Return just the single app
            return [appName]
        }
    }

    var mainApps: [WindowDef] {
        return windows.filter { !ignored.contains($0.pid) }
    }

    var skippedApps: [WindowDef] {
        return windows.filter { ignored.contains($0.pid) }
    }

    // MARK: Side Effects - Private

    /// Searches for clickable elements on the window with the given process ID and prints their text and position
    func searchClickableElements(for pid: Int) {
        print("Searching for clickable elements on window with PID: \(pid)")

        // Get the application from the process ID
        guard let app = NSRunningApplication(processIdentifier: pid_t(pid)) else {
            print("Could not find application with PID: \(pid)")
            return
        }

        print("Found application: \(app.localizedName ?? "Unknown") (Bundle: \(app.bundleIdentifier ?? "Unknown"))")

        // Get window information using Core Graphics (which we already use for window listing)
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionAll)
        let windowsListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0))

        guard let infoList = windowsListInfo as? [[String: Any]] else {
            print("Could not get Core Graphics window list")
            return
        }

        // Find windows belonging to this PID
        let pidWindows = infoList.filter { windowInfo in
            guard let windowPid = windowInfo["kCGWindowOwnerPID"] as? Int,
                  let layer = windowInfo["kCGWindowLayer"] as? Int else {
                return false
            }
            return windowPid == pid && layer == 0
        }

        print("Found \(pidWindows.count) Core Graphics windows for PID \(pid)")

        // Create overlay window if needed
        if overlayWindow == nil {
            overlayWindow = ElementOverlayWindow()
        }

        // Collect all found elements to display in overlay
        var foundElementRects: [CGRect] = []
        var foundElementTexts: [String] = []

        // For each window, sample points across its surface to find clickable elements
        for (windowIndex, windowInfo) in pidWindows.enumerated() {
            print("Searching window \(windowIndex + 1) of \(pidWindows.count)")

            guard let bounds = windowInfo["kCGWindowBounds"] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat else {
                continue
            }

            print("Window bounds: (\(x), \(y)) size: \(width)x\(height)")

            // Sample points across the window to find accessibility elements
            let (rects, texts) = sampleWindowForElements(windowBounds: CGRect(x: x, y: y, width: width, height: height))
            foundElementRects.append(contentsOf: rects)
            foundElementTexts.append(contentsOf: texts)
        }

        // Show overlay with found elements
        if !foundElementRects.isEmpty {
            overlayWindow?.showElements(foundElementRects, texts: foundElementTexts)
        }
    }

    /// Samples points across a window to find accessibility elements (optimized for speed)
    private func sampleWindowForElements(windowBounds: CGRect) -> ([CGRect], [String]) {
        let systemWideElement = AXUIElementCreateSystemWide()

        // Use fewer sample points for better performance - 3x3 grid = 4 points instead of 64
        let sampleRows = 3
        let sampleCols = 3

        // Keep track of already found elements to avoid duplicates
        var foundElements = Set<String>()
        var elementRects: [CGRect] = []
        var elementTexts: [String] = []

        for row in 1..<sampleRows {
            for col in 1..<sampleCols {
                let x = windowBounds.minX + (windowBounds.width / CGFloat(sampleCols)) * CGFloat(col)
                let y = windowBounds.minY + (windowBounds.height / CGFloat(sampleRows)) * CGFloat(row)

                let point = CGPoint(x: x, y: y)

                // Get element at this point
                var element: AXUIElement?
                let result = AXUIElementCopyElementAtPosition(systemWideElement, Float(point.x), Float(point.y), &element)

                if result == .success, let foundElement = element {
                    // Create a unique identifier for this element to avoid duplicates
                    let elementId = createElementIdentifier(element: foundElement)
                    if !foundElements.contains(elementId) {
                        foundElements.insert(elementId)

                        if let (rect, text) = checkIfElementIsClickable(element: foundElement, position: point) {
                            elementRects.append(rect)
                            elementTexts.append(text)
                        }
                    }
                }
            }
        }

        return (elementRects, elementTexts)
    }

    /// Creates a unique identifier for an accessibility element
    private func createElementIdentifier(element: AXUIElement) -> String {
        var roleRef: CFTypeRef?
        var positionRef: CFTypeRef?
        var titleRef: CFTypeRef?

        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef)
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)

        let role = (roleRef as? String) ?? "unknown"
        let title = (titleRef as? String) ?? "notitle"

        var position = CGPoint.zero
        if let positionValue = positionRef {
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        }

        return "\(role)_\(title)_\(Int(position.x))_\(Int(position.y))"
    }

    /// Checks if an accessibility element is clickable and returns its information
    private func checkIfElementIsClickable(element: AXUIElement, position: CGPoint) -> (CGRect, String)? {
        // Get element role
        var roleRef: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)

        guard roleResult == .success, let role = roleRef as? String else {
            return nil
        }

        // Check if this element is clickable (buttons, menu items, links, etc.)
        let clickableRoles = [
            kAXButtonRole,
            kAXMenuItemRole,
            kAXMenuButtonRole,
            kAXPopUpButtonRole,
            kAXCheckBoxRole,
            kAXRadioButtonRole,
            kAXDisclosureTriangleRole,
            "AXLink" // NSAccessibilityLinkRole for links in apps like Slack
        ]

        let isClickable = clickableRoles.contains((role as CFString) as String)

        if isClickable {
            // Get element text/title
            var titleRef: CFTypeRef?
            var valueRef: CFTypeRef?
            var descriptionRef: CFTypeRef?

            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
            AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descriptionRef)

            let title = titleRef as? String
            let value = valueRef as? String
            let description = descriptionRef as? String

            // Get element position and size
            var positionRef: CFTypeRef?
            var sizeRef: CFTypeRef?

            let positionResult = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef)
            let sizeResult = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)

            var elementPosition = CGPoint.zero
            var size = CGSize.zero

            if positionResult == .success, let positionValue = positionRef {
                AXValueGetValue(positionValue as! AXValue, .cgPoint, &elementPosition)
            } else {
                // Only use sampled position if we can't get the actual element position
                elementPosition = position
            }

            if sizeResult == .success, let sizeValue = sizeRef {
                AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            }

            // Determine the text to display
            let elementText = title ?? value ?? description ?? "<No text>"

            // Print the raw accessibility data - let's keep it simple
            print("Clickable Element - Text: '\(elementText)', Role: \(role), Position: (\(elementPosition.x), \(elementPosition.y)), Size: (\(size.width)x\(size.height))")

            // Return the element rect and text for overlay display
            let elementRect = CGRect(x: elementPosition.x, y: elementPosition.y, width: size.width, height: size.height)
            return (elementRect, elementText)
        }

        return nil
    }

    /// Returns an array of `WindowDef` structs representing the visible windows.
    private func getWindowsList() -> [WindowDef] {
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionAll)
        let windowsListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0))

        guard let infoList = windowsListInfo as? [[String: Any]] else {
            return []
        }

        let visibleWindows = infoList.filter { windowInfo in
            guard let layer = windowInfo["kCGWindowLayer"] as? Int,
                  let ownerName = windowInfo["kCGWindowOwnerName"] as? String else {
                return false
            }
            return layer == 0 && ownerName != "WindowManager" && ownerName != "coreautha" && ownerName != "Open and Save Panel Service" && ownerName != "loginwindow" && ownerName != "Raycast" && ownerName != "Shortcat"
        }

        // Collect currently running app names to determine which cached letters are still valid
        let currentAppNames = Set(visibleWindows.compactMap { windowInfo in
            windowInfo["kCGWindowOwnerName"] as? String
        })

        // Get all cached letters that are currently in use by running apps
        var usedAliases = Set<String>()
        for appName in currentAppNames {
            if let cachedLetter = appLetterCache[appName] {
                usedAliases.insert(cachedLetter)
            }
        }

        let windowDefs = visibleWindows.compactMap { windowInfo -> WindowDef? in
            guard let name = windowInfo["kCGWindowOwnerName"] as? String,
                  let wid = windowInfo["kCGWindowNumber"] as? Int,
                  let pid = windowInfo["kCGWindowOwnerPID"] as? Int else {
                return nil
            }

            // Log window size information and filter out small windows
            if let bounds = windowInfo["kCGWindowBounds"] as? [String: Any],
               let width = bounds["Width"] as? CGFloat,
               let height = bounds["Height"] as? CGFloat {
                if width < 200.0 || height < 200.0 {
                    return nil
                }
            }

            let matchedApp = NSWorkspace.shared.runningApplications.filter { app in
                app.processIdentifier == pid
            }.first

            guard let icon = matchedApp?.icon else {
                return nil
            }

            let bundleIdentifier = matchedApp?.bundleIdentifier ?? "unknown"
            let isIgnored = self.ignored.contains(pid)

            // Store bundle identifier for potential future pinning
            if bundleIdentifier != "unknown" {
                appBundleIdentifierCache[name] = bundleIdentifier
                saveAppBundleIdentifierCache()
            }

            var alias = ""
            // Only assign shortcut characters to non-ignored apps
            if !isIgnored {
                // Check if we already have a cached letter for this app
                if let cachedAlias = appLetterCache[name] {
                    alias = cachedAlias
                } else {
                    // This is a new app, assign a new letter
                    // Try to find a unique character from the app name
                    for char in name where !char.isWhitespace {
                        let potentialAlias = String(char).uppercased()
                        if !usedAliases.contains(potentialAlias) {
                            alias = potentialAlias
                            usedAliases.insert(potentialAlias)
                            appLetterCache[name] = alias
                            break
                        }
                    }

                    // If we couldn't find a unique alias (all characters already used)
                    // fall back to using first character with a number suffix
                    if alias.isEmpty && !name.isEmpty {
                        var counter = 1
                        var potentialAlias = String(name.first!).uppercased() + "\(counter)"
                        while usedAliases.contains(potentialAlias) {
                            counter += 1
                            potentialAlias = String(name.first!).uppercased() + "\(counter)"
                        }
                        alias = potentialAlias
                        usedAliases.insert(alias)
                        appLetterCache[name] = alias
                    }

                    // Save the cache after adding new entries
                    saveAppLetterCache()
                }
            }

            return WindowDef(
                name: name,
                wid: wid,
                pid: pid,
                alias: alias,
                icon: icon,
                bundleIdentifier: bundleIdentifier,
                isOpen: true
            )
        }

        // Add pinned apps that are not currently open
        var allWindowDefs = windowDefs

        for pinnedAppName in pinnedApps {
            if !currentAppNames.contains(pinnedAppName) {
                // Create a placeholder WindowDef for pinned but closed app
                if let cachedAlias = appLetterCache[pinnedAppName] {
                    // Try to get icon from recent apps or use a default
                    let defaultIcon = NSWorkspace.shared.icon(forFileType: "app")

                    // Get cached bundle identifier or use "unknown"
                    let cachedBundleIdentifier = appBundleIdentifierCache[pinnedAppName] ?? "unknown"

                    let pinnedWindowDef = WindowDef(
                        name: pinnedAppName,
                        wid: -1,
                        pid: -1,
                        alias: cachedAlias,
                        icon: defaultIcon,
                        bundleIdentifier: cachedBundleIdentifier,
                        isOpen: false
                    )
                    allWindowDefs.append(pinnedWindowDef)
                }
            }
        }

        // Apply uniqued() and then sort: non-ignored apps first, then ignored apps
        return allWindowDefs.uniqued().sorted { first, second in
            let firstIgnored = self.ignored.contains(first.pid)
            let secondIgnored = self.ignored.contains(second.pid)

            // If one is ignored and the other isn't, non-ignored comes first
            if firstIgnored != secondIgnored {
                return !firstIgnored
            }

            // If both have the same ignored status, sort by name
            return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
        }
    }
}
