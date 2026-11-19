import Foundation

struct SampleHeading: Sendable {
    let hebrew: String
    let english: String

    init(_ hebrew: String, _ english: String) {
        self.hebrew = hebrew
        self.english = english
    }
}

enum SampleBannerStrings {
    static let heading = SampleHeading("נתוני דוגמה", "Sample data")
    static let exit = SampleHeading("יציאה", "Exit")
    static let failedToOpen = "לא הצלחנו לפתוח את הדוגמה."
    static let failedToErase = "מחיקת הדוגמה נכשלה. אפשר לנסות לצאת שוב."
    static let failedToSave = "השינוי לא נשמר. אפשר לנסות שוב."
    static let ok = "בסדר"
}
