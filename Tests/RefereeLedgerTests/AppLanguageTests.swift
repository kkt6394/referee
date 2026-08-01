import Foundation
import XCTest
@testable import RefereeLedger

final class AppLanguageTests: XCTestCase {
    private let languageKey = "referee.app.language"

    func testDefaultsToKoreanWhenNoLanguageIsStored() {
        let defaults = makeDefaults()

        XCTAssertEqual(AppLanguageStore(userDefaults: defaults).language, .korean)
    }

    func testPersistsEnglishLanguageSelection() {
        let defaults = makeDefaults()
        let store = AppLanguageStore(userDefaults: defaults)

        store.set(.english)

        XCTAssertEqual(AppLanguageStore(userDefaults: defaults).language, .english)
        XCTAssertEqual(defaults.string(forKey: languageKey), "en")
    }

    func testFallsBackToKoreanForAnInvalidStoredLanguage() {
        let defaults = makeDefaults()
        defaults.set("fr", forKey: languageKey)

        XCTAssertEqual(AppLanguageStore(userDefaults: defaults).language, .korean)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AppLanguageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
