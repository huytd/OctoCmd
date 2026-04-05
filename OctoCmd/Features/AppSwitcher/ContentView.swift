//
//  ContentView.swift
//  OctoCmd
//
//  Created by Huy Tran on 4/25/23.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var sharedData: SharedData
    
    var body: some View {
        if !sharedData.isAccessibilityEnabled {
            AccessibilityOffView()
        } else if sharedData.isSearchMode {
            SearchModeView()
                .environmentObject(sharedData)
        } else {
            MainContentView()
                .environmentObject(sharedData)
        }
    }
}

struct AccessibilityOffView: View {
    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundColor(.red)

            Text("Accessibility Access Needed")
                .font(.system(size: 20, weight: .bold))

            Text("To search text on your screen, OctoCmd needs Accessibility permissions. Please grant access in System Settings.")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: {
                openAccessibilitySettings()
            }) {
                Text("Open System Settings")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(width: 500, height: 300)
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

struct MainContentView: View {
    @EnvironmentObject var sharedData: SharedData
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    
    var currentApps: [WindowDef] {
        switch sharedData.currentPage {
        case .mainApps:
            return sharedData.mainApps
        case .skippedApps:
            return sharedData.skippedApps
        case .groups:
            return [] // Empty for now
        case .settings:
            return [] // Empty for settings
        }
    }
    
    var pageTitle: String {
        switch sharedData.currentPage {
        case .mainApps:
            return "Pick an application"
        case .skippedApps:
            return "Skipped applications"
        case .groups:
            return "Groups"
        case .settings:
            return "Settings"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(pageTitle)
                    .fontWeight(.heavy)
                    .font(.system(size: 21.0))
                    .background(.clear)
                    .padding(.leading)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text("⌘1 Active")
                        .font(.system(size: 10.0).monospaced())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(sharedData.currentPage == .mainApps ? .black : .gray.opacity(0.3))
                        .foregroundColor(sharedData.currentPage == .mainApps ? .white : .primary)
                        .cornerRadius(4)
                    Text("⌘2 Skipped")
                        .font(.system(size: 10.0).monospaced())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(sharedData.currentPage == .skippedApps ? .black : .gray.opacity(0.3))
                        .foregroundColor(sharedData.currentPage == .skippedApps ? .white : .primary)
                        .cornerRadius(4)
                    Text("⌘3 Groups")
                        .font(.system(size: 10.0).monospaced())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(sharedData.currentPage == .groups ? .black : .gray.opacity(0.3))
                        .foregroundColor(sharedData.currentPage == .groups ? .white : .primary)
                        .cornerRadius(4)
                    Text("⌘4 Settings")
                        .font(.system(size: 10.0).monospaced())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(sharedData.currentPage == .settings ? .black : .gray.opacity(0.3))
                        .foregroundColor(sharedData.currentPage == .settings ? .white : .primary)
                        .cornerRadius(4)
                }
                .padding(.trailing)
            }
            
            ScrollView {
                if sharedData.currentPage == .groups {
                    GroupsView()
                        .environmentObject(sharedData)
                } else if sharedData.currentPage == .settings {
                    SettingsView()
                        .environmentObject(sharedData)
                } else {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Array(currentApps)) { (win: WindowDef) in
                        HStack {
                            let isPinned = sharedData.pinnedApps.contains(win.name)
                            let labelBackground = isPinned ? Color.red : Color.white
                            let labelForeground = isPinned ? Color.white : Color.black
                            let itemOpacity = win.isOpen ? 1.0 : 0.5
                            
                            Text("\(win.alias)")
                                .bold()
                                .padding(2)
                                .font(.system(size: 13.0).monospaced())
                                .frame(width: 22.0, height: 22.0)
                                .background(labelBackground)
                                .foregroundColor(labelForeground)
                                .cornerRadius(4.0)
                                .onTapGesture {
                                    sharedData.toggleAppPin(appName: win.name)
                                }
                            Image(nsImage: win.icon)
                                .frame(width: 24.0, height: 22.0)
                                .scaledToFit()
                                .opacity(itemOpacity)
                            Text("\(win.name)")
                                .padding(2)
                                .font(.system(size: 15.0))
                                .opacity(itemOpacity)
                            Spacer()
                            HStack(spacing: 2.0) {
                                Button(action: {
                                    sharedData.togglePidIgnore(pid: win.pid)
                                }) {
                                    let isSkipped = sharedData.ignored.contains(win.pid)
                                    Text(isSkipped ? "Skipped" : "Enabled")
                                        .font(.system(size: 10.0).monospaced())
                                        .padding([.top, .bottom], 2.0)
                                        .padding([.leading, .trailing], 4.0)
                                        .background(isSkipped ? .black : .red)
                                        .foregroundColor(.white)
                                        .cornerRadius(4.0)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding(.horizontal, 2.0)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 4.0)
                    }
                    }
                    .padding(.horizontal)
                }
            }
            .background(.clear)
            .scrollContentBackground(.hidden)
                        
            Spacer()
            
            HStack {
                HStack(spacing: 4.0) {
                    Text("Press")
                    Text("ESC")
                        .padding(1.0)
                        .padding(.trailing, 4.0)
                        .padding(.leading, 4.0)
                        .font(.system(size: 12.0).monospaced())
                        .background(.black)
                        .foregroundColor(.white)
                        .cornerRadius(4.0)
                    Text("to close.")
                    Text("⌘ + Q")
                        .padding(1.0)
                        .padding(.trailing, 4.0)
                        .padding(.leading, 4.0)
                        .font(.system(size: 12.0).monospaced())
                        .background(.red)
                        .foregroundColor(.white)
                        .cornerRadius(4.0)
                    Text("to exit.")
                }
                
                Spacer()
            }
            .padding()
        }
        .padding(0)
        .frame(width: 640, height: 340)
    }
}

