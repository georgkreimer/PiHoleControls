import Foundation
import CryptoKit

struct PiHoleClient {
    let baseURL: URL
    let token: String
    let allowSelfSignedCert: Bool
    private let session: URLSession?

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

    struct LegacyErrorDiagnostics: Equatable, Sendable {
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

    /// Only unsupported session authentication permits another authentication mode.
    private func sessionAuthIfPossible(forceRefresh: Bool = false) async throws -> SessionAuth? {
        if !forceRefresh, let cached = await cachedSession() {
            return cached
        }
        do {
            return try await createAndCacheSessionAuth()
        } catch let PiHoleError.invalidResponse(code, _, _, _) where [401, 403, 404, 405].contains(code ?? 0) {
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
        guard let session = try await sessionAuthIfPossible() else {
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
        guard let refreshed = try await sessionAuthIfPossible(forceRefresh: true) else {
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

    init?(host: String, token: String, allowSelfSignedCert: Bool = false, session: URLSession? = nil) {
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
        self.session = session
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
        try Task.checkCancellation()
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
        request.httpShouldHandleCookies = false
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
        if try await sessionAuthIfPossible() != nil {
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

    private func setBlockingV6(enabled: Bool, durationSeconds: Int? = nil) async throws {
        let (data, response) = try await requestV6WithAuthFallback(
            path: "api/dns/blocking", method: "POST",
            jsonBody: ["blocking": enabled, "timer": durationSeconds.map { $0 as Any } ?? NSNull()])
        guard response.statusCode == 200, decodeV6Status(from: data) == enabled else {
            throw PiHoleError.invalidResponse(statusCode: response.statusCode,
                bodyPreview: bodyPreview(from: data), endpoint: "api/dns/blocking", diagnostics: nil)
        }
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

    // MARK: - Domain management

    func fetchRecentBlocked(count: Int) async throws -> [BlockedQuery] {
        guard count > 0 else { return [] }
        do {
            let (data, response) = try await requestV6WithAuthFallback(
                path: "api/queries", queryItems: [
                    URLQueryItem(name: "upstream", value: "blocklist"),
                    URLQueryItem(name: "length", value: "\(count)")
                ])
            guard response.statusCode == 200 else {
                throw PiHoleError.invalidResponse(statusCode: response.statusCode,
                    bodyPreview: bodyPreview(from: data), endpoint: "api/queries", diagnostics: nil)
            }
            struct QueryResponse: Decodable {
                struct Query: Decodable {
                    let domain: String
                    let status: String
                    let time: Double?
                }
                let queries: [Query]
            }
            let decoded = try JSONDecoder().decode(QueryResponse.self, from: data)
            let blockedStatuses: Set<String> = [
                "GRAVITY", "REGEX", "DENYLIST", "GRAVITY_CNAME", "REGEX_CNAME", "DENYLIST_CNAME",
                "EXTERNAL_BLOCKED_IP", "EXTERNAL_BLOCKED_NULL", "EXTERNAL_BLOCKED_NXRA",
                "EXTERNAL_BLOCKED_EDE15", "SPECIAL_DOMAIN", "DBBUSY"
            ]
            return Array(decoded.queries.compactMap { query -> BlockedQuery? in
                guard !query.domain.isEmpty, blockedStatuses.contains(query.status) else { return nil }
                return BlockedQuery(domain: query.domain, timestamp: query.time.map { Date(timeIntervalSince1970: $0) })
            }.prefix(count))
        } catch let PiHoleError.invalidResponse(code, _, _, _) where code == 404 {
            // Only a missing endpoint permits the less detailed stats fallback.
        }

        let (data, response) = try await requestV6WithAuthFallback(
            path: "api/stats/recent_blocked", queryItems: [URLQueryItem(name: "count", value: "\(count)")])
        guard response.statusCode == 200 else {
            throw PiHoleError.invalidResponse(statusCode: response.statusCode,
                bodyPreview: bodyPreview(from: data), endpoint: "api/stats/recent_blocked", diagnostics: nil)
        }
        struct RecentBlocked: Decodable { let blocked: [String] }
        let decoded = try JSONDecoder().decode(RecentBlocked.self, from: data)
        return decoded.blocked.filter { !$0.isEmpty }.prefix(count).map {
            BlockedQuery(domain: $0, timestamp: nil)
        }
    }

    func allowDomain(_ domain: String) async throws {
        let (data, response) = try await requestV6WithAuthFallback(
            path: "api/domains/allow/exact", method: "POST", jsonBody: ["domain": domain])
        struct Insertion: Decodable {
            struct Processed: Decodable {
                struct Item: Decodable { let item: String }
                let success: [Item]
                let errors: [Item]
            }
            let processed: Processed
        }
        guard response.statusCode == 201,
              let result = try? JSONDecoder().decode(Insertion.self, from: data),
              result.processed.errors.isEmpty,
              result.processed.success.contains(where: { $0.item.lowercased() == domain.lowercased() }) else {
            throw PiHoleError.invalidResponse(statusCode: response.statusCode,
                bodyPreview: bodyPreview(from: data), endpoint: "api/domains/allow/exact", diagnostics: nil)
        }
    }

    func removeDomain(_ domain: String) async throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._")
        guard !domain.isEmpty, domain.utf8.count <= 253,
              domain.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { throw PiHoleError.invalidURL }
        let path = "api/domains/allow/exact/\(domain)"
        let (data, response) = try await requestV6WithAuthFallback(path: path, method: "DELETE")
        if response.statusCode == 204 { return }
        if response.statusCode == 404 {
            // Distinguish an already-removed entry from an unsupported endpoint.
            let (checkData, checkResponse) = try await requestV6WithAuthFallback(path: path)
            struct Lookup: Decodable {
                struct Domain: Decodable { let domain: String }
                let domains: [Domain]
            }
            if checkResponse.statusCode == 200,
               let lookup = try? JSONDecoder().decode(Lookup.self, from: checkData),
               lookup.domains.isEmpty { return }
        }
        throw PiHoleError.invalidResponse(statusCode: response.statusCode,
            bodyPreview: bodyPreview(from: data), endpoint: path, diagnostics: nil)
    }

    private static nonisolated(unsafe) var selfSignedSessions: [String: URLSession] = [:]
    private static let sessionLock = NSLock()

    private func urlSession() -> URLSession {
        if let session { return session }
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
            try await setBlockingV6(enabled: true)
            return
        } catch let err as PiHoleError {
            if case .invalidResponse(let statusCode, _, _, _) = err, statusCode == 404 {
                // v6 endpoint missing, fall through to legacy
            } else {
                throw err
            }
        }

        // Legacy v5 fallback
        let (data, response) = try await requestLegacy(
            queryItems: [
                URLQueryItem(name: "enable", value: nil)
            ],
            action: .enableBlocking
        )
        struct Status: Decodable { let status: String }
        guard response.statusCode == 200,
              let confirmation = try? JSONDecoder().decode(Status.self, from: data),
              confirmation.status.lowercased() == "enabled" else {
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
            try await setBlockingV6(enabled: false, durationSeconds: durationSeconds)
            return
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
        let (data, response) = try await requestLegacy(queryItems: items, action: .disableBlocking)
        struct Status: Decodable { let status: String }
        guard response.statusCode == 200,
              let confirmation = try? JSONDecoder().decode(Status.self, from: data),
              confirmation.status.lowercased() == "disabled" else {
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
private final class HostScopedSelfSignedCertDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
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
    var errorDescription: String? {
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
