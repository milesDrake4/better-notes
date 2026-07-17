import Foundation

struct BetterNotesAuthUser: Codable, Equatable {
    let id: String
    let email: String?
}

struct BetterNotesAuthSession: Codable, Equatable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let tokenType: String?
    let user: BetterNotesAuthUser?
    let message: String?

    var isSignedIn: Bool {
        accessToken?.isEmpty == false && user != nil
    }
}

enum BetterNotesAuthSessionStorage {
    private static let storageKey = "BetterNotes.authSession"

    static func currentAccessToken() -> String? {
        savedSession()?.accessToken
    }

    static func savedSession() -> BetterNotesAuthSession? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(BetterNotesAuthSession.self, from: data)
    }

    static func saveSession(_ session: BetterNotesAuthSession?) {
        if let session, let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
    }
}

@MainActor
final class BetterNotesAuthStore: ObservableObject {
    @Published private(set) var session: BetterNotesAuthSession?
    @Published var statusMessage: String?
    @Published var isWorking = false

    private let serverAddress: String

    init(serverAddress: String) {
        self.serverAddress = serverAddress
        self.session = BetterNotesAuthSessionStorage.savedSession()
    }

    var isSignedIn: Bool {
        session?.isSignedIn == true
    }

    var email: String? {
        session?.user?.email
    }

    func signUp(email: String, password: String) async {
        await authenticate(path: "/api/auth/signup", email: email, password: password)
    }

    func signIn(email: String, password: String) async {
        await authenticate(path: "/api/auth/login", email: email, password: password)
    }

    func signOut() async {
        isWorking = true
        defer { isWorking = false }

        do {
            _ = try await BetterNotesAuthClient.logout(
                serverAddress: serverAddress,
                accessToken: session?.accessToken
            )
        } catch {
            statusMessage = error.localizedDescription
        }

        session = nil
        BetterNotesAuthSessionStorage.saveSession(nil)
        statusMessage = "Signed out."
    }

    private func authenticate(path: String, email: String, password: String) async {
        isWorking = true
        statusMessage = nil
        defer { isWorking = false }

        do {
            let response = try await BetterNotesAuthClient.authenticate(
                serverAddress: serverAddress,
                path: path,
                email: email,
                password: password
            )
            session = response
            BetterNotesAuthSessionStorage.saveSession(response.isSignedIn ? response : nil)
            statusMessage = response.message ?? "Signed in as \(response.user?.email ?? email)."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

enum BetterNotesAuthClient {
    static func authenticate(
        serverAddress: String,
        path: String,
        email: String,
        password: String
    ) async throws -> BetterNotesAuthSession {
        try await request(
            serverAddress: serverAddress,
            path: path,
            method: "POST",
            accessToken: nil,
            body: AuthCredentials(email: email, password: password)
        )
    }

    static func logout(serverAddress: String, accessToken: String?) async throws -> LogoutResponse {
        try await request(
            serverAddress: serverAddress,
            path: "/api/auth/logout",
            method: "POST",
            accessToken: accessToken,
            body: EmptyAuthRequest()
        )
    }

    private static func request<RequestBody: Encodable, ResponseBody: Decodable>(
        serverAddress: String,
        path: String,
        method: String,
        accessToken: String?,
        body: RequestBody
    ) async throws -> ResponseBody {
        guard let baseURL = normalizedBaseURL(from: serverAddress) else {
            throw AuthError.invalidServerAddress
        }

        guard let requestURL = endpointURL(baseURL: baseURL, path: path) else {
            throw AuthError.invalidServerAddress
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let accessToken, !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(AuthErrorResponse.self, from: data).error)
                ?? "BetterNotes could not sign you in."
            throw AuthError.server(message)
        }

        return try JSONDecoder().decode(ResponseBody.self, from: data)
    }

    private static func normalizedBaseURL(from serverAddress: String) -> URL? {
        let trimmed = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let address = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        return URL(string: address)
    }

    private static func endpointURL(baseURL: URL, path: String) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let basePath = components?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let endpointPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let joinedPath = [basePath, endpointPath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components?.path = "/\(joinedPath)"
        return components?.url
    }
}

private struct AuthCredentials: Encodable {
    let email: String
    let password: String
}

private struct EmptyAuthRequest: Encodable {}

struct LogoutResponse: Decodable {
    let ok: Bool
}

private struct AuthErrorResponse: Decodable {
    let error: String
}

private enum AuthError: LocalizedError {
    case invalidServerAddress
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerAddress:
            "Enter a valid BetterNotes server address."
        case .invalidResponse:
            "BetterNotes returned an unreadable auth response."
        case .server(let message):
            message
        }
    }
}
