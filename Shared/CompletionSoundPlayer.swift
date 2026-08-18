import AVFoundation
import Foundation
#if os(iOS)
import AudioToolbox
import UIKit
#endif

@MainActor
final class CompletionSoundPlayer {
    private var player: AVAudioPlayer?

    func playSetCompleteTone(onlyForExternalOutput: Bool = false) {
        play(.set, onlyForExternalOutput: onlyForExternalOutput)
    }

    func playWorkoutCompleteTone(onlyForExternalOutput: Bool = false) {
        play(.workout, onlyForExternalOutput: onlyForExternalOutput)
    }

    private func play(_ tone: CompletionTone, onlyForExternalOutput: Bool) {
#if os(iOS)
        let feedbackGenerator = UINotificationFeedbackGenerator()
        feedbackGenerator.prepare()
        feedbackGenerator.notificationOccurred(.success)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
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

            player = try AVAudioPlayer(data: Self.makeToneWAV(for: tone))
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

    private static func makeToneWAV(for tone: CompletionTone) -> Data {
        let sampleRate = 44_100
        let frequencies: [Double]
        let noteDuration: Double

        switch tone {
        case .set:
            frequencies = [659.25, 880.0]
            noteDuration = 0.3
        case .workout:
            frequencies = [523.25, 659.25, 783.99, 1_046.5]
            noteDuration = 0.24
        }

        let duration = noteDuration * Double(frequencies.count)
        let sampleCount = Int(Double(sampleRate) * duration)
        var pcm = Data(capacity: sampleCount * 2)

        for index in 0..<sampleCount {
            let time = Double(index) / Double(sampleRate)
            let noteIndex = min(Int(time / noteDuration), frequencies.count - 1)
            let noteTime = time - (Double(noteIndex) * noteDuration)
            let frequency = frequencies[noteIndex]
            let envelope = min(1, noteTime * 24) * min(1, (noteDuration - noteTime) * 18)
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

    private enum CompletionTone {
        case set
        case workout
    }
}
