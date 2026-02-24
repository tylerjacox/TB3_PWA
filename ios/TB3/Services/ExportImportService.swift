// TB3 iOS — Export/Import Service (mirrors services/exportImport.ts)
// JSON export via ShareLink, import via .fileImporter

import Foundation

struct ExportImportService {
    // MARK: - Export

    /// Generate export JSON data for sharing.
    static func exportData(
        profile: SyncProfile,
        activeProgram: SyncActiveProgram?,
        sessionHistory: [SyncSessionLog],
        maxTestHistory: [SyncOneRepMaxTest]
    ) -> Data? {
        let exported = ExportedAppData(
            tb3_export: true,
            exportedAt: Date.iso8601Now(),
            appVersion: "1.0.0", // iOS app version
            schemaVersion: CURRENT_SCHEMA_VERSION,
            profile: profile,
            activeProgram: activeProgram,
            sessionHistory: sessionHistory,
            maxTestHistory: maxTestHistory
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(exported)
    }

    /// Generate a filename for export.
    static func exportFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "tb3-backup-\(formatter.string(from: Date())).json"
    }

    /// Write export data to a temporary file URL for sharing.
    static func writeExportFile(data: Data) -> URL? {
        let filename = exportFilename()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: tempURL)
            return tempURL
        } catch {
            return nil
        }
    }

    // MARK: - Import

    struct ImportPreview {
        let liftCount: Int
        let sessionCount: Int
        let maxTestCount: Int
        let lastTestDate: String?
    }

    /// Validate and preview import data.
    static func validateImport(_ data: Data) -> Result<(ExportedAppData, ImportPreview), ImportError> {
        switch ValidationService.validateImportData(data) {
        case .success(let exported):
            let uniqueLifts = Set(exported.maxTestHistory.map(\.liftName))
            let lastDate = exported.maxTestHistory.sorted(by: { $0.date > $1.date }).first?.date

            let preview = ImportPreview(
                liftCount: uniqueLifts.count,
                sessionCount: exported.sessionHistory.count,
                maxTestCount: exported.maxTestHistory.count,
                lastTestDate: lastDate
            )
            return .success((exported, preview))

        case .failure(let error):
            return .failure(error)
        }
    }

    /// Apply imported data to app state and data store.
    @MainActor
    static func performImport(
        exported: ExportedAppData,
        appState: AppState,
        dataStore: DataStore
    ) {
        // Clear existing data
        dataStore.clearAllData()

        // Apply profile
        let profile = dataStore.loadProfile()
        profile.apply(from: exported.profile)
        dataStore.saveProfile(profile)

        // Apply active program
        if let program = exported.activeProgram {
            let persisted = dataStore.createActiveProgram(
                templateId: program.templateId,
                startDate: program.startDate,
                liftSelections: program.liftSelections
            )
            persisted.currentWeek = program.currentWeek
            persisted.currentSession = program.currentSession
            persisted.lastModified = program.lastModified
            dataStore.saveActiveProgram(persisted)
        }

        // Apply session history
        for session in exported.sessionHistory {
            dataStore.addSessionLog(session)
        }

        // Apply max test history
        for test in exported.maxTestHistory {
            dataStore.addMaxTest(test)
        }

        // Reload app state
        appState.reloadFromStore(dataStore)
        appState.activeSession = nil
        ActiveSessionState.clear()
    }
}
