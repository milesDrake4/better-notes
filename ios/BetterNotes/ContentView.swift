import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = NotesStore()
    @StateObject private var authStore = BetterNotesAuthStore(serverAddress: "https://better-notes-api.onrender.com")
    @State private var didCompleteClassSetup = false
    @State private var isLoadingClassSetupProfile = false
    @State private var selectedFolderID: UUID?
    @State private var selectedNoteID: UUID?
    @State private var isShowingNewClass = false
    @State private var isShowingNewNote = false
    @State private var newClassName = ""
    @State private var selectedTemplate: NoteTemplate = .blank
    @State private var renameTarget: RenameTarget?
    @State private var renameText = ""
    @State private var deleteTarget: DeleteTarget?
    @State private var isShowingAccount = false
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
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-BetterNotesDebugMath") {
                MathRendererDebugView()
            } else {
                appContent
            }
#else
            appContent
#endif
        }
        .onAppear {
            if selectedFolderID == nil {
                selectedFolderID = store.folders.first?.id
            }
            Task {
                await authStore.refreshSessionIfNeeded()
            }
            didCompleteClassSetup = hasCompletedClassSetup()
            loadPendingSharedImport()
            refreshClassSetupProfile()
        }
        .onChange(of: authStore.session) {
            didCompleteClassSetup = hasCompletedClassSetup()
            refreshClassSetupProfile()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task {
                    await authStore.refreshSessionIfNeeded()
                }
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
        .sheet(isPresented: $isShowingAccount) {
            AccountUsageSheet(
                authStore: authStore,
                serverAddress: "https://better-notes-api.onrender.com"
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

    @ViewBuilder
    private var appContent: some View {
        if authStore.shouldShowSessionLoading {
            ProgressView("Checking your session...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !authStore.isSignedIn {
            AuthGateView(authStore: authStore)
        } else if isLoadingClassSetupProfile && !didCompleteClassSetup {
            ProgressView("Loading your account...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !didCompleteClassSetup {
            ClassSetupView(
                onSkip: {
                    markClassSetupComplete()
                },
                onFinish: createInitialClassFolders
            )
        } else if let selectedFolderID, let selectedNote {
            NoteEditorView(
                note: selectedNote,
                onBack: { selectedNoteID = nil },
                onRename: { beginRename(.note(selectedNote.id)) },
                onSaveDrawing: {
                    store.saveDrawing($0, noteID: selectedNote.id, folderID: selectedFolderID)
                },
                onSavePageDrawing: { data, pageID in
                    store.savePageDrawing(data, noteID: selectedNote.id, folderID: selectedFolderID, pageID: pageID)
                },
                onSaveTextBoxes: { textBoxes in
                    store.saveTextBoxes(textBoxes, noteID: selectedNote.id, folderID: selectedFolderID)
                },
                onSaveImageBoxes: { imageBoxes in
                    store.saveImageBoxes(imageBoxes, noteID: selectedNote.id, folderID: selectedFolderID)
                },
                onSaveAIConversation: { messages, latestTranscription, latestFeedback in
                    store.saveAIConversation(
                        messages: messages,
                        latestTranscription: latestTranscription,
                        latestFeedback: latestFeedback,
                        noteID: selectedNote.id,
                        folderID: selectedFolderID
                    )
                },
                onSaveAIThreads: { threads, selectedThreadID in
                    store.saveAIThreads(
                        threads: threads,
                        selectedThreadID: selectedThreadID,
                        noteID: selectedNote.id,
                        folderID: selectedFolderID
                    )
                },
                onAddBlankPage: {
                    store.addBlankPage(noteID: selectedNote.id, folderID: selectedFolderID)
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            if authStore.isSignedIn {
                Button {
                    isShowingAccount = true
                } label: {
                    Label("Account", systemImage: "person.crop.circle")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.blue)
                .disabled(authStore.isWorking)
                .padding(.horizontal)
                .padding(.top, 10)
            }

            Text("BetterNotes")
                .font(.largeTitle.bold())
                .padding(.horizontal)

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

    private func createInitialClassFolders(_ classNames: [String]) {
        let cleanedNames = classNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var firstCreatedFolderID: UUID?
        for name in cleanedNames {
            let folder = store.createFolder(named: name)
            firstCreatedFolderID = firstCreatedFolderID ?? folder.id
        }

        selectedFolderID = firstCreatedFolderID ?? store.folders.first?.id
        markClassSetupComplete()
    }

    private func hasCompletedClassSetup() -> Bool {
        guard let key = classSetupStorageKey else { return false }
        return UserDefaults.standard.bool(forKey: key)
    }

    private func markClassSetupComplete() {
        guard let key = classSetupStorageKey else { return }
        UserDefaults.standard.set(true, forKey: key)
        didCompleteClassSetup = true
        saveClassSetupProfileCompletion()
    }

    private var classSetupStorageKey: String? {
        guard let userID = authStore.session?.user?.id else { return nil }
        return "BetterNotes.didCompleteClassSetup.\(userID)"
    }

    private func refreshClassSetupProfile() {
        guard authStore.isSignedIn else {
            isLoadingClassSetupProfile = false
            didCompleteClassSetup = false
            return
        }

        if didCompleteClassSetup {
            saveClassSetupProfileCompletion()
            return
        }

        isLoadingClassSetupProfile = true
        Task {
            do {
                let profile = try await BetterNotesAuthClient.accountProfile(
                    serverAddress: "https://better-notes-api.onrender.com",
                    accessToken: authStore.session?.accessToken
                )
                await MainActor.run {
                    if profile.didCompleteClassSetup {
                        if let key = classSetupStorageKey {
                            UserDefaults.standard.set(true, forKey: key)
                        }
                        didCompleteClassSetup = true
                    } else {
                        didCompleteClassSetup = hasCompletedClassSetup()
                    }
                    isLoadingClassSetupProfile = false
                }
            } catch {
                await MainActor.run {
                    didCompleteClassSetup = hasCompletedClassSetup()
                    isLoadingClassSetupProfile = false
                }
            }
        }
    }

    private func saveClassSetupProfileCompletion() {
        guard authStore.isSignedIn else { return }

        Task {
            do {
                _ = try await BetterNotesAuthClient.updateAccountProfile(
                    serverAddress: "https://better-notes-api.onrender.com",
                    accessToken: authStore.session?.accessToken,
                    didCompleteClassSetup: true
                )
            } catch {
                print("Could not save class setup completion to profile: \(error.localizedDescription)")
            }
        }
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
        if url.isFileURL, url.pathExtension.lowercased() == "pdf" {
            receivePDFDocument(at: url)
            return
        }

        guard url.scheme == "betternotes" else { return }

        if url.host == "import" || url.path == "/import" {
            selectedNoteID = nil
            openPendingSharedImport()
        }
    }

    private func receivePDFDocument(at url: URL) {
        let hasSecurityAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try SharedImportInbox.enqueue(
                fileAt: url,
                displayName: url.lastPathComponent,
                role: .importAsIs
            )
            selectedNoteID = nil
            pendingSharedImport = nil
            loadPendingSharedImport()
        } catch {
            sharedImportError = error.localizedDescription
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
        let trimmedName = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNewClass = title.localizedCaseInsensitiveContains("class")
        let subtitle = isNewClass
            ? "Create a space for notes, homework, and AI chats for this class."
            : "Update the name shown in BetterNotes."

        return NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.10),
                        Color(.systemGroupedBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.14))
                                .frame(width: 54, height: 54)

                            Image(systemName: isNewClass ? "folder.badge.plus" : "pencil")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }

                        VStack(spacing: 6) {
                            Text(title)
                                .font(.title2.bold())

                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(fieldLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextField(fieldLabel, text: text)
                            .font(.title3.weight(.medium))
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .padding(.horizontal, 16)
                            .frame(height: 54)
                            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(
                                        trimmedName.isEmpty ? Color.secondary.opacity(0.16) : Color.accentColor.opacity(0.42),
                                        lineWidth: 1.2
                                    )
                            }
                            .shadow(color: Color.blue.opacity(0.06), radius: 14, x: 0, y: 8)
                            .onSubmit {
                                if !text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    onSubmit()
                                }
                            }
                    }

                    HStack(spacing: 12) {
                        Button {
                            onCancel()
                            isShowingNewClass = false
                            renameTarget = nil
                        } label: {
                            Text("Cancel")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .background(Color(.systemBackground), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                        }

                        Button(action: onSubmit) {
                            Text(actionTitle)
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(trimmedName.isEmpty ? Color.gray.opacity(0.35) : Color.accentColor, in: Capsule())
                        .disabled(trimmedName.isEmpty)
                    }
                }
                .padding(24)
                .frame(maxWidth: 470)
                .padding(26)
            }
        }
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
    }
}

#if DEBUG
private struct MathRendererDebugView: View {
    private let sample = """
    Nice work setting up the equation. First, combine like terms so \\(2x + 3x = 5x\\), then isolate the variable.
    \\nThis line should appear as a real new line, not as backslash-n text.

    Here is a display equation that should not be cut off on the right:
    \\[
    \\frac{x^2 - 9}{x - 3} = \\frac{(x - 3)(x + 3)}{x - 3} = x + 3, \\quad x \\ne 3
    \\]

    Long inline math should stay readable: \\(f(x)=\\frac{3x^2+2x-7}{\\sqrt{x+4}}\\) and the sentence around it should wrap cleanly inside the chat bubble.
    """

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Math Renderer Test")
                        .font(.largeTitle.bold())

                    Text("This screen only appears in Debug when launched with the math test flag.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Check Work", systemImage: "checkmark.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.blue)

                        LatexText(content: sample)
                            .font(.subheadline)
                    }
                    .padding(12)
                    .frame(maxWidth: 520, alignment: .leading)
                    .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Student", systemImage: "person")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.85))

                        LatexText(content: "Can you explain why \\(x \\ne 3\\)?")
                            .font(.subheadline)
                    }
                    .padding(12)
                    .frame(maxWidth: 520, alignment: .leading)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(Color.white)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("BetterNotes Debug")
        }
    }
}
#endif

