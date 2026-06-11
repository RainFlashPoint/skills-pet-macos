import Foundation
import Security

enum AIProvider: String, CaseIterable {
    case openAI
    case fal
    case replicate
    case custom

    var title: String {
        switch self {
        case .openAI: return "OpenAI"
        case .fal: return "fal.ai"
        case .replicate: return "Replicate"
        case .custom: return L("自定义", "Custom")
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: return "gpt-image-2"
        case .fal: return "fal-ai/flux-kontext"
        case .replicate: return "black-forest-labs/flux-kontext-pro"
        case .custom: return ""
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1/images/edits"
        case .fal: return "https://fal.run/"
        case .replicate: return "https://api.replicate.com/v1/predictions"
        case .custom: return ""
        }
    }
}

enum AIQualityMode: String, CaseIterable {
    case cheap
    case standard
    case high

    var title: String {
        switch self {
        case .cheap: return L("便宜", "Cheap")
        case .standard: return L("标准", "Standard")
        case .high: return L("高质量", "High quality")
        }
    }
}

struct AIModelSettings {
    var isEnabled: Bool
    var provider: AIProvider
    var model: String
    var endpoint: String
    var qualityMode: AIQualityMode

    static let defaults = AIModelSettings(
        isEnabled: false,
        provider: .fal,
        model: AIProvider.fal.defaultModel,
        endpoint: AIProvider.fal.defaultEndpoint,
        qualityMode: .cheap
    )
}

final class AIModelSettingsStore {
    static let shared = AIModelSettingsStore()

    private let defaults = UserDefaults.standard
    private let service = "local.skills-pet-lite.macos.ai"
    private let apiKeyAccount = "api-key"

    private enum Key {
        static let enabled = "aiModel.enabled"
        static let provider = "aiModel.provider"
        static let model = "aiModel.model"
        static let endpoint = "aiModel.endpoint"
        static let quality = "aiModel.quality"
    }

    func load() -> AIModelSettings {
        let provider = defaults.string(forKey: Key.provider)
            .flatMap(AIProvider.init(rawValue:)) ?? AIModelSettings.defaults.provider
        let quality = defaults.string(forKey: Key.quality)
            .flatMap(AIQualityMode.init(rawValue:)) ?? AIModelSettings.defaults.qualityMode

        return AIModelSettings(
            isEnabled: defaults.bool(forKey: Key.enabled),
            provider: provider,
            model: defaults.string(forKey: Key.model) ?? provider.defaultModel,
            endpoint: defaults.string(forKey: Key.endpoint) ?? provider.defaultEndpoint,
            qualityMode: quality
        )
    }

    func save(_ settings: AIModelSettings) {
        defaults.set(settings.isEnabled, forKey: Key.enabled)
        defaults.set(settings.provider.rawValue, forKey: Key.provider)
        defaults.set(settings.model, forKey: Key.model)
        defaults.set(settings.endpoint, forKey: Key.endpoint)
        defaults.set(settings.qualityMode.rawValue, forKey: Key.quality)
    }

    func loadAPIKey() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return ""
        }
        return key
    }

    func saveAPIKey(_ value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount
        ]

        if value.isEmpty {
            SecItemDelete(query as CFDictionary)
            return
        }

        let data = Data(value.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }
}
