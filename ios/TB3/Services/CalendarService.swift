// TB3 iOS — Calendar Service (EventKit integration)
// Logs completed workouts and optionally schedules future sessions on device calendar.

import Foundation
import EventKit
import UIKit

@MainActor
final class CalendarService {
    private let calendarState: CalendarState
    private let eventStore = EKEventStore()

    private static let calendarTitle = "TB3"
    private static let futureIdentifiersKey = "tb3_calendar_future_event_ids"
    private static let calendarIdKey = "tb3_calendar_identifier"

    init(calendarState: CalendarState) {
        self.calendarState = calendarState
    }

    // MARK: - Restore Connection (app launch)

    func restoreConnection() {
        guard let storedId = UserDefaults.standard.string(forKey: Self.calendarIdKey) else { return }

        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess || status == .authorized else {
            UserDefaults.standard.removeObject(forKey: Self.calendarIdKey)
            return
        }

        guard eventStore.calendar(withIdentifier: storedId) != nil else {
            UserDefaults.standard.removeObject(forKey: Self.calendarIdKey)
            return
        }

        calendarState.calendarIdentifier = storedId
        calendarState.isConnected = true
    }

    // MARK: - Connect

    func connect() async {
        calendarState.isLoading = true
        defer { calendarState.isLoading = false }

        do {
            let granted: Bool
            if #available(iOS 17.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await eventStore.requestAccess(to: .event)
            }

            guard granted else {
                calendarState.lastError = "Calendar access denied. Enable in Settings > Privacy > Calendars."
                return
            }

            let calendar = try findOrCreateTB3Calendar()
            calendarState.calendarIdentifier = calendar.calendarIdentifier
            calendarState.isConnected = true
            calendarState.lastError = nil

            UserDefaults.standard.set(calendar.calendarIdentifier, forKey: Self.calendarIdKey)
        } catch {
            calendarState.lastError = "Failed to set up calendar: \(error.localizedDescription)"
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        // Only delete the calendar if it's the dedicated "TB3" calendar we created.
        // If we fell back to the user's default calendar, just remove our events.
        removeFutureEvents()
        removeCompletedEvents()
        if let calendarId = calendarState.calendarIdentifier,
           let calendar = eventStore.calendar(withIdentifier: calendarId),
           calendar.title == Self.calendarTitle {
            try? eventStore.removeCalendar(calendar, commit: true)
        }

        UserDefaults.standard.removeObject(forKey: Self.calendarIdKey)
        UserDefaults.standard.removeObject(forKey: Self.futureIdentifiersKey)
        UserDefaults.standard.removeObject(forKey: "tb3_calendar_schedule_future")

        calendarState.isConnected = false
        calendarState.calendarIdentifier = nil
        calendarState.scheduleFutureWorkouts = false
        calendarState.lastError = nil
    }

    // MARK: - Log Completed Session