struct SettingsView: View {
    @EnvironmentObject var sharedData: SharedData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Keyboard Activation Section
            VStack(alignment: .leading, spacing: 10) {
                Text("Keyboard Activation")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Activation Shortcut:")
                            .font(.system(size: 14))
                        
                        Spacer()
                        
                        Text(sharedData.isRecordingShortcut ? "Recording..." : sharedData.activationShortcut)
                            .font(.system(size: 14).monospaced())
                            .padding(.horizontal, 12.0)
                            .padding(.vertical, 6.0)
                            .background(sharedData.isRecordingShortcut ? .orange : .gray.opacity(0.2))
                            .foregroundColor(sharedData.isRecordingShortcut ? .white : .primary)
                            .cornerRadius(6.0)
                            .onTapGesture(count: 2) {
                                sharedData.startRecordingShortcut()
                            }
                    }
                    
                    Text("Double-click the shortcut above to record a new one")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(.gray.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
                
                // Search Activation Setting
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Activate Search:")
                            .font(.system(size: 14))
                        
                        Spacer()
                        
                        Text(sharedData.isRecordingSearchShortcut ? "Recording..." : sharedData.searchActivationShortcut)
                            .font(.system(size: 14).monospaced())
                            .padding(.horizontal, 12.0)
                            .padding(.vertical, 6.0)
                            .background(sharedData.isRecordingSearchShortcut ? .orange : .gray.opacity(0.2))
                            .foregroundColor(sharedData.isRecordingSearchShortcut ? .white : .primary)
                            .cornerRadius(6.0)
                            .onTapGesture(count: 2) {
                                sharedData.startRecordingSearchShortcut()
                            }
                    }
                    
                    Text("Shortcut to open the app directly in search mode")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(.gray.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
                
                // Scroll Mode Setting
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Activate Scroll Mode:")
                            .font(.system(size: 14))
                        
                        Spacer()
                        
                        Text(sharedData.isRecordingScrollModeShortcut ? "Recording..." : sharedData.scrollModeShortcut)
                            .font(.system(size: 14).monospaced())
                            .padding(.horizontal, 12.0)
                            .padding(.vertical, 6.0)
                            .background(sharedData.isRecordingScrollModeShortcut ? .orange : .gray.opacity(0.2))
                            .foregroundColor(sharedData.isRecordingScrollModeShortcut ? .white : .primary)
                            .cornerRadius(6.0)
                            .onTapGesture(count: 2) {
                                sharedData.startRecordingScrollModeShortcut()
                            }
                    }
                    
                    Text("Enter scrolling mode. Use j/k or arrow keys to scroll, ESC to exit")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(.gray.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            
            Spacer()
        }
        .padding(.top)
    }
}