private struct AuthGateView: View {
    @ObservedObject var authStore: BetterNotesAuthStore
    @State private var mode: AuthMode = .signUp
    @State private var email = ""
    @State private var password = ""
    @State private var wantsUpdates = true

    var body: some View {
        GeometryReader { geometry in
            let isStacked = geometry.size.width < 700

            Group {
                if isStacked {
                    ScrollView {
                        VStack(spacing: 0) {
                            authForm
                                .padding(28)
                            betterNotesVisual
                                .frame(height: min(420, max(300, geometry.size.width * 0.72)))
                                .padding(.horizontal, 28)
                                .padding(.bottom, 28)
                        }
                    }
                } else {
                    HStack(spacing: 0) {
                        ZStack {
                            Color(.systemBackground)

                            authForm
                                .padding(.horizontal, 32)
                        }
                        .frame(width: geometry.size.width * 0.56, height: geometry.size.height)

                        betterNotesVisual
                            .frame(width: geometry.size.width * 0.44, height: geometry.size.height)
                            .clipped()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
        }
    }

    private var authForm: some View {
        VStack(alignment: .leading, spacing: 24) {
            Circle()
                .fill(Color.accentColor.opacity(0.18))
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(mode.title)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    Text(mode.secondaryPrompt)
                        .foregroundStyle(.secondary)
                    Button(mode.secondaryActionTitle) {
                        mode = mode.alternate
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .disabled(authStore.isWorking)
                }
                .font(.subheadline)
            }

            VStack(alignment: .leading, spacing: 18) {
                labeledTextField(title: "Email") {
                    TextField("", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)
                }

                labeledTextField(title: "Password") {
                    SecureField("", text: $password)
                        .textContentType(.newPassword)
                }

                HStack(spacing: 18) {
                    passwordRule("6 or more characters", met: password.count >= 6)
                    passwordRule("Use your school email", met: email.contains("@"))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if mode == .signUp {
                Button {
                    wantsUpdates.toggle()
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: wantsUpdates ? "checkmark.square.fill" : "square")
                            .font(.headline)
                            .foregroundStyle(wantsUpdates ? Color.accentColor : Color.secondary)

                        Text("I want to receive product updates, new study features, and launch announcements.")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .buttonStyle(.plain)

                Text("By creating an account, you agree to BetterNotes saving your account email and AI usage so scans can be limited and connected to your account.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message = authStore.statusMessage {
                Text(message)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(authStore.isSignedIn ? Color.green : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Task {
                        switch mode {
                        case .signUp:
                            await authStore.signUp(email: email, password: password)
                        case .login:
                            await authStore.signIn(email: email, password: password)
                        }
                    }
                } label: {
                    HStack {
                        if authStore.isWorking {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(mode.primaryActionTitle)
                    }
                    .frame(maxWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(authStore.isWorking || !canSubmit)

                HStack(spacing: 4) {
                    Text(mode.secondaryPrompt)
                        .foregroundStyle(.secondary)
                    Button(mode.secondaryActionTitle) {
                        mode = mode.alternate
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .disabled(authStore.isWorking)
                }
                .font(.subheadline)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    private func labeledTextField<Field: View>(
        title: String,
        @ViewBuilder field: () -> Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            field()
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                }
        }
    }

    private func passwordRule(_ title: String, met: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(met ? Color.accentColor : Color.secondary.opacity(0.45))
                .frame(width: 6, height: 6)
            Text(title)
        }
    }

    private var betterNotesVisual: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.92, green: 0.97, blue: 1.0),
                        Color(red: 0.68, green: 0.86, blue: 1.0),
                        Color(red: 0.26, green: 0.56, blue: 0.96)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(.white.opacity(0.22))
                    .frame(width: width * 0.9)
                    .offset(x: width * 0.28, y: -height * 0.28)

                Circle()
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: width * 0.72)
                    .offset(x: -width * 0.3, y: height * 0.3)

                studyPaper(
                    width: width * 0.58,
                    height: height * 0.46,
                    rotation: -10,
                    opacity: 0.95
                )
                .offset(x: -width * 0.12, y: -height * 0.04)

                studyPaper(
                    width: width * 0.52,
                    height: height * 0.42,
                    rotation: 9,
                    opacity: 0.72
                )
                .offset(x: width * 0.18, y: height * 0.1)

                RoundedRectangle(cornerRadius: 22)
                    .stroke(.white.opacity(0.7), style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
                    .frame(width: width * 0.46, height: height * 0.2)
                    .rotationEffect(.degrees(-4))
                    .offset(x: width * 0.02, y: -height * 0.02)

                VStack(alignment: .leading, spacing: 12) {
                    Label("AI Lens", systemImage: "sparkles")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)

                    Text("Scan homework. Get clearer feedback.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .frame(width: width * 0.58, alignment: .leading)
                .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 22))
                .shadow(color: Color.blue.opacity(0.18), radius: 20, x: 0, y: 12)
                .offset(y: height * 0.29)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func studyPaper(width: CGFloat, height: CGFloat, rotation: Double, opacity: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(.white.opacity(opacity))
                .shadow(color: Color.blue.opacity(0.18), radius: 28, x: 0, y: 18)

            VStack(alignment: .leading, spacing: 12) {
                ForEach([0.68, 0.46, 0.58, 0.34, 0.62], id: \.self) { lineWidth in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.14))
                        .frame(width: width * lineWidth, height: 7)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: width * 0.14, height: 34)
                    }
                }
            }
            .padding(24)
        }
        .frame(width: width, height: height)
        .rotationEffect(.degrees(rotation))
    }

    private var canSubmit: Bool {
        email.trimmingCharacters(in: .whitespacesAndNewlines).contains("@") && password.count >= 6
    }
}

private enum AuthMode {
    case signUp
    case login

    var title: String {
        switch self {
        case .signUp:
            return "Welcome to BetterNotes"
        case .login:
            return "Log in to BetterNotes"
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .signUp:
            return "Create an account"
        case .login:
            return "Log in"
        }
    }

    var secondaryPrompt: String {
        switch self {
        case .signUp:
            return "Already have an account?"
        case .login:
            return "Need an account?"
        }
    }

    var secondaryActionTitle: String {
        switch self {
        case .signUp:
            return "Log in"
        case .login:
            return "Create one"
        }
    }

    var alternate: AuthMode {
        switch self {
        case .signUp:
            return .login
        case .login:
            return .signUp
        }
    }
}

private struct AccountUsageSheet: View {
    @ObservedObject var authStore: BetterNotesAuthStore
    @Environment(\.dismiss) private var dismiss
    let serverAddress: String

    @State private var usage: AccountUsageSummary?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Account")
                        .font(.largeTitle.bold())
                    Text("Beta status for this BetterNotes account.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    accountRow(
                        title: "Email",
                        value: usage?.email ?? authStore.email ?? "Signed in",
                        systemImage: "envelope"
                    )

                    accountRow(
                        title: "AI scans",
                        value: scanUsageText,
                        systemImage: "sparkles"
                    )

                    accountRow(
                        title: "Backend",
                        value: backendStatusText,
                        systemImage: "server.rack"
                    )

                    accountRow(
                        title: "Plan",
                        value: usage?.plan ?? "Free beta",
                        systemImage: "creditcard"
                    )
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task {
                        await authStore.signOut()
                        dismiss()
                    }
                } label: {
                    Text("Sign Out")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.large)
                .disabled(authStore.isWorking)

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity, alignment: .center)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await loadUsage()
                        }
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                await loadUsage()
            }
        }
    }

    private var scanUsageText: String {
        guard let usage else {
            return isLoading ? "Loading..." : "Unavailable"
        }
        return "\(usage.usedScans) of \(usage.freeScanLimit) used"
    }

    private var backendStatusText: String {
        guard let usage else {
            return isLoading ? "Checking..." : "Unavailable"
        }

        if usage.aiConfigured && usage.authConfigured && usage.databaseReady {
            return usage.backendStatus
        }

        return "Needs attention"
    }

    private func accountRow(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func loadUsage() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            usage = try await BetterNotesAuthClient.accountUsage(
                serverAddress: serverAddress,
                accessToken: authStore.session?.accessToken
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ClassSetupView: View {
    let onSkip: () -> Void
    let onFinish: ([String]) -> Void

    @State private var classNames = ["", "", ""]

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(Color.accentColor)

                    Text("Set up your semester")
                        .font(.largeTitle.bold())

                    Text("Add the classes you are taking right now. BetterNotes will make a folder for each one.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 560)
                }

                VStack(spacing: 12) {
                    ForEach(classNames.indices, id: \.self) { index in
                        HStack(spacing: 10) {
                            TextField("Class name", text: $classNames[index])
                                .textInputAutocapitalization(.words)
                                .padding(14)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

                            if classNames.count > 1 {
                                Button {
                                    classNames.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Button {
                        classNames.append("")
                    } label: {
                        Label("Add Another Class", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .frame(maxWidth: 520)

                VStack(spacing: 10) {
                    Button {
                        onFinish(classNames)
                    } label: {
                        Text("Create Class Folders")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(cleanedClassNames.isEmpty)

                    Button("Skip for Now", action: onSkip)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 520)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Class Setup")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var cleanedClassNames: [String] {
        classNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct SharedPDFImportSheet: View {
    let item: PendingSharedImport
    let folders: [ClassFolder]
    let initialFolderID: UUID?
    let onImport: (UUID, SharedImportRole) -> Void
    let onDiscard: () -> Void

    @State private var selectedFolderID: UUID?

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

                Section {
                    ForEach(SharedImportRole.allCases) { role in
                        Button {
                            guard let selectedFolderID else { return }
                            onImport(selectedFolderID, role)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: role.icon)
                                    .font(.title3)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(role.title)
                                        .font(.headline)
                                    Text(role.description)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedFolderID == nil)
                    }
                } header: {
                    Text("Open PDF As")
                }
            }
            .navigationTitle("Import to BetterNotes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard", role: .destructive, action: onDiscard)
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
                        VStack(spacing: 12) {
                            ForEach(NoteTemplate.allCases) { template in
                                Button {
                                    selectTemplate(template)
                                } label: {
                                    HStack(spacing: 16) {
                                        Image(systemName: template.icon)
                                            .font(.system(size: 26, weight: .semibold))
                                            .frame(width: 42)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(template.title)
                                                .font(.headline)

                                            Text(template.subtitle)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }

                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(maxWidth: .infinity, minHeight: 86)
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
        .presentationDetents(step == .chooseType ? [.height(420), .large] : [.large])
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

private struct AuthSheet: View {
    @ObservedObject var authStore: BetterNotesAuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("BetterNotes Account")
                        .font(.title2.bold())

                    Text("Sign in to connect AI usage to your email instead of only this iPad install.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }

                if let message = authStore.statusMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(authStore.isSignedIn ? Color.green : Color.secondary)
                }

                VStack(spacing: 10) {
                    Button {
                        Task {
                            await authStore.signIn(email: email, password: password)
                            if authStore.isSignedIn {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            if authStore.isWorking {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("Sign In")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(authStore.isWorking || !canSubmit)

                    Button {
                        Task {
                            await authStore.signUp(email: email, password: password)
                            if authStore.isSignedIn {
                                dismiss()
                            }
                        }
                    } label: {
                        Text("Create Account")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(authStore.isWorking || !canSubmit)
                }

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity, alignment: .center)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var canSubmit: Bool {
        email.trimmingCharacters(in: .whitespacesAndNewlines).contains("@") && password.count >= 6
    }
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
