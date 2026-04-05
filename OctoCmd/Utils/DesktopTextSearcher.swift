//
//  DesktopTextSearcher.swift
//  OctoCmd
//
//  Created by Claude on 8/1/25.
//
//  Enhanced with Electron app support:
//  - Automatic detection of Electron applications (Slack, VS Code, Discord, etc.)
//  - Enables AXManualAccessibility attribute for better web content accessibility
//  - Enhanced role detection for web-specific UI elements
//  - Improved fallback mechanisms for accessibility-limited scenarios
//

import Cocoa
import Vision
import CoreGraphics

class DesktopTextSearcher {
    
    // MARK: - Stored Accessibility Elements
    
    struct AccessibilityTextElement {
        let text: String
        let normalizedText: String
        let role: String
        let position: CGPoint
        let size: CGSize
        let element: AXUIElement
        let label: String? // AA, AB, AC, etc. for clickable elements
        
        var centerPoint: CGPoint {
            return CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
        }
        
        var boundingRect: CGRect {
            return CGRect(origin: position, size: size)
        }
        
        var isClickable: Bool {
            let clickableRoles = [
                kAXButtonRole,
                kAXMenuItemRole,
                kAXMenuButtonRole,
                kAXPopUpButtonRole,
                kAXCheckBoxRole,
                kAXRadioButtonRole,
                kAXDisclosureTriangleRole,
                "AXImage",
                "AXLink",        // NSAccessibilityLinkRole for links in apps like Slack
                "AXWebArea",     // Web content areas in Electron apps
                "AXGroup",       // Groups that might be clickable in web content
                "AXTab",         // Tabs in web interfaces
                "AXTabGroup",    // Tab groups
                "AXList",        // Lists that might be clickable
                "AXListItem",    // List items
                "AXTable",       // Tables
                "AXRow",         // Table rows
                "AXCell",        // Table cells
                "AXApplication", // Sometimes apps expose clickable content at app level
                "AXTextField"    // Text fields can be clickable
            ]
            
            let roleString = (role as CFString) as String
            
            // Check if element has clickable role
            if clickableRoles.contains(roleString) {
                return true
            }
            
            // Special handling for web content roles
            if roleString.contains("Web") || roleString.contains("HTML") {
                return true
            }
            
            // Also check if static text has URL attribute (makes it clickable)
            return false
        }
    }
    
    private var accessibilityElements: [AccessibilityTextElement] = []
    private var currentAppPid: pid_t = 0 // Store the current app PID for window bounds lookup
    
    // MARK: - Label Generation
    
    private func generateLabels(count: Int) -> [String] {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let maxLabels = 2000
        let actualCount = min(count, maxLabels)

        if count > maxLabels {
            print("⚠️ Warning: Requested \(count) labels but limiting to \(maxLabels) for performance")
        }

        var labels: [String] = []
        labels.reserveCapacity(actualCount)

        for i in 0..<actualCount {
            var number = i
            var label = ""
            repeat {
                label.insert(alphabet[number % 26], at: label.startIndex)
                number = number / 26 - 1
            } while number >= 0
            labels.append(label)
        }

        return labels
    }
    
    // MARK: - Public Methods
    
    func clearAccessibilityElements() {
        accessibilityElements.removeAll()
        print("🗑️ Cleared accessibility elements cache")
    }
    
    /// Filters overlapping elements, keeping only the innermost (smallest) ones
    private func filterOverlappingElements(_ elements: [AccessibilityTextElement]) -> [AccessibilityTextElement] {
        // Process smaller elements first so outer containers can be discarded early
        let sorted = elements.sorted {
            $0.size.width * $0.size.height < $1.size.width * $1.size.height
        }

        var filtered: [AccessibilityTextElement] = []
        for element in sorted {
            let rect = element.boundingRect
            // Skip this element if it fully contains any previously accepted element
            if filtered.contains(where: { rect.contains($0.boundingRect) }) {
                print("🔍 Filtering out outer element: \(element.text) at \(rect)")
                continue
            }
            filtered.append(element)
        }

        return filtered
    }
    
