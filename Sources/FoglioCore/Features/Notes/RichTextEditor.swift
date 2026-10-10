import SwiftUI
import AppKit

/// Shared by Notes and task descriptions, including selection formatting.
struct RichTextEditor: View {
    let id: UUID
    @Binding var markdown: String
    @Bindable var controller: NoteEditorController
    let theme: Theme
    let baseURL: URL
    var placeholder = "Start writing…"
    var requestFocus = false
    var accessibilityName = "Note text"
    var onBlur: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            RichEditorToolbar(controller: controller, theme: theme)
            ZStack(alignment: .topLeading) {
                ContinuousNoteEditor(noteID: id, markdown: markdown, color: NSColor(theme.text),
                                     checklistAccent: NSColor(theme.accent), checklistInk: NSColor(theme.onAccent),
                                     checklistOutline: NSColor(theme.muted), controller: controller,
                                     requestFocus: requestFocus, onChange: { markdown = $0 }, onBlur: onBlur,
                                     attachmentBaseURL: baseURL, accessibilityName: accessibilityName,
                                     linkColor: NSColor(theme.accentDeep))
                if markdown.isEmpty {
                    Text(placeholder).font(Typo.sans(14)).foregroundStyle(theme.muted)
                        .padding(.horizontal, 28).padding(.top, 20).allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                if controller.hasSelection && controller.selectionPoint.y >= 42 {
                    GeometryReader { geometry in
                        InlineFormatBar(controller: controller, theme: theme)
                            .padding(5).background(theme.raised).clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.line, lineWidth: 1))
                            .shadow(theme.shadowFloat)
                            .fixedSize()
                            .offset(x: max(8, min(controller.selectionPoint.x - 105, geometry.size.width - 218)),
                                    y: max(4, min(controller.selectionPoint.y - 40, geometry.size.height - 38)))
                    }
                }
            }
        }
        .background(theme.surface).tint(theme.accentDeep)
        .alert("Couldn't attach file", isPresented: Binding(get: { controller.errorMessage != nil }, set: { if !$0 { controller.errorMessage = nil } })) {
            Button("OK") { controller.errorMessage = nil }
        } message: { Text(controller.errorMessage ?? "") }
    }
}

