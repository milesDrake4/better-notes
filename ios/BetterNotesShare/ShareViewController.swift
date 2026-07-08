import UIKit
import UniformTypeIdentifiers

@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private let icon = UIImageView(image: UIImage(systemName: "doc.badge.arrow.up"))
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let actionsStack = UIStackView()
    private let openButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private var pdfProvider: NSItemProvider?
    private var isSaving = false

    override func viewDidLoad() {
        super.viewDidLoad()
        configureInterface()
        findPDF()
    }

    private func configureInterface() {
        view.backgroundColor = .systemGroupedBackground
        preferredContentSize = CGSize(width: 640, height: 600)

        icon.tintColor = .systemBlue
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 42)

        titleLabel.text = "Import to BetterNotes"
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.textAlignment = .center

        statusLabel.text = "Preparing PDF..."
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        actionsStack.axis = .vertical
        actionsStack.spacing = 12
        actionsStack.translatesAutoresizingMaskIntoConstraints = false

        for role in SharedImportRole.allCases {
            let button = roleButton(for: role)
            actionsStack.addArrangedSubview(button)
        }

        var openConfiguration = UIButton.Configuration.filled()
        openConfiguration.title = "Open Better Notes"
        openConfiguration.image = UIImage(systemName: "arrow.up.forward.app")
        openConfiguration.imagePadding = 8
        openConfiguration.cornerStyle = .medium
        openButton.configuration = openConfiguration
        openButton.isHidden = true
        openButton.addTarget(self, action: #selector(openBetterNotes), for: .touchUpInside)

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            icon,
            titleLabel,
            statusLabel,
            actionsStack,
            openButton,
            cancelButton
        ])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            actionsStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            openButton.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func roleButton(for role: SharedImportRole) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = role.shareTitle
        configuration.subtitle = role.shareSubtitle
        configuration.image = UIImage(systemName: role.shareIcon)
        configuration.imagePadding = 8
        configuration.imagePlacement = .top
        configuration.titleAlignment = .center
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)
        configuration.cornerStyle = .medium
        configuration.baseBackgroundColor = role == .rubric ? .systemIndigo : .systemBlue
        button.configuration = configuration
        button.contentHorizontalAlignment = .center
        button.isEnabled = false
        button.titleLabel?.textAlignment = .center
        button.addAction(UIAction { [weak self] _ in
            self?.importPDF(role: role)
        }, for: .touchUpInside)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 86).isActive = true
        return button
    }

    private func findPDF() {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        pdfProvider = items
            .flatMap { $0.attachments ?? [] }
            .first { $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) }

        if pdfProvider == nil {
            statusLabel.text = "BetterNotes could not find a PDF in this share."
        } else {
            statusLabel.text = "Choose how Better Notes should use this PDF."
            setRoleButtonsEnabled(true)
        }
    }

    private func importPDF(role: SharedImportRole) {
        guard let pdfProvider, !isSaving else { return }
        let displayName = Self.normalizedPDFName(pdfProvider.suggestedName)
        isSaving = true
        setRoleButtonsEnabled(false)
        statusLabel.text = "Saving PDF as \(role.shareTitle.lowercased())..."

        pdfProvider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { [weak self] url, error in
            guard let self else { return }

            do {
                if let error {
                    throw error
                }
                guard let url else {
                    throw ShareImportError.missingPDF
                }

                try SharedImportInbox.enqueue(
                    fileAt: url,
                    displayName: displayName,
                    role: role
                )

                DispatchQueue.main.async {
                    self.showSavedState(for: role)
                    self.isSaving = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusLabel.text = error.localizedDescription
                    self.isSaving = false
                    self.setRoleButtonsEnabled(true)
                }
            }
        }
    }

    private func showSavedState(for role: SharedImportRole) {
        preferredContentSize = CGSize(width: 460, height: 300)
        titleLabel.text = "PDF Saved"
        statusLabel.text = "\(role.shareTitle) is ready. Open Better Notes to create and view the note."
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 34)
        actionsStack.isHidden = true
        openButton.isHidden = false
        cancelButton.setTitle("Done", for: .normal)
    }

    @objc private func openBetterNotes() {
        guard let url = URL(string: "betternotes://import") else {
            finish()
            return
        }

        extensionContext?.open(url) { [weak self] _ in
            DispatchQueue.main.async {
                self?.openContainingAppFallback(url)
            }
        }
    }

    private func openContainingAppFallback(_ url: URL) {
        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self

        while let currentResponder = responder {
            if currentResponder.responds(to: selector) {
                currentResponder.perform(selector, with: url)
                finish()
                return
            }

            responder = currentResponder.next
        }

        finish()
    }

    private func setRoleButtonsEnabled(_ isEnabled: Bool) {
        actionsStack.arrangedSubviews.forEach { view in
            (view as? UIButton)?.isEnabled = isEnabled
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    @objc private func cancel() {
        extensionContext?.cancelRequest(withError: ShareImportError.cancelled)
    }

    private static func normalizedPDFName(_ suggestedName: String?) -> String? {
        guard let suggestedName, !suggestedName.isEmpty else { return nil }
        return suggestedName.lowercased().hasSuffix(".pdf")
            ? suggestedName
            : "\(suggestedName).pdf"
    }
}

private extension SharedImportRole {
    var shareTitle: String {
        switch self {
        case .importAsIs: "Import As Is"
        case .homeworkContext: "Import as Homework Context"
        case .rubric: "Import as Rubric"
        }
    }

    var shareSubtitle: String {
        switch self {
        case .importAsIs: "Save with a blank note"
        case .homeworkContext: "Use as assignment questions for AI Lens"
        case .rubric: "Use as grading or solutions context"
        }
    }

    var shareIcon: String {
        switch self {
        case .importAsIs: "doc"
        case .homeworkContext: "square.and.pencil"
        case .rubric: "checkmark.seal"
        }
    }
}

private enum ShareImportError: LocalizedError {
    case missingPDF
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingPDF: "The shared PDF was unavailable."
        case .cancelled: "Import cancelled."
        }
    }
}
