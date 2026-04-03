//
//  PiHoleClientTests.swift
//  PiHoleControlsTests
//
//  Tests for PiHoleClient init, URL construction, and error types.
//  Network-dependent methods are not tested here (they require a running Pi-hole).
//

import Testing
import Foundation
@testable import PiHoleControls

@Suite("PiHoleClient Tests")
struct PiHoleClientTests {

    // MARK: - Init / URL Parsing

    @Test("Init succeeds with valid http host and token")
    func initValidHttp() {
        let client = PiHoleClient(host: "http://pi.hole", token: "abc123")
        #expect(client != nil)
        #expect(client?.baseURL.absoluteString == "http://pi.hole")
        #expect(client?.token == "abc123")
    }

    @Test("Init succeeds with valid https host and token")
    func initValidHttps() {
        let client = PiHoleClient(host: "https://pi.hole", token: "abc123")
        #expect(client != nil)
        #expect(client?.baseURL.scheme == "https")
    }

    @Test("Init succeeds with host containing port")
    func initWithPort() {
        let client = PiHoleClient(host: "http://192.168.1.2:8080", token: "tok")
        #expect(client != nil)
        #expect(client?.baseURL.port == 8080)
        #expect(client?.baseURL.host == "192.168.1.2")
    }

    @Test("Init strips path from host URL")
    func initStripsPath() {
        let client = PiHoleClient(host: "http://pi.hole/admin/api.php", token: "tok")
        #expect(client != nil)
        #expect(client?.baseURL.path == "" || client?.baseURL.path == "/")
    }

    @Test("Init strips query from host URL")
    func initStripsQuery() {
        let client = PiHoleClient(host: "http://pi.hole?foo=bar", token: "tok")
        #expect(client != nil)
        #expect(client?.baseURL.query == nil)
    }

    @Test("Init strips fragment from host URL")
    func initStripsFragment() {
        let client = PiHoleClient(host: "http://pi.hole#section", token: "tok")
        #expect(client != nil)
        #expect(client?.baseURL.fragment == nil)
    }

    @Test("Init strips user/password from host URL")
    func initStripsCredentials() {
        let client = PiHoleClient(host: "http://user:pass@pi.hole", token: "tok")
        #expect(client != nil)
        #expect(client?.baseURL.user == nil)
        #expect(client?.baseURL.password == nil)
    }

    @Test("Init returns nil for empty host")
    func initEmptyHost() {
        let client = PiHoleClient(host: "", token: "abc")
        #expect(client == nil)
    }

    @Test("Init returns nil for empty token")
    func initEmptyToken() {
        let client = PiHoleClient(host: "http://pi.hole", token: "")
        #expect(client == nil)
    }

    @Test("Init returns nil for host without scheme")
    func initNoScheme() {
        let client = PiHoleClient(host: "pi.hole", token: "abc")
        #expect(client == nil)
    }

    @Test("Init returns nil for host with ftp scheme")
    func initFtpScheme() {
        let client = PiHoleClient(host: "ftp://pi.hole", token: "abc")
        #expect(client == nil)
    }

    @Test("Init preserves allowSelfSignedCert flag")
    func initSelfSignedCert() {
        let client = PiHoleClient(host: "https://pi.hole", token: "tok", allowSelfSignedCert: true)
        #expect(client?.allowSelfSignedCert == true)

        let client2 = PiHoleClient(host: "https://pi.hole", token: "tok", allowSelfSignedCert: false)
        #expect(client2?.allowSelfSignedCert == false)
    }

    @Test("Init defaults allowSelfSignedCert to false")
    func initDefaultSelfSignedCert() {
        let client = PiHoleClient(host: "https://pi.hole", token: "tok")
        #expect(client?.allowSelfSignedCert == false)
    }

    // MARK: - PiHoleError

    @Test("invalidURL error has correct description")
    func invalidURLErrorDescription() {
        let error = PiHoleClient.PiHoleError.invalidURL
        #expect(error.errorDescription?.contains("Malformed") == true)
    }

    @Test("notConfigured error has correct description")
    func notConfiguredErrorDescription() {
        let error = PiHoleClient.PiHoleError.notConfigured
        #expect(error.errorDescription?.contains("Settings") == true)
    }

    @Test("invalidResponse includes status code in description")
    func invalidResponseStatusCode() {
        let error = PiHoleClient.PiHoleError.invalidResponse(
            statusCode: 403, bodyPreview: nil, endpoint: "/api/test", diagnostics: nil)
        #expect(error.errorDescription?.contains("403") == true)
    }

    @Test("invalidResponse includes endpoint in description")
    func invalidResponseEndpoint() {
        let error = PiHoleClient.PiHoleError.invalidResponse(
            statusCode: 500, bodyPreview: nil, endpoint: "api/dns/blocking", diagnostics: nil)
        #expect(error.errorDescription?.contains("api/dns/blocking") == true)
    }

    @Test("invalidResponse excludes bodyPreview from description")
    func invalidResponseExcludesBody() {
        let error = PiHoleClient.PiHoleError.invalidResponse(
            statusCode: 500, bodyPreview: "SECRET_DATA", endpoint: nil, diagnostics: nil)
        #expect(error.errorDescription?.contains("SECRET_DATA") == false)
    }

    @Test("Legacy server error detection")
    func legacyServerErrorDetection() {
        let diagnostics = PiHoleClient.LegacyErrorDiagnostics(
            method: "GET", endpoint: "admin/api.php", statusCode: 500,
            action: "status refresh", authMode: "query token",
            tokenLooksLikeAppPassword: false)
        let error = PiHoleClient.PiHoleError.invalidResponse(
            statusCode: 500, bodyPreview: nil, endpoint: "admin/api.php",
            diagnostics: diagnostics)

        #expect(error.isLegacyServerError == true)
        #expect(error.legacyDiagnostics != nil)
    }

    @Test("Non-legacy error is not flagged as legacy server error")
    func nonLegacyServerError() {
        let error = PiHoleClient.PiHoleError.invalidResponse(
            statusCode: 500, bodyPreview: nil, endpoint: "api/dns/blocking", diagnostics: nil)
        #expect(error.isLegacyServerError == false)
    }

    @Test("Legacy 500 with app password token shows note")
    func legacyAppPasswordNote() {
        let diagnostics = PiHoleClient.LegacyErrorDiagnostics(
            method: "GET", endpoint: "admin/api.php", statusCode: 500,
            action: "status refresh", authMode: "query token",
            tokenLooksLikeAppPassword: true)
        let error = PiHoleClient.PiHoleError.invalidResponse(
            statusCode: 500, bodyPreview: nil, endpoint: "admin/api.php",
            diagnostics: diagnostics)

        #expect(error.errorDescription?.contains("app password") == true)
        #expect(error.errorDescription?.contains("Next steps") == true)
    }

    @Test("invalidResponse with nil status code omits code from description")
    func invalidResponseNilStatusCode() {
        let error = PiHoleClient.PiHoleError.invalidResponse(
            statusCode: nil, bodyPreview: nil, endpoint: nil, diagnostics: nil)
        #expect(error.errorDescription?.contains("HTTP") == false)
    }

    // MARK: - Protocol Conformance

    @Test("PiHoleClient conforms to PiHoleClientProtocol")
    func protocolConformance() {
        let client = PiHoleClient(host: "http://pi.hole", token: "tok")
        #expect(client is (any PiHoleClientProtocol))
    }
}
