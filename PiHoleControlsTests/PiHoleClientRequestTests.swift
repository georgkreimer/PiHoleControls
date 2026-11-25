import Foundation
import Testing
@testable import PiHoleControls

private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, String))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()
        do {
            let (status, body) = try handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

@MainActor
@Suite(.serialized)
struct PiHoleClientRequestTests {
    private func client(_ handler: @escaping (URLRequest) throws -> (Int, String)) -> PiHoleClient {
        FixtureProtocol.lock.lock()
        FixtureProtocol.handler = handler
        FixtureProtocol.lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureProtocol.self]
        return PiHoleClient(host: "https://fixture.invalid", token: UUID().uuidString,
                            session: URLSession(configuration: config))!
    }

    private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    @Test func queriesUseBlocklistFilter() async throws {
        let client = client { request in
            if request.url!.path == "/api/auth" { return (404, "{}") }
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            #expect(items.contains(URLQueryItem(name: "upstream", value: "blocklist")))
            return (200, #"{"queries":[{"domain":"ads.invalid","status":"GRAVITY","time":100},{"domain":"good.invalid","status":"FORWARDED","time":101}]}"#)
        }
        let queries = try await client.fetchRecentBlocked(count: 5)
        #expect(queries.map(\.domain) == ["ads.invalid"])
    }

    @Test func fallbackDecodesStringsWithoutInventingTime() async throws {
        let client = client { request in
            if request.url!.path != "/api/stats/recent_blocked" { return (404, "{}") }
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? []
            #expect(items.contains(URLQueryItem(name: "count", value: "2")))
            return (200, #"{"blocked":["one.invalid","two.invalid","three.invalid"]}"#)
        }
        let queries = try await client.fetchRecentBlocked(count: 2)
        #expect(queries.map(\.domain) == ["one.invalid", "two.invalid"])
        #expect(queries.allSatisfy { $0.timestamp == nil })
    }

    @Test(arguments: ["{}", #"{"processed":{"success":[],"errors":[{"item":"ads.invalid","error":"already exists"}]}}"#])
    func domainInsertionRequiresOwnership(body: String) async {
        let client = client { request in
            request.url!.path == "/api/auth" ? (404, "{}") : (201, body)
        }
        await #expect(throws: PiHoleClient.PiHoleError.self) { try await client.allowDomain("ads.invalid") }
    }

    @Test(arguments: [200, 404])
    func deletionRequiresSuccessOrVerifiedAbsence(status: Int) async throws {
        let client = client { request in
            if request.url!.path == "/api/auth" { return (404, "{}") }
            if request.httpMethod == "DELETE" { return (status, "{}") }
            return (200, #"{"domains":[]}"#)
        }
        if status == 404 { try await client.removeDomain("ads.invalid") }
        else { await #expect(throws: PiHoleClient.PiHoleError.self) { try await client.removeDomain("ads.invalid") } }
    }

    @Test func unavailableRecentQueriesDoNotBecomeEmptySuccess() async {
        let client = client { request in
            if request.url!.path == "/api/auth" { return (404, "{}") }
            #expect(request.url!.path == "/api/queries")
            return (503, "{}")
        }
        await #expect(throws: PiHoleClient.PiHoleError.self) { try await client.fetchRecentBlocked(count: 5) }
    }

    @Test func timedDisableUsesServerTimer() async throws {
        let client = client { request in
            if request.url!.path == "/api/auth" { return (404, "{}") }
            #expect(request.url!.path == "/api/dns/blocking")
            let body = try jsonBody(request)
            #expect(body["timer"] as? Int == 300)
            #expect(body["duration"] == nil)
            #expect(body["blocking"] as? Bool == false)
            return (200, #"{"blocking":"disabled","timer":300}"#)
        }
        try await client.disableBlocking(durationSeconds: 300)
    }

    @Test(arguments: [401, 403, 500, 503])
    func mutationPreservesFailure(status: Int) async {
        let client = client { request in
            if request.url!.path == "/api/auth" { return (404, "{}") }
            #expect(request.url!.path == "/api/dns/blocking")
            #expect(request.httpMethod == "POST")
            return (status, "{}")
        }
        do {
            try await client.enableBlocking()
            Issue.record("Mutation unexpectedly succeeded")
        } catch let PiHoleClient.PiHoleError.invalidResponse(code, _, endpoint, _) {
            #expect(code == status)
            #expect(endpoint == "api/dns/blocking")
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func transportFailureDoesNotFallBack() async {
        let client = client { request in
            #expect(request.url!.path == "/api/auth")
            throw URLError(.timedOut)
        }
        await #expect(throws: URLError.self) { try await client.enableBlocking() }
    }

    @Test(arguments: ["[]", "{}", "Not authorized!", #"{"status":"disabled"}"#])
    func legacyEnableRequiresConfirmation(body: String) async {
        let client = client { request in
            return request.url!.path == "/admin/api.php" ? (200, body) : (404, "{}")
        }
        await #expect(throws: PiHoleClient.PiHoleError.self) { try await client.enableBlocking() }
    }

    @Test func legacyDisableKeepsDuration() async throws {
        let client = client { request in
            if request.url!.path != "/admin/api.php" { return (404, "{}") }
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            #expect(items.contains(URLQueryItem(name: "disable", value: "300")))
            return (200, #"{"status":"disabled"}"#)
        }
        try await client.disableBlocking(durationSeconds: 300)
    }

}
