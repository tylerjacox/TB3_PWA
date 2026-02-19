// TB3 iOS — Spotify Service (OAuth + Web API playback control)
// Handles connect/disconnect, token exchange via backend proxy, and now-playing polling.

import Foundation
import AuthenticationServices
import CryptoKit

enum SpotifyError: LocalizedError {
    case unauthorized
    case sessionExpired
    case rateLimited
    case networkError
    case apiError(String)
    case premiumRequired

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Spotify authorization failed."
        case .sessionExpired: return "Spotify session expired. Please reconnect in Settings."
        case .rateLimited: return "Spotify is busy. Please try again later."
        case .networkError: return "No internet connection."
        case .apiError(let msg): return msg
        case .premiumRequired: return "Spotify Premium is required for playback control."
        }
    }
}

@MainActor
final class SpotifyService: NSObject {
    private let spotifyState: SpotifyState
    private let tokenManager: SpotifyTokenManager

    private var authSession: ASWebAuthenticationSession?
    private var codeVerifier: String?

    // Polling
    private var pollTimer: Timer?
    private var isPolling = false

    init(spotifyState: SpotifyState, tokenManager: SpotifyTokenManager) {
        self.spotifyState = spotifyState
        self.tokenManager = tokenManager
    }

    // MARK: - Restore Connection (app launch)

    func restoreConnection() async {
        if let tokens = await tokenManager.getStoredTokens() {
            spotifyState.isConnected = true
            spotifyState.userName = tokens.userName
        }
    }

    // MARK: - Connect (OAuth PKCE Flow)

    func connect() async throws {
        spotifyState.isLoading = true

        // Generate PKCE code verifier + challenge
        let verifier = generateCodeVerifier()
        codeVerifier = verifier
        let challenge = generateCodeChallenge(from: verifier)

        var components = URLComponents(string: AppConfig.spotifyAuthURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: AppConfig.spotifyClientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: AppConfig.spotifyCallbackURL),
            URLQueryItem(name: "scope", value: "user-read-playback-state user-modify-playback-state user-read-currently-playing user-library-read user-library-modify"),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
        ]

        guard let authorizeURL = components.url else {
            spotifyState.isLoading = false
            throw SpotifyError.apiError("Failed to build Spotify authorization URL")
        }

