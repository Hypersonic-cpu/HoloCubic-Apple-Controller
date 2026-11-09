import Foundation

struct BLEConfiguration: Codable, Equatable {
    static let defaultToken = "clocteck-ble-debug-2026"

    var enabled = true
    var token = Self.defaultToken
    var advertiseOnLaunch = true

    enum CodingKeys: String, CodingKey {
        case enabled
        case token
        case advertiseOnLaunch = "advertise_on_launch"
    }
}

struct BLEConfigurationStore {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
            self.fileURL = base
                .appendingPathComponent("MacCtrlHTTP", isDirectory: true)
                .appendingPathComponent("ble.json", isDirectory: false)
        }
    }

    func loadOrCreate() throws -> BLEConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let configuration = BLEConfiguration()
            try save(configuration)
            return configuration
        }
        let data = try Data(contentsOf: fileURL)
        let configuration = try JSONDecoder().decode(BLEConfiguration.self, from: data)
        guard (1...256).contains(configuration.token.utf8.count) else {
            throw BLEConfigurationError.invalidToken
        }
        return configuration
    }

    func save(_ configuration: BLEConfiguration) throws {
        guard (1...256).contains(configuration.token.utf8.count) else {
            throw BLEConfigurationError.invalidToken
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(configuration)
        try data.write(to: fileURL, options: .atomic)
    }
}

enum BLEConfigurationError: Error, LocalizedError {
    case invalidToken

    var errorDescription: String? {
        switch self {
        case .invalidToken: "BLE token must contain 1–256 UTF-8 bytes"
        }
    }
}
