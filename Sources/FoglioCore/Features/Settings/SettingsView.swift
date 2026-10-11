import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// A focused page for each preference group, with navigation that stays visible.
struct SettingsView: View {
    @Bindable var state: AppState
    let store: Store
    @State private var pane: SettingsPane
    @State private var exportStatus: String?
    @State private var copiedSetup: String?
    @State private var copiedReset: Task<Void, Never>?
    @State private var pendingImport: Archive?
    @State private var confirmingImport = false
    private var theme: Theme { state.theme }

    init(state: AppState, store: Store, initialPane: SettingsPane = .appearance) {
        self.state = state; self.store = store
        _pane = State(initialValue: initialPane)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            navigation
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(pane.title).font(Typo.sans(25, .semibold)).foregroundStyle(theme.text)
                            .accessibilityAddTraits(.isHeader)
                        Text(pane.subtitle).font(Typo.sans(12.5)).foregroundStyle(theme.muted)
                    }
                    page
                }.frame(maxWidth: 780, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(32)
            }.id(pane).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(theme.bg).tint(theme.accentDeep)
            .preferredColorScheme(theme.isDark ? .dark : .light)
            .onDisappear { copiedReset?.cancel() }
            .alert("Replace your library?", isPresented: $confirmingImport) {
                Button("Replace library", role: .destructive, action: applyImport)
                Button("Cancel", role: .cancel) { pendingImport = nil }
            } message: {
                Text("This archive contains \(pendingImport?.notes.count ?? 0) notes and \(pendingImport?.tasks.count ?? 0) tasks. Importing replaces your current library. Export a backup first if you want to keep it.")
            }
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings").font(Typo.sans(17, .semibold)).foregroundStyle(theme.text)
                .padding(.horizontal, 12).padding(.top, 20).padding(.bottom, 20)
            ForEach(SettingsPane.allCases) { item in
                let selected = pane == item
                Button { pane = item } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol).font(.system(size: 13)).frame(width: 18)
                        Text(item.title).font(Typo.sans(12, selected ? .semibold : .regular))
                        Spacer(minLength: 0)
                    }.foregroundStyle(selected ? theme.accentDeep : theme.muted)
                        .padding(.horizontal, 12).frame(height: 38)
                        .background(selected ? theme.accentSoft : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .hoverHighlight(theme, cornerRadius: 7, active: !selected)
                }.buttonStyle(.flat).modifier(SettingsFocus(theme: theme))
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle").foregroundStyle(theme.accentDeep)
                Text("Preferences save automatically").font(Typo.sans(10)).foregroundStyle(theme.muted)
            }.padding(12).padding(.bottom, 10)
        }.padding(.horizontal, 12).frame(width: 208).frame(maxHeight: .infinity)
            .background(theme.surface.opacity(0.5))
            .overlay(alignment: .trailing) { Rectangle().fill(theme.line).frame(width: 1) }
    }

    @ViewBuilder private var page: some View {
        switch pane {
        case .appearance: appearancePage
        case .workflow: workflowPage
        case .agents: agentsPage
        case .storage: storagePage
        case .shortcuts: shortcutsPage
        }
    }

    private var appearancePage: some View {
        VStack(spacing: 20) {
            SettingsCard("Theme", hint: "Eight palettes, applied across your workspace.", theme: theme) {
                HStack(spacing: 8) {
                    Circle().fill(theme.accent).frame(width: 8, height: 8)
                    Text(state.themeMode.label).font(Typo.sans(11.5, .medium)).foregroundStyle(theme.text)
                    Text("· Active theme").font(Typo.sans(11.5)).foregroundStyle(theme.muted)
                }
                themeShelf("Light", ThemeMode.lightModes)
                themeShelf("Dark", ThemeMode.darkModes)
            }
            SettingsCard("Floating bar", theme: theme) {
                SettingsRow("Position", hint: "Dock the bar to an edge, or drag it there whenever you like.", theme: theme) {
                    segmented(options: BarEdge.allCases.map { ($0.label, $0) }, selection: state.barEdge) { state.barEdge = $0 }
                }
            }
        }
    }

    private func themeShelf(_ title: String, _ modes: [ThemeMode]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Typo.sans(11, .medium)).foregroundStyle(theme.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                ForEach(modes) { themeSwatch($0) }
            }
        }
    }
    private func themeSwatch(_ mode: ThemeMode) -> some View {
        let palette = mode.theme
        let selected = state.themeMode == mode
        return Button { state.themeMode = mode } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 0) {
                    VStack(spacing: 7) {
                        Circle().fill(palette.accent).frame(width: 6, height: 6)
                        RoundedRectangle(cornerRadius: 2).fill(palette.muted.opacity(0.5)).frame(width: 13, height: 3)
                        RoundedRectangle(cornerRadius: 2).fill(palette.muted.opacity(0.3)).frame(width: 13, height: 3)
                        Spacer(minLength: 0)
                    }.padding(.vertical, 12).frame(width: 28).background(palette.field)
                    VStack(alignment: .leading, spacing: 7) {
                        bar(palette.text, width: 44)
                        bar(palette.muted.opacity(0.7), width: 58)
                        HStack(spacing: 5) {
                            Circle().stroke(palette.accentDeep, lineWidth: 1).frame(width: 7, height: 7)
                            bar(palette.muted, width: 35)
                        }
                        RoundedRectangle(cornerRadius: 3).fill(palette.accent).frame(width: 30, height: 8)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 78).background(palette.surface).clipShape(RoundedRectangle(cornerRadius: 6))
                HStack {
                    Text(mode.label).font(Typo.sans(11, selected ? .semibold : .regular)).lineLimit(1)
                    Spacer(minLength: 2)
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accentDeep)
                        .opacity(selected ? 1 : 0)
                }.foregroundStyle(theme.text)
            }.padding(9).background(selected ? theme.accentSoft.opacity(0.6) : theme.field)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(selected ? theme.accentDeep : theme.line, lineWidth: selected ? 1.5 : 1) }
        }.buttonStyle(.flat).modifier(SettingsFocus(theme: theme))
            .accessibilityLabel(mode.label).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func bar(_ color: Color, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: width, height: 3)
    }

    private var workflowPage: some View {
        VStack(spacing: 20) {
            SettingsCard("Tasks", theme: theme) {
                SettingsRow("Log completed tasks", hint: "Add completed tasks to today's activity log.", theme: theme) {
                    Toggle("Log completed tasks", isOn: $state.autoLog).labelsHidden().toggleStyle(SettingsSwitch(theme: theme))
                }
                separator
                SettingsRow("Close on outside click", hint: "Close the task editor when clicking outside. Unsaved changes always ask for confirmation.", theme: theme) {
                    Toggle("Close task on outside click", isOn: $state.closeTaskOnOutsideClick).labelsHidden().toggleStyle(SettingsSwitch(theme: theme))
                }
            }
            SettingsCard("Calendar", theme: theme) {
                SettingsRow("Meeting reminder", hint: "Start the floating bar's countdown before your next meeting.", theme: theme) {
                    segmented(options: [("5 min", 5), ("10 min", 10), ("15 min", 15)], selection: state.meetingLeadMinutes) { state.meetingLeadMinutes = $0 }
                }
            }
        }
    }

    private var agentsPage: some View {
        VStack(spacing: 20) {
            SettingsCard("Access", hint: "Agents use your workspace while Foglio is open.", theme: theme) {
                HStack(spacing: 8) {
                    Circle().fill(state.agentConnectorEnabled ? theme.accent : theme.muted).frame(width: 7, height: 7)
                    Text(state.agentConnectorStatus).font(Typo.sans(11.5)).foregroundStyle(theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(theme.field)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                SettingsRow("Allow connections", hint: "Let your agents read notes, tasks, and connected calendars.", theme: theme) {
                    Toggle("Allow agents to connect", isOn: $state.agentConnectorEnabled).labelsHidden().toggleStyle(SettingsSwitch(theme: theme))
                }
                separator
                SettingsRow("Allow changes", hint: "Let connected agents create and update workspace items.", theme: theme) {
                    Toggle("Allow agents to make changes", isOn: $state.agentConnectorAllowEdits).labelsHidden()
                        .toggleStyle(SettingsSwitch(theme: theme)).disabled(!state.agentConnectorEnabled)
                }
            }
            SettingsCard("Connect an agent", hint: "Copy a setup command or configuration into your agent's MCP settings.", theme: theme) {
                agentSetupRow("Codex", hint: "Run the command in Terminal.", button: "Copy Codex setup", value: AgentConnectorSetup.codexCommand)
                separator
                agentSetupRow("Claude Code", hint: "Run the command in Terminal.", button: "Copy Claude Code setup", value: AgentConnectorSetup.claudeCodeCommand)
                separator
                agentSetupRow("Claude Desktop", hint: "Add the configuration to your desktop MCP settings.", button: "Copy Claude Desktop config", value: AgentConnectorSetup.claudeConfiguration)
            }
            Label("Connections stay on this Mac. Calendar changes need a writable macOS calendar; calendar URLs and .ics files support reading.", systemImage: "lock")
                .font(Typo.sans(11.5)).foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func agentSetupRow(_ title: String, hint: String, button: String, value: String) -> some View {
        SettingsRow(title, hint: hint, theme: theme) {
            let copied = copiedSetup == button
            Button { copyAgentSetup(button, value) } label: {
                ZStack {
                    Label("Copy setup", systemImage: "doc.on.doc").opacity(copied ? 0 : 1)
                    Label("Copied", systemImage: "checkmark").opacity(copied ? 1 : 0)
                }
            }.buttonStyle(.flat).modifier(SettingsFocus(theme: theme))
                .font(Typo.sans(11.5, .medium)).foregroundStyle(theme.accentDeep)
                .padding(.horizontal, 12).padding(.vertical, 8).background(theme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityLabel(copied ? "Copied to clipboard" : button)
                .help(copied ? "Copied to clipboard" : button)
        }
    }

    private var storagePage: some View {
        VStack(spacing: 20) {
            SettingsCard("Your library", hint: "Notes are saved as Markdown files you can read anywhere.", theme: theme) {
                HStack(spacing: 24) {
                    libraryCount(store.notes.count, label: "Notes")
                    libraryCount(store.tasks.count, label: "Tasks")
                    libraryCount(store.folders.count, label: "Folders")
                    Spacer()
                }
                separator
                Text(store.root.path).font(Typo.mono(10.5)).foregroundStyle(theme.muted)
                    .textSelection(.enabled).lineLimit(3).help(store.root.path)
                actionButton("Show in Finder", symbol: "folder") { NSWorkspace.shared.open(store.root) }
            }
            SettingsCard("Export & import", hint: "Keep a portable copy of your workspace.", theme: theme) {
                SettingsRow("Export library", hint: "Save readable Markdown files and a complete Foglio archive, including attachments.", theme: theme) {
                    actionButton("Export…", symbol: "square.and.arrow.up", primary: true, action: exportBundle)
                }
                separator
                SettingsRow("Import library", hint: "Restore a Foglio archive. This replaces your current library, so export a backup first.", theme: theme) {
                    actionButton("Import…", symbol: "square.and.arrow.down", action: importBundle)
                }
                if let exportStatus {
                    Text(exportStatus).font(Typo.sans(11.5)).foregroundStyle(theme.text)
                        .textSelection(.enabled).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.field).clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }
    private func libraryCount(_ count: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(count.formatted()).font(Typo.sans(22, .semibold)).foregroundStyle(theme.text)
            Text(label).font(Typo.sans(11)).foregroundStyle(theme.muted)
        }
    }

    private var shortcutsPage: some View {
        VStack(spacing: 20) {
            shortcutCard("From anywhere", rows: [
                ("New note in Scratch", "⌘⇧N"),
                ("Quick capture", "⌘⇧Space"),
                ("Open tasks", "⌘⇧T")
            ])
            shortcutCard("In Foglio", rows: [
                ("New note", "⌘N"),
                ("Find in the current section", "⌘F"),
                ("Insert link in the editor", "⌘K"),
                ("Open settings", "⌘,"),
                ("Save task changes", "⌘⇧Return"),
                ("Close a popup or hide the window", "Esc")
            ])
        }
    }
    private func shortcutCard(_ title: String, rows: [(String, String)]) -> some View {
        SettingsCard(title, theme: theme) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 20) {
                        Text(row.0).font(Typo.sans(12)).foregroundStyle(theme.text)
                        Spacer()
                        Text(row.1).font(Typo.mono(11)).foregroundStyle(theme.accentDeep)
                            .padding(.horizontal, 10).padding(.vertical, 6).background(theme.field)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }.padding(.vertical, 10)
                    if index < rows.count - 1 { separator }
                }
            }
        }
    }

    private var separator: some View { Rectangle().fill(theme.lineSoft).frame(height: 1) }
    private func actionButton(_ title: String, symbol: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol).font(Typo.sans(11.5, .medium))
                .foregroundStyle(primary ? theme.onAccent : theme.text)
                .padding(.horizontal, 12).padding(.vertical, 8).background(primary ? theme.accent : theme.field)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.flat).modifier(SettingsFocus(theme: theme))
    }
    private func segmented<Value: Equatable>(options: [(String, Value)], selection: Value, onPick: @escaping (Value) -> Void) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = option.1 == selection
                Button { onPick(option.1) } label: {
                    Text(option.0).font(Typo.sans(11.5, .medium)).foregroundStyle(selected ? theme.onAccent : theme.muted)
                        .frame(width: 55).padding(.vertical, 7).background(selected ? theme.accent : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }.buttonStyle(.flat).modifier(SettingsFocus(theme: theme))
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }.padding(3).background(theme.field).clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).stroke(theme.line, lineWidth: 1) }
    }

    private func copyAgentSetup(_ title: String, _ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        withAnimation(.easeOut(duration: 0.15)) { copiedSetup = title }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: "Copied to clipboard", .priority: NSAccessibilityPriorityLevel.high.rawValue])
        copiedReset?.cancel()
        copiedReset = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { copiedSetup = nil }
        }
    }

    private func exportBundle() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export here"
        panel.message = "Choose where to write the Foglio export folder."
        guard panel.runModal() == .OK, let parent = panel.url else { return }

        do {
            let root = try Exporter.export(Exporter.archive(from: store), to: parent)
            exportStatus = "Exported to \(root.lastPathComponent)"
        } catch {
            exportStatus = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importBundle() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]; panel.prompt = "Import"
        panel.message = "Choose a Foglio export folder or its foglio-archive.json."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            pendingImport = try Exporter.importArchive(from: url)
            confirmingImport = true
        } catch { exportStatus = "Import failed: \(error.localizedDescription)" }
    }
    private func applyImport() {
        guard let archive = pendingImport else { return }
        store.clearPersistenceError()
        store.replaceAll(with: archive)
        state.activeNoteId = nil; state.folderFilter = nil; state.search = ""; state.endNoteSelection()
        exportStatus = store.persistenceError.map { "Import failed: " + $0 }
            ?? "Imported \(archive.notes.count) notes and \(archive.tasks.count) tasks"
        pendingImport = nil
    }
}
