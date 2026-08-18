import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var connectivity: PhoneConnectivityManager
    @EnvironmentObject private var history: WorkoutHistoryStore

    @State private var exercise: ExerciseKind = .bicepCurl
    @State private var targetSets = 3
    @State private var targetReps = 10
    @State private var weightPounds = 22.0
    @State private var savedEventTimestamp: Date?
    @FocusState private var isWeightFieldFocused: Bool

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
                ForEach(ExerciseKind.armExercises) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }

            Stepper("Sets: \(targetSets)", value: $targetSets, in: 1...10)
            Stepper("Reps: \(targetReps)", value: $targetReps, in: 1...50)

            HStack {
                Text("Weight")
                Spacer()
                TextField("lb", value: $weightPounds, format: .number.precision(.fractionLength(1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($isWeightFieldFocused)
                    .submitLabel(.done)
                    .frame(width: 80)
                Text("lb")
                    .foregroundStyle(.secondary)
                if isWeightFieldFocused {
                    Button("Done") {
                        isWeightFieldFocused = false
                    }
                    .buttonStyle(.bordered)
                }
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
                ForEach(recentRecords.prefix(3)) { record in
                    RecentSetRow(record: record)
                }

                NavigationLink {
                    WorkoutHistoryView()
                } label: {
                    Label("View All Sets (\(history.records.count))", systemImage: "clock.arrow.circlepath")
                }
            }
        }
    }

    private var recentRecords: [WorkoutSetRecord] {
        history.records.sorted { $0.timestamp > $1.timestamp }
    }

    private var currentPlan: ExercisePlan {
        ExercisePlan(
            exercise: exercise,
            targetSets: targetSets,
            targetReps: targetReps,
            weightKilograms: WeightConversion.kilograms(fromPounds: weightPounds)
        )
    }

    private func saveLatestEventIfNeeded() {
        guard let event = connectivity.latestEvent, event.timestamp != savedEventTimestamp else { return }
        history.append(event: event)
        savedEventTimestamp = event.timestamp
    }
}

private struct RecentSetRow: View {
    let record: WorkoutSetRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.exerciseName)
                .font(.headline)
            Text("Set \(record.setNumber) • \(record.repetitions) reps • \(record.weightPounds, specifier: "%.1f") lb")
            Text("\(record.formattedDuration) • \(record.timestamp.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WorkoutHistoryView: View {
    @EnvironmentObject private var history: WorkoutHistoryStore
    @State private var sortOrder: HistorySortOrder = .newestFirst

    var body: some View {
        List {
            if history.records.isEmpty {
                ContentUnavailableView("No sets yet", systemImage: "figure.strengthtraining.traditional")
            } else {
                ForEach(sortedRecords) { record in
                    WorkoutSetDetailRow(record: record)
                }
            }
        }
        .navigationTitle("Workout History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Chronological order", selection: $sortOrder) {
                        ForEach(HistorySortOrder.allCases) { order in
                            Label(order.title, systemImage: order.systemImage).tag(order)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
    }

    private var sortedRecords: [WorkoutSetRecord] {
        history.records.sorted {
            switch sortOrder {
            case .newestFirst: $0.timestamp > $1.timestamp
            case .oldestFirst: $0.timestamp < $1.timestamp
            }
        }
    }
}

private struct WorkoutSetDetailRow: View {
    let record: WorkoutSetRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(record.exerciseName)
                .font(.headline)
            Text(record.timestamp.formatted(date: .complete, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            LabeledContent("Set number", value: "\(record.setNumber)")
            LabeledContent("Repetitions", value: "\(record.repetitions)")
            LabeledContent("Weight", value: formattedWeight)
            LabeledContent("Duration", value: record.formattedDuration)
            LabeledContent("Average heart rate", value: formattedHeartRate)
        }
        .padding(.vertical, 4)
    }

    private var formattedHeartRate: String {
        guard let averageHeartRate = record.averageHeartRate else { return "Not recorded" }
        return "\(Int(averageHeartRate.rounded())) bpm"
    }

    private var formattedWeight: String {
        "\(record.weightPounds.formatted(.number.precision(.fractionLength(1)))) lb"
    }
}

private enum HistorySortOrder: String, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newestFirst: "Newest first"
        case .oldestFirst: "Oldest first"
        }
    }

    var systemImage: String {
        switch self {
        case .newestFirst: "arrow.down"
        case .oldestFirst: "arrow.up"
        }
    }
}
