import Foundation

enum ExerciseKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case bicepCurl
    case squat
    case row
    case shoulderPress

    static let armExercises: [ExerciseKind] = [.bicepCurl, .row, .shoulderPress]

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bicepCurl: "Bicep Curl"
        case .squat: "Squat"
        case .row: "Row"
        case .shoulderPress: "Shoulder Press"
        }
    }

    /// Starter thresholds only. Tune these using labeled recordings from physical devices.
    var detectorThresholds: DetectorThresholds {
        switch self {
        case .bicepCurl:
            .init(signal: .pitch(activationRadians: 0.55, returnRadians: 0.22), minimumExcursionDuration: 0.06, minimumRepInterval: 0.22, maximumRepDuration: 4.5)
        case .squat:
            .init(signal: .verticalAcceleration(activationG: 0.10, reversalG: 0.08), minimumExcursionDuration: 0.12, minimumRepInterval: 0.35, maximumRepDuration: 5.5)
        case .row:
            .init(signal: .horizontalAcceleration(activationG: 0.08, reversalG: 0.06), minimumExcursionDuration: 0.06, minimumRepInterval: 0.22, maximumRepDuration: 4.5)
        case .shoulderPress:
            .init(signal: .verticalAcceleration(activationG: 0.07, reversalG: 0.055), minimumExcursionDuration: 0.08, minimumRepInterval: 0.24, maximumRepDuration: 5.0)
        }
    }
}

enum DetectorSignal: Sendable {
    case pitch(activationRadians: Double, returnRadians: Double)
    case verticalAcceleration(activationG: Double, reversalG: Double)
    case horizontalAcceleration(activationG: Double, reversalG: Double)
}

struct DetectorThresholds: Sendable {
    let signal: DetectorSignal
    let minimumExcursionDuration: TimeInterval
    let minimumRepInterval: TimeInterval
    let maximumRepDuration: TimeInterval
}

struct ExercisePlan: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var exercise: ExerciseKind
    var targetSets: Int
    var targetReps: Int
    var weightKilograms: Double
    var restDurationSeconds: Int

    init(
        id: UUID = UUID(),
        exercise: ExerciseKind,
        targetSets: Int,
        targetReps: Int,
        weightKilograms: Double,
        restDurationSeconds: Int = 60
    ) {
        self.id = id
        self.exercise = exercise
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.weightKilograms = weightKilograms
        self.restDurationSeconds = max(0, restDurationSeconds)
    }

    var weightPounds: Double {
        WeightConversion.pounds(fromKilograms: weightKilograms)
    }

    var formattedRestDuration: String {
        Self.formattedRestDuration(seconds: restDurationSeconds)
    }

    static func formattedRestDuration(seconds: Int) -> String {
        switch max(0, seconds) {
        case 0:
            return "No rest"
        case 1..<60:
            return "\(seconds) sec"
        default:
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            return remainingSeconds == 0 ? "\(minutes) min" : "\(minutes)m \(remainingSeconds)s"
        }
    }

    static let sample = ExercisePlan(
        exercise: .bicepCurl,
        targetSets: 3,
        targetReps: 10,
        weightKilograms: 10,
        restDurationSeconds: 60
    )

    private enum CodingKeys: String, CodingKey {
        case id
        case exercise
        case targetSets
        case targetReps
        case weightKilograms
        case restDurationSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        exercise = try container.decode(ExerciseKind.self, forKey: .exercise)
        targetSets = try container.decode(Int.self, forKey: .targetSets)
        targetReps = try container.decode(Int.self, forKey: .targetReps)
        weightKilograms = try container.decode(Double.self, forKey: .weightKilograms)
        restDurationSeconds = max(
            0,
            try container.decodeIfPresent(Int.self, forKey: .restDurationSeconds) ?? 60
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(exercise, forKey: .exercise)
        try container.encode(targetSets, forKey: .targetSets)
        try container.encode(targetReps, forKey: .targetReps)
        try container.encode(weightKilograms, forKey: .weightKilograms)
        try container.encode(restDurationSeconds, forKey: .restDurationSeconds)
    }
}

enum WeightConversion {
    static let poundsPerKilogram = 2.204_622_621_8

    static func pounds(fromKilograms kilograms: Double) -> Double {
        kilograms * poundsPerKilogram
    }

    static func kilograms(fromPounds pounds: Double) -> Double {
        pounds / poundsPerKilogram
    }
}

struct SetCompletedEvent: Codable, Sendable {
    let workoutID: UUID?
    let exercise: ExerciseKind
    let setNumber: Int
    let repetitions: Int
    let weightKilograms: Double
    let duration: TimeInterval
    let averageHeartRate: Double?
    let timestamp: Date
}

enum ConnectivityKey {
    static let planData = "planData"
    static let eventData = "eventData"
    static let messageType = "messageType"
    static let setCompleted = "setCompleted"
    static let restCompleted = "restCompleted"
    static let planAccepted = "planAccepted"
}