    func getClickableElements() -> [AccessibilityTextElement] {
        let clickableWithLabels = accessibilityElements.filter { $0.isClickable && $0.label != nil }
        
        // Get window bounds for filtering
        guard let windowBounds = getCurrentWindowBounds() else {
            print("⚠️ Could not get window bounds, returning all clickable elements")
            return clickableWithLabels
        }
        
        // Filter elements to only include those within the visible window area (with margin)
        let margin: CGFloat = 50.0 // Add some margin to avoid accidentally excluding elements
        let visibleRect = CGRect(
            x: windowBounds.minX - margin,
            y: windowBounds.minY - margin,
            width: windowBounds.width + (margin * 2),
            height: windowBounds.height + (margin * 2)
        )
        
        let visibleElements = clickableWithLabels.filter { element in
            let elementRect = element.boundingRect
            let isVisible = visibleRect.intersects(elementRect)
            
            if !isVisible {
                print("🚫 Filtering out off-screen element: \(element.text) at \(elementRect)")
            }
            
            return isVisible
        }
        
        // Filter out overlapping elements, keeping only the innermost ones
        let nonOverlappingElements = filterOverlappingElements(visibleElements)
        
        print("📍 Filtered clickable elements: \(visibleElements.count) visible, \(nonOverlappingElements.count) after overlap filtering (from \(clickableWithLabels.count) total)")
        return nonOverlappingElements
    }
    
    func findElementByLabel(_ label: String) -> AccessibilityTextElement? {
        return accessibilityElements.first { $0.label?.lowercased() == label.lowercased() }
    }
    
    // MARK: - Accessibility-based Text Extraction
    
    func extractTextFromFrontApp(pid: pid_t) {
        print("🔍 Extracting text elements from front app with PID: \(pid)")
        
        // Store the current app PID for window bounds lookup
        currentAppPid = pid
        
        // Clear previous elements
        accessibilityElements.removeAll()
        
        // Check if this is an Electron app and enable accessibility if needed
        enableAccessibilityForElectronApp(pid: pid)
        
        // Get the application window
        guard let window = getApplicationWindow(pid: pid) else {
            print("❌ Could not get window for PID: \(pid)")
            return
        }
        
        print("✅ Got window for PID: \(pid)")
        
        // Get all elements with text
        let textElements = getAllElementsWithText(from: window)
        
        print("📊 Found \(textElements.count) elements with text")
        
        // If this is an Electron app and we didn't find many elements, try a more aggressive approach
        if isElectronApp(pid: pid) && textElements.count < 10 {
            print("🔄 Low element count for Electron app, trying more aggressive accessibility extraction...")
            // Wait a bit more for accessibility to initialize
            Thread.sleep(forTimeInterval: 1.0)
            let additionalElements = getAllElementsWithText(from: window)
            if additionalElements.count > textElements.count {
                print("✅ Found \(additionalElements.count) elements with more aggressive approach")
            }
        }
        
        // Convert to AccessibilityTextElement objects and store
        var tempElements: [AccessibilityTextElement] = []
        
        for (index, element) in textElements.enumerated() {
            let textData = getTextFromElement(element)
            
            // Get the primary text content - prioritize value, then title, then other attributes
            let primaryText = textData["value"] ?? textData["title"] ?? textData["label"] ?? textData["description"] ?? textData["help"] ?? textData["roleDescription"] ?? ""
            guard !primaryText.isEmpty else { continue }
            
            // Get position
            var position = CGPoint.zero
            var positionRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
               let positionValue = positionRef {
                AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
            }
            
            // Get size
            var size = CGSize.zero
            var sizeRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
               let sizeValue = sizeRef {
                AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            }
            
            // Skip elements larger than 300x300 pixels (likely containers/backgrounds)
            if size.width > 1000 || size.height > 300 || size.width < 10 || size.height < 10 {
                print("  ⏭️ Skipping large element: \(size)")
                continue
            }
            
            let accessibilityElement = AccessibilityTextElement(
                text: primaryText,
                normalizedText: primaryText.lowercased(),
                role: textData["role"] ?? "Unknown",
                position: position,
                size: size,
                element: element,
                label: nil // Will be assigned later for clickable elements
            )
            
            tempElements.append(accessibilityElement)
            
            print("\n📝 Element \(index + 1):")
            print("  text: \(primaryText)")
            print("  role: \(accessibilityElement.role)")
            if let url = textData["url"] {
                print("  🔗 URL: \(url)")
            }
            print("  position: \(position)")
            print("  size: \(size)")
            print("  clickable: \(accessibilityElement.isClickable)")
        }
        
        // Generate labels for clickable elements
        let allClickableElements = tempElements.filter { $0.isClickable }
        let maxClickableElements = 1500 // Reasonable limit to prevent performance issues
        let clickableElements = Array(allClickableElements.prefix(maxClickableElements))
        
        if allClickableElements.count > maxClickableElements {
            print("⚠️ Found \(allClickableElements.count) clickable elements, limiting to \(maxClickableElements) for performance")
        }
        
        let labels = generateLabels(count: clickableElements.count)
        
        // Create a set of elements that should get labels (first N clickable elements)
        var clickableElementsSet = Set<ObjectIdentifier>()
        for element in clickableElements {
            clickableElementsSet.insert(ObjectIdentifier(element.element))
        }
        
        var labelIndex = 0
        for i in 0..<tempElements.count {
            if tempElements[i].isClickable && 
               clickableElementsSet.contains(ObjectIdentifier(tempElements[i].element)) && 
               labelIndex < labels.count {
                tempElements[i] = AccessibilityTextElement(
                    text: tempElements[i].text,
                    normalizedText: tempElements[i].normalizedText,
                    role: tempElements[i].role,
                    position: tempElements[i].position,
                    size: tempElements[i].size,
                    element: tempElements[i].element,
                    label: labels[labelIndex]
                )
                labelIndex += 1
                print("🏷️ Assigned label '\(labels[labelIndex-1])' to clickable element: \(tempElements[i].text)")
            }
        }
        
        accessibilityElements = tempElements
        
        print("\n💾 Stored \(accessibilityElements.count) accessibility elements (\(clickableElements.count) clickable) for searching")
    }
    
