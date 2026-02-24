// TB3 iOS — Token Manager (mirrors auth.ts token storage + refresh)
// Stores tokens in Keychain, handles refresh via Cognito OAuth2 endpoint.

import Foundation

struct UserInfo: Sendable {
    let email: String
    let userId: String
}

struct StoredTokens: Codable, Sendable {
    var idToken: String
    var accessToken: String
    var refreshToken: String
    var expiresAt: Double // milliseconds since epoch
}

actor TokenManager {
    private let cognitoDomain: String
    private let clientId: String

    private static let tokensKey = "tb3_auth_tokens"
    private static let lastAuthKey = "tb3_last_auth"

    init(cognitoDomain: String = AppConfig.cognitoDomain,
         clientId: String = AppConfig.cognitoClientId) {
        self.cognitoDomain = cognitoDomain
        self.clientId = clientId
    }

    // MARK: - Store / Load / Clear

    func storeTokens(_ tokens: StoredTokens) {
        if let data = try? JSONEncoder().encode(tokens) {
            try? Keychain.save(key: Self.tokensKey, data: data)
        }
        try? Keychain.saveString(key: Self.lastAuthKey, value: Date.iso8601Now())
    }

    func getStoredTokens() -> StoredTokens? {
        guard let data = try? Keychain.load(key: Self.tokensKey) else { return nil }
        return try? JSONDecoder().decode(StoredTokens.self, from: data)
    }

    func clearTokens() {
        Keychain.delete(key: Self.tokensKey)
    }

    // MARK: - Access Token (auto-check expiry)

    func getAccessToken() -> String? {
        guard let tokens = getStoredTokens() else { return nil }
        guard Date().timeIntervalSince1970 * 1000 < tokens.expiresAt else { return nil }
        return tokens.accessToken
    }

    func getIdToken() -> String? {
        getStoredTokens()?.idToken
    }

    // MARK: - Offline Grace Period

    func isWithinOfflineGrace() -> Bool {
        guard let lastAuthStr = Keychain.loadString(key: Self.lastAuthKey),
              let lastAuth = Date.fromISO8601(lastAuthStr) else { return false }
        let elapsed = Date().timeIntervalSince(lastAuth)
        return elapsed < Double(AppConfig.offlineGraceDays) * 24 * 60 * 60
    }

    // MARK: - Token Refresh (OAuth2 endpoint)

    /// Refresh tokens via Cognito /oauth2/token endpoint.
    /// Works for both email/password and Google OAuth users (mirrors refreshAccessToken in auth.ts).
    func refreshTokens() async -> String? {
        guard let tokens = getStoredTokens(), !tokens.refreshToken.isEmpty else { return nil }

        guard let url = URL(string: "\(cognitoDomain)/oauth2/token") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "refresh_token",
            "client_id": clientId,
            "refresh_token": tokens.refreshToken,
        ]
        request.httpBody = body
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let idToken = json?["id_token"] as? String,
                  let accessToken = json?["access_token"] as? String,
                  let expiresIn = json?["expires_in"] as? Double else {
                return nil
            }

            let newTokens = StoredTokens(
                idToken: idToken,
                accessToken: accessToken,
                refreshToken: tokens.refreshToken, // refresh token doesn't rotate
                expiresAt: Date().timeIntervalSince1970 * 1000 + expiresIn * 1000
            )

            storeTokens(newTokens)
            return accessToken
        } catch {
            return nil
        }
    }

    // MARK: - Store Tokens from OAuth Code Exchange

    func storeFromOAuthResponse(data: [String: Any], refreshToken: String? = nil) -> UserInfo? {
        guard let idToken = data["id_token"] as? String,
              let accessToken = data["access_token"] as? String,
              let expiresIn = data["expires_in"] as? Double else {
            return nil
        }

        let actualRefreshToken = (data["refresh_token"] as? String) ?? refreshToken ?? ""

        let tokens = StoredTokens(
            idToken: idToken,
            accessToken: accessToken,
            refreshToken: actualRefreshToken,
            expiresAt: Date().timeIntervalSince1970 * 1000 + expiresIn * 1000
        )

        storeTokens(tokens)

        // Parse JWT to get user info
        guard let payload = parseJwt(idToken) else { return nil }
        let email = payload["email"] as? String ?? ""
        let userId = payload["sub"] as? String ?? ""
        return UserInfo(email: email, userId: userId)
    }

    // MARK: - JWT Parsing

    nonisolated func parseJwt(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Pad to multiple of 4
        while base64.count % 4 != 0 {
            base64.append("=")
        }

        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
