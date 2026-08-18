import AVFoundation
import Foundation
#if os(iOS)
import UIKit
#endif

@MainActor
final class CompletionSoundPlayer {
    private var player: AVAudioPlayer?

    func playSetCompleteTone(onlyForExternalOutput: Bool = false) {
#if os(iOS)
        let feedbackGenerator = UINotificationFeedbackGenerator()
        feedbackGenerator.prepare()
        feedbackGenerator.notificationOccurred(.success)
#endif

        do {
            let audioSession = AVAudioSession.sharedInstance()
            // The playback category uses the system-selected Bluetooth route
            // when present and the built-in speaker otherwise.
            try audioSession.setCategory(
                .playback,
                mode: .default,
                options: [.duckOthers]
            )
            try audioSession.setActive(true)

            if onlyForExternalOutput && !Self.hasExternalOutput(audioSession.currentRoute.outputs) {
                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                return
            }

            player = try AVAudioPlayer(data: Self.makeToneWAV())
            player?.volume = 1.0
            player?.prepareToPlay()
            player?.play()
        } catch {
            // Haptics remain the fallback if the selected route cannot play audio.
            print("Unable to play completion tone: \(error)")
        }
    }

    private static func hasExternalOutput(_ outputs: [AVAudioSessionPortDescription]) -> Bool {
        outputs.contains { output in
            switch output.portType {
            case .bluetoothA2DP, .bluetoothLE, .headphones, .airPlay:
                true
            default:
                false
            }
        }
    }

    private static func makeToneWAV() -> Data {
        let sampleRate = 44_100
        let duration = 0.6
        let sampleCount = Int(Double(sampleRate) * duration)
        var pcm = Data(capacity: sampleCount * 2)

        for index in 0..<sampleCount {
            let time = Double(index) / Double(sampleRate)
            let frequency = time < 0.28 ? 659.25 : 880.0
            let envelope = min(1, time * 18) * min(1, (duration - time) * 12)
            let value = Int16(sin(2 * .pi * frequency * time) * envelope * 24_000)
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { pcm.append(contentsOf: $0) }
        }

        var wav = Data()
        func append(_ string: String) { wav.append(string.data(using: .ascii)!) }
        func appendUInt32(_ value: UInt32) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { wav.append(contentsOf: $0) }
        }
        func appendUInt16(_ value: UInt16) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { wav.append(contentsOf: $0) }
        }

        append("RIFF")
        appendUInt32(UInt32(36 + pcm.count))
        append("WAVEfmt ")
        appendUInt32(16)
        appendUInt16(1)
        appendUInt16(1)
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * 2))
        appendUInt16(2)
        appendUInt16(16)
        append("data")
        appendUInt32(UInt32(pcm.count))
        wav.append(pcm)
        return wav
    }
}
