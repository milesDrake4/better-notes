import Foundation
import SwiftUI

enum NoteTemplate: String, Codable, CaseIterable, Identifiable {
    case blank
    case homework
    case practiceExam

    var id: Self { self }

    var title: String {
        switch self {
        case .blank: "Blank note"
        case .homework: "Homework"
        case .practiceExam: "Practice exam"
        }
    }

    var icon: String {
        switch self {
        case .blank: "doc"
        case .homework: "square.and.pencil"
        case .practiceExam: "checklist"
        }
    }
}

enum AttachmentKind: String, Codable {
    case importedPDF
    case homeworkSet
    case exam
    case rubric

    var title: String {
        switch self {
        case .importedPDF: "Imported PDF"
        case .homeworkSet: "Homework Set"
        case .exam: "Exam"
        case .rubric: "Exam Rubric"
        }
    }
}

struct NoteAttachment: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: AttachmentKind
    var displayName: String
    var storedFileName: String
}

struct ClassFolder: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var notes: [StudyNote]
}

struct StudyNote: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    var colorHex: String
    var template: NoteTemplate
    var drawingData: Data?
    var attachments: [NoteAttachment]

    var color: Color {
        Color(hex: colorHex)
    }
}

@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var folders: [ClassFolder] = []

    private let storageKey = "BetterNotes.library.v1"

    init() {
        load()
    }

    func createFolder(named name: String) -> ClassFolder {
        let folder = ClassFolder(name: name, notes: [])
        folders.append(folder)
        save()
        return folder
    }

    func renameFolder(id: UUID, to name: String) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].name = name
        save()
    }

    func deleteFolder(id: UUID) {
        folders.removeAll { $0.id == id }
        save()
    }

    func createNote(
        in folderID: UUID,
        template: NoteTemplate,
        attachments: [NoteAttachment] = []
    ) -> StudyNote? {
        guard let folderIndex = folders.firstIndex(where: { $0.id == folderID }) else { return nil }

        let noteCount = folders.flatMap(\.notes).count
        let note = StudyNote(
            title: defaultTitle(for: template),
            createdAt: .now,
            modifiedAt: .now,
            colorHex: noteColors[noteCount % noteColors.count],
            template: template,
            drawingData: nil,
            attachments: attachments
        )

        folders[folderIndex].notes.append(note)
        save()
        return note
    }

    func renameNote(id: UUID, in folderID: UUID, to title: String) {
        updateNote(id: id, in: folderID) { note in
            note.title = title
            note.modifiedAt = .now
        }
    }

    func saveDrawing(_ data: Data, noteID: UUID, folderID: UUID) {
        updateNote(id: noteID, in: folderID) { note in
            note.drawingData = data
            note.modifiedAt = .now
        }
    }

    func deleteNote(id: UUID, from folderID: UUID) {
        guard let folderIndex = folders.firstIndex(where: { $0.id == folderID }) else { return }
        if let note = folders[folderIndex].notes.first(where: { $0.id == id }) {
            note.attachments.forEach(AttachmentStorage.delete)
        }
        folders[folderIndex].notes.removeAll { $0.id == id }
        save()
    }

    func folder(id: UUID?) -> ClassFolder? {
        guard let id else { return folders.first }
        return folders.first { $0.id == id }
    }

    func note(id: UUID, in folderID: UUID) -> StudyNote? {
        folder(id: folderID)?.notes.first { $0.id == id }
    }

    private func updateNote(id: UUID, in folderID: UUID, change: (inout StudyNote) -> Void) {
        guard
            let folderIndex = folders.firstIndex(where: { $0.id == folderID }),
            let noteIndex = folders[folderIndex].notes.firstIndex(where: { $0.id == id })
        else { return }

        change(&folders[folderIndex].notes[noteIndex])
        save()
    }

    private func defaultTitle(for template: NoteTemplate) -> String {
        switch template {
        case .blank: "Untitled Note"
        case .homework: "Homework"
        case .practiceExam: "Practice Exam"
        }
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([ClassFolder].self, from: data)
        else {
            folders = Self.starterFolders
            return
        }

        folders = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static let starterFolders: [ClassFolder] = [
        ClassFolder(name: "Calculus", notes: []),
        ClassFolder(name: "Chemistry", notes: []),
        ClassFolder(name: "History", notes: [])
    ]
}

enum AttachmentStorage {
    static let maxAttachmentBytes = 20 * 1024 * 1024

    static func importFile(from sourceURL: URL, kind: AttachmentKind) throws -> NoteAttachment {
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let directory = try attachmentsDirectory()
        let fileExtension = sourceURL.pathExtension
        let storedFileName = fileExtension.isEmpty
            ? UUID().uuidString
            : "\(UUID().uuidString).\(fileExtension)"
        let destinationURL = directory.appendingPathComponent(storedFileName)

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return NoteAttachment(
            kind: kind,
            displayName: sourceURL.lastPathComponent,
            storedFileName: storedFileName
        )
    }

    static func delete(_ attachment: NoteAttachment) {
        guard let directory = try? attachmentsDirectory() else { return }
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent(attachment.storedFileName)
        )
    }

    static func fileURL(for attachment: NoteAttachment) throws -> URL {
        try attachmentsDirectory().appendingPathComponent(attachment.storedFileName)
    }

    private static func attachmentsDirectory() throws -> URL {
        let baseDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseDirectory.appendingPathComponent("BetterNotesAttachments", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}

private let noteColors = [
    "#19BFE5",
    "#FF9238",
    "#7357E8",
    "#2FC989",
    "#F05A7E",
    "#F0C23E",
    "#3977E8",
    "#D45CD6"
]

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt64(cleaned, radix: 16) ?? 0
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

extension StudyNote {
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt
        case modifiedAt
        case colorHex
        case template
        case drawingData
        case attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        template = try container.decode(NoteTemplate.self, forKey: .template)
        drawingData = try container.decodeIfPresent(Data.self, forKey: .drawingData)
        attachments = try container.decodeIfPresent([NoteAttachment].self, forKey: .attachments) ?? []
    }
}
