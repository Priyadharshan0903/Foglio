import AppKit
import SwiftUI
@testable import FoglioCore

/// Opt-in layout checks; all data and preferences are isolated from the app.
@MainActor
func renderSettingsPreviewsIfRequested() {
    guard let path = ProcessInfo.processInfo.environment["FOGLIO_SETTINGS_PREVIEWS"] else { return }
    Typo.registerBundledFonts()
    let output = URL(fileURLWithPath: path)
    try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("foglio-settings-preview-\(UUID())")
    let suite = "FoglioSettingsPreview-\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
    let store = Store(root: root); store.load()
    let state = AppState(defaults: defaults); state.section = .settings
    state.agentConnectorStatus = "Connected · Reading only"
    state.agentConnectorEnabled = true
    let calendar = CalendarSource(defaults: defaults, cacheRoot: root.appendingPathComponent("calendar"))
    func render<Content: View>(_ name: String, width: CGFloat = 1200, height: CGFloat = 860, content: Content) {
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.15)); host.layoutSubtreeIfNeeded()
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        }
        window.close()
    }
    for mode in ThemeMode.allCases {
        state.themeMode = mode
        render("appearance-" + mode.rawValue, content: SettingsView(state: state, store: store))
    }
    for mode in [ThemeMode.ember, .harbor] {
        state.themeMode = mode
        for pane in SettingsPane.allCases.filter({ $0 != .appearance }) {
            render(pane.rawValue + "-" + mode.rawValue, content: SettingsView(state: state, store: store, initialPane: pane))
        }
    }
    state.themeMode = .ember
    for pane in SettingsPane.allCases {
        render(pane.rawValue + "-compact", width: 700, height: 740,
               content: SettingsView(state: state, store: store, initialPane: pane))
    }
    render("settings-window", width: 1600, height: 940, content: MainWindowView(state: state, store: store, calendar: calendar))
    print("Settings previews saved to \(path)")
}
