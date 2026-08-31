import SwiftUI

/// The Notes section: folders / list / editor (Day Log.dc.html:129-277).
struct NotesView: View {
    @Bindable var state: AppState
    let store: Store

    private var theme: Theme { state.theme }

    private var query: String {
        state.search.trimmingCharacters(in: .whitespaces)
    }

    private var visibleNotes: [Note] {
        store.notes
            .filter { state.folderFilter == nil || $0.folder == state.folderFilter }
            .filter { $0.matches(query) }
    }

    private var activeNote: Note? {
        if let id = state.activeNoteId, let found = store.note(id: id) { return found }
        return visibleNotes.first
    }

    var body: some View {
        HStack(spacing: 0) {
            folderPane
            Divider().overlay(theme.line)
            listPane
            Divider().overlay(theme.line)
            editorPane
        }
    }

    // MARK: - Folders

    private var folderPane: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                let note = store.newNote(in: state.folderFilter ?? .scratch)
                state.activeNoteId = note.id
                state.activeBlock = 0
            } label: {
                HStack(spacing: 8) {
                    IconView(icon: .capture, size: 14, lineWidth: 2)
                    Text("New note").font(Typo.sans(12.5, .semibold))
                }
                .foregroundStyle(theme.onAccent)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.flat)
            .padding(.bottom, 8)

            Text("FOLDERS")
                .font(Typo.sans(10))
                .kerning(1.6)
                .foregroundStyle(theme.muted)
                .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 6)

            folderRow(nil, label: "All notes", icon: .all, count: store.notes.count)
            ForEach(Folder.allCases) { folder in
                folderRow(
                    folder,
                    label: folder.label,
                    icon: .folder,
                    count: store.notes.filter { $0.folder == folder }.count
                )
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 16)
        .frame(width: 168)
        .frame(maxHeight: .infinity)
        .background(theme.surface)
    }

    private func folderRow(_ folder: Folder?, label: String, icon: Icon, count: Int) -> some View {
        let selected = state.folderFilter == folder
        return Button {
            state.folderFilter = folder
        } label: {
            HStack(spacing: 9) {
                IconView(icon: icon, size: 14)
                Text(label).font(Typo.sans(12.5)).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)").font(Typo.mono(11)).foregroundStyle(theme.muted)
            }
            .foregroundStyle(selected ? theme.text : theme.muted)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? theme.accentSoft : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.flat)
    }

    // MARK: - Note list

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(query.isEmpty ? (state.folderFilter?.label ?? "All notes").uppercased() : "SEARCH RESULTS")
                    .font(Typo.sans(10))
                    .kerning(1.6)
                    .foregroundStyle(theme.muted)
                Spacer()
                Text("\(visibleNotes.count)")
                    .font(Typo.mono(11))
                    .foregroundStyle(theme.muted)
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visibleNotes) { note in
                        noteRow(note)
                    }
                }
            }
        }
        .frame(width: 244)
        .frame(maxHeight: .infinity)
        .background(theme.bg)
    }

    private func noteRow(_ note: Note) -> some View {
        let selected = note.id == activeNote?.id
        return Button {
            state.activeNoteId = note.id
            state.activeBlock = nil
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(note.title.isEmpty ? "Untitled note" : note.title)
                        .font(Typo.sans(13, .medium))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    if note.pin != nil {
                        IconView(icon: .pin, size: 12, lineWidth: 1.8)
                            .foregroundStyle(theme.accentDeep)
                    }
                    Spacer(minLength: 4)
                    Text(Relative.label(for: note.updatedAt))
                        .font(Typo.mono(10.5))
                        .foregroundStyle(theme.muted)
                }
                Text(note.snippet)
                    .font(Typo.sans(11.5))
                    .foregroundStyle(theme.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? theme.accentSoft : .clear)
            .overlay(alignment: .top) { Rectangle().fill(theme.lineSoft).frame(height: 1) }
        }
        .buttonStyle(.flat)
    }

    // MARK: - Editor

    @ViewBuilder
    private var editorPane: some View {
        if let note = activeNote {
            NoteEditor(state: state, store: store, note: note)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.bg)
        } else {
            VStack {
                Text(query.isEmpty ? "No notes yet." : "Nothing matches “\(query)”.")
                    .font(Typo.sans(12.5))
                    .foregroundStyle(theme.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.bg)
        }
    }
}

/// "14:20" today, "Yesterday", a weekday inside the last week, else "3 Aug"
/// — matching the `updated` strings in the design's sample data (:647).
enum Relative {
    static func label(for date: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(date) {
            f.dateFormat = "HH:mm"
        } else if cal.isDateInYesterday(date) {
            return "Yesterday"
        } else if let days = cal.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            f.dateFormat = "EEE"
        } else {
            f.dateFormat = "d MMM"
        }
        return f.string(from: date)
    }
}
