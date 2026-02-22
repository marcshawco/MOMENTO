import SwiftUI

/// Text notes tab: card list with add/edit via sheet, delete via context menu.
struct NotesTabView: View {

    @Bindable var viewModel: ItemDetailViewModel

    @State private var showingNoteEditor = false
    @State private var editingNote: TextMemory?
    @State private var noteEditorText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            noteList
            addButton
        }
        .sheet(isPresented: $showingNoteEditor) {
            NoteEditorSheet(
                text: $noteEditorText,
                isEditing: editingNote != nil
            ) {
                if let note = editingNote {
                    viewModel.updateNote(note, body: noteEditorText)
                } else {
                    viewModel.addNote(body: noteEditorText)
                }
            }
        }
    }

    // MARK: - Note List

    @ViewBuilder
    private var noteList: some View {
        if let notes = viewModel.item?.textMemories.sorted(by: { $0.createdAt > $1.createdAt }),
           !notes.isEmpty
        {
            ForEach(notes) { note in
                noteCard(note)
            }
        } else {
            ContentUnavailableView {
                Label("No Notes", systemImage: "note.text")
            } description: {
                Text("Add notes to remember details about your item.")
            }
            .frame(height: 120)
        }
    }

    private func noteCard(_ note: TextMemory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note.body)
                .font(.subheadline)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            editingNote = note
            noteEditorText = note.body
            showingNoteEditor = true
        }
        .contextMenu {
            Button {
                editingNote = note
                noteEditorText = note.body
                showingNoteEditor = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button(role: .destructive) {
                viewModel.deleteNote(note)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Add Button

    private var addButton: some View {
        Button {
            editingNote = nil
            noteEditorText = ""
            showingNoteEditor = true
        } label: {
            Label("Add Note", systemImage: "square.and.pencil")
                .font(.subheadline.weight(.medium))
        }
    }
}

// MARK: - Note Editor Sheet

struct NoteEditorSheet: View {

    @Binding var text: String
    let isEditing: Bool
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($isFocused)
                .padding(.horizontal)
                .navigationTitle(isEditing ? "Edit Note" : "New Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            onSave()
                            dismiss()
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .fontWeight(.semibold)
                    }
                }
                .onAppear { isFocused = true }
        }
        .presentationDetents([.medium, .large])
    }
}