struct RichEditorToolbar: View {
    @Bindable var controller: NoteEditorController
    let theme: Theme
    @State private var linkLabel = ""
    @State private var linkURL = ""
    @FocusState private var linkFocused: Bool

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 6) {
            Menu {
                ForEach([EditorCommand.body, .heading1, .heading2, .heading3, .heading4, .quote], id: \.self) { command in
                    Button(command.label) { controller.insert(command) }
                }
            } label: {
                Label(styleLabel, systemImage: "textformat").font(Typo.sans(11.5)).foregroundStyle(theme.text)
            }.menuStyle(.borderlessButton).fixedSize().disabled(controller.selectedStyle == .table)
            InlineFormatBar(controller: controller, theme: theme)
            if controller.selectedStyle == .table {
                Menu {
                    Button("Add row") { controller.textView?.editTable(.addRow) }
                    Button("Add column") { controller.textView?.editTable(.addColumn) }
                    Divider()
                    Button("Delete this row") { controller.textView?.editTable(.deleteRow) }.disabled(!controller.canDeleteTableRow)
                    Button("Delete this column") { controller.textView?.editTable(.deleteColumn) }.disabled(!controller.canDeleteTableColumn)
                    Button("Convert table to text") { controller.textView?.editTable(.remove) }
                } label: {
                    Label("Table", systemImage: "tablecells").font(Typo.sans(11.5)).foregroundStyle(theme.text)
                }.menuStyle(.borderlessButton).fixedSize()
            }
            Menu {
                Button("Bulleted list") { controller.insert(.bullet) }
                Button("Numbered list") { controller.insert(.numbered) }
                Button("Checklist") { controller.insert(.checklist) }
                Button("Check or uncheck item") { controller.toggleChecklist() }.disabled(controller.selectedStyle != .checklist)
                Divider()
                Button("Remove list") { controller.format(.body) }
            } label: {
                Image(systemName: "list.bullet").foregroundStyle(theme.text).frame(width: 26, height: 26)
            }.menuStyle(.borderlessButton).fixedSize().help("Lists").disabled(controller.selectedStyle == .table)
            tool("checklist", help: "Checklist (⌘⇧7)", enabled: controller.selectedStyle != .table) { controller.insert(.checklist) }
            Menu {
                ForEach([EditorCommand.quote, .codeBlock, .divider, .table, .date, .attachment, .emoji], id: \.self) { command in
                    Button(command.label) { controller.insert(command) }
                }
                Divider()
                Button("Copy as Markdown") { controller.insert(.copyMarkdown) }
            } label: {
                Image(systemName: "plus.circle").foregroundStyle(theme.text).frame(width: 26, height: 26)
            }.menuStyle(.borderlessButton).fixedSize().help("Insert")
            tool("paperclip", help: "Attach a file or image (⌘⇧U)") { controller.insert(.attachment) }
            tool("arrow.uturn.backward", help: "Undo (⌘Z)", enabled: controller.canUndo) { controller.undo() }
            tool("arrow.uturn.forward", help: "Redo (⌘⇧Z)", enabled: controller.canRedo) { controller.redo() }
            Text("Type / for tools").font(Typo.sans(10.5)).foregroundStyle(theme.muted)
        }
        .padding(.horizontal, 24).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(theme.lineSoft).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(theme.lineSoft).frame(height: 1) }
        .popover(isPresented: $controller.linkRequested, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Insert link").font(Typo.sans(14, .semibold))
                TextField("Link text", text: $linkLabel).textFieldStyle(.plain)
                    .padding(8).background(theme.field).clipShape(RoundedRectangle(cornerRadius: 6))
                TextField("https://…", text: $linkURL).textFieldStyle(.plain).focused($linkFocused)
                    .padding(8).background(theme.field).clipShape(RoundedRectangle(cornerRadius: 6))
                    .onSubmit(applyLink)
                HStack {
                    Button("Remove link") { controller.textView?.removeLink(); controller.linkRequested = false }
                        .buttonStyle(.flat).foregroundStyle(theme.muted).disabled(!controller.hasSelection)
                    Spacer()
                    Button("Insert", action: applyLink).buttonStyle(.flat)
                        .foregroundStyle(theme.onAccent).padding(.horizontal, 12).padding(.vertical, 7)
                        .background(InlineMarkdown.safeURL(linkURL) != nil ? theme.accent : theme.muted)
                        .clipShape(RoundedRectangle(cornerRadius: 6)).disabled(InlineMarkdown.safeURL(linkURL) == nil)
                }
            }
            .font(Typo.sans(12)).foregroundStyle(theme.text).padding(16).frame(width: 320)
            .background(theme.surface).preferredColorScheme(theme.isDark ? .dark : .light)
            .onAppear { linkLabel = controller.selectedText; linkURL = ""; linkFocused = true }
        }
    }
    private var styleLabel: String {
        switch controller.selectedStyle {
        case .title: "Heading 1"
        case .heading: "Heading 2"
        case .heading3: "Heading 3"
        case .heading4: "Heading 4"
        case .quote: "Quote"
        default: "Text"
        }
    }
    private func applyLink() {
        guard InlineMarkdown.safeURL(linkURL) != nil else { return }
        controller.link(label: linkLabel, url: linkURL)
        controller.linkRequested = false
    }
    private func tool(_ symbol: String, help: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12))
                .foregroundStyle(enabled ? theme.text : theme.muted.opacity(0.5))
                .frame(width: 26, height: 26).hoverHighlight(theme, cornerRadius: 5, active: enabled)
        }.buttonStyle(.flat).help(help).accessibilityLabel(help).disabled(!enabled)
    }
}

struct InlineFormatBar: View {
    @Bindable var controller: NoteEditorController
    let theme: Theme
    var body: some View {
        HStack(spacing: 2) {
            ForEach(InlineFormat.allCases, id: \.self) { format in
                let active = controller.selectedFormats.contains(format)
                Button { controller.toggle(format) } label: {
                    Image(systemName: format.symbol).font(.system(size: 12))
                        .foregroundStyle(active ? theme.accentDeep : theme.text)
                        .frame(width: 26, height: 26).background(active ? theme.accentSoft : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5)).hoverHighlight(theme, cornerRadius: 5, active: !active)
                }.buttonStyle(.flat).help(format.label).accessibilityLabel(format.label)
                    .accessibilityAddTraits(active ? .isSelected : [])
            }
            Button { controller.linkRequested = true } label: {
                Image(systemName: "link").font(.system(size: 12)).foregroundStyle(theme.text)
                    .frame(width: 26, height: 26).hoverHighlight(theme, cornerRadius: 5)
            }.buttonStyle(.flat).help("Link (⌘K)").accessibilityLabel("Insert link")
        }
        .disabled([.codeBlock, .literal].contains(controller.selectedStyle))
    }
}
