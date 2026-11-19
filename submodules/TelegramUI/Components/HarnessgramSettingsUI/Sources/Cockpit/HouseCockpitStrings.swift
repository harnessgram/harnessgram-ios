import Foundation

/// The Cockpit tab's copy (build 23), one place: aviation words for headings and states, plain words for actions.
/// Hebrew only, right to left.
enum HouseCockpitStrings {
    static let tabTitle = "קוקפיט"
    static let screenTitle = "קוקפיט"

    static let decisionsHeader = "אישורי המראה"
    static let decisionsEmpty = "אין אישורים שמחכים לך"
    static let tasksHeader = "לוח טיסה"
    static let tasksEmpty = "אין טיסות באוויר כרגע"
    static let taskLanded = "נחת בשלום"
    static let radioHeader = "שידורי הקוקפיט"
    static let radioStation = "שידורי הקוקפיט"
    static let radioNoLink = "עוד לא חובר. הקשה פותחת את מסך השידורים"
    static let radioPlay = "הפעלת השידורים"
    static let radioPause = "השהיית השידורים"
    static let waitingRow = "מעגל ההמתנה"
    static let waitingRowDetail = "כל מה שמחכה לך, ברשימה אחת"
    static let fullCockpit = "לקוקפיט המלא"
    static let fullCockpitOpening = "פותח את הקוקפיט…"
    static let fullCockpitFailed = "לא הצלחתי לפתוח את הקוקפיט. פותח את הצ׳אט של הגשר"
    static let approve = "אישור"
    static let approveFaceIDHint = "אישור, דורש זיהוי פנים"
    static let seeFirst = "לראות קודם"
    static let choose = "לבחור"
    static let sending = "שולח…"
    static let sendFailed = "לא הצלחתי לשלוח. אפשר לנסות שוב"
    static let loading = "מתחבר למגדל…"
    static let unavailableTitle = "המגדל לא עונה"
    static let unavailableNoAnswer = "הנתונים מהגשר לא הגיעו בזמן. כדאי לבדוק את החיבור לרשת ולנסות שוב."
    static let retry = "לנסות שוב"
    static let originalText = "הטקסט המקורי"
    static let originalYes = "תשובת האישור המקורית"
    static let originalNo = "תשובת הסירוב המקורית"

    static let notPairedTitle = "הקוקפיט עוד לא מחובר"
    static let notPairedDetail = "חיבור אחד לגשר, עם זיהוי פנים, מביא לכאן את אישורי ההמראה ואת לוח הטיסה. זה אותו חיבור של הווידג׳טים."
    static let pausedDetail = "החיבור הושהה כי נכנס חשבון נוסף, הוחלף חשבון או שהייתה התנתקות. אפשר לחבר מחדש."
    static let pair = "חיבור לגשר"
    static let pairing = "מתחבר…"

    static let emptyTitle = "השמיים נקיים"
    static let emptyDetail = "אין אישורים שמחכים לך ואין טיסות באוויר. כשמשהו יגיע, הוא יופיע כאן."

    static let floatingButton = "לקוקפיט"
    static let floatingButtonHint = "פותח את הקוקפיט. אפשר לגרור את הכפתור לצד השני"

    // MARK: The wide layout ("מגדל פיקוח": iPad, Split View, the unfolded phone). English counterpart after each line.

