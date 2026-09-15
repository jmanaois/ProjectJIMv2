import Combine
import Foundation

struct WorkoutSetRecord: Codable, Identifiable {
    let id: UUID
    var workoutID: UUID?
    var timestamp: Date
    var exerciseRawValue: String
    var setNumber: Int
    var repetitions: Int
    var weightKilograms: Double
    var targetSets: Int?
    var targetRepetitions: Int?
    var plannedRestDurationSeconds: Int?
    /// Stored on the final set of a workout. Four represents "4 or more."
    var repsInReserve: Int?
    var duration: TimeInterval
    var averageHeartRate: Double?

    init(event: SetCompletedEvent) {
        id = UUID()
        workoutID = event.workoutID
        timestamp = event.timestamp
        exerciseRawValue = event.exercise.rawValue
        setNumber = event.setNumber
        repetitions = event.repetitions
        weightKilograms = event.weightKilograms
        targetSets = event.targetSets
        targetRepetitions = event.targetRepetitions
        plannedRestDurationSeconds = event.plannedRestDurationSeconds
        repsInReserve = nil
        duration = event.duration
        averageHeartRate = event.averageHeartRate
    }

    var exerciseName: String {
        ExerciseKind(rawValue: exerciseRawValue)?.displayName ?? exerciseRawValue
    }

    var weightPounds: Double {
        WeightConversion.pounds(fromKilograms: weightKilograms)
    }

    var formattedDuration: String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
    }
}

struct WorkoutSummary: Identifiable {
    let id: String
    let sets: [WorkoutSetRecord]

    var exerciseName: String {
        let names = orderedExerciseRawValues.compactMap { rawValue in
            sets.first(where: { $0.exerciseRawValue == rawValue })?.exerciseName
        }
        return names.count > 1 ? "\(names.count)-Exercise Routine" : (names.first ?? "Workout")
    }

    var orderedExerciseRawValues: [String] {
        sets.sorted { $0.timestamp < $1.timestamp }.reduce(into: []) { result, set in
            if !result.contains(set.exerciseRawValue) { result.append(set.exerciseRawValue) }
        }
    }

    var repeatedRoutine: WorkoutRoutine? {
        let chronologicalSets = sets.sorted { $0.timestamp < $1.timestamp }
        let exerciseBlocks = chronologicalSets.reduce(into: [[WorkoutSetRecord]]()) { blocks, set in
            guard let lastSet = blocks.last?.last,
                  lastSet.exerciseRawValue == set.exerciseRawValue,
                  set.setNumber > lastSet.setNumber else {
                blocks.append([set])
                return
            }
            blocks[blocks.count - 1].append(set)
        }
        let plans = exerciseBlocks.compactMap { exerciseSets -> ExercisePlan? in
            guard let first = exerciseSets.first,
                  let exercise = ExerciseKind(rawValue: first.exerciseRawValue) else { return nil }
            return ExercisePlan(
                exercise: exercise,
                targetSets: exerciseSets.compactMap(\.targetSets).last ?? exerciseSets.count,
                targetReps: exerciseSets.compactMap(\.targetRepetitions).last
                    ?? exerciseSets.map(\.repetitions).max() ?? first.repetitions,
                weightKilograms: first.weightKilograms,
                restDurationSeconds: exerciseSets.compactMap(\.plannedRestDurationSeconds).last ?? 60
            )
        }
        guard !plans.isEmpty else { return nil }
        let name = plans.count == 1 ? plans[0].exercise.displayName : "Repeated Routine"
        return WorkoutRoutine(name: name, exercises: plans)
    }

    var completedAt: Date {
        sets.map(\.timestamp).max() ?? .distantPast
    }

    var totalRepetitions: Int {
        sets.reduce(0) { $0 + $1.repetitions }
    }

    var totalDuration: TimeInterval {
        sets.reduce(0) { $0 + $1.duration }
    }

