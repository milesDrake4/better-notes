import PhotosUI
import SwiftUI

private let localMacAIServerAddress = "http://Miless-MacBook-Air-3006.local:8080"
private let productionAIServerAddress = "https://better-notes-api.onrender.com"

private enum NoteInkColor: String, CaseIterable, Identifiable {
    case black
    case blue
    case red
    case green
    case purple

    var id: Self { self }

    var title: String {
        switch self {
        case .black: "Black"
        case .blue: "Blue"
        case .red: "Red"
        case .green: "Green"
        case .purple: "Purple"
        }
    }

    var color: Color {
        switch self {
        case .black: .black
        case .blue: .blue
        case .red: .red
        case .green: .green
        case .purple: .purple
        }
    }
}

private enum NoteHighlighterColor: String, CaseIterable, Identifiable {
    case yellow
    case pink
    case green
    case blue
    case orange

    var id: Self { self }

    var title: String {
        switch self {
        case .yellow: "Yellow"
        case .pink: "Pink"
        case .green: "Green"
        case .blue: "Blue"
        case .orange: "Orange"
        }
    }

    var color: Color {
        switch self {
        case .yellow: .yellow
        case .pink: .pink
        case .green: .green
        case .blue: .cyan
        case .orange: .orange
        }
    }
}

private struct GridPreviewLines: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let spacing: CGFloat = 12
                var x: CGFloat = 0
                while x <= geometry.size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                    x += spacing
                }

                var y: CGFloat = 0
                while y <= geometry.size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    y += spacing
                }
            }
            .stroke(Color.gray.opacity(0.34), lineWidth: 1)
        }
    }
}

struct NoteEditorView: View {
    let note: StudyNote
    let onBack: () -> Void
    let onRename: () -> Void
    let onSaveDrawing: (Data) -> Void
    let onSavePageDrawing: (Data, UUID) -> Void
    let onSaveTextBoxes: ([NoteTextBox]) -> Void
    let onSaveImageBoxes: ([NoteImageBox]) -> Void
    let onSaveAIConversation: ([AIChatMessage], String?, AIFeedback?) -> Void
    let onSaveAIThreads: ([AIThread], UUID?) -> Void
    let onAddBlankPage: () -> NotePage?

