import Foundation
import Observation

enum SyncMode: String, Codable, CaseIterable {
    case automatic, manual, off
}

enum AppAppearanceMode: String, Codable, CaseIterable {
    case system, blueWhite, dark

    var displayName: String {
        switch self {
        case .system: "跟随系统"
        case .blueWhite: "蓝白"
        case .dark: "深色"
        }
    }

}

struct LLMAdapterConfig: Codable, Identifiable {
    var id: UUID
    var name: String
    var apiURL: String
    var model: String
    var keychainKey: String

    init(name: String, apiURL: String = "", model: String = "", keychainKey: String) {
        self.id = UUID()
        self.name = name
        self.apiURL = apiURL
        self.model = model
        self.keychainKey = keychainKey
    }
}

@Observable
final class LLMConfig {
    enum Keys {
        static let textAdapter = "com.grip.text-adapter"
        static let imageAdapter = "com.grip.image-adapter"
        static let syncMode = "com.grip.sync-mode"
        static let bidirectionalCompletionSyncEnabled = "com.grip.bidirectional-completion-sync-enabled"
        static let logEnabled = "com.grip.log-enabled"
        static let logPath = "com.grip.log-path"
        static let appearanceMode = "com.grip.appearance-mode"
    }

    var textAdapter: LLMAdapterConfig
    var imageAdapter: LLMAdapterConfig
    var syncMode: SyncMode
    var bidirectionalCompletionSyncEnabled: Bool
    var logEnabled: Bool
    var logPath: String
    var appearanceModeRawValue: String
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.textAdapter = LLMAdapterConfig(
            name: "文本模型",
            apiURL: "https://api.openai.com/v1/chat/completions",
            model: "gpt-4o",
            keychainKey: "com.grip.text-api-key"
        )
        self.imageAdapter = LLMAdapterConfig(
            name: "图片模型",
            apiURL: "https://api.openai.com/v1/chat/completions",
            model: "gpt-4o",
            keychainKey: "com.grip.image-api-key"
        )
        self.syncMode = .manual
        self.bidirectionalCompletionSyncEnabled = false
        self.logEnabled = true
        self.logPath = ""
        self.appearanceModeRawValue = AppAppearanceMode.system.rawValue
    }

    func save() {
        let encoder = JSONEncoder()
        if let textData = try? encoder.encode(textAdapter),
           let imageData = try? encoder.encode(imageAdapter) {
            defaults.set(textData, forKey: Keys.textAdapter)
            defaults.set(imageData, forKey: Keys.imageAdapter)
        }
        defaults.set(syncMode.rawValue, forKey: Keys.syncMode)
        defaults.set(bidirectionalCompletionSyncEnabled, forKey: Keys.bidirectionalCompletionSyncEnabled)
        defaults.set(logEnabled, forKey: Keys.logEnabled)
        defaults.set(logPath, forKey: Keys.logPath)
        defaults.set(appearanceModeRawValue, forKey: Keys.appearanceMode)
    }

    func load() {
        let decoder = JSONDecoder()
        if let textData = defaults.data(forKey: Keys.textAdapter),
           let config = try? decoder.decode(LLMAdapterConfig.self, from: textData) {
            textAdapter = config
        }
        if let imageData = defaults.data(forKey: Keys.imageAdapter),
           let config = try? decoder.decode(LLMAdapterConfig.self, from: imageData) {
            imageAdapter = config
        }
        if let raw = defaults.string(forKey: Keys.syncMode),
           let mode = SyncMode(rawValue: raw) {
            syncMode = mode
        }
        if let raw = defaults.string(forKey: Keys.appearanceMode),
           let mode = AppAppearanceMode(rawValue: raw) {
            appearanceModeRawValue = mode.rawValue
        }
        bidirectionalCompletionSyncEnabled = defaults.bool(forKey: Keys.bidirectionalCompletionSyncEnabled)
        logEnabled = defaults.bool(forKey: Keys.logEnabled)
        logPath = defaults.string(forKey: Keys.logPath) ?? ""
    }
}
