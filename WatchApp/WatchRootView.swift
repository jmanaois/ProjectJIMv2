import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject private var workout: WatchWorkoutManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var repetitionFontSize = 52.0
    @ScaledMetric(relativeTo: .largeTitle) private var timerFontSize = 46.0
    @State private var isEndWorkoutConfirmationPresented = false

    private var palette: WatchVibratoPalette {
        WatchVibratoPalette(colorScheme: colorScheme, contrast: colorSchemeContrast)
    }

    var body: some View {
        ZStack {
            palette.graphite.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 8) {
                    exerciseHeader

                    if workout.isRunning {
                        if workout.isResting {
                            restView
                        } else {
                            activeSetView
                        }
                        endWorkoutButton
                    } else {
                        readyView
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 7)
                .padding(.bottom, 6)
            }
            .scrollIndicators(.hidden)
        }
        .tint(palette.sand)
        .alert("End workout?", isPresented: $isEndWorkoutConfirmationPresented) {
            Button("Keep Training", role: .cancel) {}
            Button("End Workout", role: .destructive) { workout.endWorkout() }
        } message: {
            Text("The current unfinished set won’t be saved.")
        }
    }

    private var exerciseHeader: some View {
        VStack(spacing: 4) {
            Text(workout.isRunning ? "IN PROGRESS" : "UP NEXT")
                .font(.caption2.weight(.bold))
                .tracking(dynamicTypeSize.isAccessibilitySize ? 0.4 : 1.6)
                .foregroundStyle(palette.sandDark)
            Text(workout.plan.exercise.displayName)
                .font(.headline)
                .foregroundStyle(palette.sandLight)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 2)
    }

    private var readyView: some View {
        VStack(spacing: 10) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 4) {
                        workoutSetAndRepSummary
                        workoutWeightSummary
                    }
                } else {
                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        workoutSetAndRepSummary
                        workoutWeightSummary
                    }
                }
            }

            HStack(spacing: 5) {
                Image(systemName: "timer")
                Text("\(workout.plan.formattedRestDuration) rest")
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(palette.sandDark)

            Button {
                Task { await workout.startWorkout() }
            } label: {
                HStack(spacing: 6) {
                    if workout.isStarting { ProgressView().controlSize(.small) }
                    Text(workout.isStarting ? "Starting…" : "Start Workout")
                    if !workout.isStarting { Image(systemName: "arrow.right") }
                }
                .font(.headline)
                .foregroundStyle(palette.graphite)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Capsule())
                .background(palette.sand, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(workout.isStarting)

            if let error = workout.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(palette.alert)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var activeSetView: some View {
        VStack(spacing: 8) {
            VStack(spacing: -2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(workout.repetitions)")
                        .font(.system(size: min(repetitionFontSize, 64), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.75)
                    Text("/ \(workout.plan.targetReps)")
                        .font(.headline)
                        .foregroundStyle(palette.sandDark)
                }
                Text("SET \(workout.currentSet) OF \(workout.plan.targetSets)")
                    .font(.caption2.weight(.bold))
                    .tracking(dynamicTypeSize.isAccessibilitySize ? 0.3 : 1.2)
                    .foregroundStyle(palette.sandDark)
            }

            HStack(spacing: 5) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(palette.alert)
                Text("\(Int(workout.heartRate)) bpm")
                    .monospacedDigit()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.sandLight)

            if !workout.isDetectorCalibrated {
                Label("Hold still to calibrate", systemImage: "scope")
                    .font(.caption2)
                    .foregroundStyle(palette.sandDark)
            }

            HStack(spacing: 8) {
                adjustmentButton(
                    image: "minus",
                    accessibilityLabel: "Decrease repetitions",
                    disabled: workout.repetitions == 0
                ) {
                    workout.adjustRepetitions(by: -1)
                }
                adjustmentButton(
                    image: "plus",
                    accessibilityLabel: "Increase repetitions",
                    disabled: false
                ) {
                    workout.adjustRepetitions(by: 1)
                }
            }

            Button("Finish Set") { workout.finishCurrentSet() }
                .font(.headline)
                .foregroundStyle(palette.graphite)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Capsule())
                .background(palette.sand, in: Capsule())
                .buttonStyle(.plain)
                .disabled(workout.repetitions == 0)
                .opacity(workout.repetitions == 0 ? 0.45 : 1)
        }
    }

    private var restView: some View {
        VStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.title3)
                .foregroundStyle(palette.sandDark)

            Text(formattedRestCountdown)
                .font(.system(size: min(timerFontSize, 60), weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.sandLight)
                .minimumScaleFactor(0.75)

            Text("NEXT · SET \(workout.currentSet) OF \(workout.plan.targetSets)")
                .font(.caption2.weight(.bold))
                .tracking(dynamicTypeSize.isAccessibilitySize ? 0.2 : 1)
                .foregroundStyle(palette.sandDark)

            Button("Skip Rest") { workout.skipRest() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.graphite)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Capsule())
                .background(palette.sand, in: Capsule())
                .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var endWorkoutButton: some View {
        Button("End Workout", role: .destructive) {
            isEndWorkoutConfirmationPresented = true
        }
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.sandDark)
            .buttonStyle(.plain)
            .frame(minHeight: 44)
    }

    private var workoutSetAndRepSummary: some View {
        Text("\(workout.plan.targetSets) × \(workout.plan.targetReps)")
            .font(.system(.title, design: .rounded, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(palette.sandLight)
    }

    private var workoutWeightSummary: some View {
        Text("\(workout.plan.weightPounds.formatted(.number.precision(.fractionLength(1)))) lb")
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(palette.sandDark)
    }

    private func adjustmentButton(
        image: String,
        accessibilityLabel: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.headline)
                .foregroundStyle(palette.sandLight)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .background(palette.grey, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(workout.repetitions)")
    }

    private var formattedRestCountdown: String {
        let minutes = workout.restSecondsRemaining / 60
        let seconds = workout.restSecondsRemaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct WatchVibratoPalette {
    let graphite: Color
    let grey: Color
    let sand: Color
    let sandLight: Color
    let sandDark: Color
    let alert: Color

    init(colorScheme: ColorScheme, contrast: ColorSchemeContrast) {
        let increased = contrast == .increased
        if colorScheme == .dark {
            graphite = increased ? Color(red: 0.05, green: 0.06, blue: 0.05) : Color(red: 0.11, green: 0.12, blue: 0.11)
            grey = increased ? Color(red: 0.32, green: 0.33, blue: 0.30) : Color(red: 0.25, green: 0.26, blue: 0.24)
            sand = increased ? Color(red: 0.90, green: 0.84, blue: 0.73) : Color(red: 0.82, green: 0.76, blue: 0.65)
            sandLight = increased ? Color(red: 0.99, green: 0.96, blue: 0.89) : Color(red: 0.93, green: 0.89, blue: 0.80)
            sandDark = increased ? Color(red: 0.82, green: 0.76, blue: 0.65) : Color(red: 0.66, green: 0.59, blue: 0.48)
            alert = increased ? Color(red: 0.92, green: 0.49, blue: 0.39) : Color(red: 0.78, green: 0.40, blue: 0.32)
        } else {
            graphite = increased ? Color(red: 0.96, green: 0.94, blue: 0.89) : Color(red: 0.91, green: 0.89, blue: 0.84)
            grey = increased ? Color(red: 0.75, green: 0.67, blue: 0.54) : Color(red: 0.82, green: 0.76, blue: 0.65)
            sand = increased ? Color(red: 0.07, green: 0.08, blue: 0.07) : Color(red: 0.16, green: 0.17, blue: 0.16)
            sandLight = increased ? Color(red: 0.05, green: 0.06, blue: 0.05) : Color(red: 0.11, green: 0.12, blue: 0.11)
            sandDark = increased ? Color(red: 0.24, green: 0.25, blue: 0.22) : Color(red: 0.38, green: 0.39, blue: 0.36)
            alert = increased ? Color(red: 0.52, green: 0.16, blue: 0.12) : Color(red: 0.62, green: 0.26, blue: 0.21)
        }
    }
}
