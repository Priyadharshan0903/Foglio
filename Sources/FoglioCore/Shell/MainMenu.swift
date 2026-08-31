import AppKit

/// Builds the menu bar.
///
/// This isn't decoration: without an Edit menu, macOS gives text views no
/// ⌘C/⌘V/⌘X/⌘A/⌘Z at all, so the note editor would be unusable. The items below
/// use the standard responder-chain selectors, so they apply to whichever text
/// view is focused without any wiring.
@MainActor
enum MainMenu {
    static func install(
        onQuickCapture: @escaping () -> Void,
        onNewNote: @escaping () -> Void,
        onTasks: @escaping () -> Void,
        onSearch: @escaping () -> Void,
        onSettings: @escaping () -> Void
    ) {
        let main = NSMenu()

        // MARK: App
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Foglio", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(action(title: "Settings…", key: ",", modifiers: .command, handler: onSettings))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Foglio", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Foglio", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        // MARK: File
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(action(title: "New Note", key: "n", modifiers: [.command, .shift], handler: onNewNote))
        fileMenu.addItem(action(title: "Quick Capture", key: " ", modifiers: [.command, .shift], handler: onQuickCapture))
        fileMenu.addItem(.separator())
        let close = NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(close)
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        // MARK: Edit — standard selectors, resolved through the responder chain.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        editMenu.addItem(action(title: "Find…", key: "k", modifiers: .command, handler: onSearch))
        editItem.submenu = editMenu
        main.addItem(editItem)

        // MARK: View
        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(action(title: "Tasks", key: "t", modifiers: [.command, .shift], handler: onTasks))
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        NSApp.mainMenu = main
    }

    /// A menu item backed by a closure rather than a selector.
    private static func action(
        title: String,
        key: String,
        modifiers: NSEvent.ModifierFlags,
        handler: @escaping () -> Void
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(ClosureTarget.fire), keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        let target = ClosureTarget(handler)
        item.target = target
        item.representedObject = target // keeps the target alive
        return item
    }
}

private final class ClosureTarget: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func fire() { handler() }
}
