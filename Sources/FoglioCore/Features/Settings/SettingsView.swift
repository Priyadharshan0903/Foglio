import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings, plus the shortcuts card on the inverted surface
/// (Day Log.dc.html:460-532).
///
/// The design's first group is a Google Workspace connection. Calendar is a v2
/// feature here and will read macOS Calendar via EventKit rather than Google
/// OAuth, so that row is replaced by the store location — the thing a user of
/// this build actually wants to find.
struct SettingsView: View {
    @Bindable var state: AppState
    let store: Store

    @State private var exportStatus: String?

    private var theme: Theme { state.theme }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Settings")
                            .font(Typo.sans(19, .semibold))
                            .kerning(-0.3)
                            .foregroundStyle(theme.text)
                        Text("The bar stays out of the way; everything else is yours.")
                            .font(Typo.sans(12.5))
                            .foregroundStyle(theme.muted)
                    }

                    storageGroup
                    appearanceGroup
                    workGroup
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 14) {
                    shortcutsCard
                    focusCard
                }
                .frame(width: 264)
            }
            .padding(.horizontal, 32)
            .padding(.top, 26).padding(.bottom, 40)
        }
        .background(theme.bg)
    }

    // MARK: - Groups

    private var storageGroup: some View {
        group("Storage") {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notes folder")
                        .font(Typo.sans(13, .medium))
                        .foregroundStyle(theme.text)
                    Text("\(store.notes.count) notes as markdown files you can read anywhere")
                        .font(Typo.sans(11.5))
                        .foregroundStyle(theme.muted)
                }
                Spacer()
                Button {
                    NSWorkspace.shared.open(store.root)
                } label: {
                    Text("Reveal")
                        .font(Typo.sans(11.5, .medium))
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(theme.line, lineWidth: 1)
                        )
                }
                .buttonStyle(.flat)
            }
            .padding(.vertical, 15)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.lineSoft).frame(height: 1) }

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export / import")
                        .font(Typo.sans(13, .medium))
                        .foregroundStyle(theme.text)
                    Text(exportStatus ?? "A folder of markdown, plus an archive you can re-import")
                        .font(Typo.sans(11.5))
                        .foregroundStyle(theme.muted)
                }
                Spacer()
                Button(action: exportBundle) {
                    Text("Export…")
                        .font(Typo.sans(11.5, .medium))
                        .foregroundStyle(theme.onAccent)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.flat)

                Button(action: importBundle) {
                    Text("Import…")
                        .font(Typo.sans(11.5, .medium))
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(theme.line, lineWidth: 1)
                        )
                }
                .buttonStyle(.flat)
            }
            .padding(.vertical, 15)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.lineSoft).frame(height: 1) }
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
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]
        panel.prompt = "Import"
        panel.message = "Choose a Foglio export folder or its foglio-archive.json."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let archive = try Exporter.importArchive(from: url)
            store.replaceAll(with: archive)
            exportStatus = "Imported \(archive.notes.count) notes and \(archive.tasks.count) tasks"
        } catch {
            exportStatus = "Import failed: \(error.localizedDescription)"
        }
    }

    private var appearanceGroup: some View {
        group("Appearance & placement") {
            settingRow("Appearance", hint: "Light for daytime, dark after hours") {
                segmented(
                    options: [("Light", ThemeMode.light), ("Dark", ThemeMode.dark)],
                    selection: state.themeMode
                ) { state.themeMode = $0 }
            }
            settingRow("Bar edge", hint: "Which screen edge the strip clings to") {
                segmented(
                    options: [("Left", BarSide.left), ("Right", BarSide.right)],
                    selection: state.barSide
                ) { state.barSide = $0 }
            }
        }
    }

    private var workGroup: some View {
        group("Work") {
            settingRow("Focus block", hint: "Length of one pomodoro") {
                segmented(
                    options: [("15 min", 15), ("25 min", 25), ("45 min", 45)],
                    selection: state.focusMinutes
                ) {
                    state.focusMinutes = $0
                    state.secondsRemaining = $0 * 60
                    state.timerRunning = false
                }
            }
            settingRow("Log completed tasks", hint: "Strike through, then write into today's log") {
                segmented(
                    options: [("On", true), ("Off", false)],
                    selection: state.autoLog
                ) { state.autoLog = $0 }
            }
        }
    }

    // MARK: - Building blocks

    private func group<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(Typo.sans(10))
                .kerning(1.6)
                .foregroundStyle(theme.muted)
                .padding(.bottom, 9)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(theme.line).frame(height: 2)
                }
            content()
        }
    }

    private func settingRow<Control: View>(
        _ label: String,
        hint: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Typo.sans(13, .medium))
                    .foregroundStyle(theme.text)
                Text(hint)
                    .font(Typo.sans(11.5))
                    .foregroundStyle(theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control().frame(width: 210)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.lineSoft).frame(height: 1) }
    }

    private func segmented<Value: Equatable>(
        options: [(String, Value)],
        selection: Value,
        onPick: @escaping (Value) -> Void
    ) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = option.1 == selection
                Button { onPick(option.1) } label: {
                    Text(option.0)
                        .font(Typo.sans(11.5, .medium))
                        .foregroundStyle(selected ? theme.onAccent : theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(selected ? theme.accent : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.flat)
            }
        }
        .padding(3)
        .background(theme.field)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.line, lineWidth: 1)
        )
    }

    // MARK: - Side cards

    private var shortcutsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SHORTCUTS")
                .font(Typo.sans(10))
                .kerning(1.6)
                .foregroundStyle(theme.invMuted)
                .padding(.bottom, 12)

            ForEach(shortcuts, id: \.0) { keys, what in
                HStack(spacing: 11) {
                    Text(keys)
                        .font(Typo.mono(11))
                        .foregroundStyle(theme.invText)
                        .frame(width: 80)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.22))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    Text(what)
                        .font(Typo.sans(12.5))
                        .foregroundStyle(theme.invMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 7)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.invBg)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var shortcuts: [(String, String)] {
        [
            ("⌘⇧N", "New note in Scratch"),
            ("⌘⇧Space", "Quick capture from anywhere"),
            ("⌘⇧T", "Tasks"),
            ("⌘K", "Search notes, tasks and log"),
            ("⎋", "Send the window away, keep the bar"),
        ]
    }

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("FOCUS")
                .font(Typo.sans(10))
                .kerning(1.6)
                .foregroundStyle(theme.muted)
            Text("\(state.blocksCompleted) blocks today")
                .font(Typo.sans(14, .medium))
                .foregroundStyle(theme.text)
                .padding(.top, 7)
            Text(state.timerRunning ? "Running — \(state.mmss) left" : "\(state.focusMinutes)-minute blocks")
                .font(Typo.sans(12))
                .foregroundStyle(theme.muted)
                .padding(.top, 3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.line, lineWidth: 1)
        )
    }
}
