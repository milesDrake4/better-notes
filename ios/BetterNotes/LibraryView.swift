import SwiftUI

struct LibraryView: View {
    let folder: ClassFolder?
    let onCreateNote: () -> Void
    let onOpenNote: (StudyNote) -> Void
    let onRenameNote: (StudyNote) -> Void
    let onDeleteNote: (StudyNote) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 20)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(folder?.name ?? "Classes")
                        .font(.largeTitle.bold())
                    Text("\(folder?.notes.count ?? 0) notes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onCreateNote) {
                    Label("New", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(folder == nil)
            }

            if let folder, !folder.notes.isEmpty {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(folder.notes) { note in
                            Button {
                                onOpenNote(note)
                            } label: {
                                NoteCard(note: note)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    onRenameNote(note)
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    onDeleteNote(note)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.bottom, 32)
                }
            } else {
                ContentUnavailableView(
                    folder == nil ? "Create a class" : "No notes yet",
                    systemImage: folder == nil ? "folder.badge.plus" : "doc.badge.plus",
                    description: Text(folder == nil ? "Classes keep your schoolwork organized." : "Create a note to start writing.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(32)
        .background(Color(.systemGroupedBackground))
    }
}

private struct NoteCard: View {
    let note: StudyNote

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(note.color.gradient)
                .aspectRatio(0.78, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: note.template.icon)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(12)
                }

            Text(note.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(note.modifiedAt, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