    private func getApplicationWindow(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard result == .success else {
            print("❌ Failed to get windows attribute. Error: \(result.rawValue)")
            
            // Try to get more info about the app
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String {
                print("  App title: \(title)")
            }
            
            // Check if we can at least get the focused window
            var focusedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
               let focusedWindow = focusedRef {
                print("  ✅ Can get focused window instead")
                return (focusedWindow as! AXUIElement)
            }
            
            return nil
        }
        
        guard let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            print("❌ No windows found for app")
            return nil
        }
        
        print("✅ Found \(windows.count) windows")
        return windows.first
    }
    
    private func getCurrentWindowBounds() -> CGRect? {
        guard currentAppPid > 0 else {
            print("❌ No current app PID available for window bounds lookup")
            return nil
        }
        
        // Get window information using Core Graphics
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        guard let windowsListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0)) as? [[String: Any]] else {
            print("❌ Could not get Core Graphics window list")
            return nil
        }
        
        // Find the main window for the current app PID
        for windowInfo in windowsListInfo {
            guard let windowPid = windowInfo["kCGWindowOwnerPID"] as? Int,
                  let layer = windowInfo["kCGWindowLayer"] as? Int,
                  let bounds = windowInfo["kCGWindowBounds"] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat else {
                continue
            }
            
            // Find window belonging to current app at layer 0 (main window layer) with reasonable size
            if windowPid == Int(currentAppPid) && layer == 0 && width > 200 && height > 200 {
                let windowBounds = CGRect(x: x, y: y, width: width, height: height)
                print("✅ Found window bounds for PID \(currentAppPid): \(windowBounds)")
                return windowBounds
            }
        }
        
        print("❌ Could not find window bounds for PID \(currentAppPid)")
        return nil
    }
    
    private func getAllElementsWithText(from root: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var queue: [AXUIElement] = [root]
        var index = 0

        while index < queue.count {
            let element = queue[index]
            index += 1

            if hasText(element) {
                result.append(element)
            }

            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let children = childrenRef as? [AXUIElement] {
                queue.append(contentsOf: children)
            }
        }

        return result
    }
    
    private func hasText(_ element: AXUIElement) -> Bool {
        let textAttributes: [CFString] = [
            kAXValueAttribute as CFString,
            kAXTitleAttribute as CFString,
            kAXDescriptionAttribute as CFString,
            kAXHelpAttribute as CFString,
            kAXURLAttribute as CFString,
            "AXLabel" as CFString,           // Additional web content attribute
            "AXRoleDescription" as CFString   // Can contain text in web views
        ]
        
        for attribute in textAttributes {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, attribute, &value)
            
            if result == .success,
               let text = value as? String,
               !text.isEmpty {
                return true
            }
        }
        
        return false
    }
    
    private func getTextFromElement(_ element: AXUIElement) -> [String: String] {
        var textData: [String: String] = [:]
        
        let textAttributes: [(String, CFString)] = [
            ("value", kAXValueAttribute as CFString),
            ("title", kAXTitleAttribute as CFString),
            ("description", kAXDescriptionAttribute as CFString),
            ("help", kAXHelpAttribute as CFString),
            ("label", "AXLabel" as CFString),                    // Additional web content attribute
            ("roleDescription", "AXRoleDescription" as CFString)  // Can contain text in web views
        ]
        
        for (key, attribute) in textAttributes {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, attribute, &value)
            
            if result == .success,
               let text = value as? String,
               !text.isEmpty {
                textData[key] = text
            }
        }
        
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String {
            textData["role"] = role
        }
        
        // Check for URL attribute (makes static text clickable)
        var urlRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &urlRef) == .success,
           let url = urlRef as? String,
           !url.isEmpty {
            textData["url"] = url
        }
        
        return textData
    }
    
    struct TextMatch {
        let text: String
        let boundingBox: CGRect
        let confidence: Float
        let screenPosition: CGRect
        
        var centerPoint: CGPoint {
            return CGPoint(x: screenPosition.midX, y: screenPosition.midY)
        }
    }
    
    // MARK: - Electron App Accessibility Support
    // This section handles accessibility for Electron apps (Slack, VS Code, Discord, etc.)
    // by enabling AXManualAccessibility which forces the app to expose web content
    // to the macOS accessibility system, making links and other HTML elements accessible.
    
    private func enableAccessibilityForElectronApp(pid: pid_t) {
        guard isElectronApp(pid: pid) else { return }
        
        print("📱 Detected Electron app, enabling accessibility...")
        
        let app = AXUIElementCreateApplication(pid)
        
        // Enable AXManualAccessibility for Electron apps
        let kAXManualAccessibility = "AXManualAccessibility" as CFString
        let result = AXUIElementSetAttributeValue(app, kAXManualAccessibility, kCFBooleanTrue)
        
        if result == .success {
            print("✅ Successfully enabled AXManualAccessibility for Electron app")
            // Give the app a moment to initialize accessibility
            Thread.sleep(forTimeInterval: 0.5)
        } else {
            print("⚠️ Failed to enable AXManualAccessibility: \(result.rawValue)")
        }
    }
    
    private func isElectronApp(pid: pid_t) -> Bool {
        let app = NSRunningApplication(processIdentifier: pid)
        guard let bundleIdentifier = app?.bundleIdentifier,
              let executableName = app?.executableURL?.lastPathComponent else {
            return false
        }
        
        // Common indicators of Electron apps
        let electronIndicators = [
            "electron",
            "Electron",
            "Helper"  // Many Electron apps have "Helper" in executable name
        ]
        
        // Known Electron apps
        let knownElectronApps = [
            "com.tinyspeck.slackmacgap",  // Slack
            "com.microsoft.VSCode",       // Visual Studio Code
            "com.github.atom",            // Atom (deprecated but still used)
            "com.spotify.client",         // Spotify
            "com.github.GitHubDesktop",   // GitHub Desktop
            "com.figma.Desktop",          // Figma
            "com.discordapp.Discord",     // Discord
            "com.notion.id",              // Notion
            "org.whispersystems.signal-desktop", // Signal
            "com.github.WhatsApp"         // WhatsApp Desktop
        ]
        
        // Check bundle identifier first
        if knownElectronApps.contains(bundleIdentifier) {
            print("🎯 Identified known Electron app: \(bundleIdentifier)")
            return true
        }
        
        // Check executable name for common Electron patterns
        for indicator in electronIndicators {
            if executableName.contains(indicator) {
                print("🎯 Detected potential Electron app based on executable name: \(executableName)")
                return true
            }
        }
        
        // Additional check: look for Electron framework in bundle
        if let bundleURL = app?.bundleURL {
            let electronFrameworkPath = bundleURL.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
            if FileManager.default.fileExists(atPath: electronFrameworkPath.path) {
                print("🎯 Detected Electron app based on framework presence: \(bundleIdentifier)")
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Main Search Function
    
    func searchForText(
        _ searchText: String,
        exactMatch: Bool = false,
        completion: @escaping ([TextMatch]) -> Void
    ) {
        print("🔍 Starting search for: '\(searchText)'")
        
        // First, try to find matches in accessibility elements
        let accessibilityMatches = searchAccessibilityElements(searchText: searchText, exactMatch: exactMatch)
        
        if !accessibilityMatches.isEmpty {
            print("✅ Found \(accessibilityMatches.count) matches in accessibility elements")
            completion(accessibilityMatches)
            return
        }
        
        // Special handling for when accessibility fails but we have stored elements
        if !accessibilityElements.isEmpty {
            print("⚠️ No search matches found but we have \(accessibilityElements.count) accessibility elements available")
            print("📱 Available elements include:")
            for (index, element) in accessibilityElements.prefix(5).enumerated() {
                print("  \(index + 1). \(element.text) (role: \(element.role))")
            }
            if accessibilityElements.count > 5 {
                print("  ... and \(accessibilityElements.count - 5) more")
            }
        }
        
        print("⚠️ No accessibility matches found, falling back to OCR search")
        searchUsingOCR(searchText, exactMatch: exactMatch, completion: completion)
    }
    
    private func searchAccessibilityElements(searchText: String, exactMatch: Bool) -> [TextMatch] {
        let searchTextLowercased = searchText.lowercased()
        var matches: [TextMatch] = []
        
        for element in accessibilityElements {
            let elementText = element.normalizedText

            let isMatch: Bool
            if exactMatch {
                isMatch = elementText == searchTextLowercased
            } else {
                isMatch = elementText.contains(searchTextLowercased)
            }
            
            if isMatch {
                // Convert AccessibilityTextElement to TextMatch
                let match = TextMatch(
                    text: element.text,
                    boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1), // Normalized coordinates (not used for accessibility)
                    confidence: 1.0, // Accessibility text is always 100% confident
                    screenPosition: element.boundingRect
                )
                
                matches.append(match)
                print("🎯 Accessibility match: '\(element.text)' at \(element.centerPoint)")
            }
        }
        
        return matches
    }
    
    private func searchUsingOCR(
        _ searchText: String,
        exactMatch: Bool = false,
        completion: @escaping ([TextMatch]) -> Void
    ) {
        guard let desktopImage = captureDesktopImage() else {
            print("Failed to capture desktop image")
            completion([])
            return
        }
        
        // Resize image for faster processing
        guard let resizedImage = resizeImage(image: desktopImage, scale: 0.75) else {
            print("Failed to resize image")
            // Fallback to original image if resize fails
            recognizeText(in: desktopImage) { [weak self] recognizedTexts in
                self?.processRecognizedText(
                    recognizedTexts,
                    searchText: searchText,
                    exactMatch: exactMatch,
                    originalImageSize: CGSize(width: desktopImage.width, height: desktopImage.height),
                    completion: completion
                )
            }
            return
        }
        
        print("Resized image from \(desktopImage.width)x\(desktopImage.height) to \(resizedImage.width)x\(resizedImage.height)")
        
        recognizeText(in: resizedImage) { [weak self] recognizedTexts in
            self?.processRecognizedText(
                recognizedTexts,
                searchText: searchText,
                exactMatch: exactMatch,
                originalImageSize: CGSize(width: desktopImage.width, height: desktopImage.height),
                completion: completion
            )
        }
    }
    
    private func processRecognizedText(
        _ recognizedTexts: [VNRecognizedTextObservation],
        searchText: String,
        exactMatch: Bool,
        originalImageSize: CGSize,
        completion: @escaping ([TextMatch]) -> Void
    ) {
        let matches = filterMatches(
            recognizedTexts: recognizedTexts,
            searchText: searchText,
            exactMatch: exactMatch,
            imageSize: originalImageSize // Pass original size for coordinate conversion
        )
        
        DispatchQueue.main.async {
            completion(matches)
        }
    }
    
    // MARK: - Image Resizing
    
    private func resizeImage(image: CGImage, scale: CGFloat) -> CGImage? {
        let newWidth = Int(CGFloat(image.width) * scale)
        let newHeight = Int(CGFloat(image.height) * scale)
        
        guard let colorSpace = image.colorSpace else { return nil }
        
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: image.bitmapInfo.rawValue
        ) else { return nil }
        
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        
        return context.makeImage()
    }
    
    // MARK: - Screen Capture
    
    private func captureDesktopImage() -> CGImage? {
        // Get display bounds to understand the coordinate system
        let displayBounds = CGDisplayBounds(CGMainDisplayID())
        print("Display bounds: \(displayBounds)")
        
        // Get all windows except current app's windows
        let visibleWindows = getVisibleWindowsExcludingCurrentApp()
        print("Capturing \(visibleWindows.count) windows (excluding OctoCmd)")
        
        if visibleWindows.isEmpty {
            print("No visible windows found, falling back to display capture")
            return CGDisplayCreateImage(CGMainDisplayID())
        }
        
        // Create screenshot from visible windows only
        guard let screenshot = CGImage(
            windowListFromArrayScreenBounds: displayBounds,
            windowArray: visibleWindows as CFArray,
            imageOption: .bestResolution
        ) else {
            print("Failed to create window list image, falling back to display capture")
            return CGDisplayCreateImage(CGMainDisplayID())
        }
        
        print("Screenshot size: \(screenshot.width)x\(screenshot.height)")
        print("Display backing scale factor: \(NSScreen.main?.backingScaleFactor ?? 1.0)")
        
        return screenshot
    }
    
    private func getVisibleWindowsExcludingCurrentApp() -> [CGWindowID] {
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        let windowsListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0))
        
        guard let infoList = windowsListInfo as? [[String: Any]] else {
            return []
        }
        
        let currentPID = NSRunningApplication.current.processIdentifier
        var visibleWindows: [CGWindowID] = []
        
        for windowInfo in infoList {
            guard let windowPid = windowInfo["kCGWindowOwnerPID"] as? Int,
                  let windowID = windowInfo["kCGWindowNumber"] as? CGWindowID,
                  let layer = windowInfo["kCGWindowLayer"] as? Int else {
                continue
            }
            
            // Skip current app's windows
            if windowPid == currentPID {
                continue
            }
            
            // Only include windows at layer 0 (normal application windows)
            if layer == 0 {
                visibleWindows.append(windowID)
            }
        }
        
        return visibleWindows
    }
    
    // MARK: - Text Recognition
    
    private func recognizeText(
        in image: CGImage,
        completion: @escaping ([VNRecognizedTextObservation]) -> Void
    ) {
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                print("Text recognition error: \(error)")
                completion([])
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                print("No text observations found")
                completion([])
                return
            }
            
            completion(observations)
        }
        
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US", "en-GB"]
        
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("Failed to perform text recognition: \(error)")
                completion([])
            }
        }
    }
    
    // MARK: - Text Cleaning and Filtering
    
    private func cleanOCRText(_ text: String) -> String {
        var cleaned = text
        
        // Remove common OCR artifacts at the beginning and end
        // These are often misread UI elements or font artifacts
        let commonPrefixes = ["Ju", "B ", "I ", "1 ", "l ", "] ", "} ", "| "]
        let commonSuffixes = ["l", "1", "I", "|", "]", "}", " l", " 1", " I"]
        
        for prefix in commonPrefixes {
            if cleaned.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count))
                break
            }
        }
        
        for suffix in commonSuffixes {
            if cleaned.hasSuffix(suffix) {
                cleaned = String(cleaned.dropLast(suffix.count))
                break
            }
        }
        
        // Trim whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned.isEmpty ? text : cleaned // Return original if cleaning resulted in empty string
    }
    
    // MARK: - Text Filtering and Position Calculation
    
    private func filterMatches(
        recognizedTexts: [VNRecognizedTextObservation],
        searchText: String,
        exactMatch: Bool,
        imageSize: CGSize
    ) -> [TextMatch] {
        var matches: [TextMatch] = []
        let searchTextLowercased = searchText.lowercased()
        
        for observation in recognizedTexts {
            guard let topCandidate = observation.topCandidates(1).first else { continue }

            let candidateString = topCandidate.string
            let recognizedText = candidateString.lowercased()
            let cleanedText = cleanOCRText(candidateString)
            let cleanedRecognizedText = cleanedText.lowercased()

            let isMatch: Bool

            if exactMatch {
                isMatch = recognizedText == searchTextLowercased || cleanedRecognizedText == searchTextLowercased
            } else {
                isMatch = recognizedText.contains(searchTextLowercased) || cleanedRecognizedText.contains(searchTextLowercased)
            }

            if isMatch {
                let screenPosition = convertVisionCoordinatesToScreen(
                    boundingBox: observation.boundingBox,
                    imageSize: imageSize
                )

                let match = TextMatch(
                    text: cleanedText,
                    boundingBox: observation.boundingBox,
                    confidence: topCandidate.confidence,
                    screenPosition: screenPosition
                )

                print("Found text match: '\(candidateString)' -> cleaned: '\(cleanedText)' at screen position: \(screenPosition)")

                matches.append(match)
            }
        }
        
        // Sort by confidence (highest first)
        return matches.sorted { $0.confidence > $1.confidence }
    }
    
    private func convertVisionCoordinatesToScreen(
        boundingBox: CGRect,
        imageSize: CGSize
    ) -> CGRect {
        // Get the backing scale factor for Retina displays
        let scaleFactor = NSScreen.main?.backingScaleFactor ?? 1.0
        
        // Vision works with physical pixels, but we need logical points for mouse events
        let logicalHeight = imageSize.height / scaleFactor
        let logicalWidth = imageSize.width / scaleFactor
        
        // Vision coordinates: origin at bottom-left, normalized 0-1
        // Screen coordinates: origin at top-left
        
        let x = boundingBox.origin.x * logicalWidth
        // Vision Y coordinates are flipped compared to screen coordinates
        // Vision: (0,0) = bottom-left, Screen: (0,0) = top-left
        let y = (1.0 - boundingBox.origin.y - boundingBox.height) * logicalHeight
        let width = boundingBox.width * logicalWidth
        let height = boundingBox.height * logicalHeight
        
        // Debug logging
        print("Vision bbox: \(boundingBox)")
        print("Physical image size: \(imageSize)")
        print("Logical screen size: \(logicalWidth)x\(logicalHeight)")
        print("Scale factor: \(scaleFactor)")
        print("Converted to logical screen coords: x=\(x), y=\(y), w=\(width), h=\(height)")
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    // MARK: - Click Functionality
    
    func clickAtPoint(_ point: CGPoint) {
        print("Attempting to click at logical point: \(point)")
        
        // Validate that the point is within screen bounds
        let screenBounds = NSScreen.main?.frame ?? CGRect.zero
        print("Screen bounds: \(screenBounds)")
        
        if !screenBounds.contains(point) {
            print("WARNING: Click point \(point) is outside screen bounds \(screenBounds)")
        }
        
        // Get current mouse position for comparison
        let currentMouseLocation = NSEvent.mouseLocation
        print("Current mouse location: \(currentMouseLocation)")
        
        // For main display, origin is always (0,0) and coordinates are already correct
        // For future multi-display support, we'd need to handle different display origins
        
        let clickEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let releaseEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        
        clickEvent?.post(tap: .cghidEventTap)
        releaseEvent?.post(tap: .cghidEventTap)
        
        print("Mouse click posted at: \(point)")
        
        // Check where mouse ended up after click
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let finalMouseLocation = NSEvent.mouseLocation
            print("Mouse location after click: \(finalMouseLocation)")
            let distance = sqrt(pow(finalMouseLocation.x - point.x, 2) + pow(finalMouseLocation.y - point.y, 2))
            print("Distance from intended click: \(distance) pixels")
        }
    }
    
    func rightClickAtPoint(_ point: CGPoint) {
        print("Attempting to right-click at logical point: \(point)")
        
        let downEvent = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right)
        let upEvent = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right)
        
        downEvent?.post(tap: .cghidEventTap)
        upEvent?.post(tap: .cghidEventTap)
        
        print("Mouse right-click posted at: \(point)")
    }
    
    func moveMouseToPoint(_ point: CGPoint) {
        print("Attempting to move mouse to logical point: \(point)")
        let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) // Button is ignored for move
        moveEvent?.post(tap: .cghidEventTap)
        print("Mouse move posted to: \(point)")
    }
}
