import Foundation
import Observation

enum SyncMode: String, Codable, CaseIterable {
    case automatic, manual, off
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
    var textAdapter: LLMAdapterConfig
    var imageAdapter: LLMAdapterConfig
    var syncMode: SyncMode
    var bidirectionalCompletionSyncEnabled: Bool
    var logEnabled: Bool
    var logPath: String

    init() {
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
    }

    func save() {
        let defaults = UserDefaults.standard
        let encoder = JSONEncoder()
        if let textData = try? encoder.encode(textAdapter),
           let imageData = try? encoder.encode(imageAdapter) {
            defaults.set(textData, forKey: "com.grip.text-adapter")
            defaults.set(imageData, forKey: "com.grip.image-adapter")
        }
        defaults.set(syncMode.rawValue, forKey: "com.grip.sync-mode")
        defaults.set(bidirectionalCompletionSyncEnabled, forKey: "com.grip.bidirectional-completion-sync-enabled")
        defaults.set(logEnabled, forKey: "com.grip.log-enabled")
        defaults.set(logPath, forKey: "com.grip.log-path")
    }

    func load() {
        let defaults = UserDefaults.standard
        let decoder = JSONDecoder()
        if let textData = defaults.data(forKey: "com.grip.text-adapter"),
           let config = try? decoder.decode(LLMAdapterConfig.self, from: textData) {
            textAdapter = config
        }
        if let imageData = defaults.data(forKey: "com.grip.image-adapter"),
           let config = try? decoder.decode(LLMAdapterConfig.self, from: imageData) {
            imageAdapter = config
        }
        if let raw = defaults.string(forKey: "com.grip.sync-mode"),
           let mode = SyncMode(rawValue: raw) {
            syncMode = mode
        }
        bidirectionalCompletionSyncEnabled = defaults.bool(forKey: "com.grip.bidirectional-completion-sync-enabled")
        logEnabled = defaults.bool(forKey: "com.grip.log-enabled")
        logPath = defaults.string(forKey: "com.grip.log-path") ?? ""
    }
}
