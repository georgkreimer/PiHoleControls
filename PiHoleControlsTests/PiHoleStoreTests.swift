//
//  PiHoleStoreTests.swift
//  PiHoleControlsTests
//
//  Unit tests for PiHoleStore
//

import Testing
import Foundation
@testable import PiHoleControls

@MainActor
@Suite("PiHoleStore Tests")
struct PiHoleStoreTests {

    // MARK: - Test Helpers

    /// Creates a store with a mock client factory and zero retry delay for fast tests
    private func makeStore(mockClient: MockPiHoleClient) -> PiHoleStore {
        let store = PiHoleStore(clientFactory: { _, _, _ in mockClient }, baseRetryDelay: 0)
        store.host = "http://test.pi.hole"
        store.token = "test-token"
        return store
    }

    // MARK: - Status Fetch Tests

    @Test("Fetch status success - blocking enabled")
    func fetchStatusBlockingEnabled() async throws {
        let mock = MockPiHoleClient()
        mock.statusToReturn = true
        let store = makeStore(mockClient: mock)

        await store.refreshStatusAsync()

        #expect(store.isBlockingEnabled == true)
        #expect(store.lastError == nil)
        #expect(mock.fetchStatusCallCount >= 1)
    }

    @Test("Fetch status success - blocking disabled")
    func fetchStatusBlockingDisabled() async throws {
        let mock = MockPiHoleClient()
        mock.statusToReturn = false
        let store = makeStore(mockClient: mock)

        await store.refreshStatusAsync()

        #expect(store.isBlockingEnabled == false)
        #expect(store.lastError == nil)
    }

    @Test("Fetch status error sets lastError")
    func fetchStatusError() async throws {
        let mock = MockPiHoleClient()
        mock.errorToThrow = PiHoleClient.PiHoleError.invalidResponse(
            statusCode: 500,
            bodyPreview: nil,
            endpoint: "/api/status",
            diagnostics: nil
        )
        let store = makeStore(mockClient: mock)

        await store.refreshStatusAsync()

        #expect(store.lastError != nil)
        #expect(store.lastError?.contains("500") == true)
        // With zero retry delay and 3 attempts, all retries should complete instantly
        #expect(mock.fetchStatusCallCount == 3)
    }

    @Test("Fetch status legacy 500 surfaces once")
    func fetchStatusLegacy500NoRetry() async throws {
        let mock = MockPiHoleClient()
        mock.errorToThrow = PiHoleClient.PiHoleError.invalidResponse(
            statusCode: 500,
            bodyPreview: nil,
            endpoint: "admin/api.php",
            diagnostics: PiHoleClient.LegacyErrorDiagnostics(
                method: "GET",
                endpoint: "admin/api.php",
                statusCode: 500,
                action: "status refresh",
                authMode: "query token",
                tokenLooksLikeAppPassword: true
            )
        )
        let store = makeStore(mockClient: mock)

        await store.refreshStatusAsync()

        #expect(store.isLoading == false)
        #expect(mock.fetchStatusCallCount == 1)
        #expect(store.lastError?.contains("Next steps") == true)
    }

    // MARK: - Toggle Blocking Tests

    @Test("Toggle from enabled calls disable")
    func toggleFromEnabled() async throws {
        let mock = MockPiHoleClient()
        let store = makeStore(mockClient: mock)
        store.isBlockingEnabled = true

        store.toggleBlocking()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(mock.disableBlockingCallCount >= 1)
    }

    @Test("Toggle from disabled calls enable")
    func toggleFromDisabled() async throws {
        let mock = MockPiHoleClient()
        let store = makeStore(mockClient: mock)
        store.isBlockingEnabled = false

        store.toggleBlocking()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(mock.enableBlockingCallCount >= 1)
    }

    @Test("Toggle from unknown state refreshes status")
    func toggleFromUnknown() async throws {
        let mock = MockPiHoleClient()
        let store = makeStore(mockClient: mock)
        store.isBlockingEnabled = nil

        store.toggleBlocking()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(mock.fetchStatusCallCount >= 1)
        #expect(mock.enableBlockingCallCount == 0)
        #expect(mock.disableBlockingCallCount == 0)
    }

    // MARK: - Enable/Disable Tests

    @Test("Enable blocking updates state to true")
    func enableBlockingUpdatesState() async throws {
        let mock = MockPiHoleClient()
        let store = makeStore(mockClient: mock)
        store.isBlockingEnabled = false

        await store.enableBlockingAsync()

        #expect(store.isBlockingEnabled == true)
        #expect(mock.enableBlockingCallCount >= 1)
    }

    @Test("Disable blocking updates state to false")
    func disableBlockingUpdatesState() async throws {
        let mock = MockPiHoleClient()
        let store = makeStore(mockClient: mock)
        store.isBlockingEnabled = true

        await store.disableBlockingAsync(durationSeconds: 300)

        #expect(store.isBlockingEnabled == false)
        #expect(mock.disableBlockingCallCount >= 1)
        #expect(mock.lastDisableDuration == 300)
    }

    // MARK: - Configuration Tests

    @Test("isConfigured returns true when host and token set")
    func isConfiguredTrue() async throws {
        let mock = MockPiHoleClient()
        let store = makeStore(mockClient: mock)

        #expect(store.isConfigured == true)
    }

    @Test("isConfigured returns false when host empty")
    func isConfiguredFalseNoHost() async throws {
        let mock = MockPiHoleClient()
        let store = makeStore(mockClient: mock)
        store.host = ""

        #expect(store.isConfigured == false)
    }

    @Test("isConfigured returns false when token empty")
    func isConfiguredFalseNoToken() async throws {
        let mock = MockPiHoleClient()
        let store = makeStore(mockClient: mock)
        store.token = ""

        #expect(store.isConfigured == false)
    }

    // MARK: - Loading State Tests

    @Test("Toggle blocked while loading")
    func toggleBlockedWhileLoading() async throws {
        let mock = MockPiHoleClient()
        let store = makeStore(mockClient: mock)
        store.isLoading = true
        store.isBlockingEnabled = true

        store.toggleBlocking()

        // Should not have called anything because loading was true
        #expect(mock.disableBlockingCallCount == 0)
        #expect(mock.enableBlockingCallCount == 0)
    }
}
