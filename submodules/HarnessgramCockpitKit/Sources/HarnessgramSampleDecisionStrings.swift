import Foundation

enum HarnessgramSampleDecisionStrings {
    static func decisions(now: Date) -> [HarnessgramCockpitSnapshot.Decision] {
        return [
            .init(id: "sample-reading-room", title: "לבחור איור לפינת הקריאה?", topic: "פינת הקריאה", yesLabel: "כן", noLabel: "לא", topicURL: "", sensitive: false, detail: "הכיתה מכינה כרזה לפינת הקריאה. בתמונה יש ספרים, גלובוס ומטוס קטן. אפשר לבחור אם להשתמש באיור בכרזה.", askedAt: now.addingTimeInterval(-300)),
            .init(id: "sample-gallery", title: "לפתוח את גלריית הציורים לשיתוף?", topic: "גלריית הכיתה", yesLabel: "כן", noLabel: "לא", topicURL: "", sensitive: true, detail: "זאת הדגמה של החלטה שדורשת זיהוי פנים. הגלריה והציורים מתארים פרויקט דמיוני.", askedAt: now.addingTimeInterval(-600)),
        ]
    }
}
