import Combine
import CoreMotion
import Foundation
import HealthKit
import WatchConnectivity
import WatchKit

@MainActor
final class WatchWorkoutManager: NSObject, ObservableObject {
    @Published private(set) var plan = ExercisePlan.sample
    @Published private(set) var routine = WorkoutRoutine.single(.sample)
    @Published private(set) var currentExerciseIndex = 0
    @Published private(set) var repetitions = 0
    @Published private(set) var currentSet = 1
    @Published private(set) var heartRate = 0.0
    @Published private(set) var isRunning = false
    @Published private(set) var isStarting = false
    @Published private(set) var isResting = false
    @Published private(set) var isAwaitingExerciseStart = false
    @Published private(set) var restSecondsRemaining = 0
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
    private var latestHeartRateValue: Double?
    private var latestHeartRateRecordedAt: Date?
    private var activeWorkoutID = UUID()
    private var healthServicesPrepared = false
    private var healthPreparationTask: Task<Void, Error>?
    private var restTask: Task<Void, Never>?
    private var detectionEnabledAt = Date.distantPast

    override init() {
        super.init()
        connectivity?.delegate = self
        connectivity?.activate()
        Task { @MainActor [weak self] in
            await self?.prewarmFirstWorkout()
        }
    }

    func startWorkout() async {
        guard !isRunning, !isStarting else { return }
        isStarting = true
        errorMessage = nil
        defer { isStarting = false }

        do {
            try await prepareHealthServices()

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
            activeWorkoutID = UUID()
            currentExerciseIndex = 0
            plan = routine.exercises.first ?? .sample
            workoutStartedAt = Date()
            setStartedAt = workoutStartedAt
            detector = CycleRepDetector(exercise: plan.exercise)
            repetitions = 0
            currentSet = 1
            heartRate = 0
            latestHeartRateValue = nil
            latestHeartRateRecordedAt = nil
            isResting = false
            isAwaitingExerciseStart = false
            restSecondsRemaining = 0
            restTask?.cancel()
            restTask = nil
            heartRateSamples.removeAll()
            detectionEnabledAt = Date().addingTimeInterval(0.5)

            session.startActivity(with: workoutStartedAt)
            isRunning = true
            startMotionUpdates()
            try await beginCollection(builder, at: workoutStartedAt)
        } catch {
            restTask?.cancel()
            restTask = nil
            motionManager.stopDeviceMotionUpdates()
            workoutSession?.end()
            errorMessage = error.localizedDescription
            isRunning = false
            isResting = false
            restSecondsRemaining = 0
        }
    }

    private func prewarmFirstWorkout() async {
        let workoutType = HKObjectType.workoutType()
        guard healthStore.authorizationStatus(for: workoutType) != .notDetermined else { return }
        try? await prepareHealthServices()
    }

    private func prepareHealthServices() async throws {
        if healthServicesPrepared { return }

        if let healthPreparationTask {
            try await healthPreparationTask.value
            return
        }

        let preparationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try await self.requestHealthAuthorization()
        }
        healthPreparationTask = preparationTask