    func logCompletedSession(_ session: SyncSessionLog) {
        guard let calendar = getTB3Calendar() else { return }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar

        let liftNames = session.exercises.map {
            LiftName(rawValue: $0.liftName)?.displayName ?? $0.liftName
        }
        event.title = "TB3 — \(liftNames.joined(separator: ", "))"

        event.startDate = Date.fromISO8601(session.startedAt) ?? Date()
        event.endDate = Date.fromISO8601(session.completedAt) ?? Date()

        event.notes = buildCompletedNotes(session: session)

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
        } catch {
            calendarState.lastError = "Failed to save calendar event."
        }
    }

    // MARK: - Schedule Future Sessions

    func scheduleFutureSessions(
        program: SyncActiveProgram,
        template: TemplateDef,
        schedule: ComputedSchedule,
        sessionHistory: [SyncSessionLog]
    ) {
        guard calendarState.scheduleFutureWorkouts,
              let calendar = getTB3Calendar() else { return }

        removeFutureEvents()

        let sessions = computeFutureSessions(
            program: program,
            template: template,
            schedule: schedule,
            sessionHistory: sessionHistory
        )

        var savedIds: [String] = []
        for info in sessions {
            let event = EKEvent(eventStore: eventStore)
            event.calendar = calendar
            event.title = info.title
            event.isAllDay = true
            event.startDate = info.date
            event.endDate = info.date
            event.notes = info.notes

            do {
                try eventStore.save(event, span: .thisEvent, commit: true)
                savedIds.append(event.eventIdentifier)
            } catch {
                // Continue creating remaining events
            }
        }

        UserDefaults.standard.set(savedIds, forKey: Self.futureIdentifiersKey)
    }

    // MARK: - Remove Future Events

    func removeFutureEvents() {
        guard let eventIds = UserDefaults.standard.stringArray(forKey: Self.futureIdentifiersKey) else { return }

        for eventId in eventIds {
            if let event = eventStore.event(withIdentifier: eventId) {
                try? eventStore.remove(event, span: .thisEvent, commit: true)
            }
        }

        UserDefaults.standard.removeObject(forKey: Self.futureIdentifiersKey)
    }

    // MARK: - Remove Completed Events (for disconnect when using default calendar)

    private func removeCompletedEvents() {
        guard let calendarId = calendarState.calendarIdentifier,
              let calendar = eventStore.calendar(withIdentifier: calendarId),
              calendar.title != Self.calendarTitle else { return }
        // Only needed when using the default calendar (TB3 calendar deletion handles its own events)
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
        let oneYearAhead = Calendar.current.date(byAdding: .year, value: 1, to: Date())!
        let predicate = eventStore.predicateForEvents(withStart: oneYearAgo, end: oneYearAhead, calendars: [calendar])
        let events = eventStore.events(matching: predicate).filter { $0.title?.hasPrefix("TB3 —") == true }
        for event in events {
            try? eventStore.remove(event, span: .thisEvent, commit: false)
        }
        try? eventStore.commit()
    }

    // MARK: - Private: Calendar Management

    private func getTB3Calendar() -> EKCalendar? {
        guard let calendarId = calendarState.calendarIdentifier else { return nil }
        return eventStore.calendar(withIdentifier: calendarId)
    }

    private func findOrCreateTB3Calendar() throws -> EKCalendar {
        if let existing = eventStore.calendars(for: .event).first(where: { $0.title == Self.calendarTitle }) {
            return existing
        }

        // Try to create a dedicated "TB3" calendar. Some sources (Google/Exchange)
        // don't allow creating new calendars, so we try multiple sources in order
        // and fall back to the default calendar if none work.
        let candidateSources: [EKSource] = {
            var sources: [EKSource] = []
            // iCloud first (best for custom calendars)
            if let iCloud = eventStore.sources.first(where: { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }) {
                sources.append(iCloud)
            }
            // Local source
            if let local = eventStore.sources.first(where: { $0.sourceType == .local }) {
                sources.append(local)
            }
            // Default calendar's source as last resort for creation
            if let defaultSource = eventStore.defaultCalendarForNewEvents?.source,
               !sources.contains(where: { $0.sourceIdentifier == defaultSource.sourceIdentifier }) {
                sources.append(defaultSource)
            }
            return sources
        }()

        for source in candidateSources {
            let calendar = EKCalendar(for: .event, eventStore: eventStore)
            calendar.title = Self.calendarTitle
            calendar.cgColor = UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0).cgColor // #FF9500
            calendar.source = source
            do {
                try eventStore.saveCalendar(calendar, commit: true)
                return calendar
            } catch {
                // This source doesn't support creating calendars, try next
                continue
            }
        }

        // No source supports creating calendars — use the default calendar directly
        guard let defaultCalendar = eventStore.defaultCalendarForNewEvents else {
            throw NSError(domain: "CalendarService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No writable calendar found. Please add an iCloud or local calendar account in Settings."
            ])
        }
        return defaultCalendar
    }

    // MARK: - Private: Notes Formatting

    private func buildCompletedNotes(session: SyncSessionLog) -> String {
        let templateName = Templates.get(id: session.templateId)?.name ?? session.templateId.capitalized

        var lines: [String] = []
        lines.append("\(templateName) — Week \(session.week), Session \(session.sessionNumber)")
        lines.append("")

        var totalVolume = 0
        for exercise in session.exercises {
            let liftDisplay = LiftName(rawValue: exercise.liftName)?.displayName ?? exercise.liftName
            let completedSets = exercise.sets.filter(\.completed)
            let reps = completedSets.first?.actualReps ?? 0
            let weight = Int(exercise.actualWeight)
            let volume = completedSets.reduce(0) { $0 + Int(exercise.actualWeight) * $1.actualReps }
            totalVolume += volume

            lines.append("\(liftDisplay): \(weight) lb — \(completedSets.count)x\(reps)")
        }

        if totalVolume > 0 {
            lines.append("")
            lines.append("Total Volume: \(totalVolume.formatted()) lb")
        }

        if let start = Date.fromISO8601(session.startedAt),
           let end = Date.fromISO8601(session.completedAt) {
            let minutes = Int(end.timeIntervalSince(start) / 60)
            lines.append("Duration: \(minutes) min")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private: Future Session Scheduling

    private struct FutureSessionInfo {
        let title: String
        let date: Date
        let notes: String
    }

    private func computeFutureSessions(
        program: SyncActiveProgram,
        template: TemplateDef,
        schedule: ComputedSchedule,
        sessionHistory: [SyncSessionLog]
    ) -> [FutureSessionInfo] {
        guard program.currentWeek <= template.durationWeeks else { return [] }

        let cal = Calendar.current

        // Find starting date from training status
        let status = TrainingDayCalculator.status(
            program: program,
            template: template,
            sessionHistory: sessionHistory
        )

        let startDate: Date
        switch status {
        case .workoutDay:
            startDate = cal.startOfDay(for: Date())
        case .restDay(let resumeDate, _):
            startDate = cal.startOfDay(for: resumeDate)
        case .deloadWeek, .programComplete, .noProgram:
            return []
        }

        var results: [FutureSessionInfo] = []
        var currentDate = startDate
        var weekNum = program.currentWeek
        var sessionNum = program.currentSession

        var isFirstSession = true

        while weekNum <= template.durationWeeks {
            let weekIndex = weekNum - 1
            guard weekIndex >= 0, weekIndex < schedule.weeks.count else { break }
            let weekDef = schedule.weeks[weekIndex]

            while sessionNum <= template.sessionsPerWeek {
                let sessionIndex = sessionNum - 1
                guard sessionIndex >= 0, sessionIndex < weekDef.sessions.count else { break }
                let session = weekDef.sessions[sessionIndex]

                // Advance date before each session (except the very first)
                if !isFirstSession {
                    // 1 rest day between sessions, 2 rest days between weeks
                    let gap = (sessionNum == 1) ? 3 : 2
                    currentDate = cal.date(byAdding: .day, value: gap, to: currentDate)!
                }
                isFirstSession = false

                let liftNames = session.exercises.map {
                    LiftName(rawValue: $0.liftName)?.rawValue ?? $0.liftName
                }
                let title = "TB3 — W\(weekNum)/S\(sessionNum) (\(liftNames.joined(separator: ", ")))"
                let notes = "\(template.name) — Week \(weekNum), Session \(sessionNum)\n\(liftNames.joined(separator: ", "))"

                results.append(FutureSessionInfo(title: title, date: currentDate, notes: notes))
                sessionNum += 1
            }

            weekNum += 1
            sessionNum = 1
        }

        return results
    }
}

// MARK: - CalendarState extension for stored identifier

extension CalendarState {
    var calendarIdentifier: String? {
        get { UserDefaults.standard.string(forKey: "tb3_calendar_identifier") }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: "tb3_calendar_identifier")
            } else {
                UserDefaults.standard.removeObject(forKey: "tb3_calendar_identifier")
            }
        }
    }
}
