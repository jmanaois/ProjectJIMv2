import Foundation

/// A small, testable baseline detector. It recognizes a wrist-pitch excursion away
/// from a calibrated neutral position followed by a controlled return.
struct CycleRepDetector: Sendable {
    private enum Phase: Sendable {
        case calibrating
        case ready
        case awayFromNeutral(startedAt: TimeInterval)
    }

    private let thresholds: DetectorThresholds
    private var phase: Phase = .calibrating
    private var calibrationSamples: [Double] = []
    private var neutralPitch = 0.0
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
    mutating func ingest(pitch: Double, timestamp: TimeInterval) -> Bool {
        switch phase {
        case .calibrating:
            calibrationSamples.append(pitch)
            if calibrationSamples.count >= 30 {
                neutralPitch = calibrationSamples.reduce(0, +) / Double(calibrationSamples.count)
                calibrationSamples.removeAll(keepingCapacity: false)
                phase = .ready
            }
            return false

        case .ready:
            let excursion = angularDistance(pitch, neutralPitch)
            guard excursion >= thresholds.activationRadians,
                  timestamp - lastRepTimestamp > thresholds.minimumRepDuration else { return false }
            phase = .awayFromNeutral(startedAt: timestamp)
            return false

        case .awayFromNeutral(let startedAt):
            let duration = timestamp - startedAt
            if duration > thresholds.maximumRepDuration {
                phase = .ready
                return false
            }

            guard angularDistance(pitch, neutralPitch) <= thresholds.returnRadians,
                  duration >= thresholds.minimumRepDuration else { return false }
            lastRepTimestamp = timestamp
            phase = .ready
            return true
        }
    }

    private func angularDistance(_ first: Double, _ second: Double) -> Double {
        let raw = abs(first - second).truncatingRemainder(dividingBy: .pi * 2)
        return min(raw, .pi * 2 - raw)
    }
}

