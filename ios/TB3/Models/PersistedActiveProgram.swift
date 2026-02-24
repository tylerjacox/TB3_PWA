// TB3 iOS — Persisted Active Program (SwiftData, mirrors types.ts ActiveProgram)

import Foundation
import SwiftData

@Model
final class PersistedActiveProgram {
    var templateId: String = ""
    var startDate: String = ""
    var currentWeek: Int = 1
    var currentSession: Int = 1
    var liftSelectionsData: Data = Data()
    var lastModified: String = ""

    init() {}

    init(templateId: String, startDate: String, liftSelections: [String: [String]]) {
        self.templateId = templateId
        self.startDate = startDate
        self.currentWeek = 1
        self.currentSession = 1
        self.liftSelectionsData = (try? JSONEncoder().encode(liftSelections)) ?? Data()
        self.lastModified = Date.iso8601Now()
    }

    // MARK: - LiftSelections accessor

    var liftSelections: [String: [String]] {
        get { (try? JSONDecoder().decode([String: [String]].self, from: liftSelectionsData)) ?? [:] }
        set { liftSelectionsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    // MARK: - Conversion to/from sync payload

    func toSyncActiveProgram() -> SyncActiveProgram {
        SyncActiveProgram(
            templateId: templateId,
            startDate: startDate,
            currentWeek: currentWeek,
            currentSession: currentSession,
            liftSelections: liftSelections,
            lastModified: lastModified
        )
    }

    func apply(from sync: SyncActiveProgram) {
        templateId = sync.templateId
        startDate = sync.startDate
        currentWeek = sync.currentWeek
        currentSession = sync.currentSession
        liftSelections = sync.liftSelections
        lastModified = sync.lastModified
    }

    var templateIdEnum: TemplateId? {
        TemplateId(rawValue: templateId)
    }
}
