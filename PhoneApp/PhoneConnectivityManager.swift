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
        guard let data = try? encoder.encode(plan) else { return }
        do {
            try session?.updateApplicationContext([ConnectivityKey.planData: data])
        } catch {
            planSendConfirmation = PlanSendConfirmation(
                title: "Couldn’t Save Workout",
                message: "Try again after your Watch is available."
            )
            return
        }

        if session?.isReachable == true {
            session?.sendMessage(
                [ConnectivityKey.planData: data],
                replyHandler: { [weak self] reply in
                    guard reply[ConnectivityKey.planAccepted] as? Bool == true else { return }
                    Task { @MainActor in
                        self?.planSendConfirmation = PlanSendConfirmation(
                            title: "Workout Sent",
                            message: self?.sentConfirmationMessage(for: plan) ?? "Workout sent to Apple Watch."
                        )
                    }
                },
                errorHandler: { [weak self] _ in
                    Task { @MainActor in
                        self?.showQueuedConfirmation(for: plan)
                    }
                }
            )
        } else {
            showQueuedConfirmation(for: plan)
        }
    }

    private func showQueuedConfirmation(for plan: ExercisePlan) {
        planSendConfirmation = PlanSendConfirmation(
            title: "Workout Ready to Sync",
            message: "\(plan.exercise.displayName) will sync when the Watch app is available."
        )
    }

    private func sentConfirmationMessage(for plan: ExercisePlan) -> String {
        let setNoun = plan.targetSets == 1 ? "set" : "sets"
        let repNoun = plan.targetReps == 1 ? "rep" : "reps"
        let prescription = "\(plan.exercise.displayName): \(plan.targetSets) \(setNoun) of \(plan.targetReps) \(repNoun)."

        guard plan.targetSets > 1 else { return prescription }
        return "\(prescription) Rest between sets: \(plan.formattedRestDuration.lowercased())."
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
