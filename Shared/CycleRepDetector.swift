import Foundation

struct WristOrientation: Sendable {
    let x: Double
    let y: Double
    let z: Double
    let w: Double

    static let identity = WristOrientation(x: 0, y: 0, z: 0, w: 1)

    var normalized: WristOrientation {
        let magnitude = sqrt(x * x + y * y + z * z + w * w)
        guard magnitude > 0 else { return .identity }
        return WristOrientation(x: x / magnitude, y: y / magnitude, z: z / magnitude, w: w / magnitude)
    }

    func dot(_ other: WristOrientation) -> Double {
        x * other.x + y * other.y + z * other.z + w * other.w
    }
}

/// A small, testable baseline detector. It recognizes a 3D wrist-orientation
/// excursion away from a calibrated neutral position followed by a return.
struct CycleRepDetector: Sendable {
    private enum Phase: Sendable {
        case calibrating
        case ready
        case awayFromNeutral(startedAt: TimeInterval)
    }

    private let thresholds: DetectorThresholds
    private var phase: Phase = .calibrating
    private var calibrationSamples: [WristOrientation] = []
    private var neutralOrientation = WristOrientation.identity
    private var lastRepTimestamp: TimeInterval = -.infinity

    init(exercise: ExerciseKind) {
        thresholds = exercise.detectorThresholds
    }

    var isCalibrated: Bool {
        if case .calibrating = phase { return false }
        return true
    }

    mutating func reset(exercise: ExerciseKind? = nil) {
        self = CycleRepDetector(exercise: exercise ?? .bicepCurl)
    }

    /// Returns true once for each completed rep.
    mutating func ingest(orientation: WristOrientation, timestamp: TimeInterval) -> Bool {
        switch phase {
        case .calibrating:
            calibrationSamples.append(orientation.normalized)
            if calibrationSamples.count >= 30 {
                neutralOrientation = averageOrientation(calibrationSamples)
                calibrationSamples.removeAll(keepingCapacity: false)
                phase = .ready
            }
            return false

        case .ready:
            let excursion = angularDistance(orientation, neutralOrientation)
            guard excursion >= thresholds.activationRadians,
                  timestamp - lastRepTimestamp >= thresholds.minimumRepInterval else { return false }
            phase = .awayFromNeutral(startedAt: timestamp)
            return false

        case .awayFromNeutral(let startedAt):
            let duration = timestamp - startedAt
            if duration > thresholds.maximumRepDuration {
                phase = .ready
                return false
            }

            guard angularDistance(orientation, neutralOrientation) <= thresholds.returnRadians else { return false }

            // A very short excursion is likely a sensor spike. Return to the
            // ready phase immediately so it cannot hide the next real rep.
            guard duration >= thresholds.minimumExcursionDuration else {
                phase = .ready
                return false
            }

            lastRepTimestamp = timestamp
            phase = .ready
            return true
        }
    }

    private func averageOrientation(_ samples: [WristOrientation]) -> WristOrientation {
        guard let reference = samples.first else { return .identity }
        var x = 0.0
        var y = 0.0
        var z = 0.0
        var w = 0.0

        for sample in samples {
            // q and -q describe the same rotation. Align signs before averaging
            // so equivalent samples do not cancel each other out.
            let sign = sample.dot(reference) < 0 ? -1.0 : 1.0
            x += sample.x * sign
            y += sample.y * sign
            z += sample.z * sign
            w += sample.w * sign
        }

        return WristOrientation(x: x, y: y, z: z, w: w).normalized
    }

    private func angularDistance(_ first: WristOrientation, _ second: WristOrientation) -> Double {
        let normalizedFirst = first.normalized
        let normalizedSecond = second.normalized
        let similarity = min(1.0, abs(normalizedFirst.dot(normalizedSecond)))
        return 2 * acos(similarity)
    }
}
