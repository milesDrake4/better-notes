import Foundation
import Security

struct BetterNotesAuthUser: Codable, Equatable {
    let id: String
    let email: String?
}

struct BetterNotesAuthSession: Codable, Equatable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let expiresAt: Date?
    let tokenType: String?
    let user: BetterNotesAuthUser?
    let message: String?

    var isSignedIn: Bool {
        hasRecoverableCredentials && user != nil
    }

    var hasRecoverableCredentials: Bool {
        isAccessTokenUsable || refreshToken?.isEmpty == false
    }

    var isAccessTokenUsable: Bool {
        guard accessToken?.isEmpty == false else { return false }
        guard let expiresAt else { return true }
        return expiresAt > Date().addingTimeInterval(60)
    }

    func withUpdatedExpiry() -> BetterNotesAuthSession {
        BetterNotesAuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresIn: expiresIn,
            expiresAt: expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) } ?? expiresAt,
            tokenType: tokenType,
            user: user,
            message: message
        )
    }
}

enum BetterNotesDevice {
    static func appInstallID() -> String {
        let key = "BetterNotes.installID"
        if let existingID = UserDefaults.standard.string(forKey: key), !existingID.isEmpty {
            return existingID
        }

        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: key)
        return newID
    }
}

enum BetterNotesAuthSessionStorage {
    private static let legacyStorageKey = "BetterNotes.authSession"
    private static let keychainService = "com.milesdrake.betternotes.auth"
    private static let keychainAccount = "supabase-session"

    static func currentAccessToken() -> String? {
        savedSession()?.isAccessTokenUsable == true ? savedSession()?.accessToken : nil
    }

    static func currentAccessToken(serverAddress: String) async -> String? {
        guard let session = savedSession() else { return nil }
        if session.isAccessTokenUsable {
            return session.accessToken
        }

        guard let refreshToken = session.refreshToken, !refreshToken.isEmpty else {
            saveSession(nil)
            return nil
        }

        do {
            let refreshedSession = try await BetterNotesAuthClient.refresh(
                serverAddress: serverAddress,
                refreshToken: refreshToken
            )
            saveSession(refreshedSession.isSignedIn ? refreshedSession : nil)
            return refreshedSession.isSignedIn ? refreshedSession.accessToken : nil
        } catch {
            if BetterNotesAuthClient.shouldClearSession(after: error) {
                saveSession(nil)
            }
            return nil
        }
    }

    static func savedSession() -> BetterNotesAuthSession? {
        if let data = keychainData() {
            return try? JSONDecoder().decode(BetterNotesAuthSession.self, from: data)
        }

        guard let data = UserDefaults.standard.data(forKey: legacyStorageKey),
              let legacySession = try? JSONDecoder().decode(BetterNotesAuthSession.self, from: data)
        else {
            return nil
        }

        saveSession(legacySession)
        UserDefaults.standard.removeObject(forKey: legacyStorageKey)
        return legacySession
    }

