// TB3 iOS — Strava Service (OAuth + Activity Creation)
// Handles Strava connect/disconnect, token exchange via backend proxy, and activity posting.

import Foundation
import AuthenticationServices

enum StravaError: LocalizedError {
    case unauthorized
    case sessionExpired
    case rateLimited
    case networkError
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Strava authorization failed."
        case .sessionExpired: return "Strava session expired. Please reconnect in Settings."
        case .rateLimited: return "Strava is busy. Please try again later."
        case .networkError: return "No internet connection."
        case .apiError(let msg): return msg
        }
    }
}

@MainActor
final class StravaService: NSObject {
    private let stravaState: StravaState
    private let tokenManager: StravaTokenManager

    // Retain the auth session so it doesn't get deallocated before presenting
    private var authSession: ASWebAuthenticationSession?

    init(stravaState: StravaState, tokenManager: StravaTokenManager) {
        self.stravaState = stravaState
        self.tokenManager = tokenManager
    }

    // MARK: - Restore Connection (app launch)

    func restoreConnection() async {
        if let tokens = await tokenManager.getStoredTokens() {
            stravaState.isConnected = true
            stravaState.athleteName = tokens.athleteName
            stravaState.autoShare = UserDefaults.standard.bool(forKey: "tb3_strava_auto_share")
        }
    }

    // MARK: - Connect (OAuth Flow)

