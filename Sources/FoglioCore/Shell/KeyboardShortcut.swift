import AppKit
import Carbon.HIToolbox

extension HotKeyCenter {
    struct Shortcut: Codable, Equatable {
        let keyCode: UInt32
        let modifiers: UInt32
        /// Captured from the user's keyboard layout, rather than an ANSI letter table.
        let keyLabel: String

        static let newNote = Shortcut(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey | shiftKey), keyLabel: "N")
        static let quickCapture = Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey), keyLabel: "Space")
        static let tasks = Shortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | shiftKey), keyLabel: "T")

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
        }

        init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
            self.keyCode = keyCode; self.modifiers = modifiers; self.keyLabel = keyLabel
        }

        init(event: NSEvent) {
            keyCode = UInt32(event.keyCode)
            var flags: UInt32 = 0
            if event.modifierFlags.contains(.command) { flags |= UInt32(cmdKey) }
            if event.modifierFlags.contains(.control) { flags |= UInt32(controlKey) }
            if event.modifierFlags.contains(.option) { flags |= UInt32(optionKey) }
            if event.modifierFlags.contains(.shift) { flags |= UInt32(shiftKey) }
            modifiers = flags
            keyLabel = Self.specialKeys[keyCode]
                ?? event.characters(byApplyingModifiers: [])?.uppercased()
                ?? ""
        }

        var display: String {
            var prefix = ""
            if modifiers & UInt32(controlKey) != 0 { prefix += "⌃" }
            if modifiers & UInt32(optionKey) != 0 { prefix += "⌥" }
            if modifiers & UInt32(shiftKey) != 0 { prefix += "⇧" }
            if modifiers & UInt32(cmdKey) != 0 { prefix += "⌘" }
            return prefix + (Self.specialKeys[keyCode] ?? keyLabel)
        }

        var validationError: String? {
            let allowed = UInt32(cmdKey | controlKey | optionKey | shiftKey)
            guard keyCode < 128, ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode),
                  modifiers & ~allowed == 0,
                  !keyLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  keyLabel.count <= 32 else { return "Choose a key with Command, Control, or Option." }
            guard modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 else {
                return "Include Command, Control, or Option so typing doesn't create notes."
            }
            if self == .quickCapture { return "That shortcut is used by Quick Capture." }
            if self == .tasks { return "That shortcut is used by Open Tasks." }
            // Keep the app's existing menu and editing commands reachable.
            if modifiers == UInt32(cmdKey),
               ["q", "h", "w", "z", "x", "c", "v", "a", "f", "k", ","].contains(keyLabel.lowercased()) {
                return "That shortcut is already used by a Foglio menu command."
            }
            if modifiers == UInt32(cmdKey | shiftKey), ["z", "m", "return"].contains(keyLabel.lowercased()) {
                return "That shortcut is already used by a Foglio menu command."
            }
            if modifiers == UInt32(cmdKey | optionKey), keyLabel.lowercased() == "h" {
                return "That shortcut is already used by Hide Others."
            }
            return nil
        }

        private static let specialKeys: [UInt32: String] = [
            36: "Return", 48: "Tab", 49: "Space", 51: "⌫", 53: "Esc", 71: "Clear",
            76: "Enter", 114: "Help", 115: "Home", 116: "Page Up", 117: "⌦",
            119: "End", 121: "Page Down", 123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
            80: "F19", 90: "F20"
        ]
    }
}
