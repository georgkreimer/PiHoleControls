//
//  PiHoleClient.swift
//  PiHoleControls
//
//  Created by Georg Kreimer on 11/25/25.
//

import Foundation
import CryptoKit

struct PiHoleClient {
    let baseURL: URL
    let token: String
    let allowSelfSignedCert: Bool

    enum PiHoleError: Error {
        case invalidURL
        case invalidResponse(
            statusCode: Int?,
            bodyPreview: String?,
            endpoint: String?,
            diagnostics: LegacyErrorDiagnostics?
        )
        case notConfigured
    }

    struct LegacyErrorDiagnostics: Equatable {
        let method: String
        let endpoint: String
        let statusCode: Int
        let action: String
        let authMode: String
        let tokenLooksLikeAppPassword: Bool
    }

    private enum LegacyAction: String {
        case statusRefresh = "status refresh"
        case enableBlocking = "enable blocking"
        case disableBlocking = "disable blocking"
    }

    private enum AuthMode {
        case bearer
        case queryToken
        case tokenHeader
        case session(SessionAuth)
        case none
    }

    private struct SessionAuth {
        let sid: String
        let csrf: String?
    }

    private var sessionCacheKey: String {
        let raw = "\(baseURL.absoluteString)|\(token)"
        let hash = SHA256.hash(data: Data(raw.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func cachedSession() async -> SessionAuth? {
        if let cached = await PiHoleSessionCache.shared.get(key: sessionCacheKey) {
            return SessionAuth(sid: cached.sid, csrf: cached.csrf)
        }
        return nil
    }

    private var tokenLooksLikeLegacyToken: Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 32 else { return false }
        let hexDigits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return trimmed.unicodeScalars.allSatisfy { hexDigits.contains($0) }
    }

    private var tokenLooksLikeAppPassword: Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if tokenLooksLikeLegacyToken { return false }
        return trimmed.count >= 40
    }

    private func legacyDiagnosticsIfNeeded(
        statusCode: Int,
        action: LegacyAction
    ) -> LegacyErrorDiagnostics? {
        guard statusCode == 500 else { return nil }
        return LegacyErrorDiagnostics(
            method: "GET",
            endpoint: "admin/api.php",
            statusCode: statusCode,
            action: action.rawValue,
            authMode: "query token",
            tokenLooksLikeAppPassword: tokenLooksLikeAppPassword
        )
    }

    private func cacheSession(_ session: SessionAuth) async {
        await PiHoleSessionCache.shared.set(
            PiHoleSessionCache.Session(sid: session.sid, csrf: session.csrf),
            key: sessionCacheKey
        )
    }

    private func invalidateCachedSession() async {
        await PiHoleSessionCache.shared.remove(key: sessionCacheKey)
    }

    private func createAndCacheSessionAuth() async throws -> SessionAuth {
        let session = try await createSessionAuth()
        await cacheSession(session)
        return session
    }

    /// Returns a session auth if available/creatable. Never throws; callers should fall back to other auth modes.
    private func sessionAuthIfPossible(forceRefresh: Bool = false) async -> SessionAuth? {
        if !forceRefresh, let cached = await cachedSession() {
            return cached
        }
        do {
            return try await createAndCacheSessionAuth()
        } catch {
            return nil
        }
    }

    private func isSessionUnauthorized(_ response: HTTPURLResponse) -> Bool {
        response.statusCode == 401 || response.statusCode == 403
    }

    /// Sends a request using session auth, re-authing and retrying once if the server rejects the session.
    private func sendRequestWithSessionRetry(
        path: String,
        queryItems: [URLQueryItem],
        method: String = "GET",
        jsonBody: [String: Any]? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        guard let session = await sessionAuthIfPossible() else {
            let (data, response) = try await sendRequest(
                path: path,
                queryItems: queryItems,
                authMode: .none,
                method: method,
                jsonBody: jsonBody
            )
            return (data, response)
        }

        let (data1, response1) = try await sendRequest(
            path: path,
            queryItems: queryItems,
            authMode: .session(session),
            method: method,
            jsonBody: jsonBody
        )

        if !isSessionUnauthorized(response1) {
            return (data1, response1)
        }

        // Session likely expired/invalid. Clear cache and try to re-auth once.
        await invalidateCachedSession()
        guard let refreshed = await sessionAuthIfPossible(forceRefresh: true) else {
            return (data1, response1)
        }

        let (data2, response2) = try await sendRequest(
            path: path,
            queryItems: queryItems,
            authMode: .session(refreshed),
            method: method,
            jsonBody: jsonBody
        )
        return (data2, response2)
    }

    init?(host: String, token: String, allowSelfSignedCert: Bool = false) {
        guard !host.isEmpty, !token.isEmpty else { return nil }
        let hostString = host
        let hasScheme = hostString.hasPrefix("http://") || hostString.hasPrefix("https://")
        guard hasScheme else { return nil }
        guard let rawURL = URL(string: hostString),
            var comps = URLComponents(url: rawURL, resolvingAgainstBaseURL: false),
            let hostOnly = comps.host
        else { return nil }

        // Normalize away any provided path/query (e.g. /admin/api.php) but keep scheme and port.
        let port = comps.port
        let scheme = comps.scheme
        comps.path = ""
        comps.query = nil
        comps.fragment = nil
        comps.user = nil
        comps.password = nil
        comps.host = hostOnly
        comps.port = port
        comps.scheme = scheme

        guard let sanitizedURL = comps.url else { return nil }

        self.baseURL = sanitizedURL
        self.token = token
        self.allowSelfSignedCert = allowSelfSignedCert
    }

    /// Build and send a request with flexible auth modes (Bearer header, Token header, or query token).
    /// Build and send a request with flexible auth modes.
    private func sendRequest(
        path: String,
        queryItems: [URLQueryItem],
        authMode: AuthMode,
        method: String = "GET",
        jsonBody: [String: Any]? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let url = baseURL.appendingPathComponent(path)

        guard
            var comps = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            )
        else {
            throw PiHoleError.invalidURL
        }

        var items = comps.queryItems ?? []
        items.append(contentsOf: queryItems)
        switch authMode {
        case .queryToken:
            items.append(URLQueryItem(name: "auth", value: token))
        default:
            break
        }
        comps.queryItems = items

        guard let finalURL = comps.url else { throw PiHoleError.invalidURL }

        var request = URLRequest(url: finalURL)
        request.httpMethod = method
        switch authMode {
        case .bearer:
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .tokenHeader:
            request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        case .queryToken:
            break
        case .session(let session):
            var cookieParts: [String] = ["sid=\(session.sid)"]
            if let csrf = session.csrf { cookieParts.append("csrf=\(csrf)") }
            request.setValue(cookieParts.joined(separator: "; "), forHTTPHeaderField: "Cookie")
            if let csrf = session.csrf {
                request.setValue(csrf, forHTTPHeaderField: "X-CSRF-Token")
                request.setValue(csrf, forHTTPHeaderField: "X-CSRFToken")
            }
        case .none:
            break
        }
        if let body = jsonBody {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession().data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PiHoleError.invalidResponse(
                statusCode: nil,
                bodyPreview: nil,
                endpoint: url.path,
                diagnostics: nil
            )
        }
        return (data, http)
    }

