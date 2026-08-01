import PencilKit
import PDFKit
import SwiftUI

enum NotePageStyle: String, CaseIterable, Identifiable {
    case blank
    case grid

    var id: Self { self }

    var title: String {
        switch self {
        case .blank: "Blank"
        case .grid: "Grid"
        }
    }

    var symbol: String {
        switch self {
        case .blank: "doc"
        case .grid: "square.grid.3x3"
        }
    }
}

enum NoteEditorTool: String, CaseIterable, Identifiable {
    case pencil
    case highlighter
    case eraser
    case text
    case selector
    case photo
    case hand

    var id: Self { self }

    var title: String {
        switch self {
        case .pencil: "Pencil"
        case .highlighter: "Highlighter"
        case .eraser: "Eraser"
        case .text: "Text"
        case .selector: "Lasso"
        case .photo: "Add Photo"
        case .hand: "Pan"
        }
    }

    var symbol: String {
        switch self {
        case .pencil: "pencil"
        case .highlighter: "highlighter"
        case .eraser: "eraser"
        case .text: "textformat"
        case .selector: "lasso"
        case .photo: "photo.badge.plus"
        case .hand: "hand.draw"
        }
    }

    var instruction: String? {
        switch self {
        case .text: "Tap the page to place a text box."
        case .photo: "Tap the page to place a photo."
        case .selector: "Circle handwriting to select and move it."
        case .hand: "Drag or pinch the page to move and zoom."
        default: nil
        }
    }
}

fileprivate final class NotePageBackgroundView: UIView {
    var pageStyle: NotePageStyle = .blank {
        didSet {
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        isOpaque = true
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        UIColor.white.setFill()
        UIRectFill(rect)

        guard pageStyle == .grid else { return }

        let spacing: CGFloat = 32
        let path = UIBezierPath()
        path.lineWidth = 1 / max(window?.screen.scale ?? UIScreen.main.scale, 1)

        var x: CGFloat = 0
        while x <= bounds.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: bounds.height))
            x += spacing
        }

        var y: CGFloat = 0
        while y <= bounds.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: bounds.width, y: y))
            y += spacing
        }

        UIColor(white: 0.82, alpha: 0.72).setStroke()
        path.stroke()
    }
}

struct DrawingCanvasView: UIViewRepresentable {
    let drawingData: Data?
    let pdfBackgroundURL: URL?
    let blankPageCount: Int
    let pageStyle: NotePageStyle
    let selectedTool: NoteEditorTool
    let pencilColor: Color
    let pencilWidth: CGFloat
    let highlighterColor: Color
    let highlighterWidth: CGFloat
    let isAISelectionMode: Bool
    let undoRequest: Int
    let redoRequest: Int
    let textBoxes: [NoteTextBox]
    let textFontSize: CGFloat
    let imageBoxes: [NoteImageBox]
    let onDrawingChanged: (Data) -> Void
    let onTextBoxesChanged: ([NoteTextBox]) -> Void
    let onImageBoxesChanged: ([NoteImageBox]) -> Void
    let onPhotoPlacementRequested: (CGPoint) -> Void
    let onAISelectionChanged: (CGRect?, Data?) -> Void
    let onBlankPageExtensionNeeded: () -> Void
    let onVisibleBlankPageChanged: (Int, CGRect) -> Void

    func makeUIView(context: Context) -> PDFDrawingCanvasContainerView {
        let containerView = PDFDrawingCanvasContainerView()
        let canvasView = containerView.canvasView
        canvasView.delegate = context.coordinator
#if targetEnvironment(simulator)
        canvasView.drawingPolicy = .anyInput
#else
        canvasView.drawingPolicy = .pencilOnly
#endif
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.isScrollEnabled = false
        canvasView.bounces = false
        canvasView.alwaysBounceVertical = false
        canvasView.alwaysBounceHorizontal = false
        canvasView.contentInsetAdjustmentBehavior = .never
        canvasView.contentInset = .zero
        canvasView.scrollIndicatorInsets = .zero
        canvasView.contentOffset = .zero
        canvasView.minimumZoomScale = 1
        canvasView.maximumZoomScale = 1
        canvasView.zoomScale = 1
        canvasView.contentSize = containerView.contentSize
        context.coordinator.configureSelectionGesture(on: canvasView)
        context.coordinator.configureEraserPreviewGesture(on: canvasView)
        context.coordinator.configureTextPlacementGesture(on: canvasView)
        context.coordinator.configurePhotoPlacementGesture(on: canvasView)
        containerView.configureBackground(url: pdfBackgroundURL, blankPageCount: blankPageCount, pageStyle: pageStyle)
        containerView.onVisibleBlankPageChanged = onVisibleBlankPageChanged
        containerView.setAllowsPencilScrolling(selectedTool == .hand && !isAISelectionMode)
        applyCurrentTool(to: canvasView, coordinator: context.coordinator)

        if let drawingData, let drawing = try? PKDrawing(data: drawingData) {
            canvasView.drawing = drawing
            context.coordinator.loadedDrawingData = drawingData
        }
        context.coordinator.syncTextBoxes(textBoxes, on: canvasView)
        context.coordinator.syncImageBoxes(imageBoxes, on: canvasView)

        canvasView.becomeFirstResponder()

        context.coordinator.onDrawingChanged = onDrawingChanged
        context.coordinator.onTextBoxesChanged = onTextBoxesChanged
        context.coordinator.onImageBoxesChanged = onImageBoxesChanged
        context.coordinator.onPhotoPlacementRequested = onPhotoPlacementRequested
        context.coordinator.currentTextFontSize = textFontSize
        context.coordinator.onAISelectionChanged = onAISelectionChanged
        context.coordinator.onBlankPageExtensionNeeded = onBlankPageExtensionNeeded
        context.coordinator.blankPageCount = blankPageCount
        context.coordinator.isBlankNotebook = pdfBackgroundURL == nil
        return containerView
    }

    func updateUIView(_ containerView: PDFDrawingCanvasContainerView, context: Context) {
        let canvasView = containerView.canvasView
        context.coordinator.onDrawingChanged = onDrawingChanged
        context.coordinator.onTextBoxesChanged = onTextBoxesChanged
        context.coordinator.onImageBoxesChanged = onImageBoxesChanged
        context.coordinator.onPhotoPlacementRequested = onPhotoPlacementRequested
        context.coordinator.currentTextFontSize = textFontSize
        context.coordinator.onAISelectionChanged = onAISelectionChanged
        context.coordinator.onBlankPageExtensionNeeded = onBlankPageExtensionNeeded
        context.coordinator.blankPageCount = blankPageCount
        context.coordinator.isBlankNotebook = pdfBackgroundURL == nil
        containerView.configureBackground(url: pdfBackgroundURL, blankPageCount: blankPageCount, pageStyle: pageStyle)
        containerView.onVisibleBlankPageChanged = onVisibleBlankPageChanged
        containerView.setAllowsPencilScrolling(selectedTool == .hand && !isAISelectionMode)
        applyCurrentTool(to: canvasView, coordinator: context.coordinator)
        context.coordinator.syncTextBoxes(textBoxes, on: canvasView)
        context.coordinator.syncImageBoxes(imageBoxes, on: canvasView)
        context.coordinator.applyTextFontSizeToEditingBoxes(textFontSize, on: canvasView)
        context.coordinator.handleUndoRedo(
            undoRequest: undoRequest,
            redoRequest: redoRequest,
            canvasView: canvasView
        )

        guard
            !context.coordinator.isUsingTool,
            let drawingData,
            drawingData != context.coordinator.loadedDrawingData,
            let drawing = try? PKDrawing(data: drawingData)
        else { return }

        context.coordinator.isLoadingDrawing = true
        canvasView.drawing = drawing
        context.coordinator.loadedDrawingData = drawingData
        context.coordinator.isLoadingDrawing = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func applyCurrentTool(
        to canvasView: PKCanvasView,
        coordinator: Coordinator
    ) {
        let selectionMode: Coordinator.SelectionMode = isAISelectionMode ? .aiLens : .none

        coordinator.setSelectionMode(selectionMode, on: canvasView)
        coordinator.setEraserPreviewEnabled(selectedTool == .eraser && !isAISelectionMode)
        coordinator.setTextPlacementEnabled(selectedTool == .text && !isAISelectionMode)
        coordinator.setPhotoPlacementEnabled(selectedTool == .photo && !isAISelectionMode)
        guard !isAISelectionMode else {
            canvasView.isDrawingEnabled = false
            return
        }

        switch selectedTool {
        case .pencil:
            canvasView.isDrawingEnabled = true
            coordinator.applyToolIfNeeded(
                signature: "pencil-\(UIColor(pencilColor).cgColor)-\(pencilWidth)",
                to: canvasView
            ) {
                PKInkingTool(
                    .pen,
                    color: UIColor(pencilColor),
                    width: pencilWidth
                )
            }
        case .highlighter:
            canvasView.isDrawingEnabled = true
            coordinator.applyToolIfNeeded(
                signature: "highlighter-\(UIColor(highlighterColor).cgColor)-\(highlighterWidth)",
                to: canvasView
            ) {
                PKInkingTool(
                    .marker,
                    color: UIColor(highlighterColor).withAlphaComponent(0.55),
                    width: highlighterWidth
                )
            }
        case .eraser:
            canvasView.isDrawingEnabled = false
            coordinator.clearAppliedToolSignature()
        case .selector:
            canvasView.isDrawingEnabled = true
            coordinator.applyToolIfNeeded(
                signature: "selector",
                to: canvasView
            ) {
                PKLassoTool()
            }
        case .text, .photo, .hand:
            canvasView.isDrawingEnabled = false
            coordinator.clearAppliedToolSignature()
        }
    }

    final class PDFDrawingCanvasContainerView: UIView, UIScrollViewDelegate {
        let scrollView = UIScrollView()
        let contentView = UIView()
        let pdfBackgroundView = UIView()
        let canvasView = PKCanvasView()

        private(set) var contentSize = CGSize(width: 1600, height: 2200)
        private var renderedPDFURL: URL?
        private var renderedBlankPageCount = 1
        private var renderedPageStyle: NotePageStyle = .blank
        private var didSetInitialZoom = false
        private var blankPageRects: [CGRect] = []
        private var lastReportedBlankPageIndex: Int?
        private var lastReportedBlankPageRect: CGRect?
        var onVisibleBlankPageChanged: ((Int, CGRect) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .secondarySystemBackground

            scrollView.delegate = self
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.isScrollEnabled = true
            scrollView.alwaysBounceVertical = true
            scrollView.alwaysBounceHorizontal = true
            scrollView.minimumZoomScale = 0.2
            scrollView.maximumZoomScale = 4
            scrollView.bouncesZoom = false
            scrollView.showsVerticalScrollIndicator = true
            scrollView.showsHorizontalScrollIndicator = false
#if !targetEnvironment(simulator)
            let fingerTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            scrollView.panGestureRecognizer.allowedTouchTypes = fingerTouchTypes
            scrollView.pinchGestureRecognizer?.allowedTouchTypes = fingerTouchTypes
#endif

            pdfBackgroundView.isUserInteractionEnabled = false
            canvasView.backgroundColor = .clear
            canvasView.isOpaque = false

            addSubview(scrollView)
            scrollView.addSubview(contentView)
            contentView.addSubview(pdfBackgroundView)
            contentView.addSubview(canvasView)

            configureBlankPages(count: 1, pageStyle: .blank)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            scrollView.frame = bounds
            if contentView.frame == .zero {
                applyContentSize(contentSize)
            }
            updateZoomIfNeeded()
            updateCenteredContentInset()
            reportVisibleBlankPageIfNeeded()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            contentView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            updateCenteredContentInset()
            reportVisibleBlankPageIfNeeded()
            debugLogScrollState("did zoom")
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            reportVisibleBlankPageIfNeeded()
        }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            debugLogScrollState("will begin zoom")
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            debugLogScrollState("did end zoom scale=\(formatted(scale))")
        }

        func setAllowsPencilScrolling(_ allowsPencilScrolling: Bool) {
#if !targetEnvironment(simulator)
            let touchTypes: [NSNumber] = allowsPencilScrolling
                ? [
                    NSNumber(value: UITouch.TouchType.direct.rawValue),
                    NSNumber(value: UITouch.TouchType.pencil.rawValue)
                ]
                : [NSNumber(value: UITouch.TouchType.direct.rawValue)]

            guard scrollView.panGestureRecognizer.allowedTouchTypes != touchTypes else { return }
            scrollView.panGestureRecognizer.allowedTouchTypes = touchTypes
#endif
        }

        func configureBackground(url: URL?, blankPageCount: Int, pageStyle: NotePageStyle) {
            let pageCount = max(blankPageCount, 1)
            guard renderedPDFURL != url || renderedBlankPageCount != pageCount || renderedPageStyle != pageStyle else { return }
            let isChangingDocument = renderedPDFURL != url
            renderedPDFURL = url
            renderedBlankPageCount = pageCount
            renderedPageStyle = pageStyle
            if isChangingDocument {
                didSetInitialZoom = false
            }
            pdfBackgroundView.subviews.forEach { $0.removeFromSuperview() }

            guard let url, let document = PDFDocument(url: url), document.pageCount > 0 else {
                configureBlankPages(count: pageCount, pageStyle: pageStyle)
                return
            }

            blankPageRects = []
            lastReportedBlankPageIndex = nil
            lastReportedBlankPageRect = nil
            backgroundColor = .secondarySystemBackground
            let pageWidth = preferredPageWidth()
            let pageSpacing: CGFloat = 40
            var yOffset: CGFloat = 0

            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex) else { continue }
                let pageBounds = page.bounds(for: .mediaBox)
                let aspectRatio = pageBounds.height / max(pageBounds.width, 1)
                let pageSize = CGSize(width: pageWidth, height: pageWidth * aspectRatio)
                let pageView = UIImageView(image: render(page: page, size: pageSize))

                pageView.contentMode = .scaleAspectFit
                pageView.backgroundColor = .white
                pageView.frame = CGRect(x: 0, y: yOffset, width: pageSize.width, height: pageSize.height)
                pageView.layer.shadowColor = UIColor.black.cgColor
                pageView.layer.shadowOpacity = 0.08
                pageView.layer.shadowRadius = 10
                pageView.layer.shadowOffset = CGSize(width: 0, height: 4)
                pdfBackgroundView.addSubview(pageView)

                yOffset += pageSize.height + pageSpacing
            }

