import Foundation

/// The greeting by time of day (must-keep 6): morning 05:00-11:59, noon 12:00-16:59, evening from 17:00 until
/// the next morning.
public enum HouseGreeting: String, Equatable, Sendable {
    case morning
    case noon
    case evening

    public init(hour: Int) {
        switch hour {
        case 5 ..< 12:
            self = .morning
        case 12 ..< 17:
            self = .noon
        default:
            self = .evening
        }
    }

    public init(date: Date, calendar: Calendar = .current) {
        self.init(hour: calendar.component(.hour, from: date))
    }

    public var text: String {
        switch self {
        case .morning:
            return HouseHomeStrings.string(.greetingMorning)
        case .noon:
            return HouseHomeStrings.string(.greetingNoon)
        case .evening:
            return HouseHomeStrings.string(.greetingEvening)
        }
    }
}
