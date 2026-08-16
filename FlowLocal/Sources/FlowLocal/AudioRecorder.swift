import AVFoundation
import Foundation

/// Microphone capture via AVAudioEngine. Buffers go to `onBuffer`; RMS level to `onLevel`.
/// Honors the preferred-mic pref (falls back to system default when absent — covers
/// clamshell/headset-unplug), optional whisper-mode auto-gain, and optional tee-to-file
/// for dictation recovery.
final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private(set) var isRunning = false
    private var recoveryFile: AVAudioFile?

    func start(
        recordTo recoveryURL: URL? = nil,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onLevel: (@Sendable (Float) -> Void)? = nil
    ) throws {
        let input = engine.inputNode
        applyPreferredMic(to: input)
        let format = input.outputFormat(forBus: 0)

        if let recoveryURL {
            recoveryFile = try? AVAudioFile(forWriting: recoveryURL, settings: format.settings)
        }
        let file = recoveryFile
        let boost = Prefs.whisperModeEnabled
        let agc = boost ? AutoGain() : nil

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            if let agc { agc.apply(to: buffer) }
            try? file?.write(from: buffer)
            onBuffer(buffer)
            if let onLevel { onLevel(Self.rmsLevel(buffer)) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            // Leaving the tap installed would crash the next start() with an ObjC exception.
            input.removeTap(onBus: 0)
            recoveryFile = nil
            throw error
        }
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        recoveryFile = nil // closes the file
        isRunning = false
    }

    /// Route the engine's input to the preferred device when it's present; otherwise the
    /// system default input applies automatically (that IS the fallback path).
    /// ponytail: single preferred mic; upgrade to a ranked list if anyone asks.
    private func applyPreferredMic(to input: AVAudioInputNode) {
        let uid = Prefs.preferredMicUID
        guard !uid.isEmpty,
              var deviceID = MicSelector.deviceID(forUID: uid),
              let audioUnit = input.audioUnit
        else { return }
        AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    private static func rmsLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        return min(1, sqrt(sum / Float(n)) * 6) // ponytail: crude visual gain, fine for a level meter
    }
}

/// Whisper mode: envelope-following auto-gain so quiet speech reaches ASR at usable levels.
/// State lives on the audio thread only.
private final class AutoGain {
    private var envelope: Float = 0.05
    private let targetRMS: Float = 0.08
    private let maxGain: Float = 8

    func apply(to buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        let first = channels[0]
        for i in 0..<n { sum += first[i] * first[i] }
        let rms = sqrt(sum / Float(n))

        // Fast attack, slow release, ignore near-silence so noise isn't amplified between words.
        if rms > 0.003 {
            envelope = rms > envelope ? rms : envelope * 0.995 + rms * 0.005
        }
        let gain = min(maxGain, max(1, targetRMS / max(envelope, 0.001)))
        guard gain > 1.01 else { return }
        for c in 0..<Int(buffer.format.channelCount) {
            let data = channels[c]
            for i in 0..<n { data[i] = max(-1, min(1, data[i] * gain)) }
        }
    }
}