            applyContentSize(CGSize(width: pageWidth, height: max(yOffset - pageSpacing, 2200)))
            setNeedsLayout()
        }

        private func configureBlankPages(count: Int, pageStyle: NotePageStyle) {
            let pageWidth = preferredPageWidth()
            let pageHeight = pageWidth * 1.375
            let pageSpacing: CGFloat = 40
            var yOffset: CGFloat = 0
            blankPageRects = []

            for _ in 0..<max(count, 1) {
                let pageFrame = CGRect(
                    x: 0,
                    y: yOffset,
                    width: pageWidth,
                    height: pageHeight
                )
                let pageView = NotePageBackgroundView(frame: pageFrame)
                pageView.pageStyle = pageStyle
                pageView.layer.shadowColor = UIColor.black.cgColor
                pageView.layer.shadowOpacity = 0.08
                pageView.layer.shadowRadius = 10
                pageView.layer.shadowOffset = CGSize(width: 0, height: 4)
                pdfBackgroundView.addSubview(pageView)
                blankPageRects.append(pageFrame)

                yOffset += pageHeight + pageSpacing
            }

            applyContentSize(CGSize(width: pageWidth, height: yOffset - pageSpacing))
            reportVisibleBlankPageIfNeeded(force: true)
        }

        private func preferredPageWidth() -> CGFloat {
            let visibleWidth = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width
            return max(visibleWidth, 820)
        }

        private func applyContentSize(_ size: CGSize) {
            contentSize = size
            scrollView.contentSize = size
            contentView.frame = CGRect(origin: .zero, size: size)
            pdfBackgroundView.frame = contentView.bounds
            canvasView.frame = contentView.bounds
            canvasView.bounds = CGRect(origin: .zero, size: size)
            canvasView.contentSize = size
            canvasView.contentInset = .zero
            canvasView.scrollIndicatorInsets = .zero
            canvasView.contentOffset = .zero
            canvasView.zoomScale = 1
            updateCenteredContentInset()
        }

        private func updateZoomIfNeeded() {
            guard bounds.width > 0, !didSetInitialZoom else { return }
            let widthScale = bounds.width / max(contentSize.width, 1)
            let minimumScale = min(0.2, widthScale)
            scrollView.minimumZoomScale = minimumScale
            let initialZoom = min(max(widthScale, minimumScale), scrollView.maximumZoomScale)
            scrollView.zoomScale = initialZoom
            didSetInitialZoom = true
            updateCenteredContentInset()
        }

        private func updateCenteredContentInset() {
            let scaledWidth = contentSize.width * scrollView.zoomScale
            let horizontalInset = max((scrollView.bounds.width - scaledWidth) / 2, 0)
            let inset = UIEdgeInsets(
                top: 0,
                left: horizontalInset,
                bottom: 0,
                right: horizontalInset
            )

            guard !insetsAreNearlyEqual(scrollView.contentInset, inset) else { return }
            scrollView.contentInset = inset
        }

        private func insetsAreNearlyEqual(_ first: UIEdgeInsets, _ second: UIEdgeInsets) -> Bool {
            let tolerance: CGFloat = 0.5
            return abs(first.top - second.top) < tolerance
                && abs(first.left - second.left) < tolerance
                && abs(first.bottom - second.bottom) < tolerance
                && abs(first.right - second.right) < tolerance
        }

        private func reportVisibleBlankPageIfNeeded(force: Bool = false) {
            guard !blankPageRects.isEmpty else { return }

            let viewportCenter = CGPoint(x: scrollView.bounds.midX, y: scrollView.bounds.midY)
            let contentPoint = contentView.convert(viewportCenter, from: scrollView)
            let nearestPage = blankPageRects.enumerated().min { first, second in
                abs(first.element.midY - contentPoint.y) < abs(second.element.midY - contentPoint.y)
            }
            guard let nearestPage else { return }

            let hasMaterialRectChange = lastReportedBlankPageRect.map {
                !rectsAreNearlyEqual($0, nearestPage.element)
            } ?? true

            if force || nearestPage.offset != lastReportedBlankPageIndex || hasMaterialRectChange {
                lastReportedBlankPageIndex = nearestPage.offset
                lastReportedBlankPageRect = nearestPage.element
                onVisibleBlankPageChanged?(nearestPage.offset, nearestPage.element)
            }
        }

        private func rectsAreNearlyEqual(_ first: CGRect, _ second: CGRect) -> Bool {
            let tolerance: CGFloat = 0.5
            return abs(first.origin.x - second.origin.x) < tolerance
                && abs(first.origin.y - second.origin.y) < tolerance
                && abs(first.size.width - second.size.width) < tolerance
                && abs(first.size.height - second.size.height) < tolerance
        }

        private func render(page: PDFPage, size: CGSize) -> UIImage {
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                context.cgContext.saveGState()
                context.cgContext.translateBy(x: 0, y: size.height)
                context.cgContext.scaleBy(x: 1, y: -1)

                let pageBounds = page.bounds(for: .mediaBox)
                let scale = min(size.width / max(pageBounds.width, 1), size.height / max(pageBounds.height, 1))
                context.cgContext.scaleBy(x: scale, y: scale)
                context.cgContext.translateBy(x: -pageBounds.minX, y: -pageBounds.minY)
                page.draw(with: .mediaBox, to: context.cgContext)
                context.cgContext.restoreGState()
            }
        }

        private func debugLogScrollState(_ label: String) {
            print(
                """
                [BetterNotes:Scroll] \(label)
                  outer zoom=\(formatted(scrollView.zoomScale)) offset=\(formatted(scrollView.contentOffset)) inset=\(formatted(scrollView.contentInset)) contentSize=\(formatted(scrollView.contentSize))
                  content frame=\(formatted(contentView.frame)) bounds=\(formatted(contentView.bounds)) transform=\(contentView.transform)
                  canvas frame=\(formatted(canvasView.frame)) bounds=\(formatted(canvasView.bounds))
                """
            )
        }

        private func formatted(_ point: CGPoint) -> String {
            "(\(formatted(point.x)), \(formatted(point.y)))"
        }

        private func formatted(_ size: CGSize) -> String {
            "(\(formatted(size.width)) x \(formatted(size.height)))"
        }

        private func formatted(_ rect: CGRect) -> String {
            "(x:\(formatted(rect.origin.x)) y:\(formatted(rect.origin.y)) w:\(formatted(rect.size.width)) h:\(formatted(rect.size.height)))"
        }

        private func formatted(_ inset: UIEdgeInsets) -> String {
            "(t:\(formatted(inset.top)) l:\(formatted(inset.left)) b:\(formatted(inset.bottom)) r:\(formatted(inset.right)))"
        }

        private func formatted(_ value: CGFloat) -> String {
            value.isFinite ? String(format: "%.3f", Double(value)) : "nonfinite"
        }
    }

    final class CanvasTextBoxView: UIView, UITextViewDelegate {
        let id: UUID
        private let textView = UITextView()
        private let resizeHandle = UIView()
        private let deleteButton = UIButton(type: .system)
        private var dragStartCenter = CGPoint.zero
        private var resizeStartFrame = CGRect.zero
        private var resizeStartPoint = CGPoint.zero
        var onChange: ((NoteTextBox) -> Void)?
        var onDelete: ((UUID) -> Void)?
        var isEditingText: Bool {
            textView.isFirstResponder
        }

        init(textBox: NoteTextBox) {
            id = textBox.id
            super.init(frame: textBox.frame)
            configure(text: textBox.text, fontSize: textBox.fontSize)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func update(with textBox: NoteTextBox) {
            if frame != textBox.frame {
                frame = textBox.frame
            }
            if textView.text != textBox.text {
                textView.text = textBox.text
            }
            if textView.font?.pointSize != textBox.fontSize {
                textView.font = .systemFont(ofSize: textBox.fontSize)
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            textView.frame = bounds.insetBy(dx: 8, dy: 6)
            resizeHandle.frame = CGRect(
                x: bounds.maxX - 18,
                y: bounds.maxY - 18,
                width: 18,
                height: 18
            )
            deleteButton.frame = CGRect(
                x: bounds.maxX - 28,
                y: 0,
                width: 28,
                height: 28
            )
        }

        func focus() {
            textView.isUserInteractionEnabled = true
            setSelected(true)
            textView.becomeFirstResponder()
        }

        func finishEditing() {
            textView.resignFirstResponder()
            textView.isUserInteractionEnabled = false
            setSelected(false)
            publishChange()
        }

        func applyFontSize(_ fontSize: CGFloat) {
            guard textView.font?.pointSize != fontSize else { return }
            textView.font = .systemFont(ofSize: fontSize)
            publishChange()
        }

        private func configure(text: String, fontSize: CGFloat) {
            backgroundColor = UIColor.systemBackground.withAlphaComponent(0.92)
            layer.borderColor = UIColor.systemBlue.cgColor
            layer.borderWidth = 1.5
            layer.cornerRadius = 7
            clipsToBounds = true

            textView.text = text
            textView.backgroundColor = .clear
            textView.font = .systemFont(ofSize: fontSize)
            textView.textColor = .label
            textView.delegate = self
            textView.isScrollEnabled = false
            textView.isUserInteractionEnabled = false
            textView.textContainerInset = .zero
            textView.textContainer.lineFragmentPadding = 0
            addSubview(textView)

            resizeHandle.backgroundColor = .systemBlue
            resizeHandle.layer.cornerRadius = 5
            resizeHandle.layer.maskedCorners = [.layerMinXMinYCorner]
            addSubview(resizeHandle)

            deleteButton.setImage(UIImage(systemName: "trash.fill"), for: .normal)
            deleteButton.tintColor = .white
            deleteButton.backgroundColor = .systemBlue
            deleteButton.layer.cornerRadius = 8
            deleteButton.layer.maskedCorners = [.layerMinXMaxYCorner]
            deleteButton.addTarget(self, action: #selector(handleDeleteTap), for: .touchUpInside)
            addSubview(deleteButton)

            let moveGesture = UIPanGestureRecognizer(target: self, action: #selector(handleMove(_:)))
            addGestureRecognizer(moveGesture)

            let editGesture = UITapGestureRecognizer(target: self, action: #selector(handleEditTap(_:)))
            addGestureRecognizer(editGesture)

            let resizeGesture = UIPanGestureRecognizer(target: self, action: #selector(handleResize(_:)))
            resizeHandle.addGestureRecognizer(resizeGesture)

            setSelected(false)
        }

        func textViewDidChange(_ textView: UITextView) {
            publishChange()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            textView.isUserInteractionEnabled = false
            setSelected(false)
            publishChange()
        }

        @objc private func handleEditTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            focus()
        }

        @objc private func handleDeleteTap() {
            onDelete?(id)
        }

        @objc private func handleMove(_ gesture: UIPanGestureRecognizer) {
            guard gesture.view === self else { return }

            switch gesture.state {
            case .began:
                setSelected(true)
                dragStartCenter = center
            case .changed:
                let translation = gesture.translation(in: superview)
                center = CGPoint(
                    x: dragStartCenter.x + translation.x,
                    y: dragStartCenter.y + translation.y
                )
                publishChange()
            default:
                publishChange()
            }
        }

        @objc private func handleResize(_ gesture: UIPanGestureRecognizer) {
            guard let superview else { return }
            let point = gesture.location(in: superview)

            switch gesture.state {
            case .began:
                setSelected(true)
                resizeStartFrame = frame
                resizeStartPoint = point
            case .changed:
                let width = max(120, resizeStartFrame.width + point.x - resizeStartPoint.x)
                let height = max(44, resizeStartFrame.height + point.y - resizeStartPoint.y)
                frame = CGRect(
                    x: resizeStartFrame.minX,
                    y: resizeStartFrame.minY,
                    width: width,
                    height: height
                )
                publishChange()
            default:
                publishChange()
            }
        }

        private func publishChange() {
            onChange?(
                NoteTextBox(
                    id: id,
                    text: textView.text ?? "",
                    frame: frame,
                    fontSize: textView.font?.pointSize ?? 20
                )
            )
        }

        func setSelected(_ selected: Bool) {
            layer.borderColor = UIColor.systemBlue.cgColor
            layer.borderWidth = selected ? 1.5 : 0
            resizeHandle.isHidden = !selected
            deleteButton.isHidden = !selected
        }
    }

    final class CanvasImageBoxView: UIView {
        let id: UUID
        private let imageView = UIImageView()
        private let resizeHandle = UIView()
        private let deleteButton = UIButton(type: .system)
        private var imageData: Data
        private var dragStartCenter = CGPoint.zero
        private var resizeStartFrame = CGRect.zero
        private var resizeStartPoint = CGPoint.zero
        var onChange: ((NoteImageBox) -> Void)?
        var onDelete: ((UUID) -> Void)?

        init(imageBox: NoteImageBox) {
            id = imageBox.id
            imageData = imageBox.imageData
            super.init(frame: imageBox.frame)
            configure()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func update(with imageBox: NoteImageBox) {
            if frame != imageBox.frame {
                frame = imageBox.frame
            }
            if imageData != imageBox.imageData {
                imageData = imageBox.imageData
                imageView.image = UIImage(data: imageBox.imageData)
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            imageView.frame = bounds
            resizeHandle.frame = CGRect(
                x: bounds.maxX - 18,
                y: bounds.maxY - 18,
                width: 18,
                height: 18
            )
            deleteButton.frame = CGRect(
                x: bounds.maxX - 28,
                y: 0,
                width: 28,
                height: 28
            )
        }

        func setSelected(_ selected: Bool) {
            layer.borderColor = UIColor.systemBlue.cgColor
            layer.borderWidth = selected ? 1.5 : 0
            resizeHandle.isHidden = !selected
            deleteButton.isHidden = !selected
        }

        private func configure() {
            backgroundColor = .clear
            layer.cornerRadius = 7
            clipsToBounds = true

            imageView.image = UIImage(data: imageData)
            imageView.contentMode = .scaleAspectFit
            imageView.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.35)
            addSubview(imageView)

            resizeHandle.backgroundColor = .systemBlue
            resizeHandle.layer.cornerRadius = 5
            resizeHandle.layer.maskedCorners = [.layerMinXMinYCorner]
            addSubview(resizeHandle)

            deleteButton.setImage(UIImage(systemName: "trash.fill"), for: .normal)
            deleteButton.tintColor = .white
            deleteButton.backgroundColor = .systemBlue
            deleteButton.layer.cornerRadius = 8
            deleteButton.layer.maskedCorners = [.layerMinXMaxYCorner]
            deleteButton.addTarget(self, action: #selector(handleDeleteTap), for: .touchUpInside)
            addSubview(deleteButton)

            let moveGesture = UIPanGestureRecognizer(target: self, action: #selector(handleMove(_:)))
            addGestureRecognizer(moveGesture)

            let selectGesture = UITapGestureRecognizer(target: self, action: #selector(handleSelectTap(_:)))
            addGestureRecognizer(selectGesture)

            let resizeGesture = UIPanGestureRecognizer(target: self, action: #selector(handleResize(_:)))
            resizeHandle.addGestureRecognizer(resizeGesture)

            setSelected(false)
        }

        @objc private func handleSelectTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            setSelected(true)
        }

        @objc private func handleDeleteTap() {
            onDelete?(id)
        }

        @objc private func handleMove(_ gesture: UIPanGestureRecognizer) {
            guard gesture.view === self else { return }

            switch gesture.state {
            case .began:
                setSelected(true)
                dragStartCenter = center
            case .changed:
                let translation = gesture.translation(in: superview)
                center = CGPoint(
                    x: dragStartCenter.x + translation.x,
                    y: dragStartCenter.y + translation.y
                )
                publishChange()
            default:
                publishChange()
            }
        }

        @objc private func handleResize(_ gesture: UIPanGestureRecognizer) {
            guard let superview else { return }
            let point = gesture.location(in: superview)

            switch gesture.state {
            case .began:
                setSelected(true)
                resizeStartFrame = frame
                resizeStartPoint = point
            case .changed:
                let width = max(80, resizeStartFrame.width + point.x - resizeStartPoint.x)
                let height = max(80, resizeStartFrame.height + point.y - resizeStartPoint.y)
                frame = CGRect(
                    x: resizeStartFrame.minX,
                    y: resizeStartFrame.minY,
                    width: width,
                    height: height
                )
                publishChange()
            default:
                publishChange()
            }
        }

        private func publishChange() {
            onChange?(
                NoteImageBox(
                    id: id,
                    imageData: imageData,
                    frame: frame
                )
            )
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
        enum SelectionMode {
            case none
            case aiLens
            case toolbarLasso
        }

        var onDrawingChanged: ((Data) -> Void)?
        var onTextBoxesChanged: (([NoteTextBox]) -> Void)?
        var onImageBoxesChanged: (([NoteImageBox]) -> Void)?
        var onPhotoPlacementRequested: ((CGPoint) -> Void)?
        var onAISelectionChanged: ((CGRect?, Data?) -> Void)?
        var onBlankPageExtensionNeeded: (() -> Void)?
        var loadedDrawingData: Data?
        var blankPageCount = 1
        var isBlankNotebook = false
        var isLoadingDrawing = false
        private(set) var isUsingTool = false
        private var pendingDrawingData: Data?
        private weak var canvasView: PKCanvasView?
        private var selectionGesture: UIPanGestureRecognizer?
        private var eraserPreviewGesture: UIPanGestureRecognizer?
        private var textPlacementGesture: UITapGestureRecognizer?
        private var photoPlacementGesture: UITapGestureRecognizer?
        private let selectionLayer = CAShapeLayer()
        private let eraserFadeLayer = CAShapeLayer()
        private let eraserPreviewLayer = CAShapeLayer()
        private var displayPoints: [CGPoint] = []
        private var contentPoints: [CGPoint] = []
        private var lassoSelectedStrokeIndexes = Set<Int>()
        private var lassoSelectionPath: UIBezierPath?
        private var lassoMoveBaseDrawing: PKDrawing?
        private var lassoMoveStartPoint: CGPoint?
        private var isMovingLassoSelection = false
        private var isPreviewingLassoMove = false
        private var eraserPathPoints: [CGPoint] = []
        private var eraserBaseDrawing: PKDrawing?
        private var eraserHitStrokeIndexes = Set<Int>()
        private weak var lockedScrollView: UIScrollView?
        private var lockedScrollViewWasScrollEnabled = true
        private var lockedScrollViewPanWasEnabled = true
        private var lockedScrollViewPinchWasEnabled = true
        private weak var eraserLockedScrollView: UIScrollView?
        private var eraserLockedScrollViewPinchWasEnabled = true
        private var selectionMode: SelectionMode = .none
        private var isEraserPreviewEnabled = false
        private var isTextPlacementEnabled = false
        private var isPhotoPlacementEnabled = false
        private var appliedToolSignature: String?
        private var lastExtendedPageCount: Int?
        private var handledUndoRequest = 0
        private var handledRedoRequest = 0
        private let toolbarAccentColor = UIColor(Color.accentColor)
        private var currentTextBoxes: [NoteTextBox] = []
        private var currentImageBoxes: [NoteImageBox] = []
        var currentTextFontSize: CGFloat = 20

        func applyToolIfNeeded(
            signature: String,
            to canvasView: PKCanvasView,
            makeTool: () -> PKTool
        ) {
            guard appliedToolSignature != signature else { return }
            canvasView.tool = makeTool()
            appliedToolSignature = signature
        }

        func clearAppliedToolSignature() {
            appliedToolSignature = nil
        }

        func configureSelectionGesture(on canvasView: PKCanvasView) {
            guard selectionGesture == nil else { return }
            self.canvasView = canvasView

            selectionLayer.fillColor = nil
            selectionLayer.strokeColor = toolbarAccentColor.cgColor
            selectionLayer.lineWidth = 3
            selectionLayer.lineDashPattern = [8, 6]
            selectionLayer.lineCap = .round
            selectionLayer.lineJoin = .round
            selectionLayer.shadowColor = toolbarAccentColor.cgColor
            selectionLayer.shadowOpacity = 0
            selectionLayer.shadowRadius = 0
            selectionLayer.shadowOffset = .zero
            canvasView.layer.addSublayer(selectionLayer)

            let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleSelection(_:)))
            gesture.delegate = self
            gesture.maximumNumberOfTouches = 1
            gesture.cancelsTouchesInView = true
            gesture.isEnabled = false
            canvasView.addGestureRecognizer(gesture)
            selectionGesture = gesture
        }

        func configureEraserPreviewGesture(on canvasView: PKCanvasView) {
            guard eraserPreviewGesture == nil else { return }

            eraserFadeLayer.fillColor = nil
            eraserFadeLayer.strokeColor = UIColor.systemGray.withAlphaComponent(0.5).cgColor
            eraserFadeLayer.lineWidth = 12
            eraserFadeLayer.lineCap = .round
            eraserFadeLayer.lineJoin = .round
            eraserFadeLayer.isHidden = true
            canvasView.layer.addSublayer(eraserFadeLayer)

            eraserPreviewLayer.fillColor = UIColor.systemGray.withAlphaComponent(0.2).cgColor
            eraserPreviewLayer.strokeColor = UIColor.systemGray.withAlphaComponent(0.7).cgColor
            eraserPreviewLayer.lineWidth = 2
            eraserPreviewLayer.isHidden = true
            canvasView.layer.addSublayer(eraserPreviewLayer)

            let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleEraserPreview(_:)))
            gesture.delegate = self
            gesture.maximumNumberOfTouches = 1
            gesture.cancelsTouchesInView = true
#if !targetEnvironment(simulator)
            gesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
#endif
            gesture.isEnabled = false
            canvasView.addGestureRecognizer(gesture)
            eraserPreviewGesture = gesture
        }

        func configureTextPlacementGesture(on canvasView: PKCanvasView) {
            guard textPlacementGesture == nil else { return }
            self.canvasView = canvasView

            let gesture = UITapGestureRecognizer(target: self, action: #selector(handleTextPlacement(_:)))
            gesture.delegate = self
            gesture.numberOfTapsRequired = 1
            gesture.cancelsTouchesInView = false
            gesture.isEnabled = false
            canvasView.addGestureRecognizer(gesture)
            textPlacementGesture = gesture
        }

        func configurePhotoPlacementGesture(on canvasView: PKCanvasView) {
            guard photoPlacementGesture == nil else { return }
            self.canvasView = canvasView

            let gesture = UITapGestureRecognizer(target: self, action: #selector(handlePhotoPlacement(_:)))
            gesture.delegate = self
            gesture.numberOfTapsRequired = 1
            gesture.cancelsTouchesInView = false
            gesture.isEnabled = false
            canvasView.addGestureRecognizer(gesture)
            photoPlacementGesture = gesture
        }

        func setSelectionMode(_ mode: SelectionMode, on canvasView: PKCanvasView) {
            guard mode != selectionMode else { return }
            selectionMode = mode
            let enabled = mode != .none
            selectionGesture?.isEnabled = enabled
            canvasView.panGestureRecognizer.isEnabled = !enabled

            if !enabled {
                clearSelection()
            } else {
                clearSelection()
                if mode == .aiLens {
                    onAISelectionChanged?(nil, nil)
                }
            }
        }

        func setEraserPreviewEnabled(_ enabled: Bool) {
            guard enabled != isEraserPreviewEnabled else { return }
            isEraserPreviewEnabled = enabled
            eraserPreviewGesture?.isEnabled = enabled
            debugLogEraser("set enabled=\(enabled)")

            if enabled, let canvasView {
                lockPageZoomDuringEraser(for: canvasView)
            }

            if !enabled {
                eraserPreviewLayer.isHidden = true
                eraserPreviewLayer.path = nil
                eraserFadeLayer.isHidden = true
                eraserFadeLayer.path = nil
                eraserPathPoints.removeAll()
                eraserBaseDrawing = nil
                eraserHitStrokeIndexes.removeAll()
                unlockPageZoomAfterEraser()
            }
        }

        func setTextPlacementEnabled(_ enabled: Bool) {
            guard enabled != isTextPlacementEnabled else { return }
            isTextPlacementEnabled = enabled
            textPlacementGesture?.isEnabled = enabled
            if !enabled, let canvasView {
                let finishedEditing = finishEditingTextBoxes(on: canvasView)
                deselectTextBoxes(on: canvasView)
                if finishedEditing {
                    publishTextBoxes()
                }
            }
        }

        func setPhotoPlacementEnabled(_ enabled: Bool) {
            guard enabled != isPhotoPlacementEnabled else { return }
            isPhotoPlacementEnabled = enabled
            photoPlacementGesture?.isEnabled = enabled
            if !enabled, let canvasView {
                deselectImageBoxes(on: canvasView)
            }
        }

        func syncTextBoxes(_ textBoxes: [NoteTextBox], on canvasView: PKCanvasView) {
            guard textBoxes != currentTextBoxes else { return }
            currentTextBoxes = textBoxes

            let existingViews = canvasView.subviews.compactMap { $0 as? CanvasTextBoxView }
            let incomingIDs = Set(textBoxes.map(\.id))

            for view in existingViews where !incomingIDs.contains(view.id) {
                view.removeFromSuperview()
            }

            for textBox in textBoxes {
                if let view = existingViews.first(where: { $0.id == textBox.id }) {
                    view.update(with: textBox)
                    configureTextBoxCallback(view)
                } else {
                    let view = CanvasTextBoxView(textBox: textBox)
                    configureTextBoxCallback(view)
                    canvasView.addSubview(view)
                }
            }
        }

        func syncImageBoxes(_ imageBoxes: [NoteImageBox], on canvasView: PKCanvasView) {
            guard imageBoxes != currentImageBoxes else { return }
            currentImageBoxes = imageBoxes

            let existingViews = canvasView.subviews.compactMap { $0 as? CanvasImageBoxView }
            let incomingIDs = Set(imageBoxes.map(\.id))

            for view in existingViews where !incomingIDs.contains(view.id) {
                view.removeFromSuperview()
            }

            for imageBox in imageBoxes {
                if let view = existingViews.first(where: { $0.id == imageBox.id }) {
                    view.update(with: imageBox)
                    configureImageBoxCallback(view)
                } else {
                    let view = CanvasImageBoxView(imageBox: imageBox)
                    configureImageBoxCallback(view)
                    canvasView.addSubview(view)
                }
            }
        }

        func applyTextFontSizeToEditingBoxes(_ fontSize: CGFloat, on canvasView: PKCanvasView) {
            canvasView.subviews
                .compactMap { $0 as? CanvasTextBoxView }
                .filter(\.isEditingText)
                .forEach { $0.applyFontSize(fontSize) }
        }

        func handleUndoRedo(undoRequest: Int, redoRequest: Int, canvasView: PKCanvasView) {
            if undoRequest != handledUndoRequest {
                handledUndoRequest = undoRequest
                canvasView.becomeFirstResponder()
                canvasView.undoManager?.undo()
                publishDrawing(from: canvasView)
            }

            if redoRequest != handledRedoRequest {
                handledRedoRequest = redoRequest
                canvasView.becomeFirstResponder()
                canvasView.undoManager?.redo()
                publishDrawing(from: canvasView)
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === selectionGesture {
                return selectionMode != .none
            }

            if gestureRecognizer === eraserPreviewGesture {
                debugLogEraser("should begin enabled=\(isEraserPreviewEnabled)")
                return isEraserPreviewEnabled
            }

            if gestureRecognizer === textPlacementGesture {
                return textPlacementGesture?.isEnabled == true
            }

            if gestureRecognizer === photoPlacementGesture {
                return photoPlacementGesture?.isEnabled == true
            }

            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if gestureRecognizer === textPlacementGesture || gestureRecognizer === photoPlacementGesture {
                var view = touch.view
                while let candidate = view {
                    if candidate is CanvasTextBoxView || candidate is CanvasImageBoxView {
                        return false
                    }
                    view = candidate.superview
                }
            }

            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            if gestureRecognizer === eraserPreviewGesture || otherGestureRecognizer === eraserPreviewGesture {
                return false
            }

            return true
        }

        @objc private func handleTextPlacement(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let canvasView else { return }

            if finishEditingTextBoxes(on: canvasView) {
                publishTextBoxes()
                return
            }

            let point = gesture.location(in: canvasView)
            let frame = CGRect(
                x: point.x,
                y: point.y,
                width: 220,
                height: 72
            )
            let textBox = NoteTextBox(text: "", frame: frame, fontSize: currentTextFontSize)
            currentTextBoxes.append(textBox)

            let view = CanvasTextBoxView(textBox: textBox)
            configureTextBoxCallback(view)
            canvasView.addSubview(view)
            view.focus()
            publishTextBoxes()
        }

        @objc private func handlePhotoPlacement(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let canvasView else { return }
            let point = gesture.location(in: canvasView)
            onPhotoPlacementRequested?(point)
        }

        private func finishEditingTextBoxes(on canvasView: PKCanvasView) -> Bool {
            let textBoxViews = canvasView.subviews.compactMap { $0 as? CanvasTextBoxView }
            let editingViews = textBoxViews.filter(\.isEditingText)
            guard !editingViews.isEmpty else { return false }

            editingViews.forEach { $0.finishEditing() }
            return true
        }

        private func deselectTextBoxes(on canvasView: PKCanvasView) {
            canvasView.subviews
                .compactMap { $0 as? CanvasTextBoxView }
                .forEach { $0.setSelected(false) }
        }

        private func deselectImageBoxes(on canvasView: PKCanvasView) {
            canvasView.subviews
                .compactMap { $0 as? CanvasImageBoxView }
                .forEach { $0.setSelected(false) }
        }

        private func configureTextBoxCallback(_ view: CanvasTextBoxView) {
            view.onChange = { [weak self] updatedTextBox in
                guard let self else { return }
                if let index = currentTextBoxes.firstIndex(where: { $0.id == updatedTextBox.id }) {
                    currentTextBoxes[index] = updatedTextBox
                } else {
                    currentTextBoxes.append(updatedTextBox)
                }
                publishTextBoxes()
            }
            view.onDelete = { [weak self, weak view] id in
                guard let self else { return }
                currentTextBoxes.removeAll { $0.id == id }
                view?.removeFromSuperview()
                publishTextBoxes()
            }
        }

        private func configureImageBoxCallback(_ view: CanvasImageBoxView) {
            view.onChange = { [weak self] updatedImageBox in
                guard let self else { return }
                if let index = currentImageBoxes.firstIndex(where: { $0.id == updatedImageBox.id }) {
                    currentImageBoxes[index] = updatedImageBox
                } else {
                    currentImageBoxes.append(updatedImageBox)
                }
                onImageBoxesChanged?(currentImageBoxes)
            }
            view.onDelete = { [weak self, weak view] id in
                guard let self else { return }
                currentImageBoxes.removeAll { $0.id == id }
                view?.removeFromSuperview()
                onImageBoxesChanged?(currentImageBoxes)
            }
        }

        private func publishTextBoxes() {
            let nonEmptyOrFocusedBoxes = currentTextBoxes.filter { textBox in
                !textBox.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || canvasView?.subviews
                        .compactMap({ $0 as? CanvasTextBoxView })
                        .contains(where: { $0.id == textBox.id && $0.isEditingText }) == true
            }
            currentTextBoxes = nonEmptyOrFocusedBoxes
            removeDiscardedTextBoxViews()
            onTextBoxesChanged?(currentTextBoxes)
        }

        private func removeDiscardedTextBoxViews() {
            let savedIDs = Set(currentTextBoxes.map(\.id))
            canvasView?.subviews
                .compactMap { $0 as? CanvasTextBoxView }
                .filter { !savedIDs.contains($0.id) }
                .forEach { $0.removeFromSuperview() }
        }

        @objc private func handleSelection(_ gesture: UIPanGestureRecognizer) {
            guard let canvasView else { return }
            let displayPoint = gesture.location(in: canvasView)
            let contentPoint = CGPoint(
                x: (displayPoint.x + canvasView.contentOffset.x) / canvasView.zoomScale,
                y: (displayPoint.y + canvasView.contentOffset.y) / canvasView.zoomScale
            )

            switch gesture.state {
            case .began:
                lockPageScroll(for: canvasView)
                if beginMovingLassoSelectionIfNeeded(from: displayPoint, on: canvasView) {
                    return
                }

                clearSelection()
                displayPoints = [displayPoint]
                contentPoints = [contentPoint]
                updateSelectionPath()
            case .changed:
                if isMovingLassoSelection {
                    moveLassoSelection(to: displayPoint, on: canvasView)
                    return
                }

                displayPoints.append(displayPoint)
                contentPoints.append(contentPoint)
                updateSelectionPath()
            case .ended:
                if isMovingLassoSelection {
                    finishMovingLassoSelection(on: canvasView)
                    unlockPageScroll()
                    return
                }

                displayPoints.append(displayPoints.first ?? displayPoint)
                contentPoints.append(contentPoints.first ?? contentPoint)
                updateSelectionPath(closed: true)
                animateSelectionCapture()
                if selectionMode == .aiLens {
                    publishSelection(in: canvasView)
                } else if selectionMode == .toolbarLasso {
                    selectLassoStrokes(in: canvasView)
                }
                unlockPageScroll()
            case .cancelled, .failed:
                cancelMovingLassoSelection(on: canvasView)
                clearSelection()
                if selectionMode == .aiLens {
                    onAISelectionChanged?(nil, nil)
                }
                unlockPageScroll()
            default:
                break
            }
        }

        private func beginMovingLassoSelectionIfNeeded(
            from point: CGPoint,
            on canvasView: PKCanvasView
        ) -> Bool {
            guard
                selectionMode == .toolbarLasso,
                !lassoSelectedStrokeIndexes.isEmpty,
                let selectionBounds = lassoSelectionPath?.bounds.insetBy(dx: -28, dy: -28),
                selectionBounds.contains(point)
            else { return false }

            isMovingLassoSelection = true
            lassoMoveBaseDrawing = canvasView.drawing
            lassoMoveStartPoint = point
            return true
        }

        private func moveLassoSelection(to point: CGPoint, on canvasView: PKCanvasView) {
            guard
                let lassoMoveBaseDrawing,
                let lassoMoveStartPoint
            else { return }

            let translation = CGSize(
                width: point.x - lassoMoveStartPoint.x,
                height: point.y - lassoMoveStartPoint.y
            )
            let movedStrokes = lassoMoveBaseDrawing.strokes.enumerated().map { index, stroke in
                lassoSelectedStrokeIndexes.contains(index)
                    ? movedStroke(stroke, translation: translation)
                    : stroke
            }

            isPreviewingLassoMove = true
            canvasView.drawing = PKDrawing(strokes: movedStrokes)
            isPreviewingLassoMove = false
            updateSelectionPath(translation: translation)
        }

        private func finishMovingLassoSelection(on canvasView: PKCanvasView) {
            isMovingLassoSelection = false
            lassoMoveBaseDrawing = nil
            lassoMoveStartPoint = nil
            publishDrawing(from: canvasView)
        }

        private func cancelMovingLassoSelection(on canvasView: PKCanvasView) {
            guard isMovingLassoSelection else { return }

            if let lassoMoveBaseDrawing {
                isPreviewingLassoMove = true
                canvasView.drawing = lassoMoveBaseDrawing
                isPreviewingLassoMove = false
            }

            isMovingLassoSelection = false
            lassoMoveBaseDrawing = nil
            lassoMoveStartPoint = nil
            updateSelectionPath()
        }

        @objc private func handleEraserPreview(_ gesture: UIPanGestureRecognizer) {
            guard isEraserPreviewEnabled, let canvasView else { return }
            let point = gesture.location(in: canvasView)
            let radius: CGFloat = 18

            switch gesture.state {
            case .began:
                debugLogEraser(
                    "began point=\(formatted(point)) strokes=\(canvasView.drawing.strokes.count)",
                    canvasView: canvasView
                )
                eraserBaseDrawing = canvasView.drawing
                eraserHitStrokeIndexes.removeAll()
                eraserPathPoints = [point]
                updateEraserPreview(at: point, radius: radius)
                updateEraserFadeOverlay(near: point, radius: radius)
            case .changed:
                eraserPathPoints.append(point)
                updateEraserPreview(at: point, radius: radius)
                updateEraserFadeOverlay(near: point, radius: radius)
                debugLogEraser(
                    "changed point=\(formatted(point)) hits=\(eraserHitStrokeIndexes.count)",
                    canvasView: canvasView
                )
            case .ended:
                debugLogEraser(
                    "ended point=\(formatted(point)) hits=\(eraserHitStrokeIndexes.count)",
                    canvasView: canvasView
                )
                commitEraserChanges(on: canvasView)
                clearEraserPreview()
            case .cancelled, .failed:
                debugLogEraser("cancelled/failed state=\(gesture.state.rawValue)", canvasView: canvasView)
                clearEraserPreview()
            default:
                break
            }
        }

        private func updateEraserPreview(at point: CGPoint, radius: CGFloat) {
            let rect = CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            eraserPreviewLayer.path = UIBezierPath(ovalIn: rect).cgPath
            eraserPreviewLayer.isHidden = false
        }

        private func clearEraserPreview() {
            eraserPreviewLayer.isHidden = true
            eraserPreviewLayer.path = nil
            eraserFadeLayer.isHidden = true
            eraserFadeLayer.path = nil
            eraserPathPoints.removeAll()
            eraserBaseDrawing = nil
            eraserHitStrokeIndexes.removeAll()
        }

        private func updateEraserFadeOverlay(near point: CGPoint, radius: CGFloat) {
            guard let eraserBaseDrawing else { return }
            let previousHitCount = eraserHitStrokeIndexes.count
            addHitStrokes(near: point, in: eraserBaseDrawing, radius: radius)
            if eraserHitStrokeIndexes.count != previousHitCount {
                debugLogEraser("hit count changed \(previousHitCount)->\(eraserHitStrokeIndexes.count)")
            }

            guard !eraserHitStrokeIndexes.isEmpty else {
                eraserFadeLayer.isHidden = true
                eraserFadeLayer.path = nil
                return
            }

            let overlayPath = UIBezierPath()
            for index in eraserHitStrokeIndexes.sorted() {
                guard eraserBaseDrawing.strokes.indices.contains(index) else { continue }
                overlayPath.append(path(for: eraserBaseDrawing.strokes[index]))
            }

            eraserFadeLayer.path = overlayPath.cgPath
            eraserFadeLayer.isHidden = false
        }

        private func commitEraserChanges(on canvasView: PKCanvasView) {
            guard let eraserBaseDrawing else { return }

            if eraserHitStrokeIndexes.isEmpty {
                debugLogEraser(
                    "commit skipped, no hits. strokes=\(eraserBaseDrawing.strokes.count)",
                    canvasView: canvasView
                )
                return
            }

            let remainingStrokes = eraserBaseDrawing.strokes.enumerated().compactMap { index, stroke in
                eraserHitStrokeIndexes.contains(index) ? nil : stroke
            }
            canvasView.drawing = PKDrawing(strokes: remainingStrokes)
            debugLogEraser(
                "commit removed=\(eraserHitStrokeIndexes.count) remaining=\(remainingStrokes.count)",
                canvasView: canvasView
            )
            publishDrawing(from: canvasView)
        }

        private func addHitStrokes(near point: CGPoint, in drawing: PKDrawing, radius: CGFloat) {
            for (index, stroke) in drawing.strokes.enumerated() {
                guard !eraserHitStrokeIndexes.contains(index) else { continue }

                if strokeIntersectsEraserPoint(stroke, point: point, radius: radius) {
                    eraserHitStrokeIndexes.insert(index)
                }
            }
        }

        private func strokeIntersectsEraserPoint(_ stroke: PKStroke, point: CGPoint, radius: CGFloat) -> Bool {
            let hitRadius = radius + max(stroke.renderBounds.width, stroke.renderBounds.height, 1) * 0.01
            let hitRadiusSquared = hitRadius * hitRadius

            for strokePoint in stroke.path {
                let location = strokePoint.location.applying(stroke.transform)
                if squaredDistance(location, point) <= hitRadiusSquared {
                    return true
                }
            }

            return false
        }

        private func debugLogEraser(_ message: String, canvasView: PKCanvasView? = nil) {
            guard isEraserPreviewEnabled || message.hasPrefix("set enabled") else { return }

            if let canvasView {
                print(
                    """
                    [BetterNotes:Eraser] \(message)
                      canvas contentOffset=\(formatted(canvasView.contentOffset)) zoomScale=\(canvasView.zoomScale) contentSize=\(formatted(canvasView.contentSize))
                      canvas frame=\(formatted(canvasView.frame)) bounds=\(formatted(canvasView.bounds))
                      drawing strokes=\(canvasView.drawing.strokes.count) drawingBounds=\(formatted(canvasView.drawing.bounds))
                    """
                )
                debugLogOuterScroll("eraser \(message)", canvasView: canvasView)
            } else {
                print("[BetterNotes:Eraser] \(message)")
            }
        }

        private func debugLogOuterScroll(_ message: String, canvasView: PKCanvasView) {
            guard let outerScrollView = enclosingScrollView(for: canvasView) else {
                print("[BetterNotes:OuterScroll] \(message) no outer scroll view")
                return
            }

            let contentView = canvasView.superview
            print(
                """
                [BetterNotes:OuterScroll] \(message)
                  outer zoom=\(formatted(outerScrollView.zoomScale)) offset=\(formatted(outerScrollView.contentOffset)) inset=\(formatted(outerScrollView.contentInset)) contentSize=\(formatted(outerScrollView.contentSize))
                  content frame=\(formatted(contentView?.frame ?? .zero)) bounds=\(formatted(contentView?.bounds ?? .zero)) transform=\(String(describing: contentView?.transform))
                """
            )
        }

        private func formatted(_ point: CGPoint) -> String {
            "(\(formatted(point.x)), \(formatted(point.y)))"
        }

        private func formatted(_ size: CGSize) -> String {
            "(\(formatted(size.width)) x \(formatted(size.height)))"
        }

        private func formatted(_ rect: CGRect) -> String {
            "(x:\(formatted(rect.origin.x)) y:\(formatted(rect.origin.y)) w:\(formatted(rect.size.width)) h:\(formatted(rect.size.height)))"
        }

        private func formatted(_ inset: UIEdgeInsets) -> String {
            "(t:\(formatted(inset.top)) l:\(formatted(inset.left)) b:\(formatted(inset.bottom)) r:\(formatted(inset.right)))"
        }

        private func formatted(_ value: CGFloat) -> String {
            value.isFinite ? String(format: "%.3f", Double(value)) : "nonfinite"
        }

        private func path(for stroke: PKStroke) -> UIBezierPath {
            let path = UIBezierPath()
            var didMove = false

            for strokePoint in stroke.path {
                let location = strokePoint.location.applying(stroke.transform)

                if didMove {
                    path.addLine(to: location)
                } else {
                    path.move(to: location)
                    didMove = true
                }
            }

            return path
        }

        private func movedStroke(_ stroke: PKStroke, translation: CGSize) -> PKStroke {
            let transform = stroke.transform.translatedBy(
                x: translation.width,
                y: translation.height
            )

            return PKStroke(
                ink: stroke.ink,
                path: stroke.path,
                transform: transform,
                mask: stroke.mask
            )
        }

        private func squaredDistance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
            let x = first.x - second.x
            let y = first.y - second.y
            return x * x + y * y
        }

        private func lockPageScroll(for view: UIView) {
            guard lockedScrollView == nil, let scrollView = enclosingScrollView(for: view) else { return }
            lockedScrollView = scrollView
            lockedScrollViewWasScrollEnabled = scrollView.isScrollEnabled
            lockedScrollViewPanWasEnabled = scrollView.panGestureRecognizer.isEnabled
            lockedScrollViewPinchWasEnabled = scrollView.pinchGestureRecognizer?.isEnabled ?? true
            scrollView.isScrollEnabled = false
            scrollView.panGestureRecognizer.isEnabled = false
            scrollView.pinchGestureRecognizer?.isEnabled = false
        }

        private func unlockPageScroll() {
            guard let lockedScrollView else { return }
            lockedScrollView.isScrollEnabled = lockedScrollViewWasScrollEnabled
            lockedScrollView.panGestureRecognizer.isEnabled = lockedScrollViewPanWasEnabled
            lockedScrollView.pinchGestureRecognizer?.isEnabled = lockedScrollViewPinchWasEnabled
            self.lockedScrollView = nil
        }

        private func lockPageZoomDuringEraser(for view: UIView) {
            guard eraserLockedScrollView == nil, let scrollView = enclosingScrollView(for: view) else { return }
            eraserLockedScrollView = scrollView
            eraserLockedScrollViewPinchWasEnabled = scrollView.pinchGestureRecognizer?.isEnabled ?? true
            scrollView.pinchGestureRecognizer?.isEnabled = false
        }

        private func unlockPageZoomAfterEraser() {
            guard let eraserLockedScrollView else { return }
            eraserLockedScrollView.pinchGestureRecognizer?.isEnabled = eraserLockedScrollViewPinchWasEnabled
            self.eraserLockedScrollView = nil
        }

        private func enclosingScrollView(for view: UIView) -> UIScrollView? {
            var currentView = view.superview

            while let candidate = currentView {
                if let scrollView = candidate as? UIScrollView {
                    return scrollView
                }
                currentView = candidate.superview
            }

            return nil
        }

        private func updateSelectionPath(closed: Bool = false, translation: CGSize = .zero) {
            guard let first = displayPoints.first else {
                selectionLayer.path = nil
                return
            }

            let path = UIBezierPath()
            path.move(to: CGPoint(x: first.x + translation.width, y: first.y + translation.height))
            displayPoints.dropFirst().forEach { point in
                path.addLine(to: CGPoint(x: point.x + translation.width, y: point.y + translation.height))
            }
            if closed {
                path.close()
            }
            selectionLayer.path = path.cgPath
            applySelectionStyle(closed: closed)

            if closed {
                lassoSelectionPath = path
            }
        }

        private func applySelectionStyle(closed: Bool) {
            if closed {
                selectionLayer.fillColor = toolbarAccentColor.withAlphaComponent(0.13).cgColor
                selectionLayer.strokeColor = toolbarAccentColor.cgColor
                selectionLayer.lineWidth = 3.5
                selectionLayer.lineDashPattern = [7, 5]
                selectionLayer.shadowOpacity = 0.28
                selectionLayer.shadowRadius = 8
                selectionLayer.shadowOffset = .zero
            } else {
                selectionLayer.fillColor = nil
                selectionLayer.strokeColor = toolbarAccentColor.withAlphaComponent(0.9).cgColor
                selectionLayer.lineWidth = 3
                selectionLayer.lineDashPattern = [8, 6]
                selectionLayer.shadowOpacity = 0
                selectionLayer.shadowRadius = 0
                selectionLayer.shadowOffset = .zero
            }
        }

        private func animateSelectionCapture() {
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.985
            scale.toValue = 1
            scale.duration = 0.16
            scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
            selectionLayer.add(scale, forKey: "selectionCaptureScale")

            let opacity = CABasicAnimation(keyPath: "fillColor")
            opacity.fromValue = toolbarAccentColor.withAlphaComponent(0.03).cgColor
            opacity.toValue = toolbarAccentColor.withAlphaComponent(0.13).cgColor
            opacity.duration = 0.18
            opacity.timingFunction = CAMediaTimingFunction(name: .easeOut)
            selectionLayer.add(opacity, forKey: "selectionCaptureFill")
        }

        private func selectLassoStrokes(in canvasView: PKCanvasView) {
            guard let lassoSelectionPath, displayPoints.count >= 3 else {
                clearSelection()
                return
            }

            lassoSelectedStrokeIndexes = Set(
                canvasView.drawing.strokes.enumerated().compactMap { index, stroke in
                    strokeIntersectsSelectionPath(stroke, selectionPath: lassoSelectionPath) ? index : nil
                }
            )

            if lassoSelectedStrokeIndexes.isEmpty {
                clearSelection()
            }
        }

        private func strokeIntersectsSelectionPath(
            _ stroke: PKStroke,
            selectionPath: UIBezierPath
        ) -> Bool {
            for strokePoint in stroke.path {
                let location = strokePoint.location.applying(stroke.transform)
                if selectionPath.contains(location) {
                    return true
                }
            }

            return false
        }

        private func publishSelection(in canvasView: PKCanvasView) {
            guard contentPoints.count >= 3 else {
                onAISelectionChanged?(nil, nil)
                return
            }

            let xs = contentPoints.map(\.x)
            let ys = contentPoints.map(\.y)
            guard
                let minX = xs.min(),
                let maxX = xs.max(),
                let minY = ys.min(),
                let maxY = ys.max()
            else { return }

            let pageBounds = CGRect(origin: .zero, size: canvasView.contentSize)
            let selection = CGRect(
                x: minX,
                y: minY,
                width: maxX - minX,
                height: maxY - minY
            )
            .insetBy(dx: -28, dy: -28)
            .intersection(pageBounds)

            guard selection.width >= 20 && selection.height >= 20 else {
                clearSelection()
                onAISelectionChanged?(nil, nil)
                return
            }

            onAISelectionChanged?(selection, canvasView.drawing.dataRepresentation())
        }

        private func clearSelection() {
            displayPoints.removeAll()
            contentPoints.removeAll()
            lassoSelectedStrokeIndexes.removeAll()
            lassoSelectionPath = nil
            lassoMoveBaseDrawing = nil
            lassoMoveStartPoint = nil
            isMovingLassoSelection = false
            selectionLayer.path = nil
            applySelectionStyle(closed: false)
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isLoadingDrawing, !isPreviewingLassoMove else { return }
            let data = canvasView.drawing.dataRepresentation()
            loadedDrawingData = data
            pendingDrawingData = data

            if !isUsingTool {
                publishPendingDrawing()
            }
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            isUsingTool = true
            debugLogOuterScroll("pencil tool began", canvasView: canvasView)
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            isUsingTool = false
            pendingDrawingData = canvasView.drawing.dataRepresentation()
            debugLogOuterScroll("pencil tool ended", canvasView: canvasView)
            publishPendingDrawing()
        }

        private func publishPendingDrawing() {
            guard let pendingDrawingData else { return }
            self.pendingDrawingData = nil
            loadedDrawingData = pendingDrawingData
            onDrawingChanged?(pendingDrawingData)
            if let canvasView {
                requestBlankPageExtensionIfNeeded(for: canvasView)
            }
        }

        private func publishDrawing(from canvasView: PKCanvasView) {
            let data = canvasView.drawing.dataRepresentation()
            loadedDrawingData = data
            pendingDrawingData = nil
            onDrawingChanged?(data)
            requestBlankPageExtensionIfNeeded(for: canvasView)
        }

        private func requestBlankPageExtensionIfNeeded(for canvasView: PKCanvasView) {
            guard
                isBlankNotebook,
                blankPageCount >= 2,
                lastExtendedPageCount != blankPageCount
            else { return }

            let pageSpacing: CGFloat = 40
            let pageHeight = (canvasView.contentSize.height - CGFloat(blankPageCount - 1) * pageSpacing) / CGFloat(blankPageCount)
            let lastPageStartY = CGFloat(blankPageCount - 1) * (pageHeight + pageSpacing)

            guard canvasView.drawing.bounds.maxY >= lastPageStartY + 24 else { return }

            lastExtendedPageCount = blankPageCount
            onBlankPageExtensionNeeded?()
        }
    }
}

struct BlankNotebookCanvasView: UIViewRepresentable {
    let pages: [NotePage]
    let pageStyle: NotePageStyle
    let selectedTool: NoteEditorTool
    let pencilColor: Color
    let pencilWidth: CGFloat
    let highlighterColor: Color
    let highlighterWidth: CGFloat
    let isAISelectionMode: Bool
    let undoRequest: Int
    let redoRequest: Int
    let textBoxes: [NoteTextBox]
    let textFontSize: CGFloat
    let imageBoxes: [NoteImageBox]
    let onPageDrawingChanged: (Data, UUID) -> Void
    let onTextBoxesChanged: ([NoteTextBox]) -> Void
    let onImageBoxesChanged: ([NoteImageBox]) -> Void
    let onPhotoPlacementRequested: (CGPoint) -> Void
    let onAISelectionChanged: (CGRect?, Data?) -> Void
    let onVisibleBlankPageChanged: (Int, CGRect) -> Void

    func makeUIView(context: Context) -> NotebookContainerView {
        let view = NotebookContainerView()
        view.onVisibleBlankPageChanged = onVisibleBlankPageChanged
        view.onAISelectionChanged = onAISelectionChanged
        view.configure(
            pages: pages,
            pageStyle: pageStyle,
            coordinator: context.coordinator
        )
        context.coordinator.onPageDrawingChanged = onPageDrawingChanged
        context.coordinator.onTextBoxesChanged = onTextBoxesChanged
        context.coordinator.onImageBoxesChanged = onImageBoxesChanged
        context.coordinator.onPhotoPlacementRequested = onPhotoPlacementRequested
        context.coordinator.currentTextFontSize = textFontSize
        context.coordinator.syncTextBoxes(textBoxes, in: view)
        context.coordinator.syncImageBoxes(imageBoxes, in: view)
        context.coordinator.applyTool(
            selectedTool,
            pencilColor: UIColor(pencilColor),
            pencilWidth: pencilWidth,
            highlighterColor: UIColor(highlighterColor),
            highlighterWidth: highlighterWidth,
            isAISelectionMode: isAISelectionMode,
            in: view
        )
        return view
    }

    func updateUIView(_ view: NotebookContainerView, context: Context) {
        view.onVisibleBlankPageChanged = onVisibleBlankPageChanged
        view.onAISelectionChanged = onAISelectionChanged
        context.coordinator.onPageDrawingChanged = onPageDrawingChanged
        context.coordinator.onTextBoxesChanged = onTextBoxesChanged
        context.coordinator.onImageBoxesChanged = onImageBoxesChanged
        context.coordinator.onPhotoPlacementRequested = onPhotoPlacementRequested
        context.coordinator.currentTextFontSize = textFontSize
        let visibleState = view.captureVisibleState()
        view.configure(
            pages: pages,
            pageStyle: pageStyle,
            coordinator: context.coordinator
        )
        view.restoreVisibleState(visibleState)
        context.coordinator.syncTextBoxes(textBoxes, in: view)
        context.coordinator.syncImageBoxes(imageBoxes, in: view)
        context.coordinator.applyTextFontSizeToEditingBoxes(textFontSize, in: view)
        context.coordinator.applyTool(
            selectedTool,
            pencilColor: UIColor(pencilColor),
            pencilWidth: pencilWidth,
            highlighterColor: UIColor(highlighterColor),
            highlighterWidth: highlighterWidth,
            isAISelectionMode: isAISelectionMode,
            in: view
        )
        context.coordinator.handleUndoRedo(
            undoRequest: undoRequest,
            redoRequest: redoRequest
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class NotebookContainerView: UIView, UIScrollViewDelegate {
        let scrollView = UIScrollView()
        let contentView = UIView()
        private var pageViewsByID: [UUID: PageView] = [:]
        private var orderedPageIDs: [UUID] = []
        private var pageRects: [UUID: CGRect] = [:]
        private var renderedPageStyle: NotePageStyle = .blank
        private var didSetInitialZoom = false
        private var contentLayoutSize = CGSize.zero
        private var shouldResetInitialContentOffset = false
        private var lastReportedPageID: UUID?
        var onVisibleBlankPageChanged: ((Int, CGRect) -> Void)?
        var onAISelectionChanged: ((CGRect?, Data?) -> Void)?

        private let pageSpacing: CGFloat = 40

        struct VisibleState {
            let zoomScale: CGFloat
            let contentOffset: CGPoint
            let centeredContentPoint: CGPoint
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .secondarySystemBackground

            scrollView.delegate = self
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.isScrollEnabled = true
            scrollView.alwaysBounceVertical = true
            scrollView.alwaysBounceHorizontal = true
            scrollView.minimumZoomScale = 0.2
            scrollView.maximumZoomScale = 4
            scrollView.bouncesZoom = false
            scrollView.showsVerticalScrollIndicator = true
            scrollView.showsHorizontalScrollIndicator = false
#if !targetEnvironment(simulator)
            let fingerTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            scrollView.panGestureRecognizer.allowedTouchTypes = fingerTouchTypes
            scrollView.pinchGestureRecognizer?.allowedTouchTypes = fingerTouchTypes
#endif

            addSubview(scrollView)
            scrollView.addSubview(contentView)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            scrollView.frame = bounds
            layoutPages()
            updateZoomIfNeeded()
            updateCenteredContentInset()
            reportVisiblePageIfNeeded()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            contentView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            updateScaledContentMetrics()
            updateCenteredContentInset()
            reportVisiblePageIfNeeded()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            reportVisiblePageIfNeeded()
        }

        func setAllowsPencilScrolling(_ allowsPencilScrolling: Bool) {
#if !targetEnvironment(simulator)
            let touchTypes: [NSNumber] = allowsPencilScrolling
                ? [
                    NSNumber(value: UITouch.TouchType.direct.rawValue),
                    NSNumber(value: UITouch.TouchType.pencil.rawValue)
                ]
                : [NSNumber(value: UITouch.TouchType.direct.rawValue)]

            guard scrollView.panGestureRecognizer.allowedTouchTypes != touchTypes else { return }
            scrollView.panGestureRecognizer.allowedTouchTypes = touchTypes
#endif
        }

        func configure(pages: [NotePage], pageStyle: NotePageStyle, coordinator: Coordinator) {
            renderedPageStyle = pageStyle
            let incomingIDs = pages.map(\.id)
            let incomingIDSet = Set(incomingIDs)

            for (id, pageView) in pageViewsByID where !incomingIDSet.contains(id) {
                pageView.removeFromSuperview()
                pageViewsByID[id] = nil
                pageRects[id] = nil
            }

            for page in pages {
                let pageView: PageView
                if let existing = pageViewsByID[page.id] {
                    pageView = existing
                } else {
                    pageView = PageView(pageID: page.id)
                    pageViewsByID[page.id] = pageView
                    contentView.addSubview(pageView)
                    coordinator.configure(pageView: pageView, pageID: page.id)
                }

                pageView.backgroundView.pageStyle = pageStyle
                pageView.updateDrawingIfNeeded(page.drawingData)
            }

            if orderedPageIDs != incomingIDs {
                let isAppendingPages = !orderedPageIDs.isEmpty && incomingIDs.starts(with: orderedPageIDs)
                orderedPageIDs = incomingIDs
                if !isAppendingPages {
                    didSetInitialZoom = false
                    contentLayoutSize = .zero
                    shouldResetInitialContentOffset = true
                }
            }

            layoutPages()
            coordinator.setActivePageIDs(orderedPageIDs)
        }

        func captureVisibleState() -> VisibleState? {
            guard didSetInitialZoom,
                  scrollView.bounds.width > 0,
                  scrollView.bounds.height > 0,
                  contentView.bounds.width > 0,
                  contentView.bounds.height > 0
            else { return nil }

            let viewportCenter = CGPoint(x: scrollView.bounds.midX, y: scrollView.bounds.midY)
            return VisibleState(
                zoomScale: scrollView.zoomScale,
                contentOffset: scrollView.contentOffset,
                centeredContentPoint: contentView.convert(viewportCenter, from: scrollView)
            )
        }

        func restoreVisibleState(_ state: VisibleState?) {
            guard let state,
                  didSetInitialZoom,
                  scrollView.bounds.width > 0,
                  scrollView.bounds.height > 0,
                  contentView.bounds.width > 0,
                  contentView.bounds.height > 0
            else { return }

            if abs(scrollView.zoomScale - state.zoomScale) > 0.001 {
                scrollView.zoomScale = min(max(state.zoomScale, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
            }

            updateCenteredContentInset()

            let targetOffset: CGPoint
            if abs(scrollView.zoomScale - state.zoomScale) <= 0.001 {
                targetOffset = state.contentOffset
            } else {
                let restoredCenter = contentView.convert(state.centeredContentPoint, to: scrollView)
                targetOffset = CGPoint(
                    x: scrollView.contentOffset.x + restoredCenter.x - scrollView.bounds.midX,
                    y: scrollView.contentOffset.y + restoredCenter.y - scrollView.bounds.midY
                )
            }
            let clampedOffset = clampedContentOffset(targetOffset)

            guard distanceBetween(scrollView.contentOffset, clampedOffset) > 0.5 else { return }
            scrollView.setContentOffset(clampedOffset, animated: false)
        }

        func pageView(for id: UUID) -> PageView? {
            pageViewsByID[id]
        }

        func visiblePageID() -> UUID? {
            guard !orderedPageIDs.isEmpty else { return nil }
            let viewportCenter = CGPoint(x: scrollView.bounds.midX, y: scrollView.bounds.midY)
            let contentPoint = contentView.convert(viewportCenter, from: scrollView)
            return orderedPageIDs.compactMap { id -> (UUID, CGRect)? in
                guard let rect = pageRects[id] else { return nil }
                return (id, rect)
            }
            .min { first, second in
                abs(first.1.midY - contentPoint.y) < abs(second.1.midY - contentPoint.y)
            }?
            .0
        }

        var allPageViews: [PageView] {
            orderedPageIDs.compactMap { pageViewsByID[$0] }
        }

        private func layoutPages() {
            guard bounds.width > 0 || contentView.frame == .zero else { return }

            let pageWidth = preferredPageWidth()
            let pageHeight = pageWidth * 1.375
            var yOffset: CGFloat = 0
            pageRects = [:]

            for id in orderedPageIDs {
                guard let pageView = pageViewsByID[id] else { continue }
                let frame = CGRect(x: 0, y: yOffset, width: pageWidth, height: pageHeight)
                if pageView.frame != frame {
                    pageView.frame = frame
                }
                pageView.layoutForCurrentBounds()
                pageRects[id] = frame
                yOffset += pageHeight + pageSpacing
            }

            let contentHeight = max(yOffset - pageSpacing, pageHeight)
            let size = CGSize(width: pageWidth, height: contentHeight)
            if contentLayoutSize != size {
                contentLayoutSize = size
                updateContentViewSize(size)
            }
        }

        private func preferredPageWidth() -> CGFloat {
            let visibleWidth = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width
            return max(visibleWidth, 820)
        }

        private func updateZoomIfNeeded() {
            guard bounds.width > 0, !didSetInitialZoom else { return }
            let widthScale = bounds.width / max(contentView.bounds.width, 1)
            let minimumScale = min(0.2, widthScale)
            scrollView.minimumZoomScale = minimumScale
            scrollView.zoomScale = min(max(widthScale, minimumScale), scrollView.maximumZoomScale)
            didSetInitialZoom = true
            updateScaledContentMetrics()
            updateCenteredContentInset()
            if shouldResetInitialContentOffset {
                let initialOffset = CGPoint(x: -scrollView.contentInset.left, y: -scrollView.contentInset.top)
                scrollView.setContentOffset(clampedContentOffset(initialOffset), animated: false)
                shouldResetInitialContentOffset = false
            }
        }

        private func updateContentViewSize(_ size: CGSize) {
            contentView.bounds = CGRect(origin: .zero, size: size)

            if !didSetInitialZoom || contentView.frame == .zero {
                contentView.transform = .identity
                contentView.frame = CGRect(origin: .zero, size: size)
            } else {
                updateScaledContentMetrics()
            }
        }

        private func updateScaledContentMetrics() {
            guard contentLayoutSize.width > 0, contentLayoutSize.height > 0 else { return }

            let scaledSize = CGSize(
                width: contentLayoutSize.width * scrollView.zoomScale,
                height: contentLayoutSize.height * scrollView.zoomScale
            )
            scrollView.contentSize = scaledSize
            contentView.center = CGPoint(
                x: scaledSize.width / 2,
                y: scaledSize.height / 2
            )
        }

        private func updateCenteredContentInset() {
            let scaledWidth = contentView.bounds.width * scrollView.zoomScale
            let horizontalInset = max((scrollView.bounds.width - scaledWidth) / 2, 0)
            let inset = UIEdgeInsets(top: 0, left: horizontalInset, bottom: 0, right: horizontalInset)
            guard !insetsAreNearlyEqual(scrollView.contentInset, inset) else { return }
            scrollView.contentInset = inset
        }

        private func clampedContentOffset(_ offset: CGPoint) -> CGPoint {
            let inset = scrollView.contentInset
            let minX = -inset.left
            let minY = -inset.top
            let maxX = max(minX, scrollView.contentSize.width + inset.right - scrollView.bounds.width)
            let maxY = max(minY, scrollView.contentSize.height + inset.bottom - scrollView.bounds.height)

            return CGPoint(
                x: min(max(offset.x, minX), maxX),
                y: min(max(offset.y, minY), maxY)
            )
        }

        private func distanceBetween(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
            hypot(first.x - second.x, first.y - second.y)
        }

        private func insetsAreNearlyEqual(_ first: UIEdgeInsets, _ second: UIEdgeInsets) -> Bool {
            let tolerance: CGFloat = 0.5
            return abs(first.top - second.top) < tolerance
                && abs(first.left - second.left) < tolerance
                && abs(first.bottom - second.bottom) < tolerance
                && abs(first.right - second.right) < tolerance
        }

        private func reportVisiblePageIfNeeded() {
            guard !orderedPageIDs.isEmpty else { return }
            let viewportCenter = CGPoint(x: scrollView.bounds.midX, y: scrollView.bounds.midY)
            let contentPoint = contentView.convert(viewportCenter, from: scrollView)
            let nearest = orderedPageIDs.compactMap { id -> (UUID, CGRect)? in
                guard let rect = pageRects[id] else { return nil }
                return (id, rect)
            }.min { first, second in
                abs(first.1.midY - contentPoint.y) < abs(second.1.midY - contentPoint.y)
            }

            guard let nearest else { return }
            if nearest.0 != lastReportedPageID {
                lastReportedPageID = nearest.0
                let index = orderedPageIDs.firstIndex(of: nearest.0) ?? 0
                onVisibleBlankPageChanged?(index, nearest.1)
            }
        }
    }

    final class PageView: UIView {
        let pageID: UUID
        fileprivate let backgroundView = NotePageBackgroundView()
        let canvasView = PKCanvasView()
        private var loadedDrawingData: Data?

        init(pageID: UUID) {
            self.pageID = pageID
            super.init(frame: .zero)

            backgroundColor = .clear
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.08
            layer.shadowRadius = 10
            layer.shadowOffset = CGSize(width: 0, height: 4)

            canvasView.backgroundColor = .clear
            canvasView.isOpaque = false
            canvasView.isScrollEnabled = false
            canvasView.bounces = false
            canvasView.alwaysBounceVertical = false
            canvasView.alwaysBounceHorizontal = false
            canvasView.contentInsetAdjustmentBehavior = .never
            canvasView.contentInset = .zero
            canvasView.scrollIndicatorInsets = .zero
            canvasView.contentOffset = .zero
            canvasView.minimumZoomScale = 1
            canvasView.maximumZoomScale = 1
            canvasView.zoomScale = 1
#if targetEnvironment(simulator)
            canvasView.drawingPolicy = .anyInput
#else
            canvasView.drawingPolicy = .pencilOnly
#endif

            addSubview(backgroundView)
            addSubview(canvasView)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            layoutForCurrentBounds()
        }

        func layoutForCurrentBounds() {
            backgroundView.frame = bounds
            canvasView.frame = bounds
            guard canvasView.bounds.size != bounds.size || canvasView.contentSize != bounds.size else { return }
            canvasView.bounds = CGRect(origin: .zero, size: bounds.size)
            canvasView.contentSize = bounds.size
            canvasView.contentInset = .zero
            canvasView.scrollIndicatorInsets = .zero
            canvasView.contentOffset = .zero
            canvasView.zoomScale = 1
        }

        func updateDrawingIfNeeded(_ data: Data?) {
            guard data != loadedDrawingData else { return }
            if let data, let drawing = try? PKDrawing(data: data) {
                canvasView.drawing = drawing
                loadedDrawingData = data
            } else if data == nil {
                canvasView.drawing = PKDrawing()
                loadedDrawingData = nil
            }
        }

        func markLoaded(_ data: Data) {
            loadedDrawingData = data
        }
    }

        final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
        var onPageDrawingChanged: ((Data, UUID) -> Void)?
        var onTextBoxesChanged: (([NoteTextBox]) -> Void)?
        var onImageBoxesChanged: (([NoteImageBox]) -> Void)?
        var onPhotoPlacementRequested: ((CGPoint) -> Void)?
        var currentTextFontSize: CGFloat = 20
        var activePageIDs: [UUID] = []
        private var pageIDsByCanvas = [ObjectIdentifier: UUID]()
        private var pageViewsByID = [UUID: PageView]()
        private var eraserGesturesByCanvas = [ObjectIdentifier: UIPanGestureRecognizer]()
        private var eraserFadeLayersByCanvas = [ObjectIdentifier: CAShapeLayer]()
        private var eraserPreviewLayersByCanvas = [ObjectIdentifier: CAShapeLayer]()
        private var aiSelectionGesturesByCanvas = [ObjectIdentifier: UIPanGestureRecognizer]()
        private var aiSelectionLayersByCanvas = [ObjectIdentifier: CAShapeLayer]()
        private var textPlacementGesturesByCanvas = [ObjectIdentifier: UITapGestureRecognizer]()
        private var photoPlacementGesturesByCanvas = [ObjectIdentifier: UITapGestureRecognizer]()
        private weak var containerView: NotebookContainerView?
        private var activePageID: UUID?
        private var handledUndoRequest = 0
        private var handledRedoRequest = 0
        private var appliedSignature: String?
        private var isEraserPreviewEnabled = false
        private var isAISelectionEnabled = false
        private var isTextPlacementEnabled = false
        private var isPhotoPlacementEnabled = false
        private var currentTextBoxes: [NoteTextBox] = []
        private var currentImageBoxes: [NoteImageBox] = []
        private var aiSelectionPoints: [CGPoint] = []
        private let aiSelectionAccentColor = UIColor(Color.accentColor)
        private var eraserBaseDrawing: PKDrawing?
        private var eraserHitStrokeIndexes = Set<Int>()
        private var isUsingTool = false
        private var pendingPageDrawingData: (data: Data, pageID: UUID)?

        func configure(pageView: PageView, pageID: UUID) {
            pageView.canvasView.delegate = self
            pageIDsByCanvas[ObjectIdentifier(pageView.canvasView)] = pageID
            pageViewsByID[pageID] = pageView
            configureEraserPreview(on: pageView.canvasView)
            configureAISelection(on: pageView.canvasView)
            configureTextPlacement(on: pageView.canvasView)
            configurePhotoPlacement(on: pageView.canvasView)
            appliedSignature = nil
        }

        func setActivePageIDs(_ pageIDs: [UUID]) {
            activePageIDs = pageIDs
            let activeSet = Set(pageIDs)
            pageViewsByID = pageViewsByID.filter { activeSet.contains($0.key) }
            pageIDsByCanvas = pageIDsByCanvas.filter { activeSet.contains($0.value) }
            let activeCanvasIDs = Set(pageViewsByID.values.map { ObjectIdentifier($0.canvasView) })
            eraserGesturesByCanvas = eraserGesturesByCanvas.filter { activeCanvasIDs.contains($0.key) }
            eraserFadeLayersByCanvas = eraserFadeLayersByCanvas.filter { activeCanvasIDs.contains($0.key) }
            eraserPreviewLayersByCanvas = eraserPreviewLayersByCanvas.filter { activeCanvasIDs.contains($0.key) }
            aiSelectionGesturesByCanvas = aiSelectionGesturesByCanvas.filter { activeCanvasIDs.contains($0.key) }
            aiSelectionLayersByCanvas = aiSelectionLayersByCanvas.filter { activeCanvasIDs.contains($0.key) }
            textPlacementGesturesByCanvas = textPlacementGesturesByCanvas.filter { activeCanvasIDs.contains($0.key) }
            photoPlacementGesturesByCanvas = photoPlacementGesturesByCanvas.filter { activeCanvasIDs.contains($0.key) }
        }

        func applyTool(
            _ selectedTool: NoteEditorTool,
            pencilColor: UIColor,
            pencilWidth: CGFloat,
            highlighterColor: UIColor,
            highlighterWidth: CGFloat,
            isAISelectionMode: Bool,
            in containerView: NotebookContainerView
        ) {
            self.containerView = containerView
            containerView.setAllowsPencilScrolling(selectedTool == .hand && !isAISelectionMode)
            setEraserPreviewEnabled(selectedTool == .eraser && !isAISelectionMode)
            setAISelectionEnabled(isAISelectionMode)
            setTextPlacementEnabled(selectedTool == .text && !isAISelectionMode)
            setPhotoPlacementEnabled(selectedTool == .photo && !isAISelectionMode)
            let signature = "\(selectedTool.rawValue)-\(pencilColor.cgColor)-\(pencilWidth)-\(highlighterColor.cgColor)-\(highlighterWidth)-\(isAISelectionMode)"
            guard signature != appliedSignature else { return }
            appliedSignature = signature

            for pageView in containerView.allPageViews {
                let canvasView = pageView.canvasView
                guard !isAISelectionMode else {
                    canvasView.isDrawingEnabled = false
                    continue
                }

                switch selectedTool {
                case .pencil:
                    canvasView.isDrawingEnabled = true
                    canvasView.tool = PKInkingTool(.pen, color: pencilColor, width: pencilWidth)
                case .highlighter:
                    canvasView.isDrawingEnabled = true
                    canvasView.tool = PKInkingTool(
                        .marker,
                        color: highlighterColor.withAlphaComponent(0.55),
                        width: highlighterWidth
                    )
                case .eraser:
                    canvasView.isDrawingEnabled = false
                case .selector:
                    canvasView.isDrawingEnabled = true
                    canvasView.tool = PKLassoTool()
                case .text, .photo, .hand:
                    canvasView.isDrawingEnabled = false
                }
            }
        }

        func handleUndoRedo(undoRequest: Int, redoRequest: Int) {
            let targetPageID = activePageID
                .flatMap { pageViewsByID[$0] == nil ? nil : $0 }
                ?? containerView?.visiblePageID()
                ?? activePageIDs.first
            guard let targetPageID else { return }
            guard let canvasView = pageViewsByID[targetPageID]?.canvasView else { return }
            activePageID = targetPageID
            if undoRequest != handledUndoRequest {
                handledUndoRequest = undoRequest
                canvasView.becomeFirstResponder()
                canvasView.undoManager?.undo()
                canvasViewDrawingDidChange(canvasView)
            }
            if redoRequest != handledRedoRequest {
                handledRedoRequest = redoRequest
                canvasView.becomeFirstResponder()
                canvasView.undoManager?.redo()
                canvasViewDrawingDidChange(canvasView)
            }
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            activePageID = pageIDsByCanvas[ObjectIdentifier(canvasView)]
            isUsingTool = true
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            isUsingTool = false
            publishDrawing(from: canvasView)
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isUsingTool else {
                guard let pageID = pageIDsByCanvas[ObjectIdentifier(canvasView)] else { return }
                activePageID = pageID
                let data = canvasView.drawing.dataRepresentation()
                pageViewsByID[pageID]?.markLoaded(data)
                pendingPageDrawingData = (data, pageID)
                return
            }

            publishDrawing(from: canvasView)
        }

        private func publishDrawing(from canvasView: PKCanvasView) {
            guard let pageID = pageIDsByCanvas[ObjectIdentifier(canvasView)] else { return }
            activePageID = pageID
            let data = canvasView.drawing.dataRepresentation()
            pageViewsByID[pageID]?.markLoaded(data)
            pendingPageDrawingData = nil
            onPageDrawingChanged?(data, pageID)
        }

        private func configureEraserPreview(on canvasView: PKCanvasView) {
            let canvasID = ObjectIdentifier(canvasView)
            guard eraserGesturesByCanvas[canvasID] == nil else { return }

            let fadeLayer = CAShapeLayer()
            fadeLayer.fillColor = nil
            fadeLayer.strokeColor = UIColor.systemGray.withAlphaComponent(0.5).cgColor
            fadeLayer.lineWidth = 12
            fadeLayer.lineCap = .round
            fadeLayer.lineJoin = .round
            fadeLayer.isHidden = true
            canvasView.layer.addSublayer(fadeLayer)
            eraserFadeLayersByCanvas[canvasID] = fadeLayer

            let previewLayer = CAShapeLayer()
            previewLayer.fillColor = UIColor.systemGray.withAlphaComponent(0.2).cgColor
            previewLayer.strokeColor = UIColor.systemGray.withAlphaComponent(0.7).cgColor
            previewLayer.lineWidth = 2
            previewLayer.isHidden = true
            canvasView.layer.addSublayer(previewLayer)
            eraserPreviewLayersByCanvas[canvasID] = previewLayer

            let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleEraserPreview(_:)))
            gesture.delegate = self
            gesture.maximumNumberOfTouches = 1
            gesture.cancelsTouchesInView = true
#if !targetEnvironment(simulator)
            gesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
#endif
            gesture.isEnabled = isEraserPreviewEnabled
            canvasView.addGestureRecognizer(gesture)
            eraserGesturesByCanvas[canvasID] = gesture
        }

        private func configureAISelection(on canvasView: PKCanvasView) {
            let canvasID = ObjectIdentifier(canvasView)
            guard aiSelectionGesturesByCanvas[canvasID] == nil else { return }

            let layer = CAShapeLayer()
            layer.fillColor = aiSelectionAccentColor.withAlphaComponent(0.13).cgColor
            layer.strokeColor = aiSelectionAccentColor.cgColor
            layer.lineWidth = 3.5
            layer.lineDashPattern = [7, 5]
            layer.lineJoin = .round
            layer.lineCap = .round
            layer.shadowColor = aiSelectionAccentColor.cgColor
            layer.shadowOpacity = 0.28
            layer.shadowRadius = 8
            layer.shadowOffset = .zero
            layer.isHidden = true
            canvasView.layer.addSublayer(layer)
            aiSelectionLayersByCanvas[canvasID] = layer

            let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleAISelection(_:)))
            gesture.delegate = self
            gesture.maximumNumberOfTouches = 1
            gesture.cancelsTouchesInView = true
#if !targetEnvironment(simulator)
            gesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
#endif
            gesture.isEnabled = isAISelectionEnabled
            canvasView.addGestureRecognizer(gesture)
            aiSelectionGesturesByCanvas[canvasID] = gesture
        }

        private func setEraserPreviewEnabled(_ enabled: Bool) {
            guard enabled != isEraserPreviewEnabled else { return }
            isEraserPreviewEnabled = enabled
            eraserGesturesByCanvas.values.forEach { $0.isEnabled = enabled }

            if !enabled {
                clearEraserPreview()
            }
        }

        private func setAISelectionEnabled(_ enabled: Bool) {
            guard enabled != isAISelectionEnabled else { return }
            isAISelectionEnabled = enabled
            aiSelectionGesturesByCanvas.values.forEach { $0.isEnabled = enabled }

            if !enabled {
                clearAISelection()
                containerView?.onAISelectionChanged?(nil, nil)
            }
        }

        private func setTextPlacementEnabled(_ enabled: Bool) {
            guard enabled != isTextPlacementEnabled else { return }
            isTextPlacementEnabled = enabled
            textPlacementGesturesByCanvas.values.forEach { $0.isEnabled = enabled }

            guard !enabled, let containerView else { return }
            let finishedEditing = finishEditingTextBoxes(in: containerView)
            deselectTextBoxes(in: containerView)
            if finishedEditing {
                publishTextBoxes(in: containerView)
            }
        }

        private func setPhotoPlacementEnabled(_ enabled: Bool) {
            guard enabled != isPhotoPlacementEnabled else { return }
            isPhotoPlacementEnabled = enabled
            photoPlacementGesturesByCanvas.values.forEach { $0.isEnabled = enabled }

            if !enabled, let containerView {
                deselectImageBoxes(in: containerView)
            }
        }

        func syncTextBoxes(_ textBoxes: [NoteTextBox], in containerView: NotebookContainerView) {
            guard textBoxes != currentTextBoxes else { return }
            currentTextBoxes = textBoxes

            let existingViews = containerView.contentView.subviews.compactMap { $0 as? DrawingCanvasView.CanvasTextBoxView }
            let incomingIDs = Set(textBoxes.map(\.id))

            for view in existingViews where !incomingIDs.contains(view.id) {
                view.removeFromSuperview()
            }

            for textBox in textBoxes {
                if let view = existingViews.first(where: { $0.id == textBox.id }) {
                    view.update(with: textBox)
                    configureTextBoxCallback(view)
                    containerView.contentView.bringSubviewToFront(view)
                } else {
                    let view = DrawingCanvasView.CanvasTextBoxView(textBox: textBox)
                    configureTextBoxCallback(view)
                    containerView.contentView.addSubview(view)
                }
            }
        }

        func syncImageBoxes(_ imageBoxes: [NoteImageBox], in containerView: NotebookContainerView) {
            guard imageBoxes != currentImageBoxes else { return }
            currentImageBoxes = imageBoxes

            let existingViews = containerView.contentView.subviews.compactMap { $0 as? DrawingCanvasView.CanvasImageBoxView }
            let incomingIDs = Set(imageBoxes.map(\.id))

            for view in existingViews where !incomingIDs.contains(view.id) {
                view.removeFromSuperview()
            }

            for imageBox in imageBoxes {
                if let view = existingViews.first(where: { $0.id == imageBox.id }) {
                    view.update(with: imageBox)
                    configureImageBoxCallback(view)
                    containerView.contentView.bringSubviewToFront(view)
                } else {
                    let view = DrawingCanvasView.CanvasImageBoxView(imageBox: imageBox)
                    configureImageBoxCallback(view)
                    containerView.contentView.addSubview(view)
                }
            }
        }

        func applyTextFontSizeToEditingBoxes(_ fontSize: CGFloat, in containerView: NotebookContainerView) {
            containerView.contentView.subviews
                .compactMap { $0 as? DrawingCanvasView.CanvasTextBoxView }
                .filter(\.isEditingText)
                .forEach { $0.applyFontSize(fontSize) }
        }

        private func configureTextPlacement(on canvasView: PKCanvasView) {
            let canvasID = ObjectIdentifier(canvasView)
            guard textPlacementGesturesByCanvas[canvasID] == nil else { return }

            let gesture = UITapGestureRecognizer(target: self, action: #selector(handleTextPlacement(_:)))
            gesture.delegate = self
            gesture.numberOfTapsRequired = 1
            gesture.cancelsTouchesInView = false
            gesture.isEnabled = isTextPlacementEnabled
            canvasView.addGestureRecognizer(gesture)
            textPlacementGesturesByCanvas[canvasID] = gesture
        }

        private func configurePhotoPlacement(on canvasView: PKCanvasView) {
            let canvasID = ObjectIdentifier(canvasView)
            guard photoPlacementGesturesByCanvas[canvasID] == nil else { return }

            let gesture = UITapGestureRecognizer(target: self, action: #selector(handlePhotoPlacement(_:)))
            gesture.delegate = self
            gesture.numberOfTapsRequired = 1
            gesture.cancelsTouchesInView = false
            gesture.isEnabled = isPhotoPlacementEnabled
            canvasView.addGestureRecognizer(gesture)
            photoPlacementGesturesByCanvas[canvasID] = gesture
        }

        @objc private func handleTextPlacement(_ gesture: UITapGestureRecognizer) {
            guard isTextPlacementEnabled,
                  gesture.state == .ended,
                  let canvasView = gesture.view as? PKCanvasView,
                  let containerView
            else { return }

            if finishEditingTextBoxes(in: containerView) {
                publishTextBoxes(in: containerView)
                return
            }

            guard let frame = placementFrame(from: gesture, in: canvasView, size: CGSize(width: 220, height: 72)) else { return }
            activePageID = pageIDsByCanvas[ObjectIdentifier(canvasView)]
            let textBox = NoteTextBox(text: "", frame: frame, fontSize: currentTextFontSize)
            currentTextBoxes.append(textBox)

            let view = DrawingCanvasView.CanvasTextBoxView(textBox: textBox)
            configureTextBoxCallback(view)
            containerView.contentView.addSubview(view)
            view.focus()
            publishTextBoxes(in: containerView)
        }

        @objc private func handlePhotoPlacement(_ gesture: UITapGestureRecognizer) {
            guard isPhotoPlacementEnabled,
                  gesture.state == .ended,
                  let canvasView = gesture.view as? PKCanvasView,
                  let containerView
            else { return }

            activePageID = pageIDsByCanvas[ObjectIdentifier(canvasView)]
            let localPoint = gesture.location(in: canvasView)
            let contentPoint = canvasView.convert(localPoint, to: containerView.contentView)
            onPhotoPlacementRequested?(contentPoint)
        }

        private func placementFrame(from gesture: UITapGestureRecognizer, in canvasView: PKCanvasView, size: CGSize) -> CGRect? {
            guard let containerView else { return nil }
            let localPoint = gesture.location(in: canvasView)
            let contentPoint = canvasView.convert(localPoint, to: containerView.contentView)
            return CGRect(origin: contentPoint, size: size)
        }

        private func configureTextBoxCallback(_ view: DrawingCanvasView.CanvasTextBoxView) {
            view.onChange = { [weak self] updatedTextBox in
                guard let self, let containerView else { return }
                if let index = currentTextBoxes.firstIndex(where: { $0.id == updatedTextBox.id }) {
                    currentTextBoxes[index] = updatedTextBox
                } else {
                    currentTextBoxes.append(updatedTextBox)
                }
                publishTextBoxes(in: containerView)
            }
            view.onDelete = { [weak self, weak view] id in
                guard let self, let containerView else { return }
                currentTextBoxes.removeAll { $0.id == id }
                view?.removeFromSuperview()
                publishTextBoxes(in: containerView)
            }
        }

        private func configureImageBoxCallback(_ view: DrawingCanvasView.CanvasImageBoxView) {
            view.onChange = { [weak self] updatedImageBox in
                guard let self else { return }
                if let index = currentImageBoxes.firstIndex(where: { $0.id == updatedImageBox.id }) {
                    currentImageBoxes[index] = updatedImageBox
                } else {
                    currentImageBoxes.append(updatedImageBox)
                }
                onImageBoxesChanged?(currentImageBoxes)
            }
            view.onDelete = { [weak self, weak view] id in
                guard let self else { return }
                currentImageBoxes.removeAll { $0.id == id }
                view?.removeFromSuperview()
                onImageBoxesChanged?(currentImageBoxes)
            }
        }

        private func finishEditingTextBoxes(in containerView: NotebookContainerView) -> Bool {
            let editingViews = containerView.contentView.subviews
                .compactMap { $0 as? DrawingCanvasView.CanvasTextBoxView }
                .filter(\.isEditingText)
            guard !editingViews.isEmpty else { return false }

            editingViews.forEach { $0.finishEditing() }
            return true
        }

        private func deselectTextBoxes(in containerView: NotebookContainerView) {
            containerView.contentView.subviews
                .compactMap { $0 as? DrawingCanvasView.CanvasTextBoxView }
                .forEach { $0.setSelected(false) }
        }

        private func deselectImageBoxes(in containerView: NotebookContainerView) {
            containerView.contentView.subviews
                .compactMap { $0 as? DrawingCanvasView.CanvasImageBoxView }
                .forEach { $0.setSelected(false) }
        }

        private func publishTextBoxes(in containerView: NotebookContainerView) {
            let nonEmptyOrFocusedBoxes = currentTextBoxes.filter { textBox in
                !textBox.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || containerView.contentView.subviews
                        .compactMap({ $0 as? DrawingCanvasView.CanvasTextBoxView })
                        .contains(where: { $0.id == textBox.id && $0.isEditingText }) == true
            }
            currentTextBoxes = nonEmptyOrFocusedBoxes
            removeDiscardedTextBoxViews(in: containerView)
            onTextBoxesChanged?(currentTextBoxes)
        }

        private func removeDiscardedTextBoxViews(in containerView: NotebookContainerView) {
            let savedIDs = Set(currentTextBoxes.map(\.id))
            containerView.contentView.subviews
                .compactMap { $0 as? DrawingCanvasView.CanvasTextBoxView }
                .filter { !savedIDs.contains($0.id) }
                .forEach { $0.removeFromSuperview() }
        }

        @objc private func handleAISelection(_ gesture: UIPanGestureRecognizer) {
            guard isAISelectionEnabled, let canvasView = gesture.view as? PKCanvasView else { return }
            let point = gesture.location(in: canvasView)

            switch gesture.state {
            case .began:
                activePageID = pageIDsByCanvas[ObjectIdentifier(canvasView)]
                setPageScrollEnabled(false)
                aiSelectionPoints = [point]
                updateAISelectionLayer(on: canvasView, closed: false)
                containerView?.onAISelectionChanged?(nil, nil)
            case .changed:
                aiSelectionPoints.append(point)
                updateAISelectionLayer(on: canvasView, closed: false)
            case .ended:
                aiSelectionPoints.append(aiSelectionPoints.first ?? point)
                updateAISelectionLayer(on: canvasView, closed: true)
                publishAISelection(from: canvasView)
                setPageScrollEnabled(true)
            case .cancelled, .failed:
                clearAISelection(on: canvasView)
                containerView?.onAISelectionChanged?(nil, nil)
                setPageScrollEnabled(true)
            default:
                break
            }
        }

        private func updateAISelectionLayer(on canvasView: PKCanvasView, closed: Bool) {
            guard let layer = aiSelectionLayersByCanvas[ObjectIdentifier(canvasView)] else { return }
            guard aiSelectionPoints.count >= 2 else {
                layer.isHidden = true
                layer.path = nil
                return
            }

            let path = UIBezierPath()
            path.move(to: aiSelectionPoints[0])
            for point in aiSelectionPoints.dropFirst() {
                path.addLine(to: point)
            }
            if closed {
                path.close()
            }

            layer.path = path.cgPath
            layer.isHidden = false
        }

        private func publishAISelection(from canvasView: PKCanvasView) {
            guard aiSelectionPoints.count >= 3 else {
                containerView?.onAISelectionChanged?(nil, nil)
                return
            }

            let xs = aiSelectionPoints.map(\.x)
            let ys = aiSelectionPoints.map(\.y)
            guard
                let minX = xs.min(),
                let maxX = xs.max(),
                let minY = ys.min(),
                let maxY = ys.max()
            else {
                containerView?.onAISelectionChanged?(nil, nil)
                return
            }

            let pageBounds = CGRect(origin: .zero, size: canvasView.contentSize)
            let selection = CGRect(
                x: minX,
                y: minY,
                width: maxX - minX,
                height: maxY - minY
            )
            .insetBy(dx: -28, dy: -28)
            .intersection(pageBounds)

            guard selection.width >= 20 && selection.height >= 20 else {
                clearAISelection(on: canvasView)
                containerView?.onAISelectionChanged?(nil, nil)
                return
            }

            containerView?.onAISelectionChanged?(selection, canvasView.drawing.dataRepresentation())
        }

        private func clearAISelection(on canvasView: PKCanvasView? = nil) {
            aiSelectionPoints.removeAll()

            if let canvasView {
                let layer = aiSelectionLayersByCanvas[ObjectIdentifier(canvasView)]
                layer?.isHidden = true
                layer?.path = nil
            } else {
                aiSelectionLayersByCanvas.values.forEach {
                    $0.isHidden = true
                    $0.path = nil
                }
            }
        }

        private func setPageScrollEnabled(_ enabled: Bool) {
            containerView?.scrollView.isScrollEnabled = enabled
        }

        @objc private func handleEraserPreview(_ gesture: UIPanGestureRecognizer) {
            guard isEraserPreviewEnabled, let canvasView = gesture.view as? PKCanvasView else { return }
            let point = gesture.location(in: canvasView)
            let radius: CGFloat = 18

            switch gesture.state {
            case .began:
                activePageID = pageIDsByCanvas[ObjectIdentifier(canvasView)]
                eraserBaseDrawing = canvasView.drawing
                eraserHitStrokeIndexes.removeAll()
                updateEraserPreview(on: canvasView, at: point, radius: radius)
                updateEraserFadeOverlay(on: canvasView, near: point, radius: radius)
            case .changed:
                updateEraserPreview(on: canvasView, at: point, radius: radius)
                updateEraserFadeOverlay(on: canvasView, near: point, radius: radius)
            case .ended:
                commitEraserChanges(on: canvasView)
                clearEraserPreview(on: canvasView)
            case .cancelled, .failed:
                clearEraserPreview(on: canvasView)
            default:
                break
            }
        }

        private func updateEraserPreview(on canvasView: PKCanvasView, at point: CGPoint, radius: CGFloat) {
            let rect = CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            let layer = eraserPreviewLayersByCanvas[ObjectIdentifier(canvasView)]
            layer?.path = UIBezierPath(ovalIn: rect).cgPath
            layer?.isHidden = false
        }

        private func updateEraserFadeOverlay(on canvasView: PKCanvasView, near point: CGPoint, radius: CGFloat) {
            guard let eraserBaseDrawing else { return }
            addHitStrokes(near: point, in: eraserBaseDrawing, radius: radius)

            guard !eraserHitStrokeIndexes.isEmpty else {
                let layer = eraserFadeLayersByCanvas[ObjectIdentifier(canvasView)]
                layer?.isHidden = true
                layer?.path = nil
                return
            }

            let overlayPath = UIBezierPath()
            for index in eraserHitStrokeIndexes.sorted() {
                guard eraserBaseDrawing.strokes.indices.contains(index) else { continue }
                overlayPath.append(path(for: eraserBaseDrawing.strokes[index]))
            }

            let layer = eraserFadeLayersByCanvas[ObjectIdentifier(canvasView)]
            layer?.path = overlayPath.cgPath
            layer?.isHidden = false
        }

        private func commitEraserChanges(on canvasView: PKCanvasView) {
            guard let eraserBaseDrawing, !eraserHitStrokeIndexes.isEmpty else { return }
            let remainingStrokes = eraserBaseDrawing.strokes.enumerated().compactMap { index, stroke in
                eraserHitStrokeIndexes.contains(index) ? nil : stroke
            }
            canvasView.drawing = PKDrawing(strokes: remainingStrokes)
            canvasViewDrawingDidChange(canvasView)
        }

        private func clearEraserPreview(on canvasView: PKCanvasView? = nil) {
            if let canvasView {
                let canvasID = ObjectIdentifier(canvasView)
                eraserPreviewLayersByCanvas[canvasID]?.isHidden = true
                eraserPreviewLayersByCanvas[canvasID]?.path = nil
                eraserFadeLayersByCanvas[canvasID]?.isHidden = true
                eraserFadeLayersByCanvas[canvasID]?.path = nil
            } else {
                eraserPreviewLayersByCanvas.values.forEach {
                    $0.isHidden = true
                    $0.path = nil
                }
                eraserFadeLayersByCanvas.values.forEach {
                    $0.isHidden = true
                    $0.path = nil
                }
            }

            eraserBaseDrawing = nil
            eraserHitStrokeIndexes.removeAll()
        }

        private func addHitStrokes(near point: CGPoint, in drawing: PKDrawing, radius: CGFloat) {
            for (index, stroke) in drawing.strokes.enumerated() {
                guard !eraserHitStrokeIndexes.contains(index) else { continue }
                if strokeIntersectsEraserPoint(stroke, point: point, radius: radius) {
                    eraserHitStrokeIndexes.insert(index)
                }
            }
        }

        private func strokeIntersectsEraserPoint(_ stroke: PKStroke, point: CGPoint, radius: CGFloat) -> Bool {
            let hitRadius = radius + max(stroke.renderBounds.width, stroke.renderBounds.height, 1) * 0.01
            let hitRadiusSquared = hitRadius * hitRadius

            for strokePoint in stroke.path {
                let location = strokePoint.location.applying(stroke.transform)
                if squaredDistance(location, point) <= hitRadiusSquared {
                    return true
                }
            }

            return false
        }

        private func path(for stroke: PKStroke) -> UIBezierPath {
            let path = UIBezierPath()
            var didMove = false

            for strokePoint in stroke.path {
                let location = strokePoint.location.applying(stroke.transform)
                if didMove {
                    path.addLine(to: location)
                } else {
                    path.move(to: location)
                    didMove = true
                }
            }

            return path
        }

        private func squaredDistance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
            let x = first.x - second.x
            let y = first.y - second.y
            return x * x + y * y
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if textPlacementGesturesByCanvas.values.contains(where: { $0 === gestureRecognizer }) {
                return isTextPlacementEnabled
            }

            if photoPlacementGesturesByCanvas.values.contains(where: { $0 === gestureRecognizer }) {
                return isPhotoPlacementEnabled
            }

            guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            if eraserGesturesByCanvas.values.contains(where: { $0 === panGesture }) {
                return isEraserPreviewEnabled
            }
            if aiSelectionGesturesByCanvas.values.contains(where: { $0 === panGesture }) {
                return isAISelectionEnabled
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if textPlacementGesturesByCanvas.values.contains(where: { $0 === gestureRecognizer })
                || photoPlacementGesturesByCanvas.values.contains(where: { $0 === gestureRecognizer }) {
                var view = touch.view
                while let candidate = view {
                    if candidate is DrawingCanvasView.CanvasTextBoxView || candidate is DrawingCanvasView.CanvasImageBoxView {
                        return false
                    }
                    view = candidate.superview
                }
            }

            return true
        }
    }
}
