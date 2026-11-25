//
//  PiHoleStoreTests.swift
//  PiHoleControlsTests
//
//  Unit tests for PiHoleStore
//

import Testing
import Foundation
@testable import PiHoleControls

private final class TestStorage {
    let suite = "PiHoleControls.Tests.\(UUID())"
    var token: String?
    var now = Date()
    var defaults: UserDefaults { UserDefaults(suiteName: suite)! }
    deinit { UserDefaults.standard.removePersistentDomain(forName: suite) }
}

@MainActor
@Suite("PiHoleStore Tests")
struct PiHoleStoreTests {

    // MARK: - Test Helpers

    /// Creates a store with a mock client factory and zero retry delay for fast tests
    private func makeStore(mockClient: MockPiHoleClient) -> PiHoleStore {
        let storage = TestStorage()
        let store = PiHoleStore(clientFactory: { _, _, _ in mockClient }, baseRetryDelay: 0,
            defaults: storage.defaults,
            tokenStorage: TokenStorage(load: { storage.token }, save: { storage.token = $0 }),
            cleanupStorage: .memory, monitorNetwork: false)
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

        await store.toggleBlocking()?.value

        #expect(mock.disableBlockingCallCount >= 1)
    }

    @Test("Toggle from disabled calls enable")
    func toggleFromDisabled() async throws {
        let mock = MockPiHoleClient()
        let store = makeStore(mockClient: mock)
        store.isBlockingEnabled = false

        await store.toggleBlocking()?.value

        #expect(mock.enableBlockingCallCount >= 1)
    }

    @Test("Toggle from unknown state refreshes status")
    func toggleFromUnknown() async throws {
        let mock = MockPiHoleClient()
        let store = makeStore(mockClient: mock)
        store.isBlockingEnabled = nil

        await store.toggleBlocking()?.value

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

    @Test func connectionTestSupportsLegacy() async {
        let mock = MockPiHoleClient()
        let store = makeStore(mockClient: mock)
        let result = await store.testConnection()
        guard case .success = result else { Issue.record("Connection failed"); return }
        #expect(mock.lastAllowLegacyFallback == true)
    }

    @Test func storesUseIndependentPreferencesAndTokens() {
        let first = TestStorage()
        let second = TestStorage()
        let a = PiHoleStore(defaults: first.defaults,
            tokenStorage: TokenStorage(load: { first.token }, save: { first.token = $0 }), cleanupStorage: .memory, monitorNetwork: false)
        let b = PiHoleStore(defaults: second.defaults,
            tokenStorage: TokenStorage(load: { second.token }, save: { second.token = $0 }), cleanupStorage: .memory, monitorNetwork: false)
        a.host = "https://first.invalid"
        a.token = "first-token"
        b.token = "second-token"
        a.token = ""
        #expect(b.host.isEmpty)
        #expect(second.token == "second-token")
        #expect(first.defaults.string(forKey: "piholeHost") == "https://first.invalid")
    }

    @Test func testHostHasNoProductionConfiguration() {
        #expect(AppDelegate.isTesting)
        let delegate = AppDelegate()
        #expect(delegate.store.host.isEmpty)
        #expect(delegate.store.token.isEmpty)
    }

    @Test func countdownExpiryDoesNotSendEnable() async {
        let storage = TestStorage()
        let mock = MockPiHoleClient()
        mock.statusToReturn = false
        let store = PiHoleStore(clientFactory: { _, _, _ in mock }, baseRetryDelay: 0,
            defaults: storage.defaults,
            tokenStorage: TokenStorage(load: { storage.token }, save: { storage.token = $0 }),
            cleanupStorage: .memory, monitorNetwork: false, now: { storage.now })
        store.host = "https://first.invalid"
        store.token = "fixture"
        await store.disableBlockingAsync(durationSeconds: 300)
        storage.now.addTimeInterval(301)
        store.updateDisableCountdown()
        await store.refreshStatus().value
        #expect(mock.enableBlockingCallCount == 0)
        #expect(store.remainingDisableSeconds == nil)
        store.host = "https://second.invalid"
        store.updateDisableCountdown()
        #expect(mock.enableBlockingCallCount == 0)
        #expect(store.isBlockingEnabled == nil)
    }

    @Test func staleRefreshCannotOverwriteNewConfiguration() async {
        let mock = MockPiHoleClient()
        let store = makeStore(mockClient: mock)
        var finish: CheckedContinuation<Bool, Never>?
        var oldRefresh: Task<Void, Never>?
        await withCheckedContinuation { started in
            mock.onFetch = {
                await withCheckedContinuation { continuation in
                    finish = continuation
                    started.resume()
                }
            }
            oldRefresh = store.refreshStatus()
        }
        store.host = "https://new.invalid"
        mock.onFetch = nil
        mock.statusToReturn = false
        await store.refreshStatusAsync()
        finish?.resume(returning: true)
        // Wait for the old task, not a wall-clock delay.
        await oldRefresh?.value
        #expect(store.isBlockingEnabled == false)
    }
}
