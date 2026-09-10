import SwiftUI

/// Notes on their way out: what was deleted, how long each has left, and the
/// two ways back — put it back, or finish the job now.
///
/// Deliberately its own section rather than a folder in Notes. The trash is
/// somewhere you go to undo something, and a note in it should not turn up
/// while you are looking for a note you still have.
struct TrashView: View {
    @Bindable var state: AppState
    let store: Store

    /// Set when emptying has been asked for but not confirmed — the one action
    /// here that destroys more than one note at a time.
    @State private var confirmingEmpty = false

    /// The trashed note a "delete now" has been asked for, awaiting its own
    /// confirmation. Held as the note rather than the id so the dialog can
    /// still name it after it has gone.
    @State private var pendingDeletion: Note?

    private var theme: Theme { state.theme }

    private var query: String { state.search.trimmingCharacters(in: .whitespaces) }

    /// Only the notes still inside their ten days, whether or not the sweep
    /// that removes the expired ones has run yet.
    private var visible: [Note] {
        store.activeTrash().filter { $0.matches(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if visible.isEmpty {
                    emptyState
                } else {
                    rows
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 26).padding(.bottom, 40)
        }
        .background(theme.bg)
        .confirmationDialog(
            "Empty the trash?",
            isPresented: $confirmingEmpty,
            titleVisibility: .visible
        ) {
            Button("Delete \(visible.count) Notes", role: .destructive) { store.emptyTrash() }
            Button("Cancel", role: .cancel) { confirmingEmpty = false }
        } message: {
            Text("Their markdown files are removed from disk. This can't be undone.")
        }
        .confirmationDialog(
            pendingDeletion.map { "Delete “\(title(of: $0))” now?" } ?? "",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let note = pendingDeletion { store.deleteFromTrash(id: note.id) }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Its markdown file is removed from disk. This can't be undone.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("Trash")
                .font(Typo.sans(19, .semibold))
                .kerning(-0.3)
                .foregroundStyle(theme.text)
            Text("deleted notes are kept for \(Store.trashRetentionDays) days")
                .font(Typo.sans(12))
                .foregroundStyle(theme.muted)
            Spacer()
            if !visible.isEmpty {
                Button { confirmingEmpty = true } label: {
                    HStack(spacing: 5) {
                        IconView(icon: .trash, size: 12, lineWidth: 1.6)
                        Text("Empty Trash").font(Typo.sans(11.5))
                    }
                    .foregroundStyle(theme.clay)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .hoverHighlight(theme, cornerRadius: 6)
                }
                .buttonStyle(.flat)
            }
            Text("\(visible.count)")
                .font(Typo.mono(11.5))
                .foregroundStyle(theme.muted)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        // Says which of the two empties this is, since a search that matches
        // nothing looks exactly like a trash with nothing in it.
        Text(query.isEmpty ? "Nothing in the trash." : "No deleted notes match “\(query)”.")
            .font(Typo.sans(13))
            .foregroundStyle(theme.muted)
            .padding(.top, 40)
    }

    // MARK: - Rows

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(visible) { note in
                row(note)
            }
        }
        .padding(.top, 22)
    }

    private func row(_ note: Note) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title(of: note))
                    .font(Typo.sans(13.5, .medium))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                if !note.snippet.isEmpty {
                    Text(note.snippet)
                        .font(Typo.sans(11.5))
                        .foregroundStyle(theme.muted)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text(note.folder.label)
                        .font(Typo.sans(10.5, .medium))
                        .kerning(0.4)
                        .foregroundStyle(theme.muted)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(theme.line, lineWidth: 1)
                        )
                    if let at = note.deletedAt {
                        Text("deleted \(dayLabel(at))")
                            .font(Typo.mono(10.5))
                            .foregroundStyle(theme.muted)
                    }
                    countdown(note)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Button { store.restoreNote(id: note.id) } label: {
                    Text("Put Back")
                        .font(Typo.sans(11.5, .medium))
                        .foregroundStyle(theme.onAccent)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.flat)
                .help("Move it back to \(note.folder.label)")

                Button { pendingDeletion = note } label: {
                    Text("Delete")
                        .font(Typo.sans(11.5))
                        .foregroundStyle(theme.clay)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .hoverHighlight(theme, cornerRadius: 6)
                }
                .buttonStyle(.flat)
                .help("Remove it from disk now")
            }
            .padding(.top, 1)
        }
        .padding(.vertical, 13).padding(.horizontal, 2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.lineSoft).frame(height: 1)
        }
        .contextMenu {
            Button("Put Back") { store.restoreNote(id: note.id) }
            Divider()
            Button("Delete Now…", role: .destructive) { pendingDeletion = note }
        }
    }

    /// How long is left, in the words you'd use out loud. The last day says so
    /// rather than counting down to zero, which reads like it has already gone.
    private func countdown(_ note: Note) -> some View {
        let days = Store.trashDaysRemaining(note)
        let text = switch days {
        case 0: "deletes tonight"
        case 1: "1 day left"
        default: "\(days) days left"
        }
        // The last two days are worth noticing; before that it's just a fact.
        return Text(text)
            .font(Typo.mono(10.5))
            .foregroundStyle(days <= 1 ? theme.clay : theme.muted)
    }

    private func title(of note: Note) -> String {
        note.title.isEmpty ? "Untitled note" : note.title
    }

    private func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }
}
