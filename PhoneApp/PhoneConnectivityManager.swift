import Combine
import Foundation
import WatchConnectivity

struct PlanSendConfirmation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class PhoneConnectivityManager: NSObject, ObservableObject {
    @Published private(set) var latestEvent: SetCompletedEvent?
    @Published private(set) var completedWorkoutEvent: SetCompletedEvent?
    @Published private(set) var isWatchReachable = false
    @Published var planSendConfirmation: PlanSendConfirmation?

    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let soundPlayer = CompletionSoundPlayer()

    override init() {
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func send(plan: ExercisePlan) {
        send(routine: .single(plan))
    }

    func send(routine: WorkoutRoutine) {
        guard let firstPlan = routine.exercises.first,
              let routineData = try? encoder.encode(routine),
              let planData = try? encoder.encode(firstPlan) else { return }
        let payload: [String: Any] = [
            ConnectivityKey.routineData: routineData,
            // Keep the first exercise available to Watch builds that only understand plans.
            ConnectivityKey.planData: planData
        ]
        do {
            try session?.updateApplicationContext(payload)
        } catch {
            planSendConfirmation = PlanSendConfirmation(
                title: "Couldn’t Save Workout",
                message: "Try again after your Watch is available."
            )
            return
        }

        if session?.isReachable == true {
            session?.sendMessage(
                payload,
                replyHandler: { [weak self] reply in
                    guard reply[ConnectivityKey.planAccepted] as? Bool == true else { return }
                    Task { @MainActor in
                        self?.planSendConfirmation = PlanSendConfirmation(
                            title: "Workout Sent",
                            message: self?.sentConfirmationMessage(for: routine) ?? "Workout sent to Apple Watch."
                        )
                    }
                },
                errorHandler: { [weak self] _ in
                    Task { @MainActor in
                        self?.showQueuedConfirmation(for: routine)
                    }
                }
            )
        } else {
            showQueuedConfirmation(for: routine)
        }
    }

    private func showQueuedConfirmation(for routine: WorkoutRoutine) {
        planSendConfirmation = PlanSendConfirmation(
            title: "Workout Ready to Sync",
            message: "\(routineDisplayName(routine)) will sync when the Watch app is available."
        )
    }

    private func sentConfirmationMessage(for routine: WorkoutRoutine) -> String {
        guard routine.exercises.count == 1, let plan = routine.exercises.first else {
            return "\(routine.exercises.count) exercises and \(routine.totalTargetSets) total sets sent to Apple Watch."
        }
        let setNoun = plan.targetSets == 1 ? "set" : "sets"
        let repNoun = plan.targetReps == 1 ? "rep" : "reps"
        let prescription = "\(plan.exercise.displayName): \(plan.targetSets) \(setNoun) of \(plan.targetReps) \(repNoun)."

        guard plan.targetSets > 1 else { return prescription }
        return "\(prescription) Rest between sets: \(plan.formattedRestDuration.lowercased())."
    }

    private func routineDisplayName(_ routine: WorkoutRoutine) -> String {
        if routine.exercises.count == 1 { return routine.exercises[0].exercise.displayName }
        return "Your \(routine.exercises.count)-exercise routine"
    }

    private func receive(_ message: [String: Any]) {
        switch message[ConnectivityKey.messageType] as? String {
        case ConnectivityKey.setCompleted, ConnectivityKey.workoutCompleted:
            guard let data = message[ConnectivityKey.eventData] as? Data,
                  let event = try? decoder.decode(SetCompletedEvent.self, from: data) else { return }
            latestEvent = event
            if message[ConnectivityKey.messageType] as? String == ConnectivityKey.workoutCompleted {
                completedWorkoutEvent = event
                soundPlayer.playWorkoutCompleteTone()
            } else {
                soundPlayer.playSetCompleteTone()
            }
        case ConnectivityKey.restCompleted:
            soundPlayer.playSetCompleteTone()
        default:
            return
        }
    }
}

extension PhoneConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in self.isWatchReachable = session.isReachable }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.isWatchReachable = session.isReachable }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.receive(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in self.receive(userInfo) }
    }
}
