import AppKit
import Carbon.HIToolbox
@testable import FoglioCore

@MainActor
func shortcutTests() {
    typealias Shortcut = HotKeyCenter.Shortcut
    let custom = Shortcut(keyCode: UInt32(kVK_ANSI_Slash), modifiers: UInt32(controlKey | optionKey), keyLabel: "/")
    Check.suite("Shortcuts — keyboard input and validation") {
        for key in ["7", "/", "é", "Ж", "あ"] {
            let shortcut = Shortcut(keyCode: 26, modifiers: UInt32(cmdKey | optionKey), keyLabel: key)
            Check.expect(shortcut.validationError == nil, "accepts keyboard character \(key)")
        }
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control, .option, .capsLock],
                                    timestamp: 0, windowNumber: 0, context: nil, characters: "/",
                                    charactersIgnoringModifiers: "/", isARepeat: false, keyCode: UInt16(kVK_ANSI_Slash))!
        Check.equal(Shortcut(event: event), custom, "records actual key code and shortcut modifiers, ignoring Caps Lock")
        Check.equal(custom.display, "⌃⌥/", "shows punctuation and modifiers")
        Check.equal(Shortcut(keyCode: 122, modifiers: UInt32(cmdKey), keyLabel: "F1").display, "⌘F1", "shows function keys")
        Check.equal(Shortcut(keyCode: 123, modifiers: UInt32(controlKey), keyLabel: "Left").display, "⌃←", "shows arrows")
        Check.expect(Shortcut.newNote.validationError == nil, "default remains valid")
        Check.expect(Shortcut.quickCapture.validationError != nil, "protects Quick Capture")
        Check.expect(Shortcut.tasks.validationError != nil, "protects Open Tasks")
        for invalid in [
            Shortcut(keyCode: 0, modifiers: 0, keyLabel: "A"),
            Shortcut(keyCode: 0, modifiers: UInt32(shiftKey), keyLabel: "A"),
            Shortcut(keyCode: 55, modifiers: UInt32(cmdKey), keyLabel: "Command"),
            Shortcut(keyCode: 999, modifiers: UInt32(cmdKey), keyLabel: "A"),
            Shortcut(keyCode: 0, modifiers: UInt32(cmdKey) | 1, keyLabel: "A"),
            Shortcut(keyCode: 0, modifiers: UInt32(cmdKey), keyLabel: ""),
            Shortcut(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(cmdKey), keyLabel: "Q")
        ] {
            Check.expect(invalid.validationError != nil, "rejects unsafe or conflicting binding \(invalid.display)")
        }
    }

    let suite = "FoglioShortcutTests-\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    Check.suite("Shortcuts — persistence and failed changes") {
        let state = AppState(defaults: defaults)
        Check.equal(state.newNoteShortcut, .newNote, "existing users keep Command Shift N")
        state.themeMode = .aubergine
        var installed: [Shortcut] = []
        state.installNewNoteShortcut = { installed.append($0) }
        Check.expect(state.setNewNoteShortcut(custom), "registers custom shortcut")
        Check.equal(installed, [custom], "applies change immediately")
        Check.equal(AppState(defaults: defaults).newNoteShortcut, custom, "restores custom shortcut after restart")
        let saved = defaults.data(forKey: "newNoteShortcut")
        state.installNewNoteShortcut = { _ in throw HotKeyCenter.RegistrationError(status: -9878) }
        Check.expect(!state.setNewNoteShortcut(.newNote), "reports registration conflict")
        Check.equal(state.newNoteShortcut, custom, "failed change preserves active preference")
        Check.equal(defaults.data(forKey: "newNoteShortcut"), saved, "failed change preserves disk preference")
        Check.expect(state.newNoteShortcutError != nil, "conflict is visible in Settings")
        Check.expect(!state.setNewNoteShortcut(.tasks), "rejects Foglio conflict before registration")
        state.installNewNoteShortcut = { installed.append($0) }
        Check.expect(state.setNewNoteShortcut(.newNote), "reset restores default")
        Check.expect(state.newNoteShortcutError == nil, "successful reset clears error")
        Check.equal(AppState(defaults: defaults).newNoteShortcut, .newNote, "reset persists")
        Check.equal(AppState(defaults: defaults).themeMode, .aubergine, "shortcut change preserves other preferences")
        defaults.set(Data("invalid json".utf8), forKey: "newNoteShortcut")
        Check.equal(AppState(defaults: defaults).newNoteShortcut, .newNote, "corrupt preference falls back safely")
        defaults.set(try! JSONEncoder().encode(Shortcut.tasks), forKey: "newNoteShortcut")
        Check.equal(AppState(defaults: defaults).newNoteShortcut, .newNote, "invalid saved shortcut falls back safely")
        for mode in ThemeMode.allCases {
            state.themeMode = mode
            Check.equal(AppState(defaults: defaults).themeMode, mode, "\(mode.label) selection persists")
        }
    }

    Check.suite("Shortcuts — transactional global registration") {
        var released: [UInt32] = []
        var reject = false
        let center = HotKeyCenter(register: { _, id in
            if reject { throw HotKeyCenter.RegistrationError(status: -9878) }
            return { released.append(id) }
        })
        var calls = 0
        let original = try! center.replace(nil, with: .newNote) { calls += 1 }
        reject = true
        do {
            _ = try center.replace(original, with: custom) { calls += 10 }
            Check.expect(false, "conflicting reservation must throw")
        } catch { Check.expect(released.isEmpty, "old hotkey stays registered on conflict") }
        center.dispatch(original)
        Check.equal(calls, 1, "old shortcut still invokes original action")
        reject = false
        let replacement = try! center.replace(original, with: custom) { calls += 10 }
        Check.equal(released, [original], "successful replacement releases previous registration")
        center.dispatch(original)
        Check.equal(calls, 1, "stale queued key events cannot create a note")
        center.dispatch(replacement)
        Check.equal(calls, 11, "new key invokes action")
        var recorded: Shortcut?
        center.recordingHandler = { recorded = $0 }
        center.dispatch(replacement)
        Check.equal(recorded, custom, "existing global shortcut reaches recorder")
        Check.equal(calls, 11, "recording prevents accidental note creation")
        center.recordingHandler = nil
        let same = try! center.replace(replacement, with: custom) { calls += 10 }
        Check.equal(same, replacement, "selecting current key avoids a duplicate reservation")
        Check.equal(released, [original], "selecting current key keeps registration")
    }
}