        do {
            try await preparationTask.value
            healthServicesPrepared = true
            healthPreparationTask = nil
        } catch {
            healthPreparationTask = nil
            throw error
        }
    }

    func adjustRepetitions(by amount: Int) {
        guard isRunning, !isResting, !isAwaitingExerciseStart else { return }
        repetitions = max(0, repetitions + amount)
    }

    func finishCurrentSet() {
        guard isRunning, !isResting, !isAwaitingExerciseStart, repetitions > 0 else { return }
        let completedAt = Date()
        let completesExercise = currentSet >= plan.targetSets
        let completesWorkout = completesExercise && currentExerciseIndex >= routine.exercises.count - 1
        let event = SetCompletedEvent(
            workoutID: activeWorkoutID,
            exercise: plan.exercise,
            setNumber: currentSet,
            repetitions: repetitions,
            weightKilograms: plan.weightKilograms,
            targetSets: plan.targetSets,
            targetRepetitions: plan.targetReps,
            plannedRestDurationSeconds: plan.restDurationSeconds,
            duration: completedAt.timeIntervalSince(setStartedAt),
            averageHeartRate: averageHeartRateForCurrentSet(at: completedAt),
            timestamp: completedAt
        )
        send(
            event: event,
            messageType: completesWorkout ? ConnectivityKey.workoutCompleted : ConnectivityKey.setCompleted
        )

        if completesWorkout {
            soundPlayer.playWorkoutCompleteTone(onlyForExternalOutput: true)
            WKInterfaceDevice.current().play(.success)
            endWorkout()
        } else if completesExercise {
            let transitionRestDuration = plan.restDurationSeconds
            soundPlayer.playSetCompleteTone(onlyForExternalOutput: true)
            WKInterfaceDevice.current().play(.success)
            currentExerciseIndex += 1
            plan = routine.exercises[currentExerciseIndex]
            currentSet = 1
            repetitions = 0
            heartRateSamples.removeAll()
            isDetectorCalibrated = false
            isAwaitingExerciseStart = true
            beginRest(duration: transitionRestDuration)
        } else {
            soundPlayer.playSetCompleteTone(onlyForExternalOutput: true)
            WKInterfaceDevice.current().play(.success)
            currentSet += 1
            repetitions = 0
            heartRateSamples.removeAll()
            isDetectorCalibrated = false
            beginRest()
        }
    }

    func skipRest() {
        guard isRunning, isResting else { return }
        completeRest(shouldNotify: false)
    }

    func startCurrentExercise() {
        guard isRunning, !isResting, isAwaitingExerciseStart else { return }
        isAwaitingExerciseStart = false
        setStartedAt = Date()
        repetitions = 0
        heartRateSamples.removeAll()
        detector = CycleRepDetector(exercise: plan.exercise)
        isDetectorCalibrated = false
        // Ignore the Watch-tap and weight repositioning before collecting a neutral pose.
        detectionEnabledAt = Date().addingTimeInterval(0.5)
        WKInterfaceDevice.current().play(.start)
    }

    func endWorkout() {
        guard isRunning else { return }
        restTask?.cancel()
        restTask = nil
        isResting = false
        isAwaitingExerciseStart = false
        restSecondsRemaining = 0
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

        motionManager.deviceMotionUpdateInterval = 1.0 / 100.0
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, _ in
            guard let motion else { return }
            let sample = RepMotionSample(
                pitch: motion.attitude.pitch,
                userAcceleration: MotionVector(
                    x: motion.userAcceleration.x,
                    y: motion.userAcceleration.y,
                    z: motion.userAcceleration.z
                ),
                gravity: MotionVector(
                    x: motion.gravity.x,
                    y: motion.gravity.y,
                    z: motion.gravity.z
                )
            )
            let timestamp = motion.timestamp
            Task { @MainActor [weak self] in
                self?.ingestMotion(sample: sample, timestamp: timestamp)
            }
        }
    }

    private func ingestMotion(sample: RepMotionSample, timestamp: TimeInterval) {
        guard isRunning,
              !isResting,
              !isAwaitingExerciseStart,
              Date() >= detectionEnabledAt else { return }
        if detector.ingest(sample: sample, timestamp: timestamp) {
            repetitions += 1
            WKInterfaceDevice.current().play(.click)
            if repetitions >= plan.targetReps {
                finishCurrentSet()
            }
        }
        let calibrated = detector.isCalibrated
        if isDetectorCalibrated != calibrated {
            isDetectorCalibrated = calibrated
        }
    }

    private func send(event: SetCompletedEvent, messageType: String) {
        guard let data = try? encoder.encode(event) else { return }
        let message: [String: Any] = [
            ConnectivityKey.messageType: messageType,
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

    private func averageHeartRateForCurrentSet(at completedAt: Date) -> Double? {
        if !heartRateSamples.isEmpty {
            return heartRateSamples.reduce(0, +) / Double(heartRateSamples.count)
        }

        // HealthKit delivery is asynchronous, so a set can end after the live
        // statistic updates but before its delegate callback reaches this actor.
        if let liveValue = currentLiveHeartRateValue() {
            return liveValue
        }

        guard let latestHeartRateValue,
              let latestHeartRateRecordedAt else { return nil }
        let readingAge = completedAt.timeIntervalSince(latestHeartRateRecordedAt)
        guard (0...20).contains(readingAge) else { return nil }
        return latestHeartRateValue
    }

    private func currentLiveHeartRateValue() -> Double? {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        return workoutBuilder?.statistics(for: heartRateType)?.mostRecentQuantity()?.doubleValue(
            for: HKUnit.count().unitDivided(by: .minute())
        )
    }

    private func beginRest(duration requestedDuration: Int? = nil) {
        let duration = max(0, requestedDuration ?? plan.restDurationSeconds)
        guard duration > 0 else {
            prepareNextSet()
            return
        }

        restTask?.cancel()
        isResting = true
        restSecondsRemaining = duration
        let restEndsAt = Date().addingTimeInterval(TimeInterval(duration))

        restTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let remaining = max(0, Int(ceil(restEndsAt.timeIntervalSinceNow)))
                self.restSecondsRemaining = remaining

                if remaining == 0 {
                    self.completeRest(shouldNotify: true)
                    return
                }

                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private func completeRest(shouldNotify: Bool) {
        restTask?.cancel()
        restTask = nil
        guard isRunning else {
            isResting = false
            restSecondsRemaining = 0
            return
        }

        isResting = false
        restSecondsRemaining = 0
        prepareNextSet()

        guard shouldNotify else { return }
        soundPlayer.playSetCompleteTone(onlyForExternalOutput: true)
        WKInterfaceDevice.current().play(.notification)
        sendRestCompleted()
    }

    private func prepareNextSet() {
        setStartedAt = Date()
        heartRateSamples.removeAll()
        detector = CycleRepDetector(exercise: plan.exercise)
        isDetectorCalibrated = false
        detectionEnabledAt = isAwaitingExerciseStart ? .distantFuture : Date()
    }

    private func sendRestCompleted() {
        guard connectivity?.isReachable == true else { return }
        connectivity?.sendMessage(
            [ConnectivityKey.messageType: ConnectivityKey.restCompleted],
            replyHandler: nil,
            errorHandler: nil
        )
    }

    @discardableResult
    private func receivePlan(from message: [String: Any]) -> Bool {
        guard !isRunning else { return false }

        let receivedRoutine: WorkoutRoutine?
        if let data = message[ConnectivityKey.routineData] as? Data {
            receivedRoutine = try? decoder.decode(WorkoutRoutine.self, from: data)
        } else if let data = message[ConnectivityKey.planData] as? Data,
                  let receivedPlan = try? decoder.decode(ExercisePlan.self, from: data) {
            receivedRoutine = .single(receivedPlan)
        } else {
            receivedRoutine = nil
        }

        guard let receivedRoutine,
              !receivedRoutine.exercises.isEmpty,
              receivedRoutine.exercises.allSatisfy({ ExerciseKind.armExercises.contains($0.exercise) }) else {
            return false
        }
        routine = receivedRoutine
        currentExerciseIndex = 0
        plan = receivedRoutine.exercises[0]
        detector = CycleRepDetector(exercise: plan.exercise)
        return true
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
            do {
                try await builder.endCollection(at: date)
                _ = try await builder.finishWorkout()
            } catch {
                self.errorMessage = "The workout ended, but HealthKit couldn’t save it."
            }
            self.workoutBuilder = nil
            self.workoutSession = nil
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.errorMessage = error.localizedDescription
            self.isRunning = false
            self.isResting = false
            self.restSecondsRemaining = 0
            self.restTask?.cancel()
            self.restTask = nil
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
        let recordedAt = Date()
        Task { @MainActor in
            guard self.isRunning else { return }
            self.heartRate = value
            self.latestHeartRateValue = value
            self.latestHeartRateRecordedAt = recordedAt
            if !self.isResting {
                self.heartRateSamples.append(value)
            }
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
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            let accepted = self.receivePlan(from: message)
            replyHandler([ConnectivityKey.planAccepted: accepted])
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in self.receivePlan(from: applicationContext) }
    }
}
