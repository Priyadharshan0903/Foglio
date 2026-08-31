import AppKit
import Carbon.HIToolbox

/// System-wide shortcuts (Day Log.dc.html:1224).
///
/// Carbon's `RegisterEventHotKey` is used rather than a `CGEventTap` because it
/// needs no Accessibility permission — the app can register these on first
/// launch without sending the user to System Settings. It is old API but it is
/// not deprecated and remains the sanctioned route for global hotkeys.
///
/// ⌘K is deliberately absent: it only acts inside the window, so it's an
/// ordinary menu `.keyboardShortcut` instead of a global grab.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var registered: [EventHotKeyRef?] = []
    private var installed = false
    private var nextId: UInt32 = 1

    private init() {}

    struct Shortcut {
        let keyCode: UInt32
        let modifiers: UInt32

        /// ⌘⇧N — new note in Scratch
        static let newNote = Shortcut(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey | shiftKey))
        /// ⌘⇧Space — quick capture from anywhere
        static let quickCapture = Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey))
        /// ⌘⇧T — tasks
        static let tasks = Shortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | shiftKey))
    }

    func register(_ shortcut: Shortcut, action: @escaping () -> Void) {
        installHandlerIfNeeded()

        let id = nextId
        nextId += 1
        handlers[id] = action

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x464C_474F), id: id) // 'FLGO'
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            registered.append(ref)
        } else {
            // Another app already owns this combination. Not fatal — the same
            // action is always reachable from the bar and the rail.
            handlers[id] = nil
            NSLog("Foglio: could not register hotkey (status \(status))")
        }
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var id = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &id
                )
                guard status == noErr else { return status }
                let hotKeyId = id.id
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        HotKeyCenter.shared.handlers[hotKeyId]?()
                    }
                }
                return noErr
            },
            1,
            &spec,
            nil,
            nil
        )
    }
}
