import Foundation

struct PendingSharedImport: Identifiable, Codable, Hashable {
    var id: UUID
    var displayName: String
    var storedFileName: String
    var createdAt: Date
    var role: SharedImportRole

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case storedFileName
        case createdAt
        case role
    }

    init(
        id: UUID = UUID(),
        displayName: String,
        storedFileName: String,
        createdAt: Date = .now,
        role: SharedImportRole
    ) {
        self.id = id
        self.displayName = displayName
        self.storedFileName = storedFileName
        self.createdAt = createdAt
        self.role = role
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        storedFileName = try container.decode(String.self, forKey: .storedFileName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        role = try container.decodeIfPresent(SharedImportRole.self, forKey: .role) ?? .homeworkContext
    }
}

enum SharedImportRole: String, Codable, CaseIterable, Identifiable {
    case importAsIs
    case homeworkContext
    case rubric

    var id: Self { self }
}

enum SharedImportInbox {
    static let appGroupIdentifier = "group.com.milesdrake.betternotes"
    private static let storageKey = "BetterNotes.pendingSharedImports.v1"

    static func enqueue(
        fileAt sourceURL: URL,
        displayName: String? = nil,
        role: SharedImportRole
    ) throws {
        let directory = try inboxDirectory()
        let fileExtension = sourceURL.pathExtension.isEmpty ? "pdf" : sourceURL.pathExtension
        let storedFileName = "\(UUID().uuidString).\(fileExtension)"
        let destinationURL = directory.appendingPathComponent(storedFileName)

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        var imports = pendingImports()
        imports.append(
            PendingSharedImport(
                displayName: displayName ?? sourceURL.lastPathComponent,
                storedFileName: storedFileName,
                role: role
            )
        )
        save(imports)
    }

    static func pendingImports() -> [PendingSharedImport] {
        guard
            let defaults = UserDefaults(suiteName: appGroupIdentifier),
            let data = defaults.data(forKey: storageKey),
            let imports = try? JSONDecoder().decode([PendingSharedImport].self, from: data)
        else {
            return []
        }
        return imports.sorted { $0.createdAt < $1.createdAt }
    }

    static func fileURL(for item: PendingSharedImport) throws -> URL {
        try inboxDirectory().appendingPathComponent(item.storedFileName)
    }

    static func remove(_ item: PendingSharedImport) {
        if let url = try? fileURL(for: item) {
            try? FileManager.default.removeItem(at: url)
        }
        save(pendingImports().filter { $0.id != item.id })
    }

    private static func save(_ imports: [PendingSharedImport]) {
        guard
            let defaults = UserDefaults(suiteName: appGroupIdentifier),
            let data = try? JSONEncoder().encode(imports)
        else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func inboxDirectory() throws -> URL {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw SharedImportError.appGroupUnavailable
        }

        let directory = container.appendingPathComponent("PendingPDFImports", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}

enum SharedImportError: LocalizedError {
    case appGroupUnavailable

    var errorDescription: String? {
        "BetterNotes could not access its shared import folder."
    }
}
