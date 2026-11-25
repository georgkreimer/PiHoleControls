import Foundation
import Testing
@testable import PiHoleControls

@MainActor
@Suite struct TempAllowCleanupTests {
    @MainActor private final class Fixture {
        let suite = "PiHoleControls.CleanupTests.\(UUID())"
        var defaults: UserDefaults { UserDefaults(suiteName: suite)! }
        var data: Data?
        var failSave = false
        let mock = MockPiHoleClient()
        var clients: [String] = []
        deinit { UserDefaults.standard.removePersistentDomain(forName: suite) }

        func makeStore() -> PiHoleStore {
            let store = PiHoleStore(clientFactory: { host, _, _ in
                self.clients.append(host)
                return self.mock
            }, baseRetryDelay: 0, defaults: defaults,
                tokenStorage: TokenStorage(load: { nil }, save: { _ in }),
                cleanupStorage: CleanupStorage(load: { self.data }, save: {
                    if self.failSave { throw URLError(.cannotWriteToFile) }
                    self.data = $0
                }), automaticCleanup: false, monitorNetwork: false)
            store.host = "https://original.invalid"
            store.token = "fixture"
            return store
        }

        func seedLegacy() throws {
            let entry = PiHoleStore.TempAllowEntry(domain: "ads.invalid", expiresAt: .distantPast)
            defaults.set(try JSONEncoder().encode([entry]), forKey: "tempAllowList")
        }
    }

    @Test func newExceptionsAreDisabled() {
        let fixture = Fixture()
        let store = fixture.makeStore()
        store.tempAllowDomain("ads.invalid", durationSeconds: 300)
        #expect(fixture.mock.allowedDomains.isEmpty)
        #expect(store.tempAllowList.isEmpty)
        #expect(store.lastError != nil)
    }

    @Test func expiredLegacyEntryNeedsConfirmation() async throws {
        let fixture = Fixture()
        try fixture.seedLegacy()
        let store = fixture.makeStore()
        await store.retryTempAllowCleanup()
        #expect(store.tempAllowList.count == 1)
        #expect(store.tempAllowList.first?.server == nil)
        #expect(fixture.mock.removedDomains.isEmpty)
        #expect(fixture.data != nil)
        #expect(fixture.defaults.data(forKey: "tempAllowList") == nil)
    }

    @Test func failedRemovalSurvivesRestartAndRetries() async throws {
        let fixture = Fixture()
        try fixture.seedLegacy()
        let store = fixture.makeStore()
        fixture.mock.errorToThrow = URLError(.notConnectedToInternet)
        await store.confirmTempAllowRemoval(store.tempAllowList[0], server: store.cleanupServer!)
        #expect(store.tempAllowList.count == 1)
        #expect(store.cleanupError != nil)
        let restarted = fixture.makeStore()
        #expect(restarted.tempAllowList.first?.server == restarted.cleanupServer)
        fixture.mock.errorToThrow = nil
        await restarted.retryTempAllowCleanup()
        #expect(restarted.tempAllowList.isEmpty)
        #expect(fixture.mock.removedDomains == ["ads.invalid"])
        #expect(try JSONDecoder().decode([PiHoleStore.TempAllowEntry].self, from: fixture.data!).isEmpty)
    }

    @Test func serverSwitchNeverRedirectsCleanup() async throws {
        let fixture = Fixture()
        try fixture.seedLegacy()
        let store = fixture.makeStore()
        let original = store.cleanupServer!
        let entry = store.tempAllowList[0]
        store.host = "https://different.invalid"
        await store.confirmTempAllowRemoval(entry, server: original)
        #expect(fixture.mock.removedDomains.isEmpty)
        store.host = "https://original.invalid"
        fixture.mock.errorToThrow = URLError(.timedOut)
        await store.confirmTempAllowRemoval(entry, server: original)
        store.host = "https://different.invalid"
        fixture.mock.errorToThrow = nil
        await store.retryTempAllowCleanup()
        #expect(fixture.mock.removedDomains.isEmpty)
        #expect(store.tempAllowList.count == 1)
    }

    @Test func persistenceFailurePreventsDeletion() async throws {
        let fixture = Fixture()
        try fixture.seedLegacy()
        let store = fixture.makeStore()
        fixture.failSave = true
        await store.confirmTempAllowRemoval(store.tempAllowList[0], server: store.cleanupServer!)
        #expect(fixture.mock.removedDomains.isEmpty)
        #expect(store.tempAllowList.first?.server == nil)
        #expect(store.cleanupError != nil)
    }

    @Test func migrationFailureKeepsLegacyCopy() throws {
        let fixture = Fixture()
        try fixture.seedLegacy()
        fixture.failSave = true
        let store = fixture.makeStore()
        #expect(store.tempAllowList.count == 1)
        #expect(store.cleanupError != nil)
        #expect(fixture.defaults.data(forKey: "tempAllowList") != nil)
    }

    @Test func successfulDeletionWithFailedJournalWriteRemainsPending() async throws {
        let fixture = Fixture()
        try fixture.seedLegacy()
        let store = fixture.makeStore()
        fixture.mock.onRemove = { fixture.failSave = true }
        await store.confirmTempAllowRemoval(store.tempAllowList[0], server: store.cleanupServer!)
        #expect(fixture.mock.removedDomains == ["ads.invalid"])
        #expect(store.tempAllowList.count == 1)
        #expect(store.cleanupError != nil)
        #expect(fixture.makeStore().tempAllowList.count == 1)
    }

    @Test func inFlightCleanupIsNotDuplicatedOrRedirected() async throws {
        let fixture = Fixture()
        try fixture.seedLegacy()
        let store = fixture.makeStore()
        var finish: CheckedContinuation<Void, Never>?
        var first: Task<Void, Never>?
        await withCheckedContinuation { started in
            fixture.mock.onRemove = {
                await withCheckedContinuation { continuation in
                    finish = continuation
                    started.resume()
                }
            }
            first = Task { await store.confirmTempAllowRemoval(store.tempAllowList[0], server: store.cleanupServer!) }
        }
        await store.retryTempAllowCleanup()
        #expect(fixture.mock.removedDomains.count == 1)
        store.host = "https://different.invalid"
        await store.retryTempAllowCleanup()
        #expect(fixture.mock.removedDomains.count == 1)
        finish?.resume()
        await first?.value
        #expect(store.tempAllowList.isEmpty)
    }

    @Test func malformedJournalIsNotOverwritten() async {
        let fixture = Fixture()
        fixture.data = Data("corrupt".utf8)
        let store = fixture.makeStore()
        await store.retryTempAllowCleanup()
        #expect(store.cleanupError != nil)
        #expect(fixture.data == Data("corrupt".utf8))
        #expect(fixture.mock.removedDomains.isEmpty)
    }
}
