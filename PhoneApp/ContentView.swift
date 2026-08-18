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
        TabView {
            NavigationStack {
                List {
                    planSection
                    statusSection
                    recentWorkoutsSection
                }
                .navigationTitle("ProjectJIM")
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }

            NavigationStack {
                WorkoutHistoryView()
            }
            .tabItem {
                Label("Workouts", systemImage: "list.bullet.clipboard.fill")
            }
        }
        .onChange(of: connectivity.latestEvent?.timestamp) { _, _ in saveLatestEventIfNeeded() }
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

    private var recentWorkoutsSection: some View {
        Section("Recent workouts") {
            if workouts.isEmpty {
                ContentUnavailableView("No workouts yet", systemImage: "figure.strengthtraining.traditional")
            } else {
                ForEach(workouts.prefix(3)) { workout in
                    RecentWorkoutRow(workout: workout)
                }
            }
        }
    }

    private var workouts: [WorkoutSummary] {
        WorkoutHistoryGrouping.workouts(from: history.records)
            .sorted { $0.completedAt > $1.completedAt }
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

private struct RecentWorkoutRow: View {
    let workout: WorkoutSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workout.exerciseName)
                .font(.headline)
            Text("\(workout.sets.count) sets • \(workout.totalRepetitions) reps • \(weightDescription)")
            Text("\(formattedDuration) • \(workout.completedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var weightDescription: String {
        guard let weight = workout.weightPounds else { return "Mixed weights" }
        return "\(weight.formatted(.number.precision(.fractionLength(1)))) lb"
    }

    private var formattedDuration: String {
        workout.totalDuration.formattedWorkoutDuration
    }
}

private struct WorkoutHistoryView: View {
    @EnvironmentObject private var history: WorkoutHistoryStore
    @State private var sortOrder: WorkoutSortOrder = .newestFirst

    var body: some View {
        List {
            if workouts.isEmpty {
                ContentUnavailableView("No workouts yet", systemImage: "figure.strengthtraining.traditional")
            } else {
                ForEach(workouts) { workout in
                    WorkoutCard(workout: workout)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Workouts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Chronological order", selection: $sortOrder) {
                        ForEach(WorkoutSortOrder.allCases) { order in
                            Label(order.title, systemImage: order.systemImage).tag(order)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
    }

    private var workouts: [WorkoutSummary] {
        WorkoutHistoryGrouping.workouts(from: history.records)
            .sorted {
                switch sortOrder {
                case .newestFirst: $0.completedAt > $1.completedAt
                case .oldestFirst: $0.completedAt < $1.completedAt
                }
            }
    }
}

private struct WorkoutCard: View {
    let workout: WorkoutSummary
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Divider()

                ForEach(workout.sets) { set in
                    WorkoutSetLine(record: set)
                }
            }
            .padding(.top, 4)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text(workout.exerciseName)
                    .font(.headline)

                Text(workout.completedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 14) {
                    Label("\(workout.sets.count) sets", systemImage: "square.stack.3d.up")
                    Label("\(workout.totalRepetitions) reps", systemImage: "repeat")
                }
                .font(.subheadline)

                HStack(spacing: 14) {
                    Label(weightDescription, systemImage: "scalemass")
                    Label(workout.totalDuration.formattedWorkoutDuration, systemImage: "timer")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Label(averageHeartRateDescription, systemImage: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(heartRateColor)
            }
        }
        .tint(.primary)
        .padding(14)
        .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
    }

    private var weightDescription: String {
        guard let weight = workout.weightPounds else { return "Mixed weights" }
        return "\(weight.formatted(.number.precision(.fractionLength(1)))) lb"
    }

    private var averageHeartRateDescription: String {
        guard let averageHeartRate = workout.averageHeartRate else { return "BPM not recorded" }
        return "\(Int(averageHeartRate.rounded())) average bpm"
    }

    private var heartRateColor: Color {
        workout.averageHeartRate == nil ? .secondary : .red
    }
}

private struct WorkoutSetLine: View {
    let record: WorkoutSetRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Set \(record.setNumber)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(record.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("\(record.repetitions) reps")
                Spacer()
                Text("\(record.weightPounds, specifier: "%.1f") lb")
                Spacer()
                Text(record.formattedDuration)
            }
            .font(.caption)

            if let averageHeartRate = record.averageHeartRate {
                Label("\(Int(averageHeartRate.rounded())) bpm", systemImage: "heart")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private enum WorkoutSortOrder: String, CaseIterable, Identifiable {
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

private extension TimeInterval {
    var formattedWorkoutDuration: String {
        let totalSeconds = max(0, Int(rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
    }
}
