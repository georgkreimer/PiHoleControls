import Foundation

struct TokenStorage {
    var load: () -> String?
    var save: (String) throws -> Void

    static var keychain: TokenStorage {
        TokenStorage(load: { KeychainHelper.retrieve(key: "piholeAPIToken") },
                     save: { try KeychainHelper.save(key: "piholeAPIToken", value: $0) })
    }
}
