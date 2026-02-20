// TB3 iOS — Calendar History View (month grid showing completed sessions)

import SwiftUI

struct CalendarHistoryView: View {
    let sessions: [SyncSessionLog]

    @State private var displayedMonth = Date()
    @State private var selectedDate: DateComponents?

    private let calendar = Calendar.current
    private let weekdaySymbols = Calendar.current.veryShortWeekdaySymbols

    /// Computed synchronously from sessions so dots render on the very first frame
    /// (no lag during tab transition animations)
    private var sessionsByDay: [DateComponents: [SyncSessionLog]] {
        var dict: [DateComponents: [SyncSessionLog]] = [:]
        for session in sessions {
            guard let date = Date.fromISO8601(session.date) else { continue }
            let dc = calendar.dateComponents([.year, .month, .day], from: date)
            dict[dc, default: []].append(session)
        }
        return dict
    }

    var body: some View {
        VStack(spacing: 0) {
            // Month navigation
            monthHeader
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            // Weekday headers
            weekdayHeader
                .padding(.horizontal, 16)

            // Day grid
            dayGrid
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            // Selected day detail
            if let selected = selectedDate, let daySessions = sessionsByDay[selected], !daySessions.isEmpty {
                Divider()
                    .background(Color.tb3Border)

                List {
                    ForEach(daySessions.sorted(by: { $0.date < $1.date }), id: \.id) { session in
                        SessionLogRow(session: session)
                    }
                }
                .listStyle(.plain)
            } else {
                Spacer()
                if selectedDate != nil {
                    Text("No sessions on this day")
                        .font(.subheadline)
                        .foregroundStyle(Color.tb3Muted)
                    Spacer()
                } else {
                    Text("Tap a highlighted day to view sessions")
                        .font(.subheadline)
                        .foregroundStyle(Color.tb3Muted)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Month Header

    private var monthHeader: some View {
        HStack {
            Button {
                withAnimation { changeMonth(by: -1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body)
                    .foregroundStyle(Color.tb3Muted)
                    .padding(8)
            }

            Spacer()

            Text(monthYearString)
                .font(.headline)

            Spacer()

            Button {
                withAnimation { changeMonth(by: 1) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body)
                    .foregroundStyle(Color.tb3Muted)
                    .padding(8)
            }
        }
    }

    // MARK: - Weekday Header

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2.bold())
                    .foregroundStyle(Color.tb3Muted)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Day Grid

    private var dayGrid: some View {
        let days = daysInMonth()
        let weeks = days.chunked(into: 7)

        return VStack(spacing: 4) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            dayCell(day)
                                .frame(maxWidth: .infinity)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                    }
                }
            }
        }
    }

    private func dayCell(_ day: DayItem) -> some View {
        let isSelected = selectedDate == day.dateComponents
        let sessionCount = sessionsByDay[day.dateComponents]?.count ?? 0
        let isToday = day.dateComponents == calendar.dateComponents([.year, .month, .day], from: Date())

        return Button {
            if day.isCurrentMonth {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if selectedDate == day.dateComponents {
                        selectedDate = nil
                    } else {
                        selectedDate = day.dateComponents
                    }
                }
            }
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color.tb3Accent)
                            .frame(width: 32, height: 32)
                    } else if isToday {
                        Circle()
                            .stroke(Color.tb3Accent, lineWidth: 1.5)
                            .frame(width: 32, height: 32)
                    }

                    Text("\(day.day)")
                        .font(.system(size: 14, weight: sessionCount > 0 ? .bold : .regular))
                        .foregroundStyle(
                            isSelected ? Color.black :
                            !day.isCurrentMonth ? Color.tb3Disabled :
                            sessionCount > 0 ? Color.tb3Accent :
                            Color.tb3Text
                        )
                }

                // Session dots
                if sessionCount > 0 && !isSelected {
                    HStack(spacing: 2) {
                        ForEach(0..<min(sessionCount, 3), id: \.self) { _ in
                            Circle()
                                .fill(Color.tb3Accent)
                                .frame(width: 4, height: 4)
                        }
                    }
                } else {
                    // Reserve space
                    Color.clear.frame(height: 4)
                }
            }
            .frame(height: 40)
        }
        .buttonStyle(.plain)
        .disabled(!day.isCurrentMonth)
    }

    // MARK: - Helpers

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth)
    }

    private func changeMonth(by value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
            displayedMonth = newMonth
            selectedDate = nil
        }
    }

    struct DayItem {
        let day: Int
        let dateComponents: DateComponents
        let isCurrentMonth: Bool
    }

    private func daysInMonth() -> [DayItem?] {
        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard let firstOfMonth = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else { return [] }

        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingEmpty = firstWeekday - calendar.firstWeekday
        let adjustedLeading = leadingEmpty < 0 ? leadingEmpty + 7 : leadingEmpty

        var items: [DayItem?] = []

        // Previous month padding
        if adjustedLeading > 0, let prevMonth = calendar.date(byAdding: .month, value: -1, to: firstOfMonth) {
            let prevComponents = calendar.dateComponents([.year, .month], from: prevMonth)
            if let prevRange = calendar.range(of: .day, in: .month, for: prevMonth) {
                let prevDays = Array(prevRange)
                for i in (prevDays.count - adjustedLeading)..<prevDays.count {
                    var dc = prevComponents
                    dc.day = prevDays[i]
                    items.append(DayItem(day: prevDays[i], dateComponents: dc, isCurrentMonth: false))
                }
            }
        }

        // Current month days
        for day in range {
            var dc = components
            dc.day = day
            items.append(DayItem(day: day, dateComponents: dc, isCurrentMonth: true))
        }

        // Trailing nil padding to fill last week
        let remainder = items.count % 7
        if remainder > 0 {
            for _ in 0..<(7 - remainder) {
                items.append(nil)
            }
        }

        return items
    }
}

// MARK: - Array Chunking

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
