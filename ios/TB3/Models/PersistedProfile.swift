// TB3 iOS — Persisted Profile (SwiftData, mirrors types.ts UserProfile)

import Foundation
import SwiftData

@Model
final class PersistedProfile {
    var maxType: String = "training"
    var roundingIncrement: Double = 2.5
    var barbellWeight: Double = 45
    var plateInventoryBarbellData: Data = Data()
    var plateInventoryBeltData: Data = Data()
    var restTimerDefault: Int = 120
    var soundMode: String = "on"
    var voiceAnnouncements: Bool = false
    var voiceName: String?
    var theme: String = "dark"
    var unit: String = "lb"
    var workoutRemindersEnabled: Bool = false
    var restTimerAlertsEnabled: Bool = false
    var lastModified: String = ""

    init() {
        let now = ISO8601DateFormatter().string(from: Date())
        self.lastModified = now
        self.plateInventoryBarbellData = (try? JSONEncoder().encode(DEFAULT_PLATE_INVENTORY_BARBELL)) ?? Data()
        self.plateInventoryBeltData = (try? JSONEncoder().encode(DEFAULT_PLATE_INVENTORY_BELT)) ?? Data()
    }

    // MARK: - PlateInventory accessors

    var plateInventoryBarbell: PlateInventory {
        get { (try? JSONDecoder().decode(PlateInventory.self, from: plateInventoryBarbellData)) ?? DEFAULT_PLATE_INVENTORY_BARBELL }
        set { plateInventoryBarbellData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var plateInventoryBelt: PlateInventory {
        get { (try? JSONDecoder().decode(PlateInventory.self, from: plateInventoryBeltData)) ?? DEFAULT_PLATE_INVENTORY_BELT }
        set { plateInventoryBeltData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    // MARK: - Conversion to/from sync payload

    func toSyncProfile() -> SyncProfile {
        var profile = SyncProfile(
            maxType: maxType,
            roundingIncrement: roundingIncrement,
            barbellWeight: barbellWeight,
            plateInventoryBarbell: plateInventoryBarbell,
            plateInventoryBelt: plateInventoryBelt,
            restTimerDefault: restTimerDefault,
            soundMode: soundMode,
            voiceAnnouncements: voiceAnnouncements,
            voiceName: voiceName,
            theme: theme,
            unit: unit,
            lastModified: lastModified
        )
        profile.workoutRemindersEnabled = workoutRemindersEnabled
        profile.restTimerAlertsEnabled = restTimerAlertsEnabled
        return profile
    }

    func apply(from sync: SyncProfile) {
        maxType = sync.maxType
        roundingIncrement = sync.roundingIncrement
        barbellWeight = sync.barbellWeight
        plateInventoryBarbell = sync.plateInventoryBarbell
        plateInventoryBelt = sync.plateInventoryBelt
        restTimerDefault = sync.restTimerDefault
        soundMode = sync.soundMode
        voiceAnnouncements = sync.voiceAnnouncements
        voiceName = sync.voiceName
        theme = sync.theme
        unit = sync.unit
        lastModified = sync.lastModified
        workoutRemindersEnabled = sync.workoutRemindersEnabled
        restTimerAlertsEnabled = sync.restTimerAlertsEnabled
    }

    // MARK: - Typed accessors

    var maxTypeEnum: MaxType {
        get { MaxType(rawValue: maxType) ?? .training }
        set { maxType = newValue.rawValue }
    }

    var soundModeEnum: SoundMode {
        get { SoundMode(rawValue: soundMode) ?? .on }
        set { soundMode = newValue.rawValue }
    }

    var themeEnum: ThemeMode {
        get { ThemeMode(rawValue: theme) ?? .dark }
        set { theme = newValue.rawValue }
    }

    var unitEnum: WeightUnit {
        get { WeightUnit(rawValue: unit) ?? .lb }
        set { unit = newValue.rawValue }
    }

    var roundingIncrementValue: Double {
        get { roundingIncrement }
        set { roundingIncrement = newValue }
    }
}
