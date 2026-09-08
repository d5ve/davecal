import EventKit
import Foundation

/// What the detail window was opened for: a brand new event, or an existing
/// occurrence identified by its id plus start time.
struct EventRequest: Codable, Hashable {
    var eventIdentifier: String?
    var date: Date
    /// For a new event: `date` is the exact start time rather than just a day.
    var startsAtTime = false

    var isNew: Bool { eventIdentifier == nil }

    static func newEvent(on day: Date) -> EventRequest {
        EventRequest(eventIdentifier: nil, date: day)
    }

    static func newEvent(at time: Date) -> EventRequest {
        EventRequest(eventIdentifier: nil, date: time, startsAtTime: true)
    }

    static func existing(_ event: EKEvent) -> EventRequest {
        EventRequest(eventIdentifier: event.eventIdentifier, date: event.startDate)
    }
}
