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
        sets.first?.exerciseName ?? "Workout"
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
            sets: sets.sorted {
                if $0.setNumber == $1.setNumber { return $0.timestamp < $1.timestamp }
                return $0.setNumber < $1.setNumber
            }
        )
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
        records.insert(WorkoutSetRecord(event: event), at: 0)
        if records.count > 500 { records.removeLast(records.count - 500) }
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