        let callbackURL: URL
        do {
            callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(
                    url: authorizeURL,
                    callbackURLScheme: AppConfig.spotifyCallbackScheme
                ) { [weak self] url, error in
                    self?.authSession = nil
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: SpotifyError.apiError("No callback URL received"))
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                self.authSession = session
                session.start()
            }
        } catch {
            spotifyState.isLoading = false
            if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                return
            }
            throw error
        }

        // Extract authorization code from callback
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            spotifyState.isLoading = false
            throw SpotifyError.apiError("No authorization code received from Spotify")
        }

        try await exchangeCode(code)
        spotifyState.isLoading = false
        spotifyState.needsReauth = false
    }

    private func exchangeCode(_ code: String) async throws {
        guard let url = URL(string: AppConfig.spotifyTokenProxyURL) else {
            throw SpotifyError.apiError("Invalid token proxy URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": AppConfig.spotifyCallbackURL,
        ]
        if let verifier = codeVerifier {
            body["code_verifier"] = verifier
        }
        codeVerifier = nil

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SpotifyError.apiError("Token exchange failed")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String else {
            throw SpotifyError.apiError("Invalid token response from Spotify")
        }

        let expiresIn = (json["expires_in"] as? Double) ?? 3600

        // Fetch user profile to get display name
        let userName = await fetchUserName(accessToken: accessToken)

        let tokens = SpotifyTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().timeIntervalSince1970 + expiresIn,
            userName: userName
        )

        await tokenManager.storeTokens(tokens)
        spotifyState.isConnected = true
        spotifyState.userName = userName
    }

    private func fetchUserName(accessToken: String) async -> String? {
        guard let url = URL(string: "\(AppConfig.spotifyAPIBaseURL)/me") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return json["display_name"] as? String
    }

    // MARK: - Disconnect

    func disconnect() async {
        await tokenManager.clearTokens()
        spotifyState.isConnected = false
        spotifyState.userName = nil
        spotifyState.nowPlaying = nil
        stopPolling()
    }

    // MARK: - Now Playing (Polling)

    func startPolling() {
        guard spotifyState.isConnected, !isPolling else { return }
        isPolling = true
        // Fetch immediately, then every 10 seconds
        Task { await fetchNowPlaying() }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchNowPlaying()
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        isPolling = false
    }

    func fetchNowPlaying() async {
        guard let accessToken = await tokenManager.getValidAccessToken() else {
            if spotifyState.nowPlaying != nil { spotifyState.nowPlaying = nil }
            return
        }

        // Do network + parsing off main thread
        let result = await Task.detached { [weak self] () -> SpotifyNowPlaying? in
            return await self?.fetchAndParseNowPlaying(accessToken: accessToken)
        }.value

        // Back on main actor — only update if changed
        if let newNP = result {
            // Preserve isLiked from current state if same track
            let sameTrack = spotifyState.nowPlaying?.trackId == newNP.trackId
            let previousLiked = sameTrack ? spotifyState.nowPlaying?.isLiked ?? false : false

            let finalNP = SpotifyNowPlaying(
                trackId: newNP.trackId,
                trackName: newNP.trackName,
                artistName: newNP.artistName,
                albumArtURL: newNP.albumArtURL,
                albumArtURLLarge: newNP.albumArtURLLarge,
                isPlaying: newNP.isPlaying,
                isLiked: previousLiked
            )

            if spotifyState.nowPlaying != finalNP {
                spotifyState.nowPlaying = finalNP
            }

            if !sameTrack {
                Task { await checkIfLiked(trackId: newNP.trackId) }
            }
        } else {
            if spotifyState.nowPlaying != nil { spotifyState.nowPlaying = nil }
        }
    }

    /// Performs network fetch and JSON parsing off the main actor
    private nonisolated func fetchAndParseNowPlaying(accessToken: String) async -> SpotifyNowPlaying? {
        guard let url = URL(string: "\(AppConfig.spotifyAPIBaseURL)/me/player/currently-playing") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }

            if httpResponse.statusCode == 204 || data.isEmpty {
                return nil
            }

            guard httpResponse.statusCode == 200 else { return nil }

            return parseNowPlayingData(data)
        } catch {
            return nil // Network error — caller keeps last state
        }
    }

    /// Pure parsing — no state access, safe to call off main actor
    private nonisolated func parseNowPlayingData(_ data: Data) -> SpotifyNowPlaying? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let isPlaying = json["is_playing"] as? Bool,
              let item = json["item"] as? [String: Any],
              let trackName = item["name"] as? String,
              let trackId = item["id"] as? String else {
            return nil
        }

        let artists = item["artists"] as? [[String: Any]] ?? []
        let artistName = artists.compactMap { $0["name"] as? String }.joined(separator: ", ")

        let album = item["album"] as? [String: Any]
        let images = album?["images"] as? [[String: Any]] ?? []
        let sortedImages = images.sorted { ($0["height"] as? Int ?? 0) < ($1["height"] as? Int ?? 0) }
        let smallestImage = sortedImages.first
        let mediumImage = sortedImages.count >= 2 ? sortedImages[sortedImages.count - 2] : sortedImages.last
        let albumArtURL = smallestImage?["url"] as? String
        let albumArtURLLarge = mediumImage?["url"] as? String

        return SpotifyNowPlaying(
            trackId: trackId,
            trackName: trackName,
            artistName: artistName,
            albumArtURL: albumArtURL,
            albumArtURLLarge: albumArtURLLarge,
            isPlaying: isPlaying,
            isLiked: false // Caller will merge with existing liked state
        )
    }

    private func checkIfLiked(trackId: String) async {
        guard let accessToken = await tokenManager.getValidAccessToken() else { return }

        // GET /me/library/contains?uris=spotify:track:xxx
        let uri = "spotify:track:\(trackId)"
        let encodedUri = uri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? uri
        guard let url = URL(string: "\(AppConfig.spotifyAPIBaseURL)/me/library/contains?uris=\(encodedUri)") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse else { return }

        guard httpResponse.statusCode == 200,
              let results = try? JSONSerialization.jsonObject(with: data) as? [Bool],
              let isLiked = results.first else { return }

        if spotifyState.nowPlaying?.trackId == trackId {
            var updated = spotifyState.nowPlaying!
            updated.isLiked = isLiked
            spotifyState.nowPlaying = updated
        }
    }

    // MARK: - Playback Controls

    func nextTrack() async {
        await sendPlaybackCommand("next", method: "POST")
        // Fetch updated state after a short delay
        try? await Task.sleep(nanoseconds: 500_000_000)
        await fetchNowPlaying()
    }

    func previousTrack() async {
        await sendPlaybackCommand("previous", method: "POST")
        try? await Task.sleep(nanoseconds: 500_000_000)
        await fetchNowPlaying()
    }

    func togglePlayPause() async {
        let isPlaying = spotifyState.nowPlaying?.isPlaying ?? false
        let endpoint = isPlaying ? "pause" : "play"
        let method = "PUT"
        await sendPlaybackCommand(endpoint, method: method)
        try? await Task.sleep(nanoseconds: 300_000_000)
        await fetchNowPlaying()
    }

    func toggleLike() async {
        guard var np = spotifyState.nowPlaying else { return }

        // Update UI immediately (optimistic)
        let newLiked = !np.isLiked
        np.isLiked = newLiked
        spotifyState.nowPlaying = np

        guard let accessToken = await tokenManager.getValidAccessToken() else {
            revertLike(trackId: np.trackId, to: !newLiked)
            return
        }

        // PUT/DELETE /me/library?uris=spotify:track:xxx  (uris is a query param)
        let uri = "spotify:track:\(np.trackId)"
        let encodedUri = uri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? uri
        guard let url = URL(string: "\(AppConfig.spotifyAPIBaseURL)/me/library?uris=\(encodedUri)") else {
            revertLike(trackId: np.trackId, to: !newLiked)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = newLiked ? "PUT" : "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if (200...299).contains(httpResponse.statusCode) {
                    return
                }
                print("[Spotify] toggleLike failed: HTTP \(httpResponse.statusCode)")
                revertLike(trackId: np.trackId, to: !newLiked)
            }
        } catch {
            print("[Spotify] toggleLike error: \(error)")
            revertLike(trackId: np.trackId, to: !newLiked)
        }
    }

    private func revertLike(trackId: String, to liked: Bool) {
        if spotifyState.nowPlaying?.trackId == trackId {
            var reverted = spotifyState.nowPlaying!
            reverted.isLiked = liked
            spotifyState.nowPlaying = reverted
        }
    }

    private func sendPlaybackCommand(_ endpoint: String, method: String) async {
        guard let accessToken = await tokenManager.getValidAccessToken() else { return }
        guard let url = URL(string: "\(AppConfig.spotifyAPIBaseURL)/me/player/\(endpoint)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension SpotifyService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}