    /// Legacy Pi-hole v5 `/admin/api.php` with auth query (used after v6 attempts fail).
    private func requestLegacy(
        queryItems: [URLQueryItem],
        action: LegacyAction
    ) async throws -> (Data, HTTPURLResponse) {
        var lastError: PiHoleError = .invalidURL
        do {
            let (data, response) = try await sendRequest(
                path: "admin/api.php", queryItems: queryItems, authMode: .queryToken)
            if response.statusCode == 200 {
                return (data, response)
            }
            lastError = .invalidResponse(
                statusCode: response.statusCode,
                bodyPreview: bodyPreview(from: data),
                endpoint: "admin/api.php",
                diagnostics: legacyDiagnosticsIfNeeded(
                    statusCode: response.statusCode,
                    action: action
                )
            )
            throw lastError
        } catch let err as PiHoleError {
            lastError = err
        }

        throw lastError
    }

    // MARK: - Helpers

    private static let bodyPreviewMaxLength = 300

    private func bodyPreview(from data: Data) -> String? {
        String(data: data, encoding: .utf8).map { String($0.prefix(Self.bodyPreviewMaxLength)) }
    }

    // MARK: - v6-first helpers

    private func decodeV6Status(from data: Data) -> Bool? {
        // Some Pi-hole builds return blocking/status as Bool; others as strings ("enabled"/"disabled").
        struct FlexibleBool: Decodable {
            let value: Bool?
            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let boolVal = try? container.decode(Bool.self) {
                    value = boolVal
                } else if let strVal = try? container.decode(String.self) {
                    let lower = strVal.lowercased()
                    if lower == "enabled" || lower == "true" || lower == "1" {
                        value = true
                    } else if lower == "disabled" || lower == "false" || lower == "0" {
                        value = false
                    } else {
                        value = nil
                    }
                } else {
                    value = nil
                }
            }
        }

