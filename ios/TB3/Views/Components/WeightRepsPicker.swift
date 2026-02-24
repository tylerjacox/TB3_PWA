// TB3 iOS — Weight (menu picker) + Reps (stepper) input component

import SwiftUI
import UIKit

struct WeightRepsPicker: View {
    @Binding var weightText: String
    @Binding var repsText: String

    @State private var weightValue: Double = 0
    @State private var repsValue: Int = 0
    @State private var hasInitialized = false

    private static let weightOptions: [Double] = {
        var values: [Double] = []
        var w = 2.5
        while w <= 500 {
            values.append(w)
            w += 2.5
        }
        return values
    }()

    var body: some View {
        HStack(spacing: 12) {
            // Weight: tappable menu picker
            VStack(spacing: 4) {
                Text("WEIGHT")
                    .font(.caption2)
                    .foregroundStyle(Color.tb3Muted)

                Menu {
                    Picker("Weight", selection: $weightValue) {
                        Text("—").tag(0.0)
                        ForEach(Self.weightOptions, id: \.self) { w in
                            Text("\(formatWeight(w)) lb").tag(w)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(weightValue > 0 ? formatWeight(weightValue) : "—")
                            .font(.system(size: 22, weight: .medium).monospacedDigit())
                            .foregroundStyle(weightValue > 0 ? Color.tb3Text : Color.tb3Muted)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(Color.tb3Muted)
                    }
                    .frame(minWidth: 80, minHeight: 48)
                    .padding(.horizontal, 12)
                    .background(Color.tb3Background)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.tb3Border, lineWidth: 1))
                }
                .accessibilityLabel("Weight, \(weightValue > 0 ? "\(formatWeight(weightValue)) pounds" : "not set")")

                Text("lb")
                    .font(.caption)
                    .foregroundStyle(Color.tb3Muted)
            }

            Text("\u{00D7}")
                .font(.title3)
                .foregroundStyle(Color.tb3Muted)
                .accessibilityHidden(true)

            // Reps: stepper buttons
            VStack(spacing: 4) {
                Text("REPS")
                    .font(.caption2)
                    .foregroundStyle(Color.tb3Muted)

                HStack(spacing: 0) {
                    Button {
                        if repsValue > 1 {
                            repsValue -= 1
                            hapticTick()
                        } else if repsValue == 0 {
                            repsValue = 1
                            hapticTick()
                        }
                    } label: {
                        Text("\u{2212}")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(repsValue > 1 ? Color.tb3Accent : Color.tb3Disabled)
                            .frame(width: 44, height: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Decrease reps")

                    Text(repsValue > 0 ? "\(repsValue)" : "—")
                        .font(.system(size: 22, weight: .medium).monospacedDigit())
                        .foregroundStyle(repsValue > 0 ? Color.tb3Text : Color.tb3Muted)
                        .frame(width: 48, height: 48)
                        .background(Color.tb3Background)
                        .overlay(
                            Rectangle()
                                .fill(Color.tb3Border)
                                .frame(width: 1),
                            alignment: .leading
                        )
                        .overlay(
                            Rectangle()
                                .fill(Color.tb3Border)
                                .frame(width: 1),
                            alignment: .trailing
                        )
                        .accessibilityLabel("\(repsValue > 0 ? "\(repsValue)" : "no") reps")

                    Button {
                        if repsValue < 20 {
                            repsValue = max(1, repsValue + 1)
                            hapticTick()
                        }
                    } label: {
                        Text("+")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(repsValue < 20 ? Color.tb3Accent : Color.tb3Disabled)
                            .frame(width: 44, height: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Increase reps")
                }
                .background(Color.tb3Card)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.tb3Border, lineWidth: 1))

                Text(" ")
                    .font(.caption)
            }
        }
        .onAppear {
            guard !hasInitialized else { return }
            hasInitialized = true
            if let w = Double(weightText), w > 0 {
                weightValue = (w / 2.5).rounded() * 2.5
            }
            if let r = Int(repsText), r >= 1, r <= 20 {
                repsValue = r
            }
        }
        .onChange(of: weightValue) { _, newValue in
            weightText = newValue > 0 ? formatWeight(newValue) : ""
        }
        .onChange(of: repsValue) { _, newValue in
            repsText = newValue > 0 ? "\(newValue)" : ""
        }
    }

    private func formatWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(w))" : String(format: "%.1f", w)
    }

    private func hapticTick() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}
