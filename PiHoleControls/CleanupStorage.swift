import Foundation

struct CleanupStorage {
    var load: () throws -> Data?
    var save: (Data) throws -> Void

    static var file: CleanupStorage {
        let directory = URL.applicationSupportDirectory.appendingPathComponent("PiHoleControls", isDirectory: true)
        let url = directory.appendingPathComponent("temporary-allowlist-cleanup.json")
        return CleanupStorage(load: {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try Data(contentsOf: url)
        }, save: { data in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        })
    }

    static var memory: CleanupStorage {
        var data: Data?
        return CleanupStorage(load: { data }, save: { data = $0 })
    }
}