    var averageHeartRate: Double? {
        let values = sets.compactMap(\.averageHeartRate)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var weightPounds: Double? {
        guard let firstWeight = sets.first?.weightPounds,
              sets.allSatisfy({ abs($0.weightPounds - firstWeight) < 0.05 }) else { return nil }
        return firstWeight
    }

    var targetSets: Int? {
        sets.compactMap(\.targetSets).last
    }

    var targetRepetitions: Int? {
        sets.compactMap(\.targetRepetitions).last
    }

    var plannedRestDurationSeconds: Int? {
        sets.compactMap(\.plannedRestDurationSeconds).last
    }

    var repsInReserve: Int? {
        sets.sorted { $0.setNumber > $1.setNumber }.compactMap(\.repsInReserve).first
    }

    var wasCompletedAsPrescribed: Bool {
        guard let targetSets, let targetRepetitions else { return false }
        return sets.count >= targetSets && sets.allSatisfy { $0.repetitions >= targetRepetitions }
    }
}

enum ProgressionAction {
    case increase
    case maintain
    case decrease
}

struct ProgressionRecommendation {
    let action: ProgressionAction
    let title: String
    let explanation: String
    let recommendedWeightPounds: Double?
    let exercise: ExerciseKind
    let targetSets: Int?
    let targetRepetitions: Int?
    let restDurationSeconds: Int?
}

enum AdaptiveProgressionEngine {
    static func recommendation(
        for workoutID: UUID,
        in records: [WorkoutSetRecord],
        weightIncrementPounds: Double
    ) -> ProgressionRecommendation? {
        let workouts = WorkoutHistoryGrouping.workouts(from: records)
            .sorted { $0.completedAt > $1.completedAt }
        guard let wholeWorkout = workouts.first(where: { $0.sets.first?.workoutID == workoutID }),
              let effortSet = wholeWorkout.sets.first(where: { $0.repsInReserve != nil }),
              let exercise = ExerciseKind(rawValue: effortSet.exerciseRawValue),
              let current = exerciseSummary(from: wholeWorkout, exerciseRawValue: effortSet.exerciseRawValue),
              let currentRIR = current.repsInReserve,
              let currentWeight = current.weightPounds else { return nil }

        let comparableExerciseWorkouts = workouts.compactMap {
            exerciseSummary(from: $0, exerciseRawValue: effortSet.exerciseRawValue)
        }
        let previousComparable = comparableExerciseWorkouts.first { candidate in
            candidate.id != current.id
                && candidate.repsInReserve != nil
                && candidate.wasCompletedAsPrescribed
                && current.wasCompletedAsPrescribed
                && candidate.targetSets == current.targetSets
                && candidate.targetRepetitions == current.targetRepetitions
                && abs((candidate.weightPounds ?? -.infinity) - currentWeight) < 0.1
        }
        let increment = max(0.5, weightIncrementPounds)

        if currentRIR >= 3 {
            if let previousRIR = previousComparable?.repsInReserve, previousRIR >= 3 {
                let newWeight = currentWeight + increment
                return makeRecommendation(
                    action: .increase,
                    title: "Ready to add weight",
                    explanation: "You completed this prescription with at least 3 reps left twice in a row.",
                    weight: newWeight,
                    workout: current,
                    exercise: exercise
                )
            }
            return makeRecommendation(
                action: .maintain,
                title: "Confirm it next workout",
                explanation: "This felt easy. Repeat the same prescription once more before increasing the load.",
                weight: nil,
                workout: current,
                exercise: exercise
            )
        }

        if currentRIR == 0,
           let previousRIR = previousComparable?.repsInReserve,
           previousRIR == 0 {
            let newWeight = max(0, currentWeight - increment)
            return makeRecommendation(
                action: .decrease,
                title: "Consider a small deload",
                explanation: "You reached your limit on this prescription twice in a row.",
                weight: newWeight,
                workout: current,
                exercise: exercise
            )
        }

        let explanation = currentRIR == 0
            ? "You reached your limit today. Keep the load once more before reducing it."
            : "Finishing with 1–2 reps left is the target effort."
        return makeRecommendation(
            action: .maintain,
            title: "Keep this weight",
            explanation: explanation,
            weight: nil,
            workout: current,
            exercise: exercise
        )
    }

    private static func exerciseSummary(
        from workout: WorkoutSummary,
        exerciseRawValue: String
    ) -> WorkoutSummary? {
        let sets = workout.sets.filter { $0.exerciseRawValue == exerciseRawValue }
        guard !sets.isEmpty else { return nil }
        return WorkoutSummary(id: workout.id, sets: sets)
    }

