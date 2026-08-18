import Foundation

struct MotionVector: Sendable {
    let x: Double
    let y: Double
    let z: Double

    static let zero = MotionVector(x: 0, y: 0, z: 0)

    var magnitude: Double {
        sqrt(x * x + y * y + z * z)
    }

    var normalized: MotionVector {
        let length = magnitude
        guard length > 0 else { return .zero }
        return scaled(by: 1 / length)
    }

    func dot(_ other: MotionVector) -> Double {
        x * other.x + y * other.y + z * other.z
    }

    func scaled(by scale: Double) -> MotionVector {
        MotionVector(x: x * scale, y: y * scale, z: z * scale)
    }

    func adding(_ other: MotionVector) -> MotionVector {
        MotionVector(x: x + other.x, y: y + other.y, z: z + other.z)
    }

    func subtracting(_ other: MotionVector) -> MotionVector {
        MotionVector(x: x - other.x, y: y - other.y, z: z - other.z)
    }
}

struct RepMotionSample: Sendable {
    let pitch: Double
    let userAcceleration: MotionVector
    let gravity: MotionVector
}

/// An exercise-specific rep detector:
/// - curls use a low-high-low wrist-pitch cycle;
/// - presses use a full vertical acceleration cycle;
/// - rows use a full horizontal acceleration cycle.
struct CycleRepDetector: Sendable {
    private enum Phase: Sendable {
        case calibrating
        case ready
        case angularAway(startedAt: TimeInterval)
        case translatingOut(startedAt: TimeInterval, direction: MotionVector)
        case translatingBack(startedAt: TimeInterval, direction: MotionVector)
    }

    private let exercise: ExerciseKind
    private let thresholds: DetectorThresholds
    private var phase: Phase = .calibrating
    private var calibrationPitches: [Double] = []
    private var calibrationSampleCount = 0
    private var neutralPitch = 0.0
    private var filteredAcceleration = MotionVector.zero
    private var lastRepTimestamp: TimeInterval = -.infinity

    init(exercise: ExerciseKind) {
        self.exercise = exercise
        thresholds = exercise.detectorThresholds
    }

    var isCalibrated: Bool {
        if case .calibrating = phase { return false }
        return true
    }

    mutating func reset(exercise: ExerciseKind? = nil) {
        self = CycleRepDetector(exercise: exercise ?? self.exercise)
    }

    /// Returns true once a complete exercise-specific movement returns to its start.
    mutating func ingest(sample: RepMotionSample, timestamp: TimeInterval) -> Bool {
        filterAcceleration(sample.userAcceleration)

        switch phase {
        case .calibrating:
            calibrationSampleCount += 1
            if case .pitch = thresholds.signal {
                calibrationPitches.append(sample.pitch)
            }

            if calibrationSampleCount >= 30 {
                if !calibrationPitches.isEmpty {
                    neutralPitch = calibrationPitches.reduce(0, +) / Double(calibrationPitches.count)
                }
                calibrationPitches.removeAll(keepingCapacity: false)
                phase = .ready
            }
            return false

        case .ready:
            guard timestamp - lastRepTimestamp >= thresholds.minimumRepInterval else { return false }

            switch thresholds.signal {
            case .pitch(let activationRadians, _):
                guard angularDistance(sample.pitch, neutralPitch) >= activationRadians else { return false }
                phase = .angularAway(startedAt: timestamp)

            case .verticalAcceleration(let activationG, _),
                 .horizontalAcceleration(let activationG, _):
                let signal = translationSignal(for: sample)
                guard signal.magnitude >= activationG else { return false }
                phase = .translatingOut(startedAt: timestamp, direction: signal.normalized)
            }
            return false

        case .angularAway(let startedAt):
            let duration = timestamp - startedAt
            if duration > thresholds.maximumRepDuration {
                phase = .ready
                return false
            }

            guard case .pitch(_, let returnRadians) = thresholds.signal,
                  angularDistance(sample.pitch, neutralPitch) <= returnRadians else { return false }

            guard duration >= thresholds.minimumExcursionDuration else {
                phase = .ready
                return false
            }

            return completeRep(at: timestamp)

        case .translatingOut(let startedAt, let direction):
            let duration = timestamp - startedAt
            if duration > thresholds.maximumRepDuration {
                phase = .ready
                return false
            }

            guard translationSignal(for: sample).dot(direction) <= -translationReversalThreshold else {
                return false
            }

            guard duration >= thresholds.minimumExcursionDuration else {
                phase = .ready
                return false
            }

            phase = .translatingBack(startedAt: startedAt, direction: direction)
            return false

        case .translatingBack(let startedAt, let direction):
            let duration = timestamp - startedAt
            if duration > thresholds.maximumRepDuration {
                phase = .ready
                return false
            }

            guard translationSignal(for: sample).dot(direction) >= translationActivationThreshold else {
                return false
            }

            guard duration >= thresholds.minimumRepInterval else {
                phase = .ready
                return false
            }

            return completeRep(at: timestamp)
        }
    }

    private mutating func filterAcceleration(_ acceleration: MotionVector) {
        let previousWeight = 0.65
        let sampleWeight = 1 - previousWeight
        filteredAcceleration = filteredAcceleration.scaled(by: previousWeight)
            .adding(acceleration.scaled(by: sampleWeight))
    }

    private func translationSignal(for sample: RepMotionSample) -> MotionVector {
        let gravity = sample.gravity.normalized

        switch thresholds.signal {
        case .verticalAcceleration:
            // Gravity points down, so the opposite projection is vertical motion.
            let verticalAcceleration = -filteredAcceleration.dot(gravity)
            return MotionVector(x: verticalAcceleration, y: 0, z: 0)

        case .horizontalAcceleration:
            let verticalComponent = gravity.scaled(by: filteredAcceleration.dot(gravity))
            return filteredAcceleration.subtracting(verticalComponent)

        case .pitch:
            return .zero
        }
    }

    private var translationActivationThreshold: Double {
        switch thresholds.signal {
        case .verticalAcceleration(let activationG, _),
             .horizontalAcceleration(let activationG, _): activationG
        case .pitch: .infinity
        }
    }

    private var translationReversalThreshold: Double {
        switch thresholds.signal {
        case .verticalAcceleration(_, let reversalG),
             .horizontalAcceleration(_, let reversalG): reversalG
        case .pitch: .infinity
        }
    }

    private mutating func completeRep(at timestamp: TimeInterval) -> Bool {
        lastRepTimestamp = timestamp
        phase = .ready
        return true
    }

    private func angularDistance(_ first: Double, _ second: Double) -> Double {
        let raw = abs(first - second).truncatingRemainder(dividingBy: .pi * 2)
        return min(raw, .pi * 2 - raw)
    }
}
