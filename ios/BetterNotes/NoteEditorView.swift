import PhotosUI
import SwiftUI

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

struct NoteEditorView: View {
    let note: StudyNote
    let onBack: () -> Void
    let onRename: () -> Void
    let onSaveDrawing: (Data) -> Void
    let onSavePageDrawing: (Data, UUID) -> Void
    let onSaveTextBoxes: ([NoteTextBox]) -> Void
    let onSaveImageBoxes: ([NoteImageBox]) -> Void
    let onSaveAIConversation: ([AIChatMessage], String?, AIFeedback?) -> Void
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
    @State private var pendingScanBounds: CGRect?
    @State private var pendingScanIsFullPage = true
    @State private var aiSheetDetent: PresentationDetent = .height(330)
    @AppStorage("BetterNotes.aiServerAddress")
    private var aiServerAddress = "http://Miless-MacBook-Air-3006.local:8080"
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

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .top) {
                DrawingCanvasView(
                    drawingData: activeDrawingData,
                    pdfBackgroundURL: importedPDFBackgroundURL,
                    blankPageCount: supportsBlankPages ? blankPages.count : 1,
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
                    onAISelectionChanged: { aiSelectionBounds = $0 },
                    onBlankPageExtensionNeeded: {},
                    onVisibleBlankPageChanged: { _, _ in }
                )
                .ignoresSafeArea()

                editorHeader

                VStack {
                    floatingToolbar
                        .fixedSize()
                        .padding(.top, 24)

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
                                if hasAIConversation {
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
                        .onChange(of: note.aiMessages.count) {
                            scrollToLatestAIMessage(proxy)
                        }
                    }

                    if hasAIConversation {
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
    }

    private var statusSymbol: String {
        aiStatus?.hasPrefix("Connected") == true ? "checkmark.circle.fill" : "info.circle"
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
        !note.aiMessages.isEmpty
    }

    private var aiConversationBottomID: String {
        "ai-conversation-bottom"
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

            aiModePicker

            TextField(
                "Tell AI what to focus on (optional)",
                text: $aiFocus,
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(2, reservesSpace: true)

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
                    selectedAIMode = mode
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
            ForEach(note.aiMessages) { message in
                aiMessageBubble(message)
            }
        }
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

    private var aiCompactModePicker: some View {
        HStack(spacing: 8) {
            ForEach(AIInteractionMode.allCases) { mode in
                Button {
                    selectedAIMode = mode
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

            Divider()

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.right.circle")
                    .foregroundStyle(.blue)
                    .padding(.top, 2)

                LatexText(content: feedback.nextStep)
            }
            .font(.subheadline.weight(.medium))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
        pendingScanIsFullPage = selectionBounds == nil
        aiFeedback = nil
        aiStatus = nil
        aiSheetDetent = .height(430)
        isShowingAiScan = true
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
                    drawingData: activeDrawingData,
                    selectionBounds: pendingScanIsFullPage ? nil : pendingScanBounds,
                    mode: selectedAIMode,
                    focus: aiFocus,
                    noteTemplate: note.template,
                    attachments: note.attachments,
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
                    text: "\(result.feedback.body)\n\nNext step: \(result.feedback.nextStep)",
                    mode: selectedAIMode
                )
                onSaveAIConversation(
                    note.aiMessages + [studentMessage, assistantMessage],
                    result.transcription,
                    result.feedback
                )
                aiStatus = nil
                aiSheetDetent = .medium
            } catch {
                aiStatus = error.localizedDescription
            }
            isScanning = false
        }
    }

    private func sendFollowUp() {
        let question = aiFollowUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        aiFollowUpText = ""
        isSendingFollowUp = true
        aiStatus = "Asking AI..."

        let studentMessage = AIChatMessage(role: .student, text: question)
        let messagesWithQuestion = note.aiMessages + [studentMessage]
        onSaveAIConversation(
            messagesWithQuestion,
            note.aiLatestTranscription,
            note.aiLatestFeedback
        )

        Task {
            do {
                let reply = try await AIBackendClient.askFollowUp(
                    drawingData: activeDrawingData,
                    question: question,
                    mode: selectedAIMode,
                    transcription: note.aiLatestTranscription,
                    latestFeedback: note.aiLatestFeedback ?? aiFeedback,
                    chatMessages: messagesWithQuestion,
                    noteTemplate: note.template,
                    attachments: note.attachments,
                    serverAddress: aiServerAddress
                )
                let assistantMessage = AIChatMessage(role: .assistant, text: reply, mode: selectedAIMode)
                onSaveAIConversation(
                    messagesWithQuestion + [assistantMessage],
                    note.aiLatestTranscription,
                    note.aiLatestFeedback ?? aiFeedback
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
                }

                ForEach(NoteEditorTool.allCases) { tool in
                    Button {
                        isAISelectionMode = false
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

    private var aiLensButton: some View {
        Button {
            aiSelectionBounds = nil
            isAISelectionMode.toggle()
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
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
            .padding(.bottom, 24)
        }
    }
}
