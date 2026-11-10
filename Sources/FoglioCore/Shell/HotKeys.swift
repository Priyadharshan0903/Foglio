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
    private var registrations: [UInt32: () -> Void] = [:]
    private var shortcuts: [UInt32: Shortcut] = [:]
    private var installed = false
    private var nextId: UInt32 = 1
    private let registerNative: (Shortcut, UInt32) throws -> () -> Void
    private let usesSystemRegistration: Bool

    /// During recording, route Foglio's existing global keys to the recorder too.
    /// Carbon consumes these before AppKit's local key-event monitors see them.
    var recordingHandler: ((Shortcut) -> Void)?

    init(register: ((Shortcut, UInt32) throws -> () -> Void)? = nil) {
        usesSystemRegistration = register == nil
        registerNative = register ?? Self.registerSystem
    }

    @discardableResult
    func register(_ shortcut: Shortcut, action: @escaping () -> Void) -> UInt32? {
        do { return try replace(nil, with: shortcut, action: action) }
        catch { NSLog("Foglio: could not register hotkey: \(error.localizedDescription)"); return nil }
    }

    /// Reserve the candidate first. A failed change leaves the old key working.
    func replace(_ oldID: UInt32?, with shortcut: Shortcut, action: @escaping () -> Void) throws -> UInt32 {
        if let oldID, shortcuts[oldID] == shortcut { return oldID }
        if usesSystemRegistration { installHandlerIfNeeded() }
        let id = nextId
        nextId += 1
        let cancel = try registerNative(shortcut, id)
        registrations[id] = cancel
        handlers[id] = action
        shortcuts[id] = shortcut
        if let oldID {
            registrations.removeValue(forKey: oldID)?()
            handlers[oldID] = nil
            shortcuts[oldID] = nil
        }
        return id
    }

    func dispatch(_ id: UInt32) {
        if let recordingHandler, let shortcut = shortcuts[id] {
            recordingHandler(shortcut)
        } else {
            handlers[id]?()
        }
    }

    private static func registerSystem(_ shortcut: Shortcut, id: UInt32) throws -> () -> Void {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers,
            EventHotKeyID(signature: OSType(0x464C_474F), id: id),
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else { throw RegistrationError(status: status) }
        return { UnregisterEventHotKey(ref) }
    }

    struct RegistrationError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "That shortcut is unavailable or used by another app (macOS \(status)). Try a different combination."
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
                        HotKeyCenter.shared.dispatch(hotKeyId)
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
