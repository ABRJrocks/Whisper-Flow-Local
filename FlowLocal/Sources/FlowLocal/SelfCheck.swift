@preconcurrency import AVFoundation
import Foundation

/// Headless test mode: `FlowLocal --transcribe file.wav [--locale en_US] [--engine apple|parakeet|whisper]`
/// Prints the transcript and exits. Exercises engine install + the full session pipeline
/// without mic/UI permissions.
enum SelfCheck {
    /// `FlowLocal --refine "raw text"` — installs/loads the smallest LLM if needed,
    /// runs the full refine + guardrail path, prints the result.
    static func runRefine(text: String) async -> Int32 {
        do {
            let manager = LLMManager.shared
            let modelID: String
            if let forced = ProcessInfo.processInfo.environment["FLOWLOCAL_MODEL"] {
                modelID = forced
                if !manager.installedModels().contains(modelID) {
                    FileHandle.standardError.write(Data("Installing \(modelID)…\n".utf8))
                    try await manager.install(modelID: modelID) { _ in }
                }
                try await manager.activate(modelID: modelID)
            } else if let active = manager.activeModelID {
                modelID = active
            } else if !Prefs.llmModelID.isEmpty, manager.installedModels().contains(Prefs.llmModelID) {
                modelID = Prefs.llmModelID
                try await manager.activate(modelID: modelID)
            } else if let smallest = manager.availableModels.min(by: { $0.sizeGB < $1.sizeGB }) {
                modelID = smallest.id
                if !manager.installedModels().contains(modelID) {
                    FileHandle.standardError.write(Data("Installing \(modelID)…\n".utf8))
                    try await manager.install(modelID: modelID) { progress in
                        FileHandle.standardError.write(Data("\rdownload \(Int(progress * 100))%".utf8))
                    }
                    FileHandle.standardError.write(Data("\n".utf8))
                }
                try await manager.activate(modelID: modelID)
            } else {
                FileHandle.standardError.write(Data("No LLM models available for this hardware\n".utf8))
                return 1
            }
            guard let refiner = manager.refiner else {
                FileHandle.standardError.write(Data("Refiner not loaded\n".utf8))
                return 1
            }
            let payload = RefinePayload(
                rawTranscript: text, language: "en", appCategory: "work_message",
                formality: 0.5, concision: 0.7, emojiAllowed: false, customInstructions: "",
                textBeforeCursor: nil, protectedTerms: LLMGuardrails.protectedTokens(in: text)
            )
            let start = Date()
            let output = try await refiner.refine(payload)
            let elapsed = Date().timeIntervalSince(start)
            let validated = LLMGuardrails.validate(output: output, input: text)
            FileHandle.standardError.write(Data("model=\(modelID) latency=\(String(format: "%.2f", elapsed))s guardrail=\(validated != nil ? "pass" : "REJECTED")\n".utf8))
            print(validated ?? "(guardrails rejected; would fall back to rule text)")
            return validated != nil ? 0 : 2
        } catch {
            FileHandle.standardError.write(Data("Refine check failed: \(error)\n".utf8))
            return 1
        }
    }

    /// `FlowLocal --command "instruction" "selected text"` — Command Mode JSON path.
    static func runCommand(instruction: String, selected: String) async -> Int32 {
        do {
            await LLMManager.shared.warmUpIfConfigured()
            guard let refiner = LLMManager.shared.refiner else {
                FileHandle.standardError.write(Data("No active LLM. Run --refine first to install one.\n".utf8))
                return 1
            }
            let start = Date()
            let action = try await refiner.command(
                instruction: instruction, selectedText: selected, appCategory: "documents", language: "en"
            )
            let elapsed = Date().timeIntervalSince(start)
            FileHandle.standardError.write(Data("latency=\(String(format: "%.2f", elapsed))s\n".utf8))
            print("action=\(action.action.rawValue) keystroke=\(action.keystroke ?? "-")")
            print(action.text)
            return 0
        } catch {
            FileHandle.standardError.write(Data("Command check failed: \(error)\n".utf8))
            return 1
        }
    }

    static func run(file: String, localeID: String, engineID: String) async -> Int32 {
        let locale = Locale(identifier: localeID)
        let engine: any ASREngine
        switch engineID {
        case "parakeet": engine = ASRRouter.shared.parakeet
        case "whisper": engine = ASRRouter.shared.whisper
        default: engine = ASRRouter.shared.apple
        }
        do {
            FileHandle.standardError.write(Data("Preparing \(engine.id) for \(localeID)…\n".utf8))
            try await engine.prepare(locale: locale)

            let url = URL(fileURLWithPath: file)
            let audioFile = try AVAudioFile(forReading: url)
            let session = try await engine.startSession(locale: locale, onPartial: nil)

            let format = audioFile.processingFormat
            let chunk = AVAudioFrameCount(8192)
            while audioFile.framePosition < audioFile.length {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { break }
                try audioFile.read(into: buffer, frameCount: chunk)
                if buffer.frameLength == 0 { break }
                session.feed(buffer)
            }
            let start = Date()
            let result = try await session.finish()
            let elapsed = Date().timeIntervalSince(start)
            FileHandle.standardError.write(Data("engine=\(result.engineID) finalize=\(String(format: "%.2f", elapsed))s\n".utf8))
            print(result.text)
            return result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 2 : 0
        } catch {
            FileHandle.standardError.write(Data("Self-check failed: \(error)\n".utf8))
            return 1
        }
    }
}
