import Foundation

public enum AppLanguage: String, CaseIterable {
    case korean = "ko"
    case english = "en"
}

public struct AppLanguageStore {
    private static let persistenceKey = "referee.app.language"
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    public var language: AppLanguage {
        userDefaults.string(forKey: Self.persistenceKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .korean
    }

    public func set(_ language: AppLanguage) {
        userDefaults.set(language.rawValue, forKey: Self.persistenceKey)
    }
}
