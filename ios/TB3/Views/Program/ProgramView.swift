// TB3 iOS — Program View (template browser + active schedule)

import SwiftUI

struct ProgramView: View {
    @Environment(AppState.self) var appState
    @State private var showTemplates = false
    @State private var selectedTemplateId: String?
    @State private var liftSelections: [String: [String]] = [:]
    @State private var confirmSwitch = false
    @State private var pendingTemplateId: String?
    @State private var detailSession: ComputedSession?
    @State private var detailWeek: ComputedWeek?

    var dataStore: DataStore

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                title: "Program",
                trailing: programHeaderTrailing
            )

            ScrollView {
                VStack(spacing: 20) {
                    if showTemplates || appState.activeProgram == nil {
                        templateBrowser
                    } else {
                        scheduleView
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(Color.tb3Background)
        .confirmDialog(isPresented: $confirmSwitch, config: ConfirmDialogConfig(
            title: "Switch Program?",
            message: "Your current cycle progress will be lost. Session history is preserved.",
            confirmLabel: "Switch",
            isDanger: true,
            onConfirm: {
                if let id = pendingTemplateId {
                    startProgram(templateId: id)
                }
            }
        ))
        .sheet(isPresented: Binding(
            get: { detailSession != nil },
            set: { if !$0 { detailSession = nil; detailWeek = nil } }
        )) {
            if let session = detailSession, let week = detailWeek {
                sessionDetailSheet(session: session, week: week)
            }
        }
    }

    private var programHeaderTrailing: AnyView? {
        if showTemplates && appState.activeProgram != nil {
            return AnyView(
                Button("Back") { showTemplates = false }
                    .font(.subheadline)
            )
        } else if appState.activeProgram != nil && !showTemplates {
            return AnyView(
                Button("Switch") { showTemplates = true }
                    .font(.subheadline)
            )
        }
        return nil
    }

    // MARK: - Schedule View

    private var scheduleView: some View {
        VStack(spacing: 16) {
            if let program = appState.activeProgram,
               let template = Templates.get(id: program.templateId),
               let schedule = appState.computedSchedule {

                // Header
                VStack(spacing: 4) {
                    Text(template.name)
                        .font(.title2.bold())
                    Text("Week \(program.currentWeek) of \(template.durationWeeks) \u{2022} \(template.sessionsPerWeek)/wk")
                        .font(.subheadline)
                        .foregroundStyle(Color.tb3Muted)
                }

                // Weeks
                ForEach(Array(schedule.weeks.enumerated()), id: \.offset) { index, week in
                    WeekScheduleView(
                        week: week,
                        isCurrent: index + 1 == program.currentWeek,
                        isCompleted: index + 1 < program.currentWeek,
                        onSessionTap: { session, week in
                            detailSession = session
                            detailWeek = week
                        }
                    )
                }
            }
        }
    }

    // MARK: - Template Browser

    private var templateBrowser: some View {
        VStack(spacing: 16) {
            Text("Choose a Template")
                .font(.title2.bold())

            ForEach(Templates.all, id: \.id) { template in
                templateCard(template)
            }

            // Lift selection for selected template
            if let templateId = selectedTemplateId,
               let template = Templates.get(id: templateId) {
                let slots = collectLiftSlots(template)
                if !slots.isEmpty {
                    liftSelectionSection(slots: slots)
                }
            }

            // Start button
            if let templateId = selectedTemplateId {
                let template = Templates.get(id: templateId)
                Button {
                    if appState.activeProgram != nil {
                        pendingTemplateId = templateId
                        confirmSwitch = true
                    } else {
                        startProgram(templateId: templateId)
                    }
                } label: {
                    Text("Start \(template?.name ?? "Program")")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private func templateCard(_ template: TemplateDef) -> some View {
        let isSelected = selectedTemplateId == template.id.rawValue
        return Button {
            selectedTemplateId = template.id.rawValue
            liftSelections = [:]
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(template.name)
                        .font(.headline)
                    Spacer()
                    Text("\(template.sessionsPerWeek)/wk \u{2022} \(template.durationWeeks) wks")
                        .font(.caption)
                        .foregroundStyle(Color.tb3Muted)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.tb3Accent)
                    }
                }
                Text(template.description)
                    .font(.subheadline)
                    .foregroundStyle(Color.tb3Muted)
                    .multilineTextAlignment(.leading)
            }
            .padding()
            .background(isSelected ? Color.tb3Accent.opacity(0.1) : Color.tb3Card)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.tb3Accent : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Lift Selection

    struct LiftSlot {
        let cluster: String
        let label: String
        let options: [String]
        let defaults: [String]
        let minLifts: Int
        let maxLifts: Int
    }

    private func collectLiftSlots(_ template: TemplateDef) -> [LiftSlot] {
        guard let liftSlots = template.liftSlots else { return [] }
        return liftSlots.map { slot in
            LiftSlot(
                cluster: slot.cluster,
                label: slot.label,
                options: LiftName.allCases.map(\.rawValue),
                defaults: slot.defaults,
                minLifts: slot.minLifts,
                maxLifts: slot.maxLifts
            )
        }
    }

    private func liftSelectionSection(slots: [LiftSlot]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select Your Lifts")
                .font(.headline)

            ForEach(slots, id: \.label) { slot in
                VStack(alignment: .leading, spacing: 8) {
                    Text(slot.label)
                        .font(.subheadline.bold())

                    FlowLayout(spacing: 8) {
                        ForEach(slot.options, id: \.self) { option in
                            let selected = liftSelections[slot.label]?.contains(option) ?? false
                            let hasMax = appState.currentLifts.contains { $0.name == option }

                            Button {
                                toggleLift(slotLabel: slot.label, liftName: option, min: slot.minLifts, max: slot.maxLifts)
                            } label: {
                                HStack(spacing: 4) {
                                    if selected {
                                        Image(systemName: "checkmark")
                                            .font(.caption2)
                                    }
                                    Text(LiftName(rawValue: option)?.displayName ?? option)
                                        .font(.subheadline)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selected ? Color.tb3Accent.opacity(0.15) : Color.tb3Card)
                                .foregroundStyle(hasMax ? .primary : Color.tb3Muted)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .disabled(!hasMax)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.tb3Card)
        .cornerRadius(12)
    }

    private func toggleLift(slotLabel: String, liftName: String, min: Int, max: Int) {
        var current = liftSelections[slotLabel] ?? []
        if current.contains(liftName) {
            if current.count > min { current.removeAll { $0 == liftName } }
        } else {
            if current.count < max { current.append(liftName) }
        }
        liftSelections[slotLabel] = current
    }

    // MARK: - Session Detail Sheet

    private func sessionDetailSheet(session: ComputedSession, week: ComputedWeek) -> some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.tb3Muted.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 12)

            Text("\(week.label) • \(session.label)")
                .font(.headline)
                .padding(.bottom, 12)

            ScrollView {
                SessionPreviewCard(session: session, week: week)
                    .padding(.horizontal, 16)
            }
        }
        .background(Color.tb3Background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .preferredColorScheme(.dark)
    }

    // MARK: - Start Program

    private func startProgram(templateId: String) {
        guard let template = Templates.get(id: templateId) else { return }

        var resolvedSelections: [String: [String]] = [:]
        let slots = collectLiftSlots(template)
        for slot in slots {
            if let userSelection = liftSelections[slot.cluster], !userSelection.isEmpty {
                resolvedSelections[slot.cluster] = userSelection
            } else {
                resolvedSelections[slot.cluster] = slot.defaults
            }
        }

        let dateStr = ISO8601DateFormatter().string(from: Date())
        let program = dataStore.createActiveProgram(
            templateId: templateId,
            startDate: dateStr,
            liftSelections: resolvedSelections
        )

        appState.activeProgram = program.toSyncActiveProgram()
        appState.regenerateScheduleIfNeeded()
        showTemplates = false
        selectedTemplateId = nil
    }
}