    /// "Control tower"
    static let towerTitle = "מגדל פיקוח"
    /// "Control tower" (the desk column's title)
    static let deskTitle = "מגדל פיקוח"
    /// "Active task"
    static let deskActive = "משימה פעילה"
    /// "Landed"
    static let deskLanded = "נחתה"
    /// "Steps"
    static let deskSteps = "שלבים"
    /// "Progress"
    static let deskProgress = "התקדמות"
    /// "Step"
    static let deskStepLabel = "שלב"
    /// "Last update"
    static let deskUpdatedLabel = "עדכון אחרון"
    /// "Room"
    static let deskRoomLabel = "חדר"
    /// "Open the task's room"
    static let deskOpenRoom = "לחדר המשימה"
    /// "Waiting for you in this task"
    static let deskTaskDecisions = "מחכה לך במשימה הזו"
    /// "Pick a flight from the board"
    static let deskPickTask = "בחרו טיסה מלוח הטיסה"
    /// "Agents in the air"
    static let deskAgents = "סוכנים באוויר"
    /// "No agent is working right now"
    static let deskNoAgents = "אף סוכן לא עובד כרגע"
    /// "Task altitude"
    static let deskAltitude = "גובה משימה"
    /// "Agent"
    static let deskUnnamedAgent = "סוכן"

    // MARK: The phone tower (compact width). English counterpart after each line.

    /// "Operational view" (the radar card)
    static let phoneOverview = "מבט מבצעי"
    /// "Feet" (under the altimeter's reading)
    static let phoneFeet = "רגל"
    /// "No flight in the air" (the altimeter when every task landed)
    static let phoneNoFlight = "אין טיסה באוויר"
    /// "Lead flight"
    static let phoneLeadFlight = "הטיסה המובילה"
    /// "Opens the task's room"
    static let phoneOpenRoomHint = "פותח את חדר המשימה"

    /// "3 flights in the air"
    static func phoneFlying(_ count: Int) -> String {
        return count == 1 ? "טיסה אחת באוויר" : "\(count) טיסות באוויר"
    }

    /// "and 3 more" (agents beyond the shown ones)
    static func phoneMoreAgents(_ count: Int) -> String {
        return count == 1 ? "ועוד אחד" : "ועוד \(count)"
    }

    /// "Step 3 of 5 · tests": the lead flight's step line.
    static func phoneStepLine(position: (current: Int, total: Int)?, step: String, finished: Bool) -> String {
        if finished {
            return HouseCockpitStrings.taskLanded
        }
        var parts: [String] = []
        if let position {
            parts.append("שלב " + HouseCockpitStrings.deskStepOf(position.current, position.total))
        }
        if !step.isEmpty {
            parts.append(step)
        }
        return parts.joined(separator: " · ")
    }

    /// "Step 3 of 5"
    static func deskStepOf(_ current: Int, _ total: Int) -> String {
        return "\(current) מתוך \(total)"
    }

    /// "2 working" (agents at work, beside the radar)
    static func deskRunning(_ count: Int) -> String {
        return count == 1 ? "סוכן אחד בעבודה" : "\(count) סוכנים בעבודה"
    }

    /// "1 waits for you" / "3 wait for you"
    static func deskWaiting(_ count: Int) -> String {
        return count == 1 ? "אחד מחכה לך" : "\(count) מחכים לך"
    }

    /// The tower header's line: "3 flights in the air · 2 wait for you" (the waiting part only when something waits).
    static func towerLine(flying: Int, waiting: Int) -> String {
        let flights = flying == 1 ? "טיסה אחת באוויר" : "\(flying) טיסות באוויר"
        return waiting > 0 ? flights + " · " + HouseCockpitStrings.deskWaiting(waiting) : flights
    }

    /// "Step 3/5 · 60%" on a flight strip, or "Landed" / the percent alone.
    static func stripLine(position: (current: Int, total: Int)?, percent: Int, finished: Bool) -> String {
        if finished {
            return HouseCockpitStrings.taskLanded
        }
        if let position {
            return "שלב \(position.current)/\(position.total) · \(percent)%"
        }
        return "\(percent)%"
    }

    /// "אישורי המראה · 2": a section header with its count; the plain header at 0.
    static func header(_ title: String, count: Int) -> String {
        return count > 0 ? title + " · " + "\(count)" : title
    }

    /// VoiceOver for a waiting count: "2 ממתינים".
    static func waitingLabel(_ count: Int) -> String {
        return count == 1 ? "אחד ממתין" : "\(count) ממתינים"
    }
}
