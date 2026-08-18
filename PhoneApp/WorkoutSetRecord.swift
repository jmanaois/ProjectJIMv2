import Combine
import Foundation

struct WorkoutSetRecord: Codable, Identifiable {
    let id: UUID
    var timestamp: Date
    var exerciseRawValue: String
    var setNumber: Int
    var repetitions: Int
    var weightKilograms: Double
    var duration: TimeInterval
    var averageHeartRate: Double?

    init(event: SetCompletedEvent) {
        id = UUID()
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
