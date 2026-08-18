import Foundation

enum ExerciseKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case bicepCurl
    case squat
    case row
    case shoulderPress

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
        case .bicepCurl: .init(activationRadians: 0.55, returnRadians: 0.22, minimumRepDuration: 0.45, maximumRepDuration: 4.5)
        case .squat: .init(activationRadians: 0.42, returnRadians: 0.18, minimumRepDuration: 0.65, maximumRepDuration: 5.5)
        case .row: .init(activationRadians: 0.48, returnRadians: 0.20, minimumRepDuration: 0.45, maximumRepDuration: 4.5)
        case .shoulderPress: .init(activationRadians: 0.52, returnRadians: 0.20, minimumRepDuration: 0.55, maximumRepDuration: 5.0)
        }
    }
}

struct DetectorThresholds: Sendable {
    let activationRadians: Double
    let returnRadians: Double
    let minimumRepDuration: TimeInterval
    let maximumRepDuration: TimeInterval
}

struct ExercisePlan: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var exercise: ExerciseKind
    var targetSets: Int
    var targetReps: Int
    var weightKilograms: Double

    static let sample = ExercisePlan(
        exercise: .bicepCurl,
        targetSets: 3,
        targetReps: 10,
        weightKilograms: 10
    )
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

