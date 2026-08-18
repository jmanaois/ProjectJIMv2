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
                    Button("End Workout", role: .destructive) { workout.endWorkout() }
                } else {
                    Text("\(workout.plan.targetSets) × \(workout.plan.targetReps) at \(workout.plan.weightKilograms, specifier: "%.1f") kg")
                        .font(.caption)
                        .multilineTextAlignment(.center)

                    Button("Start Workout") {
                        Task { await workout.startWorkout() }
                    }
                    .buttonStyle(.borderedProminent)

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
}

