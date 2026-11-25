import Foundation

public struct ServerConfiguration: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var host: String
    public var allowSelfSignedCert: Bool

    public init(id: UUID = UUID(), name: String, host: String, allowSelfSignedCert: Bool = false) {
        self.id = id
        self.name = name
        self.host = host
        self.allowSelfSignedCert = allowSelfSignedCert
    }

    public var isValid: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var tokenKeychainKey: String {
        "apiToken-\(id.uuidString)"
    }
}

public class ServerConfigurationStore {
    private let userDefaults: UserDefaults
    private let keychainAccessGroup: String?
    private static let storageKey = "serverConfigurations"

    public init(suiteName: String? = nil, keychainAccessGroup: String? = nil) {
        self.userDefaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        self.keychainAccessGroup = keychainAccessGroup
    }

    public var servers: [ServerConfiguration] {
        get {
            guard let data = userDefaults.data(forKey: Self.storageKey) else { return [] }
            return (try? JSONDecoder().decode([ServerConfiguration].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            userDefaults.set(data, forKey: Self.storageKey)
        }
    }

    public func add(_ server: ServerConfiguration) {
        var current = servers
        current.append(server)
        servers = current
    }

    public func update(_ server: ServerConfiguration) {
        var current = servers
        guard let index = current.firstIndex(where: { $0.id == server.id }) else { return }
        current[index] = server
        servers = current
    }

    public func delete(_ id: UUID) {
        var current = servers
        guard let index = current.firstIndex(where: { $0.id == id }) else { return }
        let server = current.remove(at: index)
        servers = current
        try? KeychainHelper.delete(key: server.tokenKeychainKey, accessGroup: keychainAccessGroup)
    }

    public func saveToken(_ token: String, for server: ServerConfiguration) throws {
        try KeychainHelper.save(key: server.tokenKeychainKey, value: token, accessGroup: keychainAccessGroup)
    }

    public func retrieveToken(for server: ServerConfiguration) -> String? {
        KeychainHelper.retrieve(key: server.tokenKeychainKey, accessGroup: keychainAccessGroup)
    }
}
