import SwiftUI

struct NoteEditorView: View {
    let note: StudyNote
    let onBack: () -> Void
    let onRename: () -> Void
    let onSaveDrawing: (Data) -> Void

    @State private var isShowingAiScan = false
    @State private var aiFocus = ""
    @State private var aiStatus: String?
    @State private var aiFeedback: AIFeedback?
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
    @State private var toolbarPosition: CGPoint?
    @GestureState private var toolbarDrag = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                DrawingCanvasView(
                    drawingData: note.drawingData,
                    pdfBackgroundURL: importedPDFBackgroundURL,
                    selectedTool: selectedTool,
                    isAISelectionMode: isAISelectionMode,
                    onDrawingChanged: onSaveDrawing,
                    onAISelectionChanged: { aiSelectionBounds = $0 }
                )
                .ignoresSafeArea()

                editorHeader

                floatingToolbar
                    .fixedSize()
                    .position(draggedToolbarPosition(in: geometry.size))
                    .simultaneousGesture(toolbarDragGesture(in: geometry.size))

                if let instruction = selectedTool.instruction {
                    Text(instruction)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                        .padding(.top, 104)
                        .allowsHitTesting(false)
                }

                if isAISelectionMode {
                    aiSelectionControls
                }
            }
            .onAppear {
                if toolbarPosition == nil {
                    toolbarPosition = initialToolbarPosition(in: geometry.size)
                }
            }
        }
        .navigationBarBackButtonHidden()
        .sheet(isPresented: $isShowingAiScan) {
            NavigationStack {
                Group {
                    if let aiFeedback {
                        ScrollView {
                            feedbackView(aiFeedback)
                                .padding(20)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 10) {
                                Image(systemName: pendingScanIsFullPage ? "doc.viewfinder" : "viewfinder")
                                    .foregroundStyle(.blue)

                                Text(pendingScanIsFullPage ? "Scan Page" : "Scan Selection")
                                    .font(.headline)

                                Spacer()
                            }

                            TextField(
                                "What should AI focus on? (optional)",
                                text: $aiFocus,
                                axis: .vertical
                            )
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2, reservesSpace: true)

                            if !note.attachments.isEmpty {
                                Label(contextSummary, systemImage: "paperclip")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

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
                            .disabled(isScanning)

                            if let aiStatus {
                            Label(aiStatus, systemImage: statusSymbol)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity, alignment: .top)
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
            .presentationDetents([.height(330), .medium], selection: $aiSheetDetent)
            .presentationDragIndicator(.visible)
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

    private var contextSummary: String {
        let assignmentCount = note.attachments.filter { $0.kind != .rubric }.count
        let rubricCount = note.attachments.filter { $0.kind == .rubric }.count

        switch (assignmentCount, rubricCount) {
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

    private func prepareScan(selectionBounds: CGRect?) {
        isAISelectionMode = false
        pendingScanBounds = selectionBounds
        pendingScanIsFullPage = selectionBounds == nil
        aiFeedback = nil
        aiStatus = nil
        aiSheetDetent = .height(330)
        isShowingAiScan = true
    }

    private func performScan() {
        isScanning = true
        aiStatus = "Reading your handwriting..."
        aiFeedback = nil

        Task {
            do {
                aiFeedback = try await AIBackendClient.scanDrawing(
                    drawingData: note.drawingData,
                    selectionBounds: pendingScanIsFullPage ? nil : pendingScanBounds,
                    focus: aiFocus,
                    noteTemplate: note.template,
                    attachments: note.attachments,
                    serverAddress: aiServerAddress
                )
                aiStatus = nil
                aiSheetDetent = .medium
            } catch {
                aiStatus = error.localizedDescription
            }
            isScanning = false
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
        HStack(spacing: 4) {
            ForEach(NoteEditorTool.allCases) { tool in
                Button {
                    isAISelectionMode = false
                    selectedTool = tool
                } label: {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 40, height: 40)
                        .foregroundStyle(selectedTool == tool ? Color.white : Color.primary)
                        .background(
                            selectedTool == tool ? Color.accentColor : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tool.title)
                .help(tool.title)
            }

            Divider()
                .frame(height: 26)
                .padding(.horizontal, 3)

            Button {
                aiSelectionBounds = nil
                isAISelectionMode.toggle()
            } label: {
                Image(systemName: "viewfinder")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(isAISelectionMode ? Color.white : Color.accentColor)
                    .background(
                        isAISelectionMode ? Color.accentColor : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("AI Lens")
            .help("AI Lens")
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

    private func initialToolbarPosition(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: 48)
    }

    private func draggedToolbarPosition(in size: CGSize) -> CGPoint {
        let position = toolbarPosition ?? initialToolbarPosition(in: size)
        return CGPoint(
            x: position.x + toolbarDrag.width,
            y: position.y + toolbarDrag.height
        )
    }

    private func toolbarDragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($toolbarDrag) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let current = toolbarPosition ?? initialToolbarPosition(in: size)
                let proposed = CGPoint(
                    x: current.x + value.translation.width,
                    y: current.y + value.translation.height
                )
                toolbarPosition = CGPoint(
                    x: min(max(proposed.x, 190), max(190, size.width - 190)),
                    y: min(max(proposed.y, 46), max(46, size.height - 46))
                )
            }
    }
}
