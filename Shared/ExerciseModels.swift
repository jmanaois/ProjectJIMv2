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
            .init(activationRadians: 0.55, returnRadians: 0.27, minimumExcursionDuration: 0.06, minimumRepInterval: 0.22, maximumRepDuration: 4.5)
        case .squat:
            .init(activationRadians: 0.42, returnRadians: 0.18, minimumExcursionDuration: 0.12, minimumRepInterval: 0.35, maximumRepDuration: 5.5)
        case .row:
            .init(activationRadians: 0.48, returnRadians: 0.25, minimumExcursionDuration: 0.06, minimumRepInterval: 0.22, maximumRepDuration: 4.5)
        case .shoulderPress:
            .init(activationRadians: 0.52, returnRadians: 0.25, minimumExcursionDuration: 0.08, minimumRepInterval: 0.24, maximumRepDuration: 5.0)
        }
    }
}

struct DetectorThresholds: Sendable {
    let activationRadians: Double
    let returnRadians: Double
    let minimumExcursionDuration: TimeInterval
    let minimumRepInterval: TimeInterval
    let maximumRepDuration: TimeInterval
}

struct ExercisePlan: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var exercise: ExerciseKind
    var targetSets: Int
    var targetReps: Int
    var weightKilograms: Double

    var weightPounds: Double {
        WeightConversion.pounds(fromKilograms: weightKilograms)
    }

    static let sample = ExercisePlan(
        exercise: .bicepCurl,
        targetSets: 3,
        targetReps: 10,
        weightKilograms: 10
    )
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
}
