import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var connectivity: PhoneConnectivityManager
    @EnvironmentObject private var history: WorkoutHistoryStore

    @State private var exercise: ExerciseKind = .bicepCurl
    @State private var targetSets = 3
    @State private var targetReps = 10
    @State private var weight = 10.0
    @State private var savedEventTimestamp: Date?

    var body: some View {
        NavigationStack {
            List {
                planSection
                statusSection
                historySection
            }
            .navigationTitle("ProjectJIM")
            .onChange(of: connectivity.latestEvent?.timestamp) { _, _ in saveLatestEventIfNeeded() }
        }
    }

    private var planSection: some View {
        Section("Next exercise") {
            Picker("Exercise", selection: $exercise) {
                ForEach(ExerciseKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }

            Stepper("Sets: \(targetSets)", value: $targetSets, in: 1...10)
            Stepper("Reps: \(targetReps)", value: $targetReps, in: 1...50)

            HStack {
                Text("Weight")
                Spacer()
                TextField("kg", value: $weight, format: .number.precision(.fractionLength(1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                Text("kg")
                    .foregroundStyle(.secondary)
            }

            Button("Send Plan to Watch") {
                connectivity.send(plan: currentPlan)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var statusSection: some View {
        Section("Connection") {
            Label(
                connectivity.isWatchReachable ? "Watch reachable" : "Plan will sync when Watch is available",
                systemImage: connectivity.isWatchReachable ? "applewatch.radiowaves.left.and.right" : "applewatch.slash"
            )

            if let event = connectivity.latestEvent {
                LabeledContent("Latest set", value: "\(event.repetitions) reps")
                LabeledContent("Exercise", value: event.exercise.displayName)
            }
        }
    }

    private var historySection: some View {
        Section("Recent sets") {
            if history.records.isEmpty {
                ContentUnavailableView("No sets yet", systemImage: "figure.strengthtraining.traditional")
            } else {
                ForEach(history.records.prefix(20)) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.exerciseName).font(.headline)
                        Text("\(record.repetitions) reps × \(record.weightKilograms, specifier: "%.1f") kg")
                        Text(record.timestamp, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var currentPlan: ExercisePlan {
        ExercisePlan(
            exercise: exercise,
            targetSets: targetSets,
            targetReps: targetReps,
            weightKilograms: weight
        )
    }

    private func saveLatestEventIfNeeded() {
        guard let event = connectivity.latestEvent, event.timestamp != savedEventTimestamp else { return }
        history.append(event: event)
        savedEventTimestamp = event.timestamp
    }
}
