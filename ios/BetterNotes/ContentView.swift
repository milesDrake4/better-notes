import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = NotesStore()
    @State private var selectedFolderID: UUID?
    @State private var selectedNoteID: UUID?
    @State private var isShowingNewClass = false
    @State private var isShowingNewNote = false
    @State private var newClassName = ""
    @State private var selectedTemplate: NoteTemplate = .blank
    @State private var renameTarget: RenameTarget?
    @State private var renameText = ""
    @State private var deleteTarget: DeleteTarget?
    @State private var pendingSharedImport: PendingSharedImport?
    @State private var sharedImportError: String?

    private var selectedFolder: ClassFolder? {
        store.folder(id: selectedFolderID)
    }

    private var selectedNote: StudyNote? {
        guard let selectedFolderID, let selectedNoteID else { return nil }
        return store.note(id: selectedNoteID, in: selectedFolderID)
    }

    var body: some View {
        Group {
            if let selectedFolderID, let selectedNote {
                NoteEditorView(
                    note: selectedNote,
                    onBack: { selectedNoteID = nil },
                    onRename: { beginRename(.note(selectedNote.id)) },
                    onSaveDrawing: {
                        store.saveDrawing($0, noteID: selectedNote.id, folderID: selectedFolderID)
                    }
                )
            } else {
                NavigationSplitView {
                    sidebar
                        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
                } detail: {
                    LibraryView(
                        folder: selectedFolder,
                        onCreateNote: { isShowingNewNote = true },
                        onOpenNote: { selectedNoteID = $0.id },
                        onRenameNote: { beginRename(.note($0.id)) },
                        onDeleteNote: { deleteTarget = .note($0.id) }
                    )
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        .onAppear {
            if selectedFolderID == nil {
                selectedFolderID = store.folders.first?.id
            }
            loadPendingSharedImport()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                loadPendingSharedImport()
            }
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .onChange(of: selectedFolderID) {
            selectedNoteID = nil
        }
        .sheet(isPresented: $isShowingNewClass) {
            nameSheet(
                title: "New Class",
                fieldLabel: "Class name",
                text: $newClassName,
                actionTitle: "Create",
                onCancel: { newClassName = "" },
                onSubmit: createFolder
            )
        }
        .sheet(isPresented: $isShowingNewNote) {
            NewNoteSheet(
                selection: $selectedTemplate,
                onCancel: {
                    selectedTemplate = .blank
                    isShowingNewNote = false
                },
                onCreate: createNote
            )
        }
        .sheet(item: $renameTarget) { target in
            nameSheet(
                title: target.title,
                fieldLabel: target.fieldLabel,
                text: $renameText,
                actionTitle: "Save",
                onCancel: { renameText = "" },
                onSubmit: { finishRename(target) }
            )
        }
        .sheet(item: $pendingSharedImport) { item in
            SharedPDFImportSheet(
                item: item,
                folders: store.folders,
                initialFolderID: selectedFolderID ?? store.folders.first?.id,
                onImport: { folderID, role in
                    importSharedPDF(item, into: folderID, role: role)
                },
                onDiscard: {
                    SharedImportInbox.remove(item)
                    pendingSharedImport = nil
                }
            )
        }
        .alert(
            deleteTarget?.title ?? "Delete",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            presenting: deleteTarget
        ) { target in
            Button("Delete", role: .destructive) {
                performDelete(target)
            }
            Button("Cancel", role: .cancel) {
                deleteTarget = nil
            }
        } message: { target in
            Text(target.message)
        }
        .alert(
            "Could Not Import PDF",
            isPresented: Binding(
                get: { sharedImportError != nil },
                set: { if !$0 { sharedImportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                sharedImportError = nil
            }
        } message: {
            Text(sharedImportError ?? "")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("BetterNotes")
                .font(.largeTitle.bold())
                .padding(.horizontal)
                .padding(.top)

            Button {
                isShowingNewClass = true
            } label: {
                Label("New Class", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)

            if store.folders.isEmpty {
                ContentUnavailableView(
                    "No classes",
                    systemImage: "folder.badge.plus",
                    description: Text("Create a class to organize your notes.")
                )
            } else {
                List(selection: $selectedFolderID) {
                    ForEach(store.folders) { folder in
                        Label(folder.name, systemImage: "folder")
                            .tag(folder.id)
                            .contextMenu {
                                Button {
                                    beginRename(.folder(folder.id))
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    deleteTarget = .folder(folder.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private func createFolder() {
        let name = newClassName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let folder = store.createFolder(named: name)
        selectedFolderID = folder.id
        newClassName = ""
        isShowingNewClass = false
    }

    private func createNote(attachments: [NoteAttachment]) {
        guard
            let folderID = selectedFolder?.id,
            let note = store.createNote(
                in: folderID,
                template: selectedTemplate,
                attachments: attachments
            )
        else { return }

        selectedNoteID = note.id
        selectedTemplate = .blank
        isShowingNewNote = false
    }

    private func beginRename(_ target: RenameTarget) {
        switch target {
        case .folder(let id):
            renameText = store.folder(id: id)?.name ?? ""
        case .note(let id):
            guard let folderID = selectedFolder?.id else { return }
            renameText = store.note(id: id, in: folderID)?.title ?? ""
        }
        renameTarget = target
    }

    private func finishRename(_ target: RenameTarget) {
        let value = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        switch target {
        case .folder(let id):
            store.renameFolder(id: id, to: value)
        case .note(let id):
            guard let folderID = selectedFolder?.id else { return }
            store.renameNote(id: id, in: folderID, to: value)
        }

        renameText = ""
        renameTarget = nil
    }

    private func performDelete(_ target: DeleteTarget) {
        switch target {
        case .folder(let id):
            store.deleteFolder(id: id)
            if selectedFolderID == id {
                selectedFolderID = store.folders.first?.id
                selectedNoteID = nil
            }
        case .note(let id):
            guard let folderID = selectedFolder?.id else { return }
            store.deleteNote(id: id, from: folderID)
            if selectedNoteID == id {
                selectedNoteID = nil
            }
        }
        deleteTarget = nil
    }

    private func loadPendingSharedImport() {
        guard pendingSharedImport == nil else { return }
        pendingSharedImport = SharedImportInbox.pendingImports().first
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "betternotes" else { return }

        if url.host == "import" || url.path == "/import" {
            selectedNoteID = nil
            openPendingSharedImport()
        }
    }

    private func openPendingSharedImport() {
        guard let item = SharedImportInbox.pendingImports().first else {
            pendingSharedImport = nil
            return
        }

        guard let folderID = selectedFolderID ?? store.folders.first?.id else {
            pendingSharedImport = item
            return
        }

        pendingSharedImport = nil
        importSharedPDF(item, into: folderID, role: item.role)
    }

    private func importSharedPDF(
        _ item: PendingSharedImport,
        into folderID: UUID,
        role: SharedImportRole
    ) {
        do {
            let sourceURL = try SharedImportInbox.fileURL(for: item)
            var attachment = try AttachmentStorage.importFile(
                from: sourceURL,
                kind: role.attachmentKind
            )
            attachment.displayName = item.displayName

            guard let note = store.createNote(
                in: folderID,
                template: role.noteTemplate,
                attachments: [attachment]
            ) else {
                AttachmentStorage.delete(attachment)
                throw SharedPDFImportError.folderUnavailable
            }

            SharedImportInbox.remove(item)
            selectedFolderID = folderID
            selectedNoteID = note.id
            pendingSharedImport = nil

            DispatchQueue.main.async {
                loadPendingSharedImport()
            }
        } catch {
            sharedImportError = error.localizedDescription
        }
    }

    private func nameSheet(
        title: String,
        fieldLabel: String,
        text: Binding<String>,
        actionTitle: String,
        onCancel: @escaping () -> Void,
        onSubmit: @escaping () -> Void
    ) -> some View {
        NavigationStack {
            Form {
                TextField(fieldLabel, text: text)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        isShowingNewClass = false
                        renameTarget = nil
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(actionTitle, action: onSubmit)
                        .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct SharedPDFImportSheet: View {
    let item: PendingSharedImport
    let folders: [ClassFolder]
    let initialFolderID: UUID?
    let onImport: (UUID, SharedImportRole) -> Void
    let onDiscard: () -> Void

    @State private var selectedFolderID: UUID?
    @State private var role: SharedImportRole

    init(
        item: PendingSharedImport,
        folders: [ClassFolder],
        initialFolderID: UUID?,
        onImport: @escaping (UUID, SharedImportRole) -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.item = item
        self.folders = folders
        self.initialFolderID = initialFolderID
        self.onImport = onImport
        self.onDiscard = onDiscard
        _selectedFolderID = State(initialValue: initialFolderID ?? folders.first?.id)
        _role = State(initialValue: item.role)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Shared PDF") {
                    Label(item.displayName, systemImage: "doc.richtext")
                        .lineLimit(2)
                }

                Section("Class") {
                    if folders.isEmpty {
                        Text("Create a class before importing this PDF.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Class", selection: $selectedFolderID) {
                            ForEach(folders) { folder in
                                Text(folder.name)
                                    .tag(Optional(folder.id))
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }

                Section("Use PDF As") {
                    Picker("Import type", selection: $role) {
                        ForEach(SharedImportRole.allCases) { role in
                            Label(role.title, systemImage: role.icon)
                                .tag(role)
                        }
                    }
                    .pickerStyle(.inline)

                    Text(role.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Import to BetterNotes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard", role: .destructive, action: onDiscard)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create Note") {
                        guard let selectedFolderID else { return }
                        onImport(selectedFolderID, role)
                    }
                    .disabled(selectedFolderID == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private extension SharedImportRole {
    var title: String {
        switch self {
        case .importAsIs: "Import As Is"
        case .homeworkContext: "Homework Context"
        case .rubric: "Rubric"
        }
    }

    var icon: String {
        switch self {
        case .importAsIs: "doc"
        case .homeworkContext: "square.and.pencil"
        case .rubric: "checkmark.seal"
        }
    }

    var description: String {
        switch self {
        case .importAsIs:
            "Better Notes will save this PDF with a blank note without using it as AI context."
        case .homeworkContext:
            "AI Lens will treat this PDF as the assignment questions while you work in the note."
        case .rubric:
            "AI Lens will treat this PDF as grading criteria or solutions context."
        }
    }

    var noteTemplate: NoteTemplate {
        switch self {
        case .importAsIs: .blank
        case .homeworkContext: .homework
        case .rubric: .practiceExam
        }
    }

    var attachmentKind: AttachmentKind {
        switch self {
        case .importAsIs: .importedPDF
        case .homeworkContext: .homeworkSet
        case .rubric: .rubric
        }
    }
}

private enum SharedPDFImportError: LocalizedError {
    case folderUnavailable

    var errorDescription: String? {
        "The selected class is no longer available."
    }
}

private struct NewNoteSheet: View {
    @Binding var selection: NoteTemplate
    let onCancel: () -> Void
    let onCreate: ([NoteAttachment]) -> Void

    @State private var step: NewNoteStep = .chooseType
    @State private var attachments: [AttachmentKind: NoteAttachment] = [:]
    @State private var importTarget: AttachmentKind?
    @State private var isImporting = false
    @State private var draggingOverKind: AttachmentKind?
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    switch step {
                    case .chooseType:
                        VStack(spacing: 16) {
                            ForEach(NoteTemplate.allCases) { template in
                                Button {
                                    selectTemplate(template)
                                } label: {
                                    VStack(spacing: 14) {
                                        Image(systemName: template.icon)
                                            .font(.system(size: 34))
                                        Text(template.title)
                                            .font(.headline)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 130)
                                    .foregroundStyle(selection == template ? Color.accentColor : .primary)
                                    .background(selection == template ? Color.accentColor.opacity(0.14) : Color(.secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(selection == template ? Color.accentColor : .clear, lineWidth: 2)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    case .uploadFiles:
                        VStack(alignment: .leading, spacing: 14) {
                            Text(selection == .homework ? "Homework Files" : "Exam Files")
                                .font(.title2.bold())

                            Text("These files will be saved with the note so AI Lens can use the original questions and grading criteria.")
                                .foregroundStyle(.secondary)

                            ForEach(requiredAttachments, id: \.self) { kind in
                                attachmentDropZone(for: kind)
                            }
                        }
                    }
                }
                .padding(24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(step == .chooseType ? "New Note" : selection.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step == .chooseType {
                        Button("Cancel") {
                            discardAttachments()
                            onCancel()
                        }
                    } else {
                        Button {
                            returnToTypePicker()
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(Array(attachments.values))
                    }
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: false,
                onCompletion: handleImport
            )
            .alert(
                "Could Not Upload File",
                isPresented: Binding(
                    get: { importError != nil },
                    set: { if !$0 { importError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    importError = nil
                }
            } message: {
                Text(importError ?? "")
            }
        }
        .presentationDetents([.large])
        .presentationContentInteraction(.scrolls)
    }

    private var requiredAttachments: [AttachmentKind] {
        switch selection {
        case .blank: []
        case .homework: [.homeworkSet]
        case .practiceExam: [.exam, .rubric]
        }
    }

    private func attachmentDropZone(for kind: AttachmentKind) -> some View {
        let attachment = attachments[kind]
        let isDragging = draggingOverKind == kind
        let zoneHeight: CGFloat = selection == .practiceExam ? 170 : 230

        return RoundedRectangle(cornerRadius: 12)
            .fill(isDragging ? Color.accentColor.opacity(0.12) : Color(.systemBackground))
            .frame(height: zoneHeight)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isDragging ? Color.accentColor : Color.secondary.opacity(0.28),
                        style: StrokeStyle(lineWidth: 2, dash: [10, 8])
                    )
            }
            .overlay {
                VStack(spacing: selection == .practiceExam ? 9 : 16) {
                    Image(systemName: attachment == nil ? "tray.and.arrow.down" : "checkmark.circle.fill")
                        .font(.system(size: selection == .practiceExam ? 26 : 38))
                        .foregroundStyle(attachment == nil ? Color.accentColor : .green)

                    VStack(spacing: 4) {
                        Text(attachment == nil ? "Drag \(kind.title) here" : "\(kind.title) Added")
                            .font(selection == .practiceExam ? .headline : .title3.bold())
                        Text(attachment?.displayName ?? "PDF or image")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Button {
                        importTarget = kind
                        isImporting = true
                    } label: {
                        Label(attachment == nil ? "Choose File" : "Replace File", systemImage: "folder")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(selection == .practiceExam ? .regular : .large)
                }
                .padding(selection == .practiceExam ? 12 : 24)
            }
            .onDrop(
                of: [UTType.pdf, UTType.image, UTType.fileURL],
                isTargeted: Binding(
                    get: { draggingOverKind == kind },
                    set: { draggingOverKind = $0 ? kind : nil }
                )
            ) { providers in
                handleDrop(providers, kind: kind)
            }
    }

    private func selectTemplate(_ template: NoteTemplate) {
        changeSelection(to: template)
        if template != .blank {
            step = .uploadFiles
        }
    }

    private func changeSelection(to template: NoteTemplate) {
        let retainedKinds: Set<AttachmentKind>
        switch template {
        case .blank: retainedKinds = []
        case .homework: retainedKinds = [.homeworkSet]
        case .practiceExam: retainedKinds = [.exam, .rubric]
        }

        let discardedKinds = attachments.keys.filter { !retainedKinds.contains($0) }
        for kind in discardedKinds {
            if let attachment = attachments.removeValue(forKey: kind) {
                AttachmentStorage.delete(attachment)
            }
        }
        selection = template
    }

    private func returnToTypePicker() {
        changeSelection(to: .blank)
        step = .chooseType
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard let kind = importTarget else { return }
        defer { importTarget = nil }

        do {
            guard let sourceURL = try result.get().first else { return }
            importURL(sourceURL, kind: kind)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func importURL(_ sourceURL: URL, kind: AttachmentKind) {
        do {
            let attachment = try AttachmentStorage.importFile(from: sourceURL, kind: kind)
            if let existing = attachments[kind] {
                AttachmentStorage.delete(existing)
            }
            attachments[kind] = attachment
        } catch {
            importError = error.localizedDescription
        }
    }

    private func handleDrop(_ providers: [NSItemProvider], kind: AttachmentKind) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }

        let typeIdentifier: String
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            typeIdentifier = UTType.pdf.identifier
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            typeIdentifier = UTType.image.identifier
        } else {
            typeIdentifier = UTType.fileURL.identifier
        }

        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
            DispatchQueue.main.async {
                draggingOverKind = nil
                if let error {
                    importError = error.localizedDescription
                } else if let url {
                    importURL(url, kind: kind)
                }
            }
        }

        return true
    }

    private func discardAttachments() {
        attachments.values.forEach(AttachmentStorage.delete)
        attachments.removeAll()
    }
}

private enum NewNoteStep {
    case chooseType
    case uploadFiles
}

private enum RenameTarget: Identifiable {
    case folder(UUID)
    case note(UUID)

    var id: String {
        switch self {
        case .folder(let id): "folder-\(id)"
        case .note(let id): "note-\(id)"
        }
    }

    var title: String {
        switch self {
        case .folder: "Rename Class"
        case .note: "Rename Note"
        }
    }

    var fieldLabel: String {
        switch self {
        case .folder: "Class name"
        case .note: "Note title"
        }
    }
}

private enum DeleteTarget {
    case folder(UUID)
    case note(UUID)

    var title: String {
        switch self {
        case .folder: "Delete Class?"
        case .note: "Delete Note?"
        }
    }

    var message: String {
        switch self {
        case .folder: "This deletes the class and every note inside it."
        case .note: "This note and its handwritten work will be deleted."
        }
    }
}
