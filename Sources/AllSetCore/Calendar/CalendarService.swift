import AppKit
import EventKit
import Observation

/// Upcoming events from the Calendar app, for the Calendar widget.
@Observable @MainActor
public final class CalendarService {
    public struct Event: Identifiable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var start: Date
        public var end: Date
        public var isAllDay: Bool
        public var color: WidgetColor?
    }

    public enum Access: Sendable {
        case notDetermined
        case granted
        case denied
        /// Running without an Info.plist (e.g. from `.build`), where asking
        /// would crash; the packaged app can ask.
        case unavailable
    }

    public private(set) var events: [Event] = []
    public private(set) var access: Access = .notDetermined

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var changeObserver: NSObjectProtocol?
    @ObservationIgnored private var refreshLoop: Task<Void, Never>?

    public init() {}

    public func start() {
        updateAccess()
        guard changeObserver == nil else { return }
        changeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // Keeps "in 10 min" labels and the day's list current.
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    public func requestAccess() async {
        guard access == .notDetermined else { return }
        let granted: Bool = await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { granted, _ in
                continuation.resume(returning: granted)
            }
        }
        access = granted ? .granted : .denied
        refresh()
    }

    public func refresh() {
        updateAccess()
        guard access == .granted else {
            if !events.isEmpty { events = [] }
            return
        }
        let now = Date.now
        let predicate = store.predicateForEvents(withStart: Calendar.current.startOfDay(for: now),
                                                 end: now.addingTimeInterval(7 * 24 * 3600), calendars: nil)
        let upcoming = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(12)
            .map { event in
                // Every occurrence of a repeating event shares one identifier.
                Event(id: "\(event.eventIdentifier ?? event.title ?? "")|\(event.startDate.timeIntervalSince1970)",
                      title: event.title ?? "Untitled",
                      start: event.startDate,
                      end: event.endDate,
                      isAllDay: event.isAllDay,
                      color: Self.color(event.calendar?.color))
            }
        let list = Array(upcoming)
        if list != events { events = list }
    }

    private func updateAccess() {
        let current: Access
        if Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") == nil {
            current = .unavailable
        } else {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess: current = .granted
            case .notDetermined: current = .notDetermined
            default: current = .denied
            }
        }
        // Setting it even unchanged would redraw everything showing it.
        if current != access { access = current }
    }

    private static func color(_ color: NSColor?) -> WidgetColor? {
        guard let rgb = color?.usingColorSpace(.sRGB) else { return nil }
        return WidgetColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }
}
