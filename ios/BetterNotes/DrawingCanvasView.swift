import PencilKit
import PDFKit
import SwiftUI

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

struct DrawingCanvasView: UIViewRepresentable {
    let drawingData: Data?
    let pdfBackgroundURL: URL?
    let blankPageCount: Int
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
    let onAISelectionChanged: (CGRect?) -> Void
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
        canvasView.minimumZoomScale = 1
        canvasView.maximumZoomScale = 1
        canvasView.contentSize = containerView.contentSize
        context.coordinator.configureSelectionGesture(on: canvasView)
        context.coordinator.configureEraserPreviewGesture(on: canvasView)
        context.coordinator.configureTextPlacementGesture(on: canvasView)
        context.coordinator.configurePhotoPlacementGesture(on: canvasView)
        containerView.configureBackground(url: pdfBackgroundURL, blankPageCount: blankPageCount)
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
        containerView.configureBackground(url: pdfBackgroundURL, blankPageCount: blankPageCount)
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
            scrollView.bouncesZoom = true
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

            configureBlankPages(count: 1)
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

        func configureBackground(url: URL?, blankPageCount: Int) {
            let pageCount = max(blankPageCount, 1)
            guard renderedPDFURL != url || renderedBlankPageCount != pageCount else { return }
            let isChangingDocument = renderedPDFURL != url
            renderedPDFURL = url
            renderedBlankPageCount = pageCount
            if isChangingDocument {
                didSetInitialZoom = false
            }
            pdfBackgroundView.subviews.forEach { $0.removeFromSuperview() }

            guard let url, let document = PDFDocument(url: url), document.pageCount > 0 else {
                configureBlankPages(count: pageCount)
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

        private func configureBlankPages(count: Int) {
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
                let pageView = UIView(
                    frame: pageFrame
                )
                pageView.backgroundColor = .white
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
            canvasView.contentSize = size
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
        var onAISelectionChanged: ((CGRect?) -> Void)?
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
                    onAISelectionChanged?(nil)
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
                canvasView.undoManager?.undo()
                publishDrawing(from: canvasView)
            }

            if redoRequest != handledRedoRequest {
                handledRedoRequest = redoRequest
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
                    onAISelectionChanged?(nil)
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
                onAISelectionChanged?(nil)
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
                onAISelectionChanged?(nil)
                return
            }

            onAISelectionChanged?(selection)
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
