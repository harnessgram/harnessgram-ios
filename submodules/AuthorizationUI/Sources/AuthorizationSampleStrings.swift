import Foundation

enum AuthorizationSampleStrings {
    static func isHebrew(languageCode: String) -> Bool {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["HARNESSGRAM_DEMO_LANGUAGE"] == "he" {
            return true
        }
        let languages = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages
        if let language = languages.first, self.isHebrewCode(language) {
            return true
        }
        #endif
        return self.isHebrewCode(languageCode)
    }

    private static func isHebrewCode(_ languageCode: String) -> Bool {
        languageCode.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first == "he"
    }

    static func explore(languageCode: String) -> String {
        self.isHebrew(languageCode: languageCode) ? "לסייר בדוגמה, בלי חשבון" : "Explore a sample (no account)"
    }
}
