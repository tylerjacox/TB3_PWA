// TB3 iOS — Date Formatting Extensions

import Foundation

// MARK: - Cached Formatters (expensive to create, reuse them)

nonisolated(unsafe) private let iso8601Formatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    return f
}()

nonisolated(unsafe) private let iso8601FractionalFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let shortDisplayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .none
    return f
}()

private let fullDisplayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
}()

extension Date {
    /// ISO 8601 string (matching PWA's new Date().toISOString())
    var iso8601: String {
        iso8601Formatter.string(from: self)
    }

    /// ISO 8601 string for current time
    static func iso8601Now() -> String {
        Date().iso8601
    }

    /// Generate a UUID string (matching PWA's generateId())
    static func generateId() -> String {
        UUID().uuidString.lowercased()
    }

    /// Parse ISO 8601 string
    static func fromISO8601(_ string: String) -> Date? {
        iso8601FractionalFormatter.date(from: string) ?? iso8601Formatter.date(from: string)
    }

    /// Display format: "Jan 15, 2024"
    var shortDisplay: String {
        shortDisplayFormatter.string(from: self)
    }

    /// Display format: "Jan 15, 2024 at 3:30 PM"
    var fullDisplay: String {
        fullDisplayFormatter.string(from: self)
    }
}

extension String {
    /// Parse this string as an ISO 8601 date
    var asDate: Date? {
        Date.fromISO8601(self)
    }
}

/// Generate a UUID string (matching PWA's generateId())
func generateId() -> String {
    UUID().uuidString.lowercased()
}
