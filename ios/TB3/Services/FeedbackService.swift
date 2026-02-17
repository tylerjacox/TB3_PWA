// TB3 iOS — Feedback Service (mirrors services/feedback.ts)
// Haptics via UIFeedbackGenerator, audio tones via AVAudioEngine, speech via AVSpeechSynthesizer.

import Foundation
import AVFoundation
import UIKit

@MainActor
final class FeedbackService {
    private var audioEngine: AVAudioEngine?
    private var speechSynthesizer = AVSpeechSynthesizer()
    private var soundMode: String = "on"
    private var voiceEnabled: Bool = false
    private var voiceName: String?
    private var castConnected: Bool = false

    // Voice milestone thresholds (seconds remaining)
    private static let milestoneLabels: [Int: String] = [
        60: "One minute",
        30: "Thirty seconds",
        15: "Fifteen seconds",
        5: "Five", 4: "Four", 3: "Three", 2: "Two", 1: "One",
    ]

    func configure(soundMode: String, voiceEnabled: Bool, voiceName: String?, castConnected: Bool = false) {
        self.soundMode = soundMode
        self.voiceEnabled = voiceEnabled
        self.voiceName = voiceName
        self.castConnected = castConnected
    }

    // MARK: - Haptics

    private func vibrate(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard soundMode != "off" else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    private func vibrateNotification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard soundMode != "off" else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }

    private func vibratePattern(_ count: Int, style: UIImpactFeedbackGenerator.FeedbackStyle = .light, interval: TimeInterval = 0.1) {
        guard soundMode != "off" else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * interval) {
                generator.impactOccurred()
            }
        }
    }

    // MARK: - Audio Tones

    struct ToneSpec {
        let frequency: Double
        let duration: TimeInterval
        let delay: TimeInterval
    }

    private func playTones(_ tones: [ToneSpec]) {
        guard soundMode == "on", !castConnected else { return }

        // Configure audio session
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)

        let engine = AVAudioEngine()
        let mainMixer = engine.mainMixerNode
        let format = mainMixer.outputFormat(forBus: 0)
        let sampleRate = format.sampleRate

        for tone in tones {
            // Capture values for the audio render callback (runs on IO thread, not MainActor)
            let freq = tone.frequency
            let sr = sampleRate

            let sourceNode = AVAudioSourceNode { @Sendable _, _, frameCount, audioBufferList -> OSStatus in
                let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
                let amplitude: Float = 0.15
                for frame in 0..<Int(frameCount) {
                    let sampleTime = Double(frame) / sr
                    let value = Float(sin(2.0 * .pi * freq * sampleTime)) * amplitude
                    for buffer in ablPointer {
                        let buf = buffer.mData?.assumingMemoryBound(to: Float.self)
                        buf?[frame] = value
                    }
                }
                return noErr
            }

            engine.attach(sourceNode)
            engine.connect(sourceNode, to: mainMixer, format: format)

            let startDelay = tone.delay
            let stopDelay = tone.delay + tone.duration

            DispatchQueue.main.asyncAfter(deadline: .now() + startDelay) {
                try? engine.start()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + stopDelay) {
                engine.stop()
                engine.detach(sourceNode)
            }
        }

        self.audioEngine = engine
    }

    // MARK: - Speech

    private func speak(_ text: String) {
        guard voiceEnabled, !castConnected else { return }
        speechSynthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.55 // ~1.1x normal speed (matching PWA)

        if let voiceName, let voice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.name == voiceName }) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        speechSynthesizer.speak(utterance)
    }

    // MARK: - Feedback Events

    /// Set completed — light haptic + two-tone beep
    func setComplete() {
        vibrate(.light)
        playTones([
            ToneSpec(frequency: 660, duration: 0.06, delay: 0),
            ToneSpec(frequency: 880, duration: 0.08, delay: 0.06),
        ])
    }

    /// All sets for exercise completed — 3 haptic pulses + rising chord
    func exerciseComplete() {
        vibratePattern(3, style: .medium)
        playTones([
            ToneSpec(frequency: 784, duration: 0.1, delay: 0),
            ToneSpec(frequency: 1047, duration: 0.15, delay: 0.1),
            ToneSpec(frequency: 1319, duration: 0.2, delay: 0.25),
        ])
    }

    /// Rest timer overtime — 5 haptic pulses + ascending scale + "Go" voice
    func restComplete() {
        vibratePattern(5, style: .medium)
        playTones([
            ToneSpec(frequency: 523, duration: 0.1, delay: 0),
            ToneSpec(frequency: 659, duration: 0.1, delay: 0.1),
            ToneSpec(frequency: 784, duration: 0.15, delay: 0.2),
        ])
        speak("Go")
    }

    /// Entire session completed — notification haptic + bold ascending scale
    func sessionComplete() {
        vibrateNotification(.success)
        playTones([
            ToneSpec(frequency: 523, duration: 0.15, delay: 0),
            ToneSpec(frequency: 659, duration: 0.15, delay: 0.15),
            ToneSpec(frequency: 784, duration: 0.2, delay: 0.3),
        ])
    }

    /// Undo — medium haptic, no tone
    func undo() {
        vibrate(.medium)
    }

    /// Error — 3 light pulses + low buzz tone
    func error() {
        vibratePattern(3, style: .light, interval: 0.06)
        playTones([
            ToneSpec(frequency: 220, duration: 0.1, delay: 0),
        ])
    }

    // MARK: - Voice Milestones

    /// Returns the milestone label if it should be announced (call at each timer tick).
    func voiceMilestoneLabel(secondsRemaining: Int) -> String? {
        return Self.milestoneLabels[secondsRemaining]
    }

    /// Speak a voice milestone countdown
    func speakMilestone(_ label: String) {
        speak(label)
    }

    /// Test voice output
    func speakTest(_ text: String = "Testing voice announcements") {
        speak(text)
    }
}