        struct V6Status: Decodable {
            let blocking: FlexibleBool?
            let enabled: FlexibleBool?
            let status: FlexibleBool?
        }

        if let decoded = try? JSONDecoder().decode(V6Status.self, from: data) {
            if let blocking = decoded.blocking?.value { return blocking }
            if let enabled = decoded.enabled?.value { return enabled }
            if let status = decoded.status?.value { return status }
        }
        return nil
    }

    private func createSessionAuth() async throws -> SessionAuth {
        let body = ["password": token]
        let (data, response) = try await sendRequest(
            path: "api/auth",
            queryItems: [],
            authMode: .none,
            method: "POST",
            jsonBody: body)
        guard response.statusCode == 200 else {
            throw PiHoleError.invalidResponse(
                statusCode: response.statusCode,
                bodyPreview: bodyPreview(from: data),
                endpoint: "api/auth",
                diagnostics: nil
            )
        }
        // Some Pi-hole v6 builds return the CSRF field as "csff" (server-side typo).
        // We decode both and prefer "csff" when present for compatibility.
        struct AuthSession: Decodable {
            let valid: Bool?
            let sid: String?
            let csff: String?
            let csrf: String?
        }
        struct AuthResponse: Decodable { let session: AuthSession }
        guard let decoded = try? JSONDecoder().decode(AuthResponse.self, from: data),
            let sid = decoded.session.sid
        else {
            throw PiHoleError.invalidResponse(
                statusCode: response.statusCode,
                bodyPreview: bodyPreview(from: data),
                endpoint: "api/auth",
                diagnostics: nil
            )
        }
        let csrf = decoded.session.csff ?? decoded.session.csrf
        return SessionAuth(sid: sid, csrf: csrf)
    }

    /// Sends a v6 API request trying all auth modes: session first, then bearer/tokenHeader/queryToken.
    /// Returns the response from the first auth mode that doesn't return 401/403.
    /// If all modes return 401/403, throws the last auth error.
    private func requestV6WithAuthFallback(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String = "GET",
        jsonBody: [String: Any]? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var lastAuthError: PiHoleError?

        // Prefer session if available (works with app passwords), with one re-auth retry.
        if await sessionAuthIfPossible() != nil {
            let (data, response) = try await sendRequestWithSessionRetry(
                path: path, queryItems: queryItems, method: method, jsonBody: jsonBody)
            if response.statusCode != 401 && response.statusCode != 403 {
                return (data, response)
            }
            lastAuthError = .invalidResponse(
                statusCode: response.statusCode,
                bodyPreview: bodyPreview(from: data),
                endpoint: path,
                diagnostics: nil
            )
        }

        // Fall back to other auth modes.
        for mode in [AuthMode.bearer, .tokenHeader, .queryToken] {
            let (data, response) = try await sendRequest(
                path: path, queryItems: queryItems, authMode: mode, method: method, jsonBody: jsonBody)
            if response.statusCode != 401 && response.statusCode != 403 {
                return (data, response)
            }
            lastAuthError = .invalidResponse(
                statusCode: response.statusCode,
                bodyPreview: bodyPreview(from: data),
                endpoint: path,
                diagnostics: nil
            )
        }

        throw lastAuthError ?? PiHoleError.invalidResponse(
            statusCode: nil, bodyPreview: nil, endpoint: path, diagnostics: nil)
    }

    /// Tries multiple endpoint/method combos with auth fallback. Returns true if any succeeds (2xx).
    private func performV6Mutation(
        attempts: [(path: String, method: String, body: [String: Any]?)]
    ) async throws -> Bool {
        var lastError: PiHoleError?
        for attempt in attempts {
            do {
                let (data, response) = try await requestV6WithAuthFallback(
                    path: attempt.path, method: attempt.method, jsonBody: attempt.body)
                if (200...204).contains(response.statusCode) { return true }
                lastError = .invalidResponse(
                    statusCode: response.statusCode,
                    bodyPreview: bodyPreview(from: data),
                    endpoint: attempt.path,
                    diagnostics: nil
                )
            } catch let err as PiHoleError {
                lastError = err
            } catch {
                continue
            }
        }
        if let err = lastError { throw err }
        return false
    }

    private func fetchStatusV6() async throws -> Bool? {
        let (data, response) = try await requestV6WithAuthFallback(path: "api/dns/blocking")
        guard response.statusCode == 200 else {
            throw PiHoleError.invalidResponse(
                statusCode: response.statusCode,
                bodyPreview: bodyPreview(from: data),
                endpoint: "api/dns/blocking",
                diagnostics: nil
            )
        }
        if let status = decodeV6Status(from: data) { return status }
        throw PiHoleError.invalidResponse(
            statusCode: response.statusCode,
            bodyPreview: bodyPreview(from: data),
            endpoint: "api/dns/blocking",
            diagnostics: nil
        )
    }

    private func enableV6() async throws -> Bool {
        let payload: [String: Any] = ["status": "enabled", "blocking": true]
        return try await performV6Mutation(attempts: [
            ("api/dns/blocking", "POST", payload),
            ("api/dns/blocking", "PUT", payload),
            ("api/dns/blocking/enable", "POST", nil),
        ])
    }

    private func disableV6(durationSeconds: Int?) async throws -> Bool {
        var payload: [String: Any] = ["status": "disabled", "blocking": false]
        if let durationSeconds { payload["duration"] = durationSeconds }
        return try await performV6Mutation(attempts: [
            ("api/dns/blocking", "POST", payload),
            ("api/dns/blocking", "PUT", payload),
            ("api/dns/blocking/disable", "POST", durationSeconds.map { ["duration": $0] }),
        ])
    }

    /// Cache of host-scoped sessions so we don't create a new URLSession per request.
    private static var selfSignedSessions: [String: URLSession] = [:]
    private static let sessionLock = NSLock()

    private func urlSession() -> URLSession {
        guard allowSelfSignedCert, let host = baseURL.host else { return .shared }
        Self.sessionLock.lock()
        defer { Self.sessionLock.unlock() }
        if let existing = Self.selfSignedSessions[host] { return existing }
        let configuration = URLSessionConfiguration.default
        // Disable automatic cookie handling — we manage cookies manually via headers.
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        let delegate = HostScopedSelfSignedCertDelegate(allowedHost: host)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        Self.selfSignedSessions[host] = session
        return session
    }

    func fetchStatus(allowLegacyFallback: Bool = true) async throws -> Bool {
        // v6 first
        do {
            if let v6 = try await fetchStatusV6() {
                return v6
            }
        } catch let err as PiHoleError {
            // Only fall back to legacy if v6 endpoint is missing (404). Otherwise surface the v6 error.
            if !allowLegacyFallback { throw err }
            if case .invalidResponse(let statusCode, _, _, _) = err, statusCode == 404 {
                // Only fall back to legacy when v6 endpoints are missing.
            } else {
                throw err
            }
        }

        // Legacy v5 fallback
        let (data, response) = try await requestLegacy(
            queryItems: [
                URLQueryItem(name: "status", value: nil)
            ],
            action: .statusRefresh
        )
        struct StatusResponse: Decodable { let status: String }
        do {
            let decoded = try JSONDecoder().decode(StatusResponse.self, from: data)
            return decoded.status.lowercased() == "enabled"
        } catch {
            throw PiHoleError.invalidResponse(
                statusCode: response.statusCode,
                bodyPreview: bodyPreview(from: data),
                endpoint: "admin/api.php",
                diagnostics: legacyDiagnosticsIfNeeded(
                    statusCode: response.statusCode,
                    action: .statusRefresh
                )
            )
        }
    }

    func enableBlocking() async throws {
        // v6 first; only fall back to legacy on 404 (endpoint missing)
        do {
            if try await enableV6() { return }
        } catch let err as PiHoleError {
            if case .invalidResponse(let statusCode, _, _, _) = err, statusCode == 404 {
                // v6 endpoint missing, fall through to legacy
            } else {
                throw err
            }
        }

        // Legacy v5 fallback
        let (_, response) = try await requestLegacy(
            queryItems: [
                URLQueryItem(name: "enable", value: nil)
            ],
            action: .enableBlocking
        )
        guard response.statusCode == 200 else {
            throw PiHoleError.invalidResponse(
                statusCode: response.statusCode,
                bodyPreview: nil,
                endpoint: "admin/api.php",
                diagnostics: legacyDiagnosticsIfNeeded(
                    statusCode: response.statusCode,
                    action: .enableBlocking
                )
            )
        }
    }

    func disableBlocking(durationSeconds: Int? = nil) async throws {
        // v6 first; only fall back to legacy on 404 (endpoint missing)
        do {
            if try await disableV6(durationSeconds: durationSeconds) { return }
        } catch let err as PiHoleError {
            if case .invalidResponse(let statusCode, _, _, _) = err, statusCode == 404 {
                // v6 endpoint missing, fall through to legacy
            } else {
                throw err
            }
        }

        // Legacy v5 fallback
        var items: [URLQueryItem]
        if let seconds = durationSeconds {
            items = [URLQueryItem(name: "disable", value: "\(seconds)")]
        } else {
            items = [URLQueryItem(name: "disable", value: nil)]
        }
        let (_, response) = try await requestLegacy(queryItems: items, action: .disableBlocking)
        guard response.statusCode == 200 else {
            throw PiHoleError.invalidResponse(
                statusCode: response.statusCode,
                bodyPreview: nil,
                endpoint: "admin/api.php",
                diagnostics: legacyDiagnosticsIfNeeded(
                    statusCode: response.statusCode,
                    action: .disableBlocking
                )
            )
        }
    }
}

