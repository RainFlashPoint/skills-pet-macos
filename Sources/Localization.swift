import Foundation

enum AppLanguage: String {
    case zh
    case en

    private static let defaultsKey = "appLanguage"

    static var current: AppLanguage {
        get {
            if let raw = UserDefaults.standard.string(forKey: defaultsKey),
               let language = AppLanguage(rawValue: raw) {
                return language
            }
            return .zh
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    var title: String {
        switch self {
        case .zh: return "中文"
        case .en: return "English"
        }
    }
}

func L(_ zh: String, _ en: String) -> String {
    AppLanguage.current == .zh ? zh : en
}
