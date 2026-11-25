import Testing
import Foundation
@testable import PiHoleKit

@Suite("ServerConfiguration Tests")
struct ServerConfigurationTests {

    // MARK: - Model Tests

    @Test("Round-trip encode/decode preserves all fields")
    func roundTrip() throws {
        let id = UUID()
        let config = ServerConfiguration(id: id, name: "Home Pi", host: "https://pi.hole", allowSelfSignedCert: true)

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ServerConfiguration.self, from: data)

        #expect(decoded.id == id)
        #expect(decoded.name == "Home Pi")
        #expect(decoded.host == "https://pi.hole")
        #expect(decoded.allowSelfSignedCert == true)
    }

    @Test("isValid returns true for non-empty host")
    func isValidTrue() {
        let config = ServerConfiguration(name: "Test", host: "https://pi.hole")
        #expect(config.isValid == true)
    }

    @Test("isValid returns false for empty host")
    func isValidFalseEmpty() {
        let config = ServerConfiguration(name: "Test", host: "")
        #expect(config.isValid == false)
    }

    @Test("isValid returns false for whitespace-only host")
    func isValidFalseWhitespace() {
        let config = ServerConfiguration(name: "Test", host: "   ")
        #expect(config.isValid == false)
    }

    @Test("tokenKeychainKey includes UUID")
    func tokenKeychainKey() {
        let id = UUID()
        let config = ServerConfiguration(id: id, name: "Test", host: "https://pi.hole")
        #expect(config.tokenKeychainKey == "apiToken-\(id.uuidString)")
    }

    @Test("Default allowSelfSignedCert is false")
    func defaultSelfSignedCert() {
        let config = ServerConfiguration(name: "Test", host: "https://pi.hole")
        #expect(config.allowSelfSignedCert == false)
    }

    @Test("Equatable compares all fields")
    func equatable() {
        let id = UUID()
        let a = ServerConfiguration(id: id, name: "A", host: "https://a.hole")
        let b = ServerConfiguration(id: id, name: "A", host: "https://a.hole")
        let c = ServerConfiguration(id: id, name: "B", host: "https://a.hole")

        #expect(a == b)
        #expect(a != c)
    }
}

@Suite("ServerConfigurationStore Tests")
struct ServerConfigurationStoreTests {

    private let testSuiteName = "com.test.pihole.\(UUID().uuidString.prefix(8))"

    private func makeStore() -> ServerConfigurationStore {
        ServerConfigurationStore(suiteName: testSuiteName)
    }

    private func cleanup() {
        UserDefaults(suiteName: testSuiteName)?.removePersistentDomain(forName: testSuiteName)
    }

    // MARK: - CRUD Tests

    @Test("Empty store returns empty array")
    func emptyStore() {
        let store = makeStore()
        defer { cleanup() }

        #expect(store.servers.isEmpty)
    }

    @Test("Add server persists to UserDefaults")
    func addServer() {
        let store = makeStore()
        defer { cleanup() }

        let config = ServerConfiguration(name: "Home", host: "https://pi.hole")
        store.add(config)

        #expect(store.servers.count == 1)
        #expect(store.servers.first?.name == "Home")
    }

    @Test("Add multiple servers")
    func addMultiple() {
        let store = makeStore()
        defer { cleanup() }

        store.add(ServerConfiguration(name: "Home", host: "https://pi1.hole"))
        store.add(ServerConfiguration(name: "Office", host: "https://pi2.hole"))

        #expect(store.servers.count == 2)
    }

    @Test("Update server modifies existing entry")
    func updateServer() {
        let store = makeStore()
        defer { cleanup() }

        var config = ServerConfiguration(name: "Home", host: "https://pi.hole")
        store.add(config)

        config.name = "Updated Home"
        config.host = "https://new.hole"
        store.update(config)

        #expect(store.servers.count == 1)
        #expect(store.servers.first?.name == "Updated Home")
        #expect(store.servers.first?.host == "https://new.hole")
    }

    @Test("Delete server removes entry")
    func deleteServer() {
        let store = makeStore()
        defer { cleanup() }

        let config = ServerConfiguration(name: "Home", host: "https://pi.hole")
        store.add(config)
        store.delete(config.id)

        #expect(store.servers.isEmpty)
    }

    @Test("Delete last server returns to empty state")
    func deleteLastServer() {
        let store = makeStore()
        defer { cleanup() }

        let config = ServerConfiguration(name: "Only One", host: "https://pi.hole")
        store.add(config)

        #expect(store.servers.count == 1)
        store.delete(config.id)
        #expect(store.servers.isEmpty)
    }

    @Test("Delete server also removes Keychain token")
    func deleteRemovesToken() throws {
        let store = makeStore()
        defer { cleanup() }

        let config = ServerConfiguration(name: "Home", host: "https://pi.hole")
        store.add(config)
        try store.saveToken("secret-token", for: config)

        #expect(store.retrieveToken(for: config) == "secret-token")

        store.delete(config.id)
        #expect(store.retrieveToken(for: config) == nil)
    }

    // MARK: - Token Tests

    @Test("Save and retrieve token for server")
    func saveAndRetrieveToken() throws {
        let store = makeStore()
        defer { cleanup() }

        let config = ServerConfiguration(name: "Home", host: "https://pi.hole")
        try store.saveToken("my-api-token", for: config)

        let retrieved = store.retrieveToken(for: config)
        #expect(retrieved == "my-api-token")

        try KeychainHelper.delete(key: config.tokenKeychainKey)
    }

    @Test("Retrieve token returns nil when not set")
    func retrieveTokenNil() {
        let store = makeStore()
        defer { cleanup() }

        let config = ServerConfiguration(name: "Home", host: "https://pi.hole")
        #expect(store.retrieveToken(for: config) == nil)
    }

    // MARK: - Corrupt Data Tests

    @Test("Loading corrupt data returns empty array")
    func corruptDataReturnsEmpty() {
        let store = makeStore()
        defer { cleanup() }

        let defaults = UserDefaults(suiteName: testSuiteName)!
        defaults.set(Data("not valid json".utf8), forKey: "serverConfigurations")

        #expect(store.servers.isEmpty)
    }

    @Test("Loading missing key returns empty array")
    func missingKeyReturnsEmpty() {
        let store = makeStore()
        defer { cleanup() }

        #expect(store.servers.isEmpty)
    }

    // MARK: - Persistence Across Instances

    @Test("Data persists across store instances with same suite")
    func persistsAcrossInstances() {
        defer { cleanup() }

        let store1 = makeStore()
        let config = ServerConfiguration(name: "Persisted", host: "https://pi.hole")
        store1.add(config)

        let store2 = ServerConfigurationStore(suiteName: testSuiteName)
        #expect(store2.servers.count == 1)
        #expect(store2.servers.first?.name == "Persisted")
    }
}