    func connect() async throws {
        stravaState.isLoading = true

        var components = URLComponents(string: AppConfig.stravaAuthURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: AppConfig.stravaClientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: AppConfig.stravaCallbackURL),
            URLQueryItem(name: "scope", value: "activity:write"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
        ]

        guard let authorizeURL = components.url else {
            stravaState.isLoading = false
            throw StravaError.apiError("Failed to build Strava authorization URL")
        }

        let callbackURL: URL
        do {
            callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(
                    url: authorizeURL,
                    callbackURLScheme: AppConfig.stravaCallbackScheme
                ) { [weak self] url, error in
                    self?.authSession = nil
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: StravaError.apiError("No callback URL received"))
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = true
                self.authSession = session
                session.start()
            }
        } catch {
            stravaState.isLoading = false
            // User cancelled — don't throw
            if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                return
            }
            throw error
        }

        // Extract authorization code from callback
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            stravaState.isLoading = false
            throw StravaError.apiError("No authorization code received from Strava")
        }

        // Exchange code for tokens via backend proxy
        try await exchangeCode(code)
        stravaState.isLoading = false
    }

    private func exchangeCode(_ code: String) async throws {
        guard let url = URL(string: AppConfig.stravaTokenProxyURL) else {
            throw StravaError.apiError("Invalid token proxy URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw StravaError.apiError("Token exchange failed")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let expiresAt = json["expires_at"] as? Double,
              let athlete = json["athlete"] as? [String: Any],
              let athleteId = athlete["id"] as? Int else {
            throw StravaError.apiError("Invalid token response from Strava")
        }

        let firstName = athlete["firstname"] as? String
        let lastName = athlete["lastname"] as? String
        let athleteName = [firstName, lastName].compactMap { $0 }.joined(separator: " ")

        let tokens = StravaTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            athleteId: athleteId,
            athleteName: athleteName.isEmpty ? nil : athleteName
        )

        await tokenManager.storeTokens(tokens)
        stravaState.isConnected = true
        stravaState.athleteName = tokens.athleteName
    }

    // MARK: - Disconnect

    func disconnect() async {
        // Deauthorize with Strava
        if let accessToken = await tokenManager.getStoredTokens()?.accessToken {
            var request = URLRequest(url: URL(string: AppConfig.stravaDeauthorizeURL)!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: request)
        }

        await tokenManager.clearTokens()
        stravaState.isConnected = false
        stravaState.athleteName = nil
        stravaState.autoShare = false
        UserDefaults.standard.set(false, forKey: "tb3_strava_auto_share")
    }

    // MARK: - Share Activity

    func shareActivity(session: SyncSessionLog) async {
        let activity = StravaActivityFormatter.format(session: session)
        print("[Strava] Sharing activity: \(activity.name)")
        print("[Strava] Description: \(activity.description)")

        do {
            try await postActivity(activity)
            print("[Strava] Share succeeded")
            stravaState.lastShareSuccess = true
            stravaState.lastShareError = nil
        } catch StravaError.unauthorized, StravaError.sessionExpired {
            // Try refresh, then retry once
            if let _ = await tokenManager.refreshTokens() {
                do {
                    try await postActivity(activity)
                    stravaState.lastShareSuccess = true
                    stravaState.lastShareError = nil
                } catch {
                    stravaState.isConnected = false
                    stravaState.lastShareSuccess = false
                    stravaState.lastShareError = "Strava session expired. Please reconnect."
                }
            } else {
                stravaState.isConnected = false
                stravaState.lastShareSuccess = false
                stravaState.lastShareError = "Strava session expired. Please reconnect."
            }
        } catch {
            print("[Strava] Share error: \(error.localizedDescription)")
            stravaState.lastShareSuccess = false
            stravaState.lastShareError = error.localizedDescription
        }
    }

    private func postActivity(_ activity: StravaActivityFormatter.StravaActivity) async throws {
        guard let accessToken = await tokenManager.getValidAccessToken() else {
            throw StravaError.sessionExpired
        }

        guard let url = URL(string: "\(AppConfig.stravaAPIBaseURL)/activities") else {
            throw StravaError.apiError("Invalid Strava API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "name": activity.name,
            "sport_type": activity.sportType,
            "start_date_local": activity.startDateLocal,
            "elapsed_time": activity.elapsedTime,
            "description": activity.description,
            "trainer": activity.trainer,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StravaError.networkError
        }

        print("[Strava] POST /activities → \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200...201:
            return // Success
        case 401:
            throw StravaError.unauthorized
        case 429:
            throw StravaError.rateLimited
        default:
            let body = String(data: data, encoding: .utf8) ?? "no body"
            print("[Strava] Error body: \(body)")
            throw StravaError.apiError("Strava returned status \(httpResponse.statusCode)")
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension StravaService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}

// MARK: - Activity Formatter

enum StravaActivityFormatter {
    struct StravaActivity {
        let name: String
        let sportType: String
        let startDateLocal: String
        let elapsedTime: Int
        let description: String
        let trainer: Bool
    }

    static func format(session: SyncSessionLog) -> StravaActivity {
        let templateName = Templates.get(id: session.templateId)?.name ?? session.templateId.capitalized

        let name = "TB3 \(templateName) — W\(session.week)/S\(session.sessionNumber)"

        var lines: [String] = []
        for exercise in session.exercises {
            let liftDisplay = LiftName(rawValue: exercise.liftName)?.displayName ?? exercise.liftName
            let completedSets = exercise.sets.filter(\.completed)
            let totalSets = exercise.sets.count
            let reps = completedSets.first?.actualReps ?? completedSets.first?.targetReps ?? 0
            let partial = completedSets.count < totalSets ? " (partial)" : ""
            let weight = Int(exercise.targetWeight)
            lines.append("\(liftDisplay): \(weight) lb — \(completedSets.count)×\(reps)\(partial)")
        }

        // Footer
        let template = Templates.get(id: session.templateId)
        let weekDef = template?.weeks.first { $0.weekNumber == session.week }
        let percentage = weekDef?.percentage ?? 0

        lines.append("")
        if let temp = session.temperatureF {
            lines.append("TB3 \(templateName) | Week \(session.week) Session \(session.sessionNumber) | \(percentage)% | \(Int(temp))°F")
        } else {
            lines.append("TB3 \(templateName) | Week \(session.week) Session \(session.sessionNumber) | \(percentage)%")
        }

        // Duration
        let start = Date.fromISO8601(session.startedAt) ?? Date()
        let end = Date.fromISO8601(session.completedAt) ?? Date()
        let elapsed = Int(end.timeIntervalSince(start))

        return StravaActivity(
            name: name,
            sportType: "WeightTraining",
            startDateLocal: session.startedAt,
            elapsedTime: max(elapsed, 60),
            description: lines.joined(separator: "\n"),
            trainer: true
        )
    }
}
