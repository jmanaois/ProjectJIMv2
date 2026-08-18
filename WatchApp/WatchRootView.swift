import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject private var workout: WatchWorkoutManager

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(workout.plan.exercise.displayName)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                if workout.isRunning {
                    if workout.isResting {
                        Text("Rest")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(formattedRestCountdown)
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .monospacedDigit()

                        Text("Next: Set \(workout.currentSet) of \(workout.plan.targetSets)")
                            .font(.caption)

                        Button("Skip Rest") {
                            workout.skipRest()
                        }
                        .tint(.orange)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(workout.repetitions)")
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                            Text("/ \(workout.plan.targetReps)")
                                .foregroundStyle(.secondary)
                        }

                        Text("Set \(workout.currentSet) of \(workout.plan.targetSets)")
                        Label("\(Int(workout.heartRate)) bpm", systemImage: "heart.fill")
                            .foregroundStyle(.red)

                        if !workout.isDetectorCalibrated {
                            Label("Hold still to calibrate", systemImage: "scope")
                                .font(.caption2)
                        }

                        HStack {
                            Button { workout.adjustRepetitions(by: -1) } label: {
                                Image(systemName: "minus")
                            }
                            .disabled(workout.repetitions == 0)

                            Button { workout.adjustRepetitions(by: 1) } label: {
                                Image(systemName: "plus")
                            }
                        }

                        Button("Finish Set") { workout.finishCurrentSet() }
                            .tint(.green)
                    }

                    Button("End Workout", role: .destructive) { workout.endWorkout() }
                } else {
                    Text("\(workout.plan.targetSets) × \(workout.plan.targetReps) at \(workout.plan.weightPounds, specifier: "%.1f") lb")
                        .font(.caption)
                        .multilineTextAlignment(.center)

                    Text("\(workout.plan.formattedRestDuration) rest")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Button {
                        Task { await workout.startWorkout() }
                    } label: {
                        if workout.isStarting {
                            HStack(spacing: 6) {
                                ProgressView()
                                Text("Starting…")
                            }
                        } else {
                            Text("Start Workout")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(workout.isStarting)

                    if let error = workout.errorMessage {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var formattedRestCountdown: String {
        let minutes = workout.restSecondsRemaining / 60
        let seconds = workout.restSecondsRemaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
