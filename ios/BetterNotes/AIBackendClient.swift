import Foundation
import PencilKit
import UIKit

struct AIBackendHealth: Decodable {
    let status: String
    let aiConfigured: Bool
    let model: String
}

struct AIFeedback: Codable, Hashable {
    let title: String
    let body: String
    let nextStep: String
}

struct AIScanResult {
    let transcription: String
    let feedback: AIFeedback
}

enum AIBackendClient {
    static func health(serverAddress: String) async throws -> AIBackendHealth {
        try await request(
            serverAddress: serverAddress,
            path: "/api/health",
            method: "GET",
            body: Optional<EmptyRequest>.none
        )
    }

    static func scanDrawing(
        drawingData: Data?,
        selectionBounds: CGRect?,
        mode: AIInteractionMode,
        focus: String,
        noteTemplate: NoteTemplate,
        attachments: [NoteAttachment],
        chatMessages: [AIChatMessage] = [],
        serverAddress: String
    ) async throws -> AIScanResult {
        let image = try drawingImageDataURL(from: drawingData, selectionBounds: selectionBounds)
        let context = try noteContext(from: attachments)
        let transcription: TranscriptionResponse = try await request(
            serverAddress: serverAddress,
            path: "/api/ai-transcribe",
            method: "POST",
            body: TranscriptionRequest(
                image: image,
                scope: selectionBounds == nil ? "full page" : "lasso selection"
            )
        )

        let feedback: AIFeedback = try await request(
            serverAddress: serverAddress,
            path: "/api/ai-feedback",
            method: "POST",
            body: FeedbackRequest(
                transcription: transcription.transcription,
                mode: mode.rawValue,
                prompt: focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? mode.defaultPrompt
                    : focus,
                noteType: noteTemplate.rawValue,
                noteContextFiles: context.assignmentFiles,
                noteContextImages: context.assignmentImages,
                referenceFiles: context.referenceFiles,
                referenceImages: context.referenceImages,
                chatMessages: chatMessages
            )
        )

        return AIScanResult(transcription: transcription.transcription, feedback: feedback)
    }

    static func askFollowUp(
        drawingData: Data?,
        question: String,
        mode: AIInteractionMode,
        transcription: String?,
        latestFeedback: AIFeedback?,
        chatMessages: [AIChatMessage],
        noteTemplate: NoteTemplate,
        attachments: [NoteAttachment],
        serverAddress: String
    ) async throws -> String {
        let notePageImage = try? drawingImageDataURL(from: drawingData, selectionBounds: nil)
        let context = try noteContext(from: attachments)

        let response: FollowUpResponse = try await request(
            serverAddress: serverAddress,
            path: "/api/ai-followup",
            method: "POST",
            body: FollowUpRequest(
                question: question,
                mode: mode.rawValue,
                transcription: transcription,
                latestFeedback: latestFeedback,
                chatMessages: chatMessages,
                noteType: noteTemplate.rawValue,
                noteContextFiles: context.assignmentFiles,
                noteContextImages: context.assignmentImages,
                referenceFiles: context.referenceFiles,
                referenceImages: context.referenceImages,
                notePageImage: notePageImage
            )
        )

        return response.reply
    }