struct GroupsView: View {
    @EnvironmentObject var sharedData: SharedData
    @State private var showingCreateGroup = false
    @State private var newGroupName = ""
    @State private var selectedGroupId: UUID?
    @State private var showingAppSelection = false
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Create group button
            HStack {
                Button(action: {
                    showingCreateGroup = true
                }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("Create Group")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .font(.system(size: 12))
                    .background(.black)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
            }
            .padding(.horizontal)
            
            // Groups list
            if !sharedData.appGroups.isEmpty {
                ForEach(sharedData.appGroups) { group in
                    GroupRowView(group: group)
                        .environmentObject(sharedData)
                }
            }
        }
        .padding(.top)
        .sheet(isPresented: $showingCreateGroup) {
            CreateGroupView(groupName: $newGroupName) { name in
                if !name.isEmpty {
                    sharedData.createGroup(name: name)
                }
                showingCreateGroup = false
                newGroupName = ""
                sharedData.isTextInputActive = false
            } onCancel: {
                showingCreateGroup = false
                newGroupName = ""
                sharedData.isTextInputActive = false
            }
            .environmentObject(sharedData)
        }
    }
}

struct GroupRowView: View {
    let group: AppGroup
    @EnvironmentObject var sharedData: SharedData
    @State private var showingAppSelection = false
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: {
                    withAnimation {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                    Text(group.name)
                        .font(.system(size: 13, weight: .bold))
                    
                    Text("(\(group.appNames.count) apps)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Button(action: {
                    showingAppSelection = true
                }) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    sharedData.deleteGroup(id: group.id)
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            if isExpanded {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if group.appNames.isEmpty {
                        Text("No apps in this group")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.leading, 20)
                    } else {
                        ForEach(group.appNames, id: \.self) { appName in
                            HStack {
                                Text("• \(appName)")
                                    .font(.system(size: 12))
                                    .padding(.leading, 20)
                                
                                Spacer()
                                
                                Button(action: {
                                    sharedData.removeAppFromGroup(groupId: group.id, appName: appName)
                                }) {
                                    Image(systemName: "minus.circle")
                                        .font(.system(size: 12))
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.gray.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
        .sheet(isPresented: $showingAppSelection) {
            AppSelectionView(groupId: group.id)
                .environmentObject(sharedData)
        }
    }
}

struct CreateGroupView: View {
    @Binding var groupName: String
    let onCreate: (String) -> Void
    let onCancel: () -> Void
    @EnvironmentObject var sharedData: SharedData
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Create New Group")
                .font(.headline)
                .padding(.top)
            
            TextField("Group Name", text: $groupName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused($isTextFieldFocused)
                .onSubmit {
                    onCreate(groupName)
                }
                .padding(.horizontal)
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)
                
                Button("Create") {
                    onCreate(groupName)
                }
                .keyboardShortcut(.return)
                .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .frame(width: 300, height: 150)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
        .onChange(of: isTextFieldFocused) { focused in
            sharedData.isTextInputActive = focused
        }
    }
}

struct AppSelectionView: View {
    let groupId: UUID
    @EnvironmentObject var sharedData: SharedData
    @Environment(\.dismiss) private var dismiss
    
    var availableApps: [String] {
        let groupApps = sharedData.appGroups.first(where: { $0.id == groupId })?.appNames ?? []
        return sharedData.availableApps.filter { !groupApps.contains($0) }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Add Apps to Group")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding()
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(availableApps, id: \.self) { appName in
                        Button(action: {
                            sharedData.addAppToGroup(groupId: groupId, appName: appName)
                        }) {
                            HStack {
                                Text(appName)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.blue)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(.gray.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal)
            }
        }
        .frame(width: 400, height: 500)
    }
}



struct SearchModeView: View {
    @EnvironmentObject var sharedData: SharedData
    @FocusState private var isTextFieldFocused: Bool
    @State private var textSearcher = DesktopTextSearcher()
    @State private var searchDebounceTimer: DispatchWorkItem?
    @State private var eventMonitor: Any?
    
    var body: some View {
        VStack {
            HStack {
                TextField("Search text...", text: $sharedData.searchQuery)
                    .textFieldStyle(.plain)
                    .focused($isTextFieldFocused)
                    .font(.system(size: 16))
                    .onSubmit {
                        // First check if the query matches a label
                        let trimmedQuery = sharedData.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let labelMatch = textSearcher.findElementByLabel(trimmedQuery) {
                            clickOnElement(labelMatch, clickType: .left)
                        } else if !sharedData.textSearchResults.isEmpty && sharedData.selectedResultIndex < sharedData.textSearchResults.count {
                            let selectedMatch = sharedData.textSearchResults[sharedData.selectedResultIndex]
                            clickOnText(selectedMatch, clickType: .left)
                        }
                    }
                    .onMoveCommand { direction in
                        if direction == .up {
                            sharedData.selectedResultIndex = max(0, sharedData.selectedResultIndex - 1)
                            sharedData.updateTextSearchOverlay()
                        } else if direction == .down {
                            sharedData.selectedResultIndex = min(sharedData.textSearchResults.count - 1, sharedData.selectedResultIndex + 1)
                            sharedData.updateTextSearchOverlay()
                        }
                    }
                    .onChange(of: sharedData.searchQuery) { newValue in
                        performSearch(query: newValue)
                    }
                
                if sharedData.isSearching {
                    ProgressView()
                        .scaleEffect(0.5)
                } else if (!sharedData.searchQuery.isEmpty) {
                    Text("\(sharedData.textSearchResults.count) matches")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24.0)
        }
        .frame(width: 320)
        .padding(.bottom, 24.0)
        .background(.clear)
        .clipped()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
            
            // Extract text from front app window
            if sharedData.lastPid > 0 {
                textSearcher.extractTextFromFrontApp(pid: pid_t(sharedData.lastPid))
                
                // Show clickable elements overlay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let clickableElements = textSearcher.getClickableElements()
                    if !clickableElements.isEmpty {
                        sharedData.showClickableElementsOverlay(clickableElements)
                        print("📍 Showing \(clickableElements.count) clickable elements with labels")
                    }
                }
            }
            
            // Add local event monitor for key presses
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                return handleKeyEvent(event)
            }
        }
        .onDisappear {
            searchDebounceTimer?.cancel()
            textSearcher.clearAccessibilityElements()
            sharedData.hideClickableElementsOverlay()
            
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard isTextFieldFocused else { return event }

        // Check for Enter key (keyCode 36 for Return, 76 for Enter on numpad)
        if event.keyCode == 36 || event.keyCode == 76 {
            // First check if the query matches a label
            let trimmedQuery = sharedData.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if let labelMatch = textSearcher.findElementByLabel(trimmedQuery) {
                let flags = event.modifierFlags
                
                if flags.contains(.shift) {
                    clickOnElement(labelMatch, clickType: .moveOnly)
                    return nil // Event handled
                } else if flags.contains(.control) {
                    clickOnElement(labelMatch, clickType: .right)
                    return nil // Event handled
                }
                // Default case (left click) is handled by onSubmit
                return event
            }
            
            // Fallback to text search results
            guard !sharedData.textSearchResults.isEmpty,
                  sharedData.selectedResultIndex < sharedData.textSearchResults.count else {
                return event
            }
            
            let selectedMatch = sharedData.textSearchResults[sharedData.selectedResultIndex]
            let flags = event.modifierFlags
            
            if flags.contains(.shift) {
                clickOnText(selectedMatch, clickType: .moveOnly)
                return nil // Event handled
            } else if flags.contains(.control) {
                clickOnText(selectedMatch, clickType: .right)
                return nil // Event handled
            }
        }
        
        return event // Pass event through
    }

    
    private func performSearch(query: String) {
        searchDebounceTimer?.cancel()
        
        guard !query.isEmpty else {
            sharedData.textSearchResults = []
            sharedData.selectedResultIndex = 0
            sharedData.hideTextSearchOverlay()
            sharedData.updateClickableElementsHighlight(nil)
            sharedData.updateClickableElementsFilter(nil)
            return
        }

        // First check if the query matches a label
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        sharedData.updateClickableElementsFilter(trimmedQuery)
        if let labelMatch = textSearcher.findElementByLabel(trimmedQuery) {
            // Highlight the matching label
            sharedData.updateClickableElementsHighlight(trimmedQuery)
            
            // Clear text search results since we found a label match
            sharedData.textSearchResults = []
            sharedData.selectedResultIndex = 0
            sharedData.hideTextSearchOverlay()
            
            print("🏷️ Found label match for '\(trimmedQuery)': \(labelMatch.text)")
            return
        }
        
        // Clear label highlight if no label match
        sharedData.updateClickableElementsHighlight(nil)
        
        searchDebounceTimer = DispatchWorkItem {
            sharedData.isSearching = true
            
            textSearcher.searchForText(query, exactMatch: false) { matches in
                DispatchQueue.main.async {
                    sharedData.textSearchResults = Array(matches.prefix(10)) // Show more results now
                    sharedData.selectedResultIndex = 0 // Reset selection to first item
                    sharedData.isSearching = false
                    
                    print("Search completed with \(matches.count) matches")
                    
                    // Show overlay with results
                    print("About to call updateTextSearchOverlay()")
                    sharedData.updateTextSearchOverlay()
                }
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: searchDebounceTimer!)
    }
    
    private enum ClickType {
        case left, right, moveOnly
    }
    
    private func clickOnText(_ match: DesktopTextSearcher.TextMatch, clickType: ClickType) {
        print("Selected match \(sharedData.selectedResultIndex + 1) of \(sharedData.textSearchResults.count):")
        print("Text: '\(match.text)'")
        print("Center point: \(match.centerPoint)")
        print("Full bounds: \(match.screenPosition)")
        
        // Pause event tap before exiting search mode (same as ESC key handling)
        print("▶️ Pausing event tap for search exit")
        if let appDelegate = AppDelegate.shared,
           let tap = appDelegate.eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        
        sharedData.exitSearchMode()
        NSApp.hide(nil)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            switch clickType {
            case .left:
                self.textSearcher.clickAtPoint(match.centerPoint)
            case .right:
                self.textSearcher.rightClickAtPoint(match.centerPoint)
            case .moveOnly:
                self.textSearcher.moveMouseToPoint(match.centerPoint)
            }
        }
        
        // Resume event tap after click (same as ESC key handling)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            print("◀️ Resuming event tap after search exit")
            if let appDelegate = AppDelegate.shared,
               let tap = appDelegate.eventTap {
                let wasEnabled = CGEvent.tapIsEnabled(tap: tap)
                print("🔍 Event tap enabled before resume: \(wasEnabled)")
                
                if !wasEnabled {
                    CGEvent.tapEnable(tap: tap, enable: true)
                    let isNowEnabled = CGEvent.tapIsEnabled(tap: tap)
                    print("🔍 Event tap enabled after resume attempt: \(isNowEnabled)")
                    
                    if isNowEnabled {
                        print("✅ Event tap resumed successfully.")
                    } else {
                        print("❌ Failed to resume event tap, attempting recovery.")
                        appDelegate.recoverEventTap()
                    }
                } else {
                    print("ℹ️ Event tap was already enabled, no resume needed.")
                }
            } else {
                print("❌ Could not access AppDelegate or event tap is nil")
            }
        }
    }
    
    private func clickOnElement(_ element: DesktopTextSearcher.AccessibilityTextElement, clickType: ClickType) {
        print("Clicking on labeled element:")
        print("Label: '\(element.label ?? "no label")'")
        print("Text: '\(element.text)'")
        print("Center point: \(element.centerPoint)")
        print("Full bounds: \(element.boundingRect)")
        
        // Pause event tap before exiting search mode (same as ESC key handling)
        print("▶️ Pausing event tap for search exit")
        if let appDelegate = AppDelegate.shared,
           let tap = appDelegate.eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        
        sharedData.exitSearchMode()
        NSApp.hide(nil)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            switch clickType {
            case .left:
                self.textSearcher.clickAtPoint(element.centerPoint)
            case .right:
                self.textSearcher.rightClickAtPoint(element.centerPoint)
            case .moveOnly:
                self.textSearcher.moveMouseToPoint(element.centerPoint)
            }
        }
        
        // Resume event tap after click (same as ESC key handling)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            print("◀️ Resuming event tap after search exit")
            if let appDelegate = AppDelegate.shared,
               let tap = appDelegate.eventTap {
                let wasEnabled = CGEvent.tapIsEnabled(tap: tap)
                print("🔍 Event tap enabled before resume: \(wasEnabled)")
                
                if !wasEnabled {
                    CGEvent.tapEnable(tap: tap, enable: true)
                    let isNowEnabled = CGEvent.tapIsEnabled(tap: tap)
                    print("🔍 Event tap enabled after resume attempt: \(isNowEnabled)")
                    
                    if isNowEnabled {
                        print("✅ Event tap resumed successfully.")
                    } else {
                        print("❌ Failed to resume event tap, attempting recovery.")
                        appDelegate.recoverEventTap()
                    }
                } else {
                    print("ℹ️ Event tap was already enabled, no resume needed.")
                }
            } else {
                print("❌ Could not access AppDelegate or event tap is nil")
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var sharedData = SharedData()
    static var previews: some View {
        SearchModeView()
            .environmentObject(sharedData)
    }
}
