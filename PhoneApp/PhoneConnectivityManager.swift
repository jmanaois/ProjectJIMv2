import Combine
import Foundation
import WatchConnectivity

struct PlanSendConfirmation: Identifiable {
    let id = UUID()
    let message: String
}

@MainActor
final class PhoneConnectivityManager: NSObject, ObservableObject {
    @Published private(set) var latestEvent: SetCompletedEvent?
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
        try? session?.updateApplicationContext([ConnectivityKey.planData: data])

        if session?.isReachable == true {
            session?.sendMessage(
                [ConnectivityKey.planData: data],
                replyHandler: { [weak self] reply in
                    guard reply[ConnectivityKey.planAccepted] as? Bool == true else { return }
                    Task { @MainActor in
                        self?.planSendConfirmation = PlanSendConfirmation(
                            message: "\(plan.exercise.displayName), \(plan.targetSets) sets of \(plan.targetReps). Rest between sets: \(plan.formattedRestDuration.lowercased())."
                        )
                    }
                },
                errorHandler: nil
            )
        }
    }

    private func receive(_ message: [String: Any]) {
        switch message[ConnectivityKey.messageType] as? String {
        case ConnectivityKey.setCompleted:
            guard let data = message[ConnectivityKey.eventData] as? Data,
                  let event = try? decoder.decode(SetCompletedEvent.self, from: data) else { return }
            latestEvent = event
            soundPlayer.playSetCompleteTone()
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
