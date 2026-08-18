import Combine
import CoreMotion
import Foundation
import HealthKit
import WatchConnectivity
import WatchKit

@MainActor
final class WatchWorkoutManager: NSObject, ObservableObject {
    @Published private(set) var plan = ExercisePlan.sample
    @Published private(set) var repetitions = 0
    @Published private(set) var currentSet = 1
    @Published private(set) var heartRate = 0.0
    @Published private(set) var isRunning = false
    @Published private(set) var isDetectorCalibrated = false
    @Published private(set) var errorMessage: String?

    private let healthStore = HKHealthStore()
    private let motionManager = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "ProjectJIM.motion"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private let connectivity: WCSession? = WCSession.isSupported() ? .default : nil
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let soundPlayer = CompletionSoundPlayer()

    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var detector = CycleRepDetector(exercise: .bicepCurl)
    private var workoutStartedAt = Date()
    private var setStartedAt = Date()
    private var heartRateSamples: [Double] = []

    override init() {
        super.init()
        connectivity?.delegate = self
        connectivity?.activate()
    }

    func startWorkout() async {
        guard !isRunning else { return }
        errorMessage = nil

        do {
            try await requestHealthAuthorization()

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .traditionalStrengthTraining
            configuration.locationType = .indoor

            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )
            session.delegate = self
            builder.delegate = self

            workoutSession = session
            workoutBuilder = builder
            workoutStartedAt = Date()
            setStartedAt = workoutStartedAt
            detector = CycleRepDetector(exercise: plan.exercise)
            repetitions = 0
            currentSet = 1
            heartRateSamples.removeAll()

            session.startActivity(with: workoutStartedAt)
            try await beginCollection(builder, at: workoutStartedAt)
            startMotionUpdates()
            isRunning = true
        } catch {
            errorMessage = error.localizedDescription
            isRunning = false
        }
    }

    func adjustRepetitions(by amount: Int) {
        repetitions = max(0, repetitions + amount)
    }

    func finishCurrentSet() {
        guard isRunning, repetitions > 0 else { return }
        let event = SetCompletedEvent(
            exercise: plan.exercise,
            setNumber: currentSet,
            repetitions: repetitions,
            weightKilograms: plan.weightKilograms,
            duration: Date().timeIntervalSince(setStartedAt),
            averageHeartRate: heartRateSamples.isEmpty ? nil : heartRateSamples.reduce(0, +) / Double(heartRateSamples.count),
            timestamp: Date()
        )
        send(event: event)
        soundPlayer.playSetCompleteTone(onlyForExternalOutput: true)
        WKInterfaceDevice.current().play(.success)

        if currentSet >= plan.targetSets {
            endWorkout()
        } else {
            currentSet += 1
            repetitions = 0
            setStartedAt = Date()
            heartRateSamples.removeAll()
            detector = CycleRepDetector(exercise: plan.exercise)
            isDetectorCalibrated = false
        }
    }

    func endWorkout() {
        guard isRunning else { return }
        motionManager.stopDeviceMotionUpdates()
        workoutSession?.end()
        isRunning = false
    }

    private func requestHealthAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable(),
              let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let workout = HKObjectType.workoutType()
        try await healthStore.requestAuthorization(toShare: [workout], read: [heartRate])
    }

    private func beginCollection(_ builder: HKLiveWorkoutBuilder, at date: Date) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.beginCollection(withStart: date) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume() }
                else { continuation.resume(throwing: WorkoutError.collectionFailed) }
            }
        }
    }

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            errorMessage = "Motion data is unavailable on this device."
            return
        }

        motionManager.deviceMotionUpdateInterval = 1.0 / 50.0
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, _ in
            guard let motion else { return }
            let pitch = motion.attitude.pitch
            let timestamp = motion.timestamp
            Task { @MainActor [weak self] in
                self?.ingestMotion(pitch: pitch, timestamp: timestamp)
            }
        }
    }

    private func ingestMotion(pitch: Double, timestamp: TimeInterval) {
        guard isRunning else { return }
        if detector.ingest(pitch: pitch, timestamp: timestamp) {
            repetitions += 1
            WKInterfaceDevice.current().play(.click)
            if repetitions >= plan.targetReps {
                finishCurrentSet()
            }
        }
        isDetectorCalibrated = detector.isCalibrated
    }

    private func send(event: SetCompletedEvent) {
        guard let data = try? encoder.encode(event) else { return }
        let message: [String: Any] = [
            ConnectivityKey.messageType: ConnectivityKey.setCompleted,
            ConnectivityKey.eventData: data
        ]

        if connectivity?.isReachable == true {
            connectivity?.sendMessage(message, replyHandler: nil) { [weak self] _ in
                self?.connectivity?.transferUserInfo(message)
            }
        } else {
            connectivity?.transferUserInfo(message)
        }
    }

    private func receivePlan(from message: [String: Any]) {
        guard !isRunning,
              let data = message[ConnectivityKey.planData] as? Data,
              let receivedPlan = try? decoder.decode(ExercisePlan.self, from: data) else { return }
        plan = receivedPlan
        detector = CycleRepDetector(exercise: receivedPlan.exercise)
    }

    private enum WorkoutError: LocalizedError {
        case collectionFailed
        var errorDescription: String? { "HealthKit could not begin collecting workout data." }
    }
}

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        guard toState == .ended else { return }
        Task { @MainActor [weak self] in
            guard let self, let builder = self.workoutBuilder else { return }
            builder.endCollection(withEnd: date) { _, _ in
                builder.finishWorkout { _, _ in }
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.errorMessage = error.localizedDescription
            self.isRunning = false
            self.motionManager.stopDeviceMotionUpdates()
        }
    }
}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(heartRateType),
              let value = workoutBuilder.statistics(for: heartRateType)?.mostRecentQuantity()?.doubleValue(
                for: HKUnit.count().unitDivided(by: .minute())
              ) else { return }
        Task { @MainActor in
            self.heartRate = value
            self.heartRateSamples.append(value)
        }
    }
}

extension WatchWorkoutManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let context = session.receivedApplicationContext
        Task { @MainActor in self.receivePlan(from: context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.receivePlan(from: message) }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in self.receivePlan(from: applicationContext) }
    }
}