/// Accepts self-signed certs only for the specified Pi-hole host. All other hosts use default validation.
private final class HostScopedSelfSignedCertDelegate: NSObject, URLSessionDelegate {
    private let allowedHost: String

    init(allowedHost: String) {
        self.allowedHost = allowedHost
    }

    func urlSession(
        _ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let challengeHost = challenge.protectionSpace.host
        if challengeHost == allowedHost, let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

extension PiHoleClient.PiHoleError {
    var legacyDiagnostics: PiHoleClient.LegacyErrorDiagnostics? {
        if case .invalidResponse(_, _, _, let diagnostics) = self {
            return diagnostics
        }
        return nil
    }

    var isLegacyServerError: Bool {
        guard let diagnostics = legacyDiagnostics else { return false }
        return diagnostics.endpoint == "admin/api.php" && diagnostics.statusCode == 500
    }
}

// MARK: - Error descriptions for UI
extension PiHoleClient.PiHoleError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return
                "Malformed Pi-hole URL. Include http:// or https:// and avoid extra paths (use the base host/port only)."
        case .notConfigured:
            return "Enter host and API token in Settings first."
        case .invalidResponse(let statusCode, _, let endpoint, let diagnostics):
            // Note: bodyPreview is intentionally excluded to avoid exposing sensitive server responses
            var base = "Pi-hole API returned an error"
            if let code = statusCode { base += " (HTTP \(code))" }
            if let endpoint { base += "\nEndpoint: \(endpoint)" }
            if let diagnostics {
                base += "\nDiagnostics: action=\(diagnostics.action), method=\(diagnostics.method), auth=\(diagnostics.authMode), status=\(diagnostics.statusCode)"
            }
            if let diagnostics, diagnostics.statusCode == 500, diagnostics.endpoint == "admin/api.php" {
                base += "\nNext steps:\n- Verify Pi-hole is v5 (legacy API) or upgrade to v6.\n- Confirm the API token is the legacy token (not an app password).\n- Check server health and that /admin/api.php is reachable."
                if diagnostics.tokenLooksLikeAppPassword {
                    base += "\nNote: Your token looks like a v6 app password, which the legacy API does not accept."
                }
            }
            return base
        }
    }
}