    @State private var isShowingAiScan = false
    @State private var aiFocus = ""
    @State private var aiStatus: String?
    @State private var aiFeedback: AIFeedback?
    @State private var selectedAIMode: AIInteractionMode = .check
    @State private var aiFollowUpText = ""
    @State private var isSendingFollowUp = false
    @State private var isScanning = false
    @State private var isCheckingServer = false
    @State private var isAISelectionMode = false
    @State private var aiSelectionBounds: CGRect?
    @State private var aiSelectionDrawingData: Data?
    @State private var pendingScanBounds: CGRect?
    @State private var pendingScanDrawingData: Data?
    @State private var hasPendingScan = false
    @State private var pendingScanIsFullPage = true
    @State private var aiSheetDetent: PresentationDetent = .height(330)
    @AppStorage("BetterNotes.aiServerAddress")
    private var aiServerAddress = productionAIServerAddress
    @AppStorage("BetterNotes.lastAIMode")
    private var lastAIModeRawValue = AIInteractionMode.check.rawValue
    @AppStorage("BetterNotes.notePageStyle")
    private var pageStyleRawValue = NotePageStyle.blank.rawValue
    @State private var selectedTool: NoteEditorTool = .pencil
    @State private var pencilColor: NoteInkColor = .black
    @State private var pencilWidth: CGFloat = 6
    @State private var highlighterColor: NoteHighlighterColor = .yellow
    @State private var highlighterWidth: CGFloat = 8
    @State private var textFontSize: CGFloat = 20
    @State private var pendingPhotoPoint: CGPoint?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isShowingPhotoPicker = false
    @State private var undoRequest = 0
    @State private var redoRequest = 0
    @State private var isShowingPaperStylePicker = false

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .top) {
                if supportsBlankPages {
                    BlankNotebookCanvasView(
                        pages: blankPages,
                        pageStyle: selectedPageStyle,
                        selectedTool: selectedTool,
                        pencilColor: pencilColor.color,
                        pencilWidth: pencilWidth * 2,
                        highlighterColor: highlighterColor.color,
                        highlighterWidth: highlighterWidth * 2,
                        isAISelectionMode: isAISelectionMode,
                        undoRequest: undoRequest,
                        redoRequest: redoRequest,
                        textBoxes: note.textBoxes,
                        textFontSize: textFontSize,
                        imageBoxes: note.imageBoxes,
                        onPageDrawingChanged: onSavePageDrawing,
                        onTextBoxesChanged: onSaveTextBoxes,
                        onImageBoxesChanged: onSaveImageBoxes,
                        onPhotoPlacementRequested: beginPhotoPlacement,
                        onAISelectionChanged: { bounds, drawingData in
                            aiSelectionBounds = bounds
                            aiSelectionDrawingData = drawingData
                        },
                        onVisibleBlankPageChanged: { _, _ in }
                    )
                    .ignoresSafeArea()
                } else {
                    DrawingCanvasView(
                        drawingData: activeDrawingData,
                        pdfBackgroundURL: importedPDFBackgroundURL,
                        blankPageCount: 1,
                        pageStyle: .blank,
                        selectedTool: selectedTool,
                        pencilColor: pencilColor.color,
                        pencilWidth: pencilWidth * 2,
                        highlighterColor: highlighterColor.color,
                        highlighterWidth: highlighterWidth * 2,
                        isAISelectionMode: isAISelectionMode,
                        undoRequest: undoRequest,
                        redoRequest: redoRequest,
                        textBoxes: note.textBoxes,
                        textFontSize: textFontSize,
                        imageBoxes: note.imageBoxes,
                        onDrawingChanged: saveActiveDrawing,
                        onTextBoxesChanged: onSaveTextBoxes,
                        onImageBoxesChanged: onSaveImageBoxes,
                        onPhotoPlacementRequested: beginPhotoPlacement,
                        onAISelectionChanged: { bounds, drawingData in
                            aiSelectionBounds = bounds
                            aiSelectionDrawingData = drawingData
                        },
                        onBlankPageExtensionNeeded: {},
                        onVisibleBlankPageChanged: { _, _ in }
                    )
                    .ignoresSafeArea()
                }

                editorHeader

                VStack {
                    floatingToolbar
                        .fixedSize()
                        .padding(.top, 24)

                    if supportsBlankPages && isShowingPaperStylePicker {
                        paperStylePicker
                            .padding(.top, 6)
                    }

                    if isAISelectionMode {
                        aiLensTabStrip
                            .padding(.top, 6)
                    }

                    Spacer()
                }

                if let instruction = activeInstruction {
                    Text(instruction)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isAISelectionMode ? Color.white : Color.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            isAISelectionMode ? Color.accentColor : Color.clear,
                            in: Capsule()
                        )
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                        .padding(.top, 104)
                        .allowsHitTesting(false)
                }

                if isAISelectionMode {
                    aiSelectionControls
                }
            }
        }
        .navigationBarBackButtonHidden()
        .sheet(isPresented: $isShowingAiScan) {
            NavigationStack {
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                if hasPendingScan {
                                    scanSetupPanel
                                } else if hasAIConversation {
                                    aiThreadSwitcher
                                    aiConversationView
                                    Color.clear
                                        .frame(height: 1)
                                        .id(aiConversationBottomID)
                                } else {
                                    scanSetupPanel

                                    if let aiFeedback {
                                        feedbackView(aiFeedback)
                                    }
                                }
                            }
                            .padding(20)
                            .frame(maxWidth: 660)
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                        .onAppear {
                            scrollToLatestAIMessage(proxy)
                        }
                        .onChange(of: activeAIMessages.count) {
                            scrollToLatestAIMessage(proxy)
                        }
                    }

                    if !hasPendingScan && hasAIConversation {
                        Divider()

                        pinnedAIChatControls
                        Divider()

                        followUpComposer
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            checkServer()
                        } label: {
                            Image(systemName: "network")
                        }
                        .disabled(isCheckingServer || isScanning)
                        .accessibilityLabel("Check AI connection")
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            hasPendingScan = false
                            isShowingAiScan = false
                        }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.height(430), .medium, .large], selection: $aiSheetDetent)
            .presentationDragIndicator(.visible)
        }
        .photosPicker(
            isPresented: $isShowingPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .onChange(of: selectedPhotoItem) { _, item in
            Task {
                await placeSelectedPhoto(item)
            }
        }
        .onAppear {
            migrateAIServerAddressIfNeeded()
            restoreLastAIMode()
        }
    }

    private var statusSymbol: String {
        aiStatus?.hasPrefix("Connected") == true ? "checkmark.circle.fill" : "info.circle"
    }

    private func migrateAIServerAddressIfNeeded() {
        let savedAddress = aiServerAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            savedAddress.isEmpty ||
                savedAddress.hasPrefix(localMacAIServerAddress) ||
                savedAddress.hasPrefix("http://localhost:") ||
                savedAddress.hasPrefix("http://127.0.0.1:")
        else { return }

        aiServerAddress = productionAIServerAddress
    }

    private func restoreLastAIMode() {
        guard let mode = AIInteractionMode(rawValue: lastAIModeRawValue) else {
            lastAIModeRawValue = selectedAIMode.rawValue
            return
        }

        selectedAIMode = mode
    }

    private func setAIMode(_ mode: AIInteractionMode) {
        selectedAIMode = mode
        lastAIModeRawValue = mode.rawValue

        guard let currentThread = selectedAIScanThread else { return }

        let updatedThread = AIThread(
            id: currentThread.id,
            title: currentThread.title,
            createdAt: currentThread.createdAt,
            updatedAt: .now,
            mode: mode,
            scanScope: currentThread.scanScope,
            transcription: currentThread.transcription,
            latestFeedback: currentThread.latestFeedback,
            messages: currentThread.messages
        )
        let updatedThreads = aiThreads.map { thread in
            thread.id == updatedThread.id ? updatedThread : thread
        }
        onSaveAIThreads(updatedThreads, updatedThread.id)
    }

    private func restoreAIModeFromThread(_ thread: AIThread) {
        selectedAIMode = thread.mode
        lastAIModeRawValue = thread.mode.rawValue
    }

    private var importedPDFBackgroundURL: URL? {
        guard
            let attachment = note.attachments.first(where: { $0.kind == .importedPDF }),
            let url = try? AttachmentStorage.fileURL(for: attachment)
        else { return nil }

        return url
    }

    private var supportsBlankPages: Bool {
        importedPDFBackgroundURL == nil
    }

    private var blankPages: [NotePage] {
        note.blankPages
    }

    private var activeDrawingData: Data? {
        supportsBlankPages ? (note.drawingData ?? blankPages.first?.drawingData) : note.drawingData
    }

    private var contextSummary: String {
        let assignmentCount = note.attachments.filter { $0.kind == .homeworkSet || $0.kind == .exam }.count
        let rubricCount = note.attachments.filter { $0.kind == .rubric }.count

        switch (assignmentCount, rubricCount) {
        case (0, 0):
            return "AI Lens has no assignment or rubric context attached."
        case (0, 1):
            return "AI Lens will include 1 rubric attachment."
        case (0, let rubrics):
            return "AI Lens will include \(rubrics) rubric attachments."
        case (1, 0):
            return "AI Lens will include 1 assignment attachment."
        case (let assignments, 0):
            return "AI Lens will include \(assignments) assignment attachments."
        default:
            return "AI Lens will include \(assignmentCount) assignment and \(rubricCount) rubric attachments."
        }
    }

    private var hasAssignmentContext: Bool {
        note.attachments.contains { $0.kind == .homeworkSet || $0.kind == .exam }
    }

    private var hasRubricContext: Bool {
        note.attachments.contains { $0.kind == .rubric }
    }

    private var hasAIConversation: Bool {
        !aiThreads.isEmpty
    }

    private var aiConversationBottomID: String {
        "ai-conversation-bottom"
    }

    private var aiThreads: [AIThread] {
        if !note.aiThreads.isEmpty {
            return note.aiThreads
        }

        guard !note.aiMessages.isEmpty else { return [] }
        return [
            AIThread(
                title: "Previous Chat",
                mode: note.aiLatestFeedback == nil ? .check : selectedAIMode,
                scanScope: "scan",
                transcription: note.aiLatestTranscription,
                latestFeedback: note.aiLatestFeedback,
                messages: note.aiMessages
            )
        ]
    }

    private var selectedAIThread: AIThread? {
        let threads = aiThreads
        if let selectedID = note.selectedAIThreadID,
           let selected = threads.first(where: { $0.id == selectedID }) {
            return selected
        }
        return threads.last
    }

    private var selectedAIScanThread: AIThread? {
        guard let selectedID = note.selectedAIThreadID else { return nil }
        return aiThreads.first { $0.id == selectedID }
    }

    private var aiLensDropdownTitle: String {
        selectedAIScanThread?.title ?? "New Chat"
    }

    private var aiLensDropdownIcon: String {
        selectedAIScanThread?.mode.icon ?? "plus.message"
    }

    private var activeAIMessages: [AIChatMessage] {
        selectedAIThread?.messages ?? []
    }

    private var activeAITranscription: String? {
        selectedAIThread?.transcription ?? note.aiLatestTranscription
    }

    private var activeAIFeedback: AIFeedback? {
        selectedAIThread?.latestFeedback ?? note.aiLatestFeedback ?? aiFeedback
    }

    private var scanDestinationText: String {
        if let selectedAIScanThread {
            return "Adding this scan to \(selectedAIScanThread.title)"
        }

        return "Starting a new AI chat"
    }

    private var activeInstruction: String? {
        if isAISelectionMode {
            nil
        } else {
            selectedTool.instruction
        }
    }

    private var scanSetupPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: pendingScanIsFullPage ? "doc.viewfinder" : "viewfinder")
                    .foregroundStyle(.blue)

                Text(pendingScanIsFullPage ? "Scan Page" : "Scan Selection")
                    .font(.headline)

                Spacer()
            }

            Label(scanDestinationText, systemImage: selectedAIScanThread == nil ? "plus.message" : "text.bubble")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            aiModePicker

            TextField(
                "Tell AI what to focus on (optional)",
                text: $aiFocus,
                axis: .vertical
            )
            .lineLimit(2, reservesSpace: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.03), radius: 6, y: 2)

            contextStatusRow

            Button {
                performScan()
            } label: {
                HStack {
                    if isScanning {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isScanning ? "Reading Work..." : "Ask AI")
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isScanning || isSendingFollowUp)

            if let aiStatus {
                Label(aiStatus, systemImage: statusSymbol)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private var aiModePicker: some View {
        HStack(spacing: 8) {
            ForEach(AIInteractionMode.allCases) { mode in
                Button {
                    setAIMode(mode)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 17, weight: .semibold))

                        Text(mode.title)
                            .font(.caption.weight(.semibold))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(selectedAIMode == mode ? Color.white : Color.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 66)
                    .background(
                        selectedAIMode == mode ? Color.accentColor : Color(.tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                selectedAIMode == mode ? Color.accentColor : Color.primary.opacity(0.12),
                                lineWidth: 1
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var contextStatusRow: some View {
        HStack(spacing: 8) {
            contextStatusPill(
                title: "Assignment",
                isAttached: hasAssignmentContext,
                icon: "doc.text"
            )

            contextStatusPill(
                title: "Rubric",
                isAttached: hasRubricContext,
                icon: "checkmark.seal"
            )
        }
        .accessibilityElement(children: .combine)
    }

    private func contextStatusPill(title: String, isAttached: Bool, icon: String) -> some View {
        Label("\(title): \(isAttached ? "Attached" : "Not attached")", systemImage: isAttached ? icon : "xmark.circle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(isAttached ? Color.green : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isAttached ? Color.green.opacity(0.12) : Color.primary.opacity(0.06),
                in: Capsule()
            )
    }

    private var aiConversationView: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(activeAIMessages) { message in
                aiMessageBubble(message)
            }
        }
    }

    private var aiLensTabStrip: some View {
        HStack(spacing: 8) {
            Menu {
                Button {
                    onSaveAIThreads(aiThreads, nil)
                } label: {
                    Label("New Chat", systemImage: "plus.message")
                }

                if !aiThreads.isEmpty {
                    Divider()

                    ForEach(aiThreads) { thread in
                        Button {
                            restoreAIModeFromThread(thread)
                            onSaveAIThreads(aiThreads, thread.id)
                        } label: {
                            Label(thread.title, systemImage: thread.mode.icon)
                        }
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: aiLensDropdownIcon)
                        .font(.system(size: 13, weight: .semibold))

                    Text(aiLensDropdownTitle)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: 150, alignment: .leading)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(selectedAIScanThread == nil ? Color.accentColor : Color.primary)
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                }
            }
            .accessibilityLabel("AI chat menu")
        }
        .padding(7)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 9, y: 4)
    }

    private var aiThreadSwitcher: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AI Chats")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("New scan creates a new chat")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(aiThreads) { thread in
                        Button {
                            openAIThread(thread)
                        } label: {
                            Label(thread.title, systemImage: thread.mode.icon)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .foregroundStyle(selectedAIThread?.id == thread.id ? Color.white : Color.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    selectedAIThread?.id == thread.id
                                        ? Color.accentColor
                                        : Color(.secondarySystemGroupedBackground),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private var aiChatControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            aiModePicker
            contextStatusRow

            if let aiStatus {
                Label(aiStatus, systemImage: statusSymbol)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private var pinnedAIChatControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            aiCompactModePicker
            contextStatusRow
            HStack(spacing: 8) {
                addScanToChatButton
                newAIChatScanButton
            }

            if let aiStatus {
                Label(aiStatus, systemImage: statusSymbol)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private var addScanToChatButton: some View {
        Button {
            beginAddingScanToCurrentAIThread()
        } label: {
            Label("Add Scan to This Chat", systemImage: "viewfinder")
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .foregroundStyle(Color.accentColor)
                .background(Color.accentColor.opacity(0.1), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(selectedAIThread == nil || isScanning || isSendingFollowUp)
        .accessibilityLabel("Add scan to this AI chat")
    }

    private var newAIChatScanButton: some View {
        Button {
            beginNewAIChatScan()
        } label: {
            Label("New Chat Scan", systemImage: "plus.message")
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .foregroundStyle(Color.primary)
                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(isScanning || isSendingFollowUp)
        .accessibilityLabel("Start a new AI chat scan")
    }

    private var aiCompactModePicker: some View {
        HStack(spacing: 8) {
            ForEach(AIInteractionMode.allCases) { mode in
                Button {
                    setAIMode(mode)
                } label: {
                    Label(mode.title, systemImage: mode.icon)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .foregroundStyle(selectedAIMode == mode ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            selectedAIMode == mode ? Color.accentColor : Color(.secondarySystemGroupedBackground),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .stroke(Color.primary.opacity(selectedAIMode == mode ? 0 : 0.1), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func aiMessageBubble(_ message: AIChatMessage) -> some View {
        let isStudent = message.role == .student

        return HStack {
            if isStudent {
                Spacer(minLength: 52)
            }

            VStack(alignment: .leading, spacing: 6) {
                if let mode = message.mode {
                    Label(mode.title, systemImage: mode.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isStudent ? Color.white.opacity(0.85) : Color.blue)
                }

                LatexText(content: message.text)
                    .font(.subheadline)
            }
            .padding(12)
            .background(
                isStudent ? Color.accentColor : Color.blue.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .foregroundStyle(isStudent ? Color.white : Color.primary)

            if !isStudent {
                Spacer(minLength: 52)
            }
        }
    }

    private var followUpComposer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask a follow-up", text: $aiFollowUpText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))

            Button {
                sendFollowUp()
            } label: {
                if isSendingFollowUp {
                    ProgressView()
                        .frame(width: 34, height: 34)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 31, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .buttonStyle(.plain)
            .disabled(
                isSendingFollowUp ||
                isScanning ||
                aiFollowUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private func scrollToLatestAIMessage(_ proxy: ScrollViewProxy) {
        guard hasAIConversation else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(aiConversationBottomID, anchor: .bottom)
            }
        }
    }

    private func feedbackView(_ feedback: AIFeedback) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(feedback.title, systemImage: "checkmark.bubble")
                .font(.headline)
                .foregroundStyle(.blue)

            LatexText(content: feedback.body)

            if let nextStep = cleanedNextStep(feedback) {
                Divider()

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.right.circle")
                        .foregroundStyle(.blue)
                        .padding(.top, 2)

                    LatexText(content: nextStep)
                }
                .font(.subheadline.weight(.medium))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func cleanedNextStep(_ feedback: AIFeedback) -> String? {
        guard let nextStep = feedback.nextStep?.trimmingCharacters(in: .whitespacesAndNewlines),
              !nextStep.isEmpty else {
            return nil
        }
        return nextStep
    }

    private func assistantChatText(for feedback: AIFeedback) -> String {
        guard let nextStep = cleanedNextStep(feedback) else {
            return feedback.body
        }
        return "\(feedback.body)\n\nNext step: \(nextStep)"
    }

    private func checkServer() {
        isCheckingServer = true
        aiStatus = "Checking your Mac..."
        aiFeedback = nil

        Task {
            do {
                let health = try await AIBackendClient.health(serverAddress: aiServerAddress)
                aiStatus = health.aiConfigured
                    ? "Connected. AI is ready using \(health.model)."
                    : "Connected, but OPENAI_API_KEY is not configured on the Mac."
            } catch {
                aiStatus = "Could not connect: \(error.localizedDescription)"
            }
            isCheckingServer = false
        }
    }

    private func saveActiveDrawing(_ data: Data) {
        onSaveDrawing(data)
    }

    private func extendBlankNotebookIfNeeded() {
        guard supportsBlankPages else { return }
        _ = onAddBlankPage()
    }

    private func addPageManually() {
        guard supportsBlankPages else { return }
        isAISelectionMode = false
        _ = onAddBlankPage()
    }

    private func beginPhotoPlacement(at point: CGPoint) {
        pendingPhotoPoint = point
        selectedPhotoItem = nil
        isShowingPhotoPicker = true
    }

    @MainActor
    private func placeSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let point = pendingPhotoPoint else { return }
        defer {
            pendingPhotoPoint = nil
            selectedPhotoItem = nil
        }

        do {
            guard
                let data = try await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else { return }

            let maxSide: CGFloat = 280
            let aspectRatio = image.size.width / max(image.size.height, 1)
            let size: CGSize
            if aspectRatio >= 1 {
                size = CGSize(width: maxSide, height: maxSide / aspectRatio)
            } else {
                size = CGSize(width: maxSide * aspectRatio, height: maxSide)
            }

            let storedData = image.jpegData(compressionQuality: 0.82) ?? data
            let imageBox = NoteImageBox(
                imageData: storedData,
                frame: CGRect(
                    x: point.x,
                    y: point.y,
                    width: max(size.width, 80),
                    height: max(size.height, 80)
                )
            )
            onSaveImageBoxes(note.imageBoxes + [imageBox])
        } catch {
            aiStatus = "Could not add photo: \(error.localizedDescription)"
        }
    }

    private func prepareScan(selectionBounds: CGRect?) {
        isAISelectionMode = false
        pendingScanBounds = selectionBounds
        pendingScanDrawingData = selectionBounds == nil ? nil : aiSelectionDrawingData
        hasPendingScan = true
        pendingScanIsFullPage = selectionBounds == nil
        aiFeedback = nil
        aiStatus = nil
        aiSheetDetent = .height(430)
        isShowingAiScan = true
    }

    private func openAIThread(_ thread: AIThread) {
        restoreAIModeFromThread(thread)
        hasPendingScan = false
        pendingScanBounds = nil
        pendingScanDrawingData = nil
        pendingScanIsFullPage = true
        aiFeedback = nil
        aiStatus = nil
        aiSheetDetent = .medium
        onSaveAIThreads(aiThreads, thread.id)
        isShowingAiScan = true
    }

    private func beginAddingScanToCurrentAIThread() {
        guard let thread = selectedAIThread else { return }

        restoreAIModeFromThread(thread)
        hasPendingScan = false
        pendingScanBounds = nil
        pendingScanDrawingData = nil
        pendingScanIsFullPage = true
        aiSelectionBounds = nil
        aiSelectionDrawingData = nil
        aiFeedback = nil
        aiStatus = nil
        onSaveAIThreads(aiThreads, thread.id)
        isShowingAiScan = false
        isAISelectionMode = true
    }

    private func beginNewAIChatScan() {
        hasPendingScan = false
        pendingScanBounds = nil
        pendingScanDrawingData = nil
        pendingScanIsFullPage = true
        aiSelectionBounds = nil
        aiSelectionDrawingData = nil
        aiFeedback = nil
        aiStatus = nil
        onSaveAIThreads(aiThreads, nil)
        isShowingAiScan = false
        isAISelectionMode = true
    }

    private func performScan() {
        isScanning = true
        aiStatus = "Reading your handwriting..."
        aiFeedback = nil
        let prompt = aiFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        let studentPrompt = prompt.isEmpty ? selectedAIMode.defaultPrompt : prompt

        Task {
            do {
                let result = try await AIBackendClient.scanDrawing(
                    drawingData: pendingScanDrawingData ?? activeDrawingData,
                    selectionBounds: pendingScanIsFullPage ? nil : pendingScanBounds,
                    mode: selectedAIMode,
                    focus: aiFocus,
                    noteTemplate: note.template,
                    attachments: note.attachments,
                    chatMessages: selectedAIScanThread?.messages ?? [],
                    serverAddress: aiServerAddress
                )
                aiFeedback = result.feedback
                let studentMessage = AIChatMessage(
                    role: .student,
                    text: "\(pendingScanIsFullPage ? "Scan page" : "Scan selection"): \(studentPrompt)",
                    mode: selectedAIMode
                )
                let assistantMessage = AIChatMessage(
                    role: .assistant,
                    text: assistantChatText(for: result.feedback),
                    mode: selectedAIMode
                )
                if let targetThread = selectedAIScanThread {
                    let updatedThread = AIThread(
                        id: targetThread.id,
                        title: targetThread.title,
                        createdAt: targetThread.createdAt,
                        updatedAt: .now,
                        mode: selectedAIMode,
                        scanScope: pendingScanIsFullPage ? "page" : "selection",
                        transcription: result.transcription,
                        latestFeedback: result.feedback,
                        messages: targetThread.messages + [studentMessage, assistantMessage]
                    )
                    let updatedThreads = aiThreads.map { thread in
                        thread.id == updatedThread.id ? updatedThread : thread
                    }
                    onSaveAIThreads(updatedThreads, updatedThread.id)
                } else {
                    let newThread = AIThread(
                        title: generatedAIThreadTitle(
                            feedback: result.feedback,
                            transcription: result.transcription
                        ),
                        mode: selectedAIMode,
                        scanScope: pendingScanIsFullPage ? "page" : "selection",
                        transcription: result.transcription,
                        latestFeedback: result.feedback,
                        messages: [studentMessage, assistantMessage]
                    )
                    onSaveAIThreads(aiThreads + [newThread], newThread.id)
                }
                aiStatus = nil
                hasPendingScan = false
                aiFocus = ""
                aiSheetDetent = .medium
            } catch {
                aiStatus = error.localizedDescription
            }
            isScanning = false
        }
    }

    private func generatedAIThreadTitle(feedback: AIFeedback, transcription: String) -> String {
        if let chatTitle = feedback.chatTitle?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines),
            isUsefulAIThreadTitle(chatTitle) {
            return shortenedAIThreadTitle(chatTitle)
        }

        let title = feedback.title
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if isUsefulAIThreadTitle(title) {
            return shortenedAIThreadTitle(title)
        }

        let firstLine = transcription
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""

        if isUsefulAIThreadTitle(firstLine) {
            return shortenedAIThreadTitle(firstLine)
        }

        return "New AI Chat"
    }

    private func isUsefulAIThreadTitle(_ title: String) -> Bool {
        guard title.count >= 4 else { return false }
        let genericTitles = [
            "AI feedback",
            "Feedback",
            "Check work",
            "Hint",
            "Grade"
        ]
        return !genericTitles.contains { title.localizedCaseInsensitiveContains($0) && title.count <= $0.count + 4 }
    }

    private func shortenedAIThreadTitle(_ title: String) -> String {
        let words = title.split(separator: " ")
        let shortened = words.prefix(6).joined(separator: " ")
        return shortened.count > 42
            ? String(shortened.prefix(39)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
            : shortened
    }

    private func saveCurrentAIThread(threadID: UUID? = nil, messages: [AIChatMessage]) {
        guard let currentThread = threadID.flatMap({ id in aiThreads.first { $0.id == id } }) ?? selectedAIThread else {
            onSaveAIConversation(messages, nil, nil)
            return
        }

        let updatedThread = AIThread(
            id: currentThread.id,
            title: currentThread.title,
            createdAt: currentThread.createdAt,
            updatedAt: .now,
            mode: currentThread.mode,
            scanScope: currentThread.scanScope,
            transcription: currentThread.transcription,
            latestFeedback: currentThread.latestFeedback,
            messages: messages
        )
        let updatedThreads = aiThreads.map { thread in
            thread.id == updatedThread.id ? updatedThread : thread
        }
        onSaveAIThreads(updatedThreads, updatedThread.id)
    }

    private func sendFollowUp() {
        let question = aiFollowUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        aiFollowUpText = ""
        isSendingFollowUp = true
        aiStatus = "Asking AI..."

        let studentMessage = AIChatMessage(role: .student, text: question)
        let baseThread = selectedAIThread
        let messagesWithQuestion = activeAIMessages + [studentMessage]
        saveCurrentAIThread(messages: messagesWithQuestion)

        Task {
            do {
                let reply = try await AIBackendClient.askFollowUp(
                    drawingData: activeDrawingData,
                    question: question,
                    mode: selectedAIMode,
                    transcription: activeAITranscription,
                    latestFeedback: activeAIFeedback,
                    chatMessages: messagesWithQuestion,
                    noteTemplate: note.template,
                    attachments: note.attachments,
                    serverAddress: aiServerAddress
                )
                let assistantMessage = AIChatMessage(role: .assistant, text: reply, mode: selectedAIMode)
                saveCurrentAIThread(
                    threadID: baseThread?.id,
                    messages: messagesWithQuestion + [assistantMessage]
                )
                aiStatus = nil
                aiSheetDetent = .medium
            } catch {
                aiStatus = error.localizedDescription
            }
            isSendingFollowUp = false
        }
    }

    private var editorHeader: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .frame(width: 38, height: 38)
            }
            .accessibilityLabel("Back")

            Button(action: onRename) {
                HStack(spacing: 6) {
                    Text(note.title)
                        .font(.headline)
                        .lineLimit(1)
                    Image(systemName: "pencil")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.top, 14)
        .padding(.horizontal, 16)
    }

    private var floatingToolbar: some View {
        VStack(spacing: 7) {
            HStack(spacing: 4) {
                Button {
                    undoRequest += 1
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Undo")
                .help("Undo")

                Button {
                    redoRequest += 1
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Redo")
                .help("Redo")

                if supportsBlankPages {
                    Button {
                        addPageManually()
                    } label: {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add Page")
                    .help("Add Page")

                    pageStyleMenu
                }

                ForEach(NoteEditorTool.allCases) { tool in
                    Button {
                        isAISelectionMode = false
                        isShowingPaperStylePicker = false
                        selectedTool = tool
                    } label: {
                        toolButtonIcon(for: tool)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tool.title)
                    .help(tool.title)
                    .opacity(isAISelectionMode ? 0.42 : 1)
                }

                Divider()
                    .frame(height: 26)
                    .padding(.horizontal, 3)

                aiLensButton
            }

            if !isAISelectionMode {
                if selectedTool == .pencil || selectedTool == .highlighter {
                    toolOptionsRow
                } else if selectedTool == .text {
                    textOptionsRow
                }
            }
        }
        .padding(7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
        .contentShape(Rectangle())
    }

    private func toolButtonIcon(for tool: NoteEditorTool) -> some View {
        Image(systemName: tool.symbol)
            .font(.system(size: 17, weight: .medium))
            .frame(width: 40, height: 40)
            .foregroundStyle(!isAISelectionMode && selectedTool == tool ? Color.white : Color.primary)
            .background(
                !isAISelectionMode && selectedTool == tool ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
    }

    private var selectedPageStyle: NotePageStyle {
        NotePageStyle(rawValue: pageStyleRawValue) ?? .blank
    }

    private var pageStyleMenu: some View {
        Button {
            isAISelectionMode = false
            isShowingPaperStylePicker.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selectedPageStyle.symbol)
                    .font(.system(size: 16, weight: .semibold))

                Text("Paper")
                    .font(.caption.weight(.semibold))
            }
            .frame(width: 82, height: 40)
            .foregroundStyle(isShowingPaperStylePicker ? Color.white : Color.accentColor)
            .background(
                isShowingPaperStylePicker ? Color.accentColor : Color.accentColor.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.accentColor.opacity(isShowingPaperStylePicker ? 0 : 0.28), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Paper Style")
        .help("Paper Style")
    }

    private var paperStylePicker: some View {
        HStack(spacing: 10) {
            ForEach(NotePageStyle.allCases) { style in
                paperStyleOption(style)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    private func paperStyleOption(_ style: NotePageStyle) -> some View {
        Button {
            pageStyleRawValue = style.rawValue
        } label: {
            VStack(spacing: 7) {
                paperStylePreview(style)
                    .frame(width: 82, height: 54)

                Text(style.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selectedPageStyle == style ? Color.accentColor : Color.primary)
            }
            .padding(8)
            .background(
                selectedPageStyle == style ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selectedPageStyle == style ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.title)
        .help(style.title)
    }

    private func paperStylePreview(_ style: NotePageStyle) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)

            if style == .grid {
                GridPreviewLines()
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
    }

    private var aiLensButton: some View {
        Button {
            aiSelectionBounds = nil
            if isAISelectionMode {
                isAISelectionMode = false
            } else {
                onSaveAIThreads(aiThreads, nil)
                isAISelectionMode = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "viewfinder.circle.fill")
                    .font(.system(size: 18, weight: .semibold))

                Text("AI Lens")
                    .font(.caption.weight(.semibold))
            }
            .frame(width: 92, height: 40)
            .foregroundStyle(isAISelectionMode ? Color.white : Color.accentColor)
            .background(
                isAISelectionMode ? Color.accentColor : Color.accentColor.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.accentColor.opacity(isAISelectionMode ? 0 : 0.28), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isAISelectionMode ? "Exit AI Lens" : "AI Lens")
        .help(isAISelectionMode ? "Exit AI Lens" : "AI Lens")
    }

    private var toolOptionsRow: some View {
        HStack(spacing: 12) {
            colorDots

            Divider()
                .frame(height: 22)

            thicknessSlider
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
    }

    private var colorDots: some View {
        HStack(spacing: 8) {
            if selectedTool == .highlighter {
                ForEach(NoteHighlighterColor.allCases) { option in
                    colorButton(
                        color: option.color,
                        isSelected: option == highlighterColor,
                        title: option.title
                    ) {
                        highlighterColor = option
                    }
                }
            } else {
                ForEach(NoteInkColor.allCases) { option in
                    colorButton(
                        color: option.color,
                        isSelected: option == pencilColor,
                        title: option.title
                    ) {
                        pencilColor = option
                    }
                }
            }
        }
    }

    private func colorButton(
        color: Color,
        isSelected: Bool,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 22, height: 22)
                .overlay {
                    Circle()
                        .stroke(Color.white, lineWidth: isSelected ? 3 : 1)
                }
                .overlay {
                    Circle()
                        .stroke(Color.primary.opacity(isSelected ? 0.65 : 0.18), lineWidth: 1)
                }
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
    }

    private var activeThickness: CGFloat {
        selectedTool == .highlighter ? highlighterWidth : pencilWidth
    }

    private var activeThicknessBinding: Binding<Double> {
        Binding(
            get: { Double(activeThickness) },
            set: { setActiveThickness(CGFloat($0)) }
        )
    }

    private var thicknessSlider: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.primary.opacity(0.36))
                .frame(width: 5, height: 5)

            Slider(value: activeThicknessBinding, in: 1...12, step: 1)
                .frame(width: 132)
                .accessibilityLabel("Size")

            Circle()
                .fill(Color.primary.opacity(0.55))
                .frame(width: 14, height: 14)

            Text("\(Int(activeThickness))")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)
        }
    }

    private func setActiveThickness(_ width: CGFloat) {
        if selectedTool == .highlighter {
            highlighterWidth = width
        } else {
            pencilWidth = width
        }
    }

    private var textOptionsRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "textformat.size.smaller")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            Slider(value: $textFontSize, in: 12...44, step: 1)
                .frame(width: 150)
                .accessibilityLabel("Text Size")

            Image(systemName: "textformat.size.larger")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)

            Text("\(Int(textFontSize))")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
    }

    private var aiSelectionControls: some View {
        VStack {
            Spacer()

            VStack(spacing: 10) {
                Text(
                    aiSelectionBounds == nil
                        ? "Draw a loop around the work you want AI to check."
                        : "Selection ready"
                )
                .font(.subheadline.weight(.medium))

                HStack(spacing: 10) {
                    Button {
                        isAISelectionMode = false
                        aiSelectionBounds = nil
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Cancel AI selection")

                    Button {
                        guard let aiSelectionBounds else { return }
                        prepareScan(selectionBounds: aiSelectionBounds)
                    } label: {
                        Label("Scan Selection", systemImage: "viewfinder")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(aiSelectionBounds == nil)

                    Button {
                        prepareScan(selectionBounds: nil)
                    } label: {
                        Label("Scan Page", systemImage: "doc.viewfinder")
                    }
                    .buttonStyle(.bordered)

                    if let selectedAIScanThread {
                        Button {
                            openAIThread(selectedAIScanThread)
                        } label: {
                            Label("Open Chat", systemImage: "text.bubble")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
            .padding(.bottom, 24)
        }
    }
}