    static func saveSession(_ session: BetterNotesAuthSession?) {
        UserDefaults.standard.removeObject(forKey: legacyStorageKey)
        deleteKeychainSession()

        guard let session, let data = try? JSONEncoder().encode(session.withUpdatedExpiry()) else {
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func keychainData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func deleteKeychainSession() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
final class BetterNotesAuthStore: ObservableObject {
    @Published private(set) var session: BetterNotesAuthSession?
    @Published var statusMessage: String?
    @Published var isWorking = false
    @Published private(set) var isCheckingSession = false

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

    var shouldShowSessionLoading: Bool {
        isCheckingSession && session?.hasRecoverableCredentials == true
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

    func refreshSessionIfNeeded() async {
        guard let currentSession = session else { return }
        if currentSession.isAccessTokenUsable { return }

        guard let refreshToken = currentSession.refreshToken, !refreshToken.isEmpty else {
            session = nil
            BetterNotesAuthSessionStorage.saveSession(nil)
            statusMessage = "Sign in again to continue."
            return
        }

        isCheckingSession = true
        defer { isCheckingSession = false }

        do {
            let refreshedSession = try await BetterNotesAuthClient.refresh(
                serverAddress: serverAddress,
                refreshToken: refreshToken
            )
            session = refreshedSession
            BetterNotesAuthSessionStorage.saveSession(refreshedSession.isSignedIn ? refreshedSession : nil)
        } catch {
            if BetterNotesAuthClient.shouldClearSession(after: error) {
                session = nil
                BetterNotesAuthSessionStorage.saveSession(nil)
                statusMessage = "Sign in again to continue."
            } else {
                statusMessage = "Could not refresh your session. Better Notes will try again when the connection improves."
            }
        }
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
            let normalizedResponse = response.withUpdatedExpiry()
            session = normalizedResponse
            BetterNotesAuthSessionStorage.saveSession(normalizedResponse.isSignedIn ? normalizedResponse : nil)
            statusMessage = normalizedResponse.message ?? "Signed in as \(normalizedResponse.user?.email ?? email)."
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

    static func refresh(serverAddress: String, refreshToken: String) async throws -> BetterNotesAuthSession {
        let session: BetterNotesAuthSession = try await request(
            serverAddress: serverAddress,
            path: "/api/auth/refresh",
            method: "POST",
            accessToken: nil,
            body: RefreshCredentials(refreshToken: refreshToken)
        )
        return session.withUpdatedExpiry()
    }

    static func accountUsage(serverAddress: String, accessToken: String?) async throws -> AccountUsageSummary {
        try await request(
            serverAddress: serverAddress,
            path: "/api/account/usage",
            method: "GET",
            accessToken: accessToken,
            body: Optional<EmptyAuthRequest>.none
        )
    }

    static func accountProfile(serverAddress: String, accessToken: String?) async throws -> AccountProfile {
        try await request(
            serverAddress: serverAddress,
            path: "/api/account/profile",
            method: "GET",
            accessToken: accessToken,
            body: Optional<EmptyAuthRequest>.none
        )
    }

    static func updateAccountProfile(
        serverAddress: String,
        accessToken: String?,
        didCompleteClassSetup: Bool
    ) async throws -> AccountProfile {
        try await request(
            serverAddress: serverAddress,
            path: "/api/account/profile",
            method: "POST",
            accessToken: accessToken,
            body: AccountProfileUpdate(didCompleteClassSetup: didCompleteClassSetup)
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
        body: RequestBody?
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
        request.setValue(BetterNotesDevice.appInstallID(), forHTTPHeaderField: "X-BetterNotes-Install-ID")

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(AuthErrorResponse.self, from: data).error)
                ?? "BetterNotes could not sign you in."
            throw AuthError.server(statusCode: httpResponse.statusCode, message: message)
        }

        return try JSONDecoder().decode(ResponseBody.self, from: data)
    }

    static func shouldClearSession(after error: Error) -> Bool {
        guard case AuthError.server(let statusCode, _) = error else {
            return false
        }

        return statusCode == 400 || statusCode == 401 || statusCode == 403
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

private struct RefreshCredentials: Encodable {
    let refreshToken: String
}

private struct EmptyAuthRequest: Encodable {}

private struct AccountProfileUpdate: Encodable {
    let didCompleteClassSetup: Bool
}

struct LogoutResponse: Decodable {
    let ok: Bool
}

struct AccountUsageSummary: Decodable, Equatable {
    let email: String?
    let freeScanLimit: Int
    let usedScans: Int
    let remainingScans: Int
    let plan: String
    let backendStatus: String
    let aiConfigured: Bool
    let authConfigured: Bool
    let databaseReady: Bool
}

struct AccountProfile: Decodable, Equatable {
    let email: String?
    let didCompleteClassSetup: Bool
    let databaseReady: Bool
}

private struct AuthErrorResponse: Decodable {
    let error: String
}

private enum AuthError: LocalizedError {
    case invalidServerAddress
    case invalidResponse
    case server(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidServerAddress:
            "Enter a valid BetterNotes server address."
        case .invalidResponse:
            "BetterNotes returned an unreadable auth response."
        case .server(_, let message):
            message
        }
    }
}
