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
        case .selector: "Select"
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
        case .selector: "Draw around handwriting to select it."
        case .hand: "Drag or pinch the page to move and zoom."
        default: nil
        }
    }
}

struct DrawingCanvasView: UIViewRepresentable {
    let drawingData: Data?
    let pdfBackgroundURL: URL?
    let selectedTool: NoteEditorTool
    let isAISelectionMode: Bool
    let onDrawingChanged: (Data) -> Void
    let onAISelectionChanged: (CGRect?) -> Void

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
        containerView.configurePDFBackground(url: pdfBackgroundURL)
        apply(selectedTool, isAISelectionMode: isAISelectionMode, to: canvasView, coordinator: context.coordinator)

        if let drawingData, let drawing = try? PKDrawing(data: drawingData) {
            canvasView.drawing = drawing
            context.coordinator.loadedDrawingData = drawingData
        }

        canvasView.becomeFirstResponder()

        context.coordinator.onDrawingChanged = onDrawingChanged
        context.coordinator.onAISelectionChanged = onAISelectionChanged
        return containerView
    }

    func updateUIView(_ containerView: PDFDrawingCanvasContainerView, context: Context) {
        let canvasView = containerView.canvasView
        context.coordinator.onDrawingChanged = onDrawingChanged
        context.coordinator.onAISelectionChanged = onAISelectionChanged
        containerView.configurePDFBackground(url: pdfBackgroundURL)
        apply(selectedTool, isAISelectionMode: isAISelectionMode, to: canvasView, coordinator: context.coordinator)

        guard
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

    private func apply(
        _ selectedTool: NoteEditorTool,
        isAISelectionMode: Bool,
        to canvasView: PKCanvasView,
        coordinator: Coordinator
    ) {
        coordinator.setAISelectionMode(isAISelectionMode, on: canvasView)
        guard !isAISelectionMode else {
            canvasView.isDrawingEnabled = false
            return
        }

        switch selectedTool {
        case .pencil:
            canvasView.isDrawingEnabled = true
            canvasView.tool = PKInkingTool(.pen, color: .label, width: 3)
        case .highlighter:
            canvasView.isDrawingEnabled = true
            canvasView.tool = PKInkingTool(
                .marker,
                color: UIColor.systemYellow.withAlphaComponent(0.55),
                width: 18
            )
        case .eraser:
            canvasView.isDrawingEnabled = true
            canvasView.tool = PKEraserTool(.vector)
        case .selector:
            canvasView.isDrawingEnabled = true
            canvasView.tool = PKLassoTool()
        case .text, .photo, .hand:
            canvasView.isDrawingEnabled = false
        }
    }

    final class PDFDrawingCanvasContainerView: UIView, UIScrollViewDelegate {
        let scrollView = UIScrollView()
        let contentView = UIView()
        let pdfBackgroundView = UIView()
        let canvasView = PKCanvasView()

        private(set) var contentSize = CGSize(width: 1600, height: 2200)
        private var renderedPDFURL: URL?
        private var didSetInitialZoom = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .secondarySystemBackground

            scrollView.delegate = self
            scrollView.alwaysBounceVertical = true
            scrollView.alwaysBounceHorizontal = true
            scrollView.minimumZoomScale = 0.3
            scrollView.maximumZoomScale = 4
            scrollView.showsVerticalScrollIndicator = true
            scrollView.showsHorizontalScrollIndicator = false

            pdfBackgroundView.isUserInteractionEnabled = false
            canvasView.backgroundColor = .clear
            canvasView.isOpaque = false

            addSubview(scrollView)
            scrollView.addSubview(contentView)
            contentView.addSubview(pdfBackgroundView)
            contentView.addSubview(canvasView)

            configureBlankPage()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            scrollView.frame = bounds
            applyContentSize(contentSize)
            updateZoomIfNeeded()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            contentView
        }

        func configurePDFBackground(url: URL?) {
            guard renderedPDFURL != url else { return }
            renderedPDFURL = url
            pdfBackgroundView.subviews.forEach { $0.removeFromSuperview() }

            guard let url, let document = PDFDocument(url: url), document.pageCount > 0 else {
                configureBlankPage()
                return
            }

            backgroundColor = .secondarySystemBackground
            let pageWidth: CGFloat = 1600
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
        }

        private func configureBlankPage() {
            let pageView = UIView(frame: CGRect(origin: .zero, size: CGSize(width: 1600, height: 2200)))
            pageView.backgroundColor = .white
            pdfBackgroundView.addSubview(pageView)
            applyContentSize(CGSize(width: 1600, height: 2200))
        }

        private func applyContentSize(_ size: CGSize) {
            contentSize = size
            scrollView.contentSize = size
            contentView.frame = CGRect(origin: .zero, size: size)
            pdfBackgroundView.frame = contentView.bounds
            canvasView.frame = contentView.bounds
            canvasView.contentSize = size
        }

        private func updateZoomIfNeeded() {
            guard bounds.width > 0, !didSetInitialZoom else { return }
            let widthScale = bounds.width / max(contentSize.width, 1)
            let initialZoom = min(max(widthScale, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
            scrollView.zoomScale = initialZoom
            didSetInitialZoom = true
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
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
        var onDrawingChanged: ((Data) -> Void)?
        var onAISelectionChanged: ((CGRect?) -> Void)?
        var loadedDrawingData: Data?
        var isLoadingDrawing = false
        private weak var canvasView: PKCanvasView?
        private var selectionGesture: UIPanGestureRecognizer?
        private let selectionLayer = CAShapeLayer()
        private var displayPoints: [CGPoint] = []
        private var contentPoints: [CGPoint] = []
        private var isAISelectionMode = false

        func configureSelectionGesture(on canvasView: PKCanvasView) {
            guard selectionGesture == nil else { return }
            self.canvasView = canvasView

            selectionLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.12).cgColor
            selectionLayer.strokeColor = UIColor.systemBlue.cgColor
            selectionLayer.lineWidth = 3
            selectionLayer.lineDashPattern = [8, 6]
            canvasView.layer.addSublayer(selectionLayer)

            let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleSelection(_:)))
            gesture.delegate = self
            gesture.maximumNumberOfTouches = 1
            gesture.cancelsTouchesInView = true
            gesture.isEnabled = false
            canvasView.addGestureRecognizer(gesture)
            selectionGesture = gesture
        }

        func setAISelectionMode(_ enabled: Bool, on canvasView: PKCanvasView) {
            guard enabled != isAISelectionMode else { return }
            isAISelectionMode = enabled
            selectionGesture?.isEnabled = enabled
            canvasView.panGestureRecognizer.isEnabled = !enabled

            if !enabled {
                clearSelection()
            } else {
                clearSelection()
                onAISelectionChanged?(nil)
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            isAISelectionMode
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
                clearSelection()
                displayPoints = [displayPoint]
                contentPoints = [contentPoint]
                updateSelectionPath()
            case .changed:
                displayPoints.append(displayPoint)
                contentPoints.append(contentPoint)
                updateSelectionPath()
            case .ended:
                displayPoints.append(displayPoints.first ?? displayPoint)
                contentPoints.append(contentPoints.first ?? contentPoint)
                updateSelectionPath(closed: true)
                publishSelection(in: canvasView)
            case .cancelled, .failed:
                clearSelection()
                onAISelectionChanged?(nil)
            default:
                break
            }
        }

        private func updateSelectionPath(closed: Bool = false) {
            guard let first = displayPoints.first else {
                selectionLayer.path = nil
                return
            }

            let path = UIBezierPath()
            path.move(to: first)
            displayPoints.dropFirst().forEach(path.addLine)
            if closed {
                path.close()
            }
            selectionLayer.path = path.cgPath
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

            onAISelectionChanged?(
                selection.width >= 20 && selection.height >= 20 ? selection : nil
            )
        }

        private func clearSelection() {
            displayPoints.removeAll()
            contentPoints.removeAll()
            selectionLayer.path = nil
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isLoadingDrawing else { return }
            let data = canvasView.drawing.dataRepresentation()
            loadedDrawingData = data
            onDrawingChanged?(data)
        }
    }
}