    private static func request<RequestBody: Encodable, ResponseBody: Decodable>(
        serverAddress: String,
        path: String,
        method: String,
        body: RequestBody?
    ) async throws -> ResponseBody {
        guard let baseURL = normalizedBaseURL(from: serverAddress) else {
            throw AIBackendError.invalidServerAddress
        }

        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var request = URLRequest(url: baseURL.appendingPathComponent(cleanPath))
        request.httpMethod = method
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(BetterNotesDevice.appInstallID(), forHTTPHeaderField: "X-BetterNotes-Install-ID")
        if let accessToken = BetterNotesAuthSessionStorage.currentAccessToken(), !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIBackendError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data).error)
                ?? "The BetterNotes server returned an error."
            throw AIBackendError.server(message)
        }

        return try JSONDecoder().decode(ResponseBody.self, from: data)
    }

    private static func normalizedBaseURL(from serverAddress: String) -> URL? {
        let trimmed = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let address = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        return URL(string: address)
    }

    private static func drawingImageDataURL(
        from drawingData: Data?,
        selectionBounds: CGRect?
    ) throws -> String {
        guard
            let drawingData,
            let drawing = try? PKDrawing(data: drawingData),
            !drawing.strokes.isEmpty
        else {
            throw AIBackendError.emptyPage
        }

        let pageBounds = CGRect(x: 0, y: 0, width: 1600, height: 2200)
        let renderBounds = selectionBounds?.intersection(pageBounds) ?? pageBounds
        guard !renderBounds.isEmpty else {
            throw AIBackendError.emptySelection
        }

        let scale = min(1, 1400 / max(renderBounds.width, renderBounds.height))
        let outputSize = CGSize(
            width: max(1, renderBounds.width * scale),
            height: max(1, renderBounds.height * scale)
        )
        let renderer = UIGraphicsImageRenderer(size: outputSize)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: outputSize))

            let renderedDrawing = drawing.image(from: renderBounds, scale: scale)
            renderedDrawing.draw(in: CGRect(origin: .zero, size: outputSize))
        }

        guard let pngData = image.pngData() else {
            throw AIBackendError.imageEncodingFailed
        }
        return "data:image/png;base64,\(pngData.base64EncodedString())"
    }

    private static func noteContext(from attachments: [NoteAttachment]) throws -> NoteContextPayload {
        var context = NoteContextPayload()
        var totalBytes = 0

        for attachment in attachments {
            let url = try AttachmentStorage.fileURL(for: attachment)
            let data = try Data(contentsOf: url)
            totalBytes += data.count

            if data.count > AttachmentStorage.maxAttachmentBytes || totalBytes > AttachmentStorage.maxAttachmentBytes * 2 {
                throw AIBackendError.attachmentTooLarge
            }

            let lowercasedExtension = url.pathExtension.lowercased()
            switch lowercasedExtension {
            case "pdf":
                let file = AIContextFile(
                    filename: attachment.displayName,
                    fileData: "data:application/pdf;base64,\(data.base64EncodedString())"
                )
                if attachment.kind == .rubric {
                    context.referenceFiles.append(file)
                } else if attachment.kind == .homeworkSet || attachment.kind == .exam {
                    context.assignmentFiles.append(file)
                }
            case "png", "jpg", "jpeg", "heic", "heif":
                let image = try imageDataURL(from: data, fileExtension: lowercasedExtension)
                if attachment.kind == .rubric {
                    context.referenceImages.append(image)
                } else if attachment.kind == .homeworkSet || attachment.kind == .exam {
                    context.assignmentImages.append(image)
                }
            default:
                continue
            }
        }

        return context
    }

    private static func imageDataURL(from data: Data, fileExtension: String) throws -> String {
        let mimeType: String
        switch fileExtension {
        case "jpg", "jpeg":
            mimeType = "image/jpeg"
        case "heic", "heif":
            guard
                let image = UIImage(data: data),
                let jpegData = image.jpegData(compressionQuality: 0.9)
            else {
                throw AIBackendError.imageEncodingFailed
            }
            return "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
        default:
            mimeType = "image/png"
        }

        return "data:\(mimeType);base64,\(data.base64EncodedString())"
    }
}

private struct EmptyRequest: Encodable {}

private struct TranscriptionRequest: Encodable {
    let image: String
    let scope: String
}

private struct TranscriptionResponse: Decodable {
    let transcription: String
}

private struct FeedbackRequest: Encodable {
    let transcription: String
    let mode: String
    let prompt: String
    let noteType: String
    let noteContextFiles: [AIContextFile]
    let noteContextImages: [String]
    let referenceFiles: [AIContextFile]
    let referenceImages: [String]
    let chatMessages: [AIChatMessage]
}

private struct FollowUpRequest: Encodable {
    let question: String
    let mode: String
    let transcription: String?
    let latestFeedback: AIFeedback?
    let chatMessages: [AIChatMessage]
    let noteType: String
    let noteContextFiles: [AIContextFile]
    let noteContextImages: [String]
    let referenceFiles: [AIContextFile]
    let referenceImages: [String]
    let notePageImage: String?
}

private struct FollowUpResponse: Decodable {
    let reply: String
}

private struct NoteContextPayload {
    var assignmentFiles: [AIContextFile] = []
    var assignmentImages: [String] = []
    var referenceFiles: [AIContextFile] = []
    var referenceImages: [String] = []
}

private struct AIContextFile: Encodable {
    let filename: String
    let fileData: String

    private enum CodingKeys: String, CodingKey {
        case filename
        case fileData = "fileData"
    }
}

private struct ErrorResponse: Decodable {
    let error: String
}

enum AIBackendError: LocalizedError {
    case invalidServerAddress
    case invalidResponse
    case emptyPage
    case emptySelection
    case imageEncodingFailed
    case attachmentTooLarge
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerAddress:
            "Enter a valid BetterNotes server address."
        case .invalidResponse:
            "The BetterNotes server returned an unreadable response."
        case .emptyPage:
            "Write something on the page before scanning it."
        case .emptySelection:
            "Draw a larger loop around the work you want to scan."
        case .imageEncodingFailed:
            "BetterNotes could not prepare the page image."
        case .attachmentTooLarge:
            "The attached assignment is too large for this prototype AI scan. Try a smaller PDF or scan without context."
        case .server(let message):
            message
        }
    }
}