    private static func makeRecommendation(
        action: ProgressionAction,
        title: String,
        explanation: String,
        weight: Double?,
        workout: WorkoutSummary,
        exercise: ExerciseKind
    ) -> ProgressionRecommendation {
        ProgressionRecommendation(
            action: action,
            title: title,
            explanation: explanation,
            recommendedWeightPounds: weight,
            exercise: exercise,
            targetSets: workout.targetSets,
            targetRepetitions: workout.targetRepetitions,
            restDurationSeconds: workout.plannedRestDurationSeconds
        )
    }
}

enum WorkoutHistoryGrouping {
    static func workouts(from records: [WorkoutSetRecord]) -> [WorkoutSummary] {
        var summaries: [WorkoutSummary] = []

        let currentRecords = records.filter { $0.workoutID != nil }
        let groupedCurrentRecords = Dictionary(grouping: currentRecords) { $0.workoutID! }
        summaries.append(contentsOf: groupedCurrentRecords.map { workoutID, sets in
            makeSummary(id: "workout-\(workoutID.uuidString)", sets: sets)
        })

        let legacyRecords = records
            .filter { $0.workoutID == nil }
            .sorted { $0.timestamp < $1.timestamp }
        var legacyGroup: [WorkoutSetRecord] = []

        for record in legacyRecords {
            if let previous = legacyGroup.last, startsNewLegacyWorkout(record, after: previous) {
                summaries.append(makeLegacySummary(from: legacyGroup))
                legacyGroup = []
            }
            legacyGroup.append(record)
        }

        if !legacyGroup.isEmpty {
            summaries.append(makeLegacySummary(from: legacyGroup))
        }

        return summaries
    }

    private static func startsNewLegacyWorkout(
        _ record: WorkoutSetRecord,
        after previous: WorkoutSetRecord
    ) -> Bool {
        let gap = record.timestamp.timeIntervalSince(previous.timestamp)
        return gap > 30 * 60
            || record.exerciseRawValue != previous.exerciseRawValue
            || abs(record.weightKilograms - previous.weightKilograms) > 0.01
            || record.setNumber <= previous.setNumber
    }

    private static func makeLegacySummary(from sets: [WorkoutSetRecord]) -> WorkoutSummary {
        let firstID = sets.first?.id.uuidString ?? UUID().uuidString
        return makeSummary(id: "legacy-\(firstID)", sets: sets)
    }

    private static func makeSummary(id: String, sets: [WorkoutSetRecord]) -> WorkoutSummary {
        WorkoutSummary(
            id: id,
            sets: sets.sorted { $0.timestamp < $1.timestamp }
        )
    }
}

struct ExercisePersonalRecord: Identifiable {
    let exercise: ExerciseKind
    let heaviestWeightPounds: Double
    let mostRepetitions: Int
    let estimatedOneRepMaxPounds: Double
    let achievedAt: Date

    var id: ExerciseKind { exercise }
}

enum PersonalRecordEngine {
    static func records(from sets: [WorkoutSetRecord]) -> [ExercisePersonalRecord] {
        Dictionary(grouping: sets) { $0.exerciseRawValue }.compactMap { rawValue, exerciseSets in
            guard let exercise = ExerciseKind(rawValue: rawValue),
                  let bestEstimatedSet = exerciseSets.max(by: {
                      estimatedOneRepMax(for: $0) < estimatedOneRepMax(for: $1)
                  }) else { return nil }
            return ExercisePersonalRecord(
                exercise: exercise,
                heaviestWeightPounds: exerciseSets.map(\.weightPounds).max() ?? 0,
                mostRepetitions: exerciseSets.map(\.repetitions).max() ?? 0,
                estimatedOneRepMaxPounds: estimatedOneRepMax(for: bestEstimatedSet),
                achievedAt: bestEstimatedSet.timestamp
            )
        }.sorted { $0.exercise.displayName < $1.exercise.displayName }
    }

    private static func estimatedOneRepMax(for set: WorkoutSetRecord) -> Double {
        set.weightPounds * (1 + Double(set.repetitions) / 30)
    }
}

@MainActor
final class WorkoutHistoryStore: ObservableObject {
    @Published private(set) var records: [WorkoutSetRecord] = []

    private let storageKey = "gymRepCoach.workoutSetHistory.v1"

    init() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([WorkoutSetRecord].self, from: data) else { return }
        records = decoded
    }

    func append(event: SetCompletedEvent) {
        if records.contains(where: {
            $0.workoutID == event.workoutID
                && $0.setNumber == event.setNumber
                && $0.timestamp == event.timestamp
        }) { return }
        records.insert(WorkoutSetRecord(event: event), at: 0)
        if records.count > 500 { records.removeLast(records.count - 500) }
        persist()
    }

    func recordEffort(repsInReserve: Int, for workoutID: UUID, exercise: ExerciseKind) {
        let indices = records.indices.filter {
            records[$0].workoutID == workoutID && records[$0].exerciseRawValue == exercise.rawValue
        }
        guard let finalSetIndex = indices.max(by: { records[$0].timestamp < records[$1].timestamp }) else { return }
        records[finalSetIndex].repsInReserve = min(max(0, repsInReserve), 4)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
