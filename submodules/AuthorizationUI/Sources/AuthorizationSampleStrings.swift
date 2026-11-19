enum AuthorizationSampleStrings {
    static func isHebrew(languageCode: String) -> Bool {
        languageCode.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first == "he"
    }

    static func explore(languageCode: String) -> String {
        self.isHebrew(languageCode: languageCode) ? "לסייר בדוגמה, בלי חשבון" : "Explore a sample (no account)"
    }
}
