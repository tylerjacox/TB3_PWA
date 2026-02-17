// TB3 iOS — Profile View (settings, 1RM entry, sync, data management)

import SwiftUI
import AVFoundation

struct ProfileView: View {
    @Environment(AppState.self) var appState
    @Bindable var vm: ProfileViewModel
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenHeader(title: "Profile")

                Form {
                    // 1RM Entry
                    liftEntrySection

                    // Settings
                    settingsSection

                    // Plate Inventory
                    plateInventorySection

                    // Sync
                    syncSection

                    // Data Management
                    dataSection

                    // About
                    aboutSection
                }
                .scrollContentBackground(.hidden)
            }
            .background(Color.tb3Background)
            .navigationBarHidden(true)
            .confirmDialog(isPresented: $vm.showDeleteConfirm, config: ConfirmDialogConfig(
                title: "Delete All Data?",
                message: "This will permanently delete all your training data, maxes, and settings. This cannot be undone.",
                confirmLabel: "Delete Everything",
                isDanger: true,
                onConfirm: { vm.deleteAllData() }
            ))
        }
    }

    // MARK: - Lift Entry

    private var liftEntrySection: some View {
        Section("Your Lifts") {
            ForEach(LiftName.allCases, id: \.rawValue) { lift in
                liftRow(lift)
            }
        }
    }

    private func liftRow(_ lift: LiftName) -> some View {
        let current = appState.currentLifts.first { $0.name == lift.rawValue }

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                vm.toggleLift(lift.rawValue)
            } label: {
                HStack {
                    Text(lift.displayName)
                        .font(.body)
                        .foregroundStyle(Color.tb3Text)

                    Spacer()

                    if let current {
                        Text("\(Int(current.workingMax)) lb")
                            .font(.subheadline.monospaced())
                            .foregroundStyle(Color.tb3Muted)
                    } else {
                        Text("Not set")
                            .font(.subheadline)
                            .foregroundStyle(Color.tb3Disabled)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.tb3Disabled)
                        .rotationEffect(.degrees(vm.expandedLift == lift.rawValue ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if vm.expandedLift == lift.rawValue {
                VStack(spacing: 12) {
                    WeightRepsPicker(
                        weightText: $vm.liftWeight,
                        repsText: $vm.liftReps
                    )

                    // Plate visualizer
                    if let weight = Double(vm.liftWeight), weight > 0 {
                        let isBodyweight = lift.rawValue == LiftName.weightedPullUp.rawValue
                        let plateResult = isBodyweight
                            ? PlateCalculator.calculateBeltPlates(
                                totalWeight: weight,
                                inventory: appState.profile.plateInventoryBelt)
                            : PlateCalculator.calculateBarbellPlates(
                                totalWeight: weight,
                                barbellWeight: appState.profile.barbellWeight,
                                inventory: appState.profile.plateInventoryBarbell)
                        PlateDisplayView(result: plateResult, isBodyweight: isBodyweight)
                    }

                    Button("Save") {
                        vm.save1RM(liftName: lift.rawValue)
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(vm.liftWeight.isEmpty || vm.liftReps.isEmpty)
                }

                // Percentage table
                if let current {
                    percentageTable(workingMax: current.workingMax)
                }
            }
        }
    }

    private func percentageTable(workingMax: Double) -> some View {
        let rounding = appState.profile.roundingIncrement
        let percentages = [100, 95, 90, 85, 80, 75, 70, 65]

        return VStack(alignment: .leading, spacing: 4) {
            ForEach(percentages, id: \.self) { pct in
                let weight = OneRepMaxCalculator.roundWeight(workingMax * Double(pct) / 100.0, increment: rounding)
                HStack {
                    Text("\(pct)%")
                        .font(.caption.monospaced())
                        .foregroundStyle(Color.tb3Muted)
                        .frame(width: 40, alignment: .trailing)
                    Text("\(Int(weight)) lb")
                        .font(.caption.monospaced())
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Settings

    private var settingsSection: some View {
        Section("Settings") {
            // Max Type
            Picker("Max Type", selection: Binding(
                get: { appState.profile.maxType },
                set: { vm.updateMaxType($0) }
            )) {
                Text("Training (90%)").tag("training")
                Text("True 1RM").tag("true")
            }

            // Rounding
            Picker("Rounding", selection: Binding(
                get: { appState.profile.roundingIncrement },
                set: { vm.updateRounding($0) }
            )) {
                Text("2.5 lb").tag(2.5)
                Text("5 lb").tag(5.0)
            }

            // Barbell Weight
            HStack {
                Text("Barbell Weight")
                Spacer()
                NumberInputField(
                    text: Binding(
                        get: { "\(Int(appState.profile.barbellWeight))" },
                        set: { vm.updateBarbellWeight($0) }
                    ),
                    placeholder: "45"
                )
                .frame(width: 60, height: 22)
                Text("lb")
                    .foregroundStyle(Color.tb3Muted)
            }

            // Rest Timer
            HStack {
                Text("Rest Timer Default")
                Spacer()
                NumberInputField(
                    text: Binding(
                        get: { "\(appState.profile.restTimerDefault)" },
                        set: { vm.updateRestTimer($0) }
                    ),
                    placeholder: "120"
                )
                .frame(width: 60, height: 22)
                Text("sec")
                    .foregroundStyle(Color.tb3Muted)
            }

            // Sound Mode
            Picker("Sound", selection: Binding(
                get: { appState.profile.soundMode },
                set: { vm.updateSoundMode($0) }
            )) {
                Text("On").tag("on")
                Text("Vibrate").tag("vibrate")
                Text("Off").tag("off")
            }

            // Voice
            Toggle("Voice Countdown", isOn: Binding(
                get: { appState.profile.voiceAnnouncements },
                set: { vm.updateVoice($0) }
            ))

            if appState.profile.voiceAnnouncements {
                VoicePickerRow(
                    selectedVoiceName: appState.profile.voiceName,
                    onSelect: { vm.updateVoiceName($0) },
                    onPreview: { vm.previewVoice($0) }
                )
            }
        }
    }

    // MARK: - Plate Inventory

    private var plateInventorySection: some View {
        Section("Plate Inventory") {
            NavigationLink("Barbell Plates") {
                PlateInventoryEditorView(
                    inventory: Binding(
                        get: { appState.profile.plateInventoryBarbell },
                        set: { newValue in
                            appState.profile.plateInventoryBarbell = newValue
                            let profile = vm.dataStore.loadProfile()
                            profile.apply(from: appState.profile)
                            vm.dataStore.saveProfile(profile)
                            appState.regenerateScheduleIfNeeded()
                        }
                    ),
                    title: "Barbell Plates"
                )
            }

            NavigationLink("Belt Plates") {
                PlateInventoryEditorView(
                    inventory: Binding(
                        get: { appState.profile.plateInventoryBelt },
                        set: { newValue in
                            appState.profile.plateInventoryBelt = newValue
                            let profile = vm.dataStore.loadProfile()
                            profile.apply(from: appState.profile)
                            vm.dataStore.saveProfile(profile)
                            appState.regenerateScheduleIfNeeded()
                        }
                    ),
                    title: "Belt Plates"
                )
            }
        }
    }

    // MARK: - Sync

    private var syncSection: some View {
        Section("Sync") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if appState.syncState.isSyncing {
                        Label("Syncing...", systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline)
                    } else if let lastSync = appState.syncState.lastSyncedAt {
                        Label("Last synced", systemImage: "checkmark.circle")
                            .font(.subheadline)
                        Text(lastSync)
                            .font(.caption)
                            .foregroundStyle(Color.tb3Muted)
                    } else {
                        Label("Not synced", systemImage: "xmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(Color.tb3Muted)
                    }

                    if let error = appState.syncState.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color.tb3Error)
                    }
                }

                Spacer()

                Button("Sync Now") {
                    vm.syncNow()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appState.syncState.isSyncing)
            }

            HStack {
                Text("Sessions")
                Spacer()
                Text("\(appState.sessionHistory.count)")
                    .foregroundStyle(Color.tb3Muted)
            }

            HStack {
                Text("Max Tests")
                Spacer()
                Text("\(appState.maxTestHistory.count)")
                    .foregroundStyle(Color.tb3Muted)
            }
        }
    }

    // MARK: - Data Management

    private var dataSection: some View {
        Section("Data") {
            Button("Export Data") {
                // TODO: Phase 6 — ExportImportService
            }

            Button("Import Data") {
                // TODO: Phase 6 — ExportImportService
            }

            if appState.authState.isAuthenticated {
                Button("Sign Out") {
                    Task { await vm.signOut() }
                }
            }

            Button("Delete All Data", role: .destructive) {
                vm.showDeleteConfirm = true
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0")
                    .foregroundStyle(Color.tb3Muted)
            }

            if let email = appState.authState.email {
                HStack {
                    Text("Account")
                    Spacer()
                    Text(email)
                        .foregroundStyle(Color.tb3Muted)
                }
            }
        }
    }
}

// MARK: - Voice Picker Row

private struct VoicePickerRow: View {
    let selectedVoiceName: String?
    let onSelect: (String?) -> Void
    let onPreview: (String?) -> Void

    private var englishVoices: [(name: String, label: String)] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { a, b in
                // Premium/enhanced voices first, then by name
                if a.quality != b.quality { return a.quality.rawValue > b.quality.rawValue }
                return a.name < b.name
            }
            .map { voice in
                let quality = voice.quality == .enhanced ? " (Enhanced)" :
                              voice.quality == .premium ? " (Premium)" : ""
                let region = voiceRegion(voice.language)
                return (name: voice.name, label: "\(voice.name)\(quality) — \(region)")
            }
    }

    var body: some View {
        NavigationLink {
            List {
                // Default option
                Button {
                    onSelect(nil)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("System Default")
                                .foregroundStyle(Color.primary)
                            Text("en-US")
                                .font(.caption)
                                .foregroundStyle(Color.tb3Muted)
                        }
                        Spacer()
                        if selectedVoiceName == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(.tb3Accent)
                        }
                    }
                }

                // All English voices
                ForEach(englishVoices, id: \.name) { voice in
                    Button {
                        onSelect(voice.name)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(voice.label)
                                    .foregroundStyle(Color.primary)
                            }
                            Spacer()
                            if selectedVoiceName == voice.name {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.tb3Accent)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onPreview(selectedVoiceName)
                    } label: {
                        Image(systemName: "play.circle")
                    }
                }
            }
        } label: {
            HStack {
                Text("Voice")
                Spacer()
                Text(selectedVoiceName ?? "Default")
                    .foregroundStyle(Color.tb3Muted)
            }
        }
    }

    private func voiceRegion(_ language: String) -> String {
        switch language {
        case "en-US": return "US"
        case "en-GB": return "UK"
        case "en-AU": return "Australia"
        case "en-IE": return "Ireland"
        case "en-ZA": return "South Africa"
        case "en-IN": return "India"
        case "en-SG": return "Singapore"
        default:
            let parts = language.split(separator: "-")
            return parts.count > 1 ? String(parts[1]) : language
        }
    }
}

