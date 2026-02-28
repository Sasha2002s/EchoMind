//
//  AppleSpeechFileTranscriber.swift
//  EchoMind
//
//  Created by Oleksandr Stepanov on 28.02.26.
//


internal import Speech
import Foundation


// MARK: - Apple Speech Transcription (file)

final class AppleSpeechFileTranscriber {
    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
    }
    static func ensureAuthorized() async throws {
        let auth = await requestAuthorization()
        guard auth == .authorized else {
            throw NSError(
                domain: "AppleSpeechFileTranscriber",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: authorizationMessage(for: auth)]
            )
        }
    }

    static func authorizationMessage(for status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return ""
        case .denied:
            return "Speech recognition permission was denied. You can enable it in Settings."
        case .restricted:
            return "Speech recognition is restricted on this device."
        case .notDetermined:
            return "Speech recognition permission was not granted yet."
        @unknown default:
            return "Speech recognition permission is unavailable."
        }
    }

    func transcribeFile(url: URL, locale: Locale) async throws -> String {
        // Prefer a recognizer that matches the user’s current locale.
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer() else {
            throw NSError(domain: "AppleSpeechFileTranscriber", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is not available for this language."])
        }

        if !recognizer.isAvailable {
            throw NSError(domain: "AppleSpeechFileTranscriber", code: 2, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is currently unavailable."])
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation

        return try await withCheckedThrowingContinuation { cont in
            var didResume = false
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error, !didResume {
                    didResume = true
                    cont.resume(throwing: error)
                    return
                }

                guard let result else { return }

                if result.isFinal, !didResume {
                    didResume = true
                    cont.resume(returning: result.bestTranscription.formattedString)
                }
            }

            // If the Task gets cancelled externally, propagate cancellation.
            Task {
                if Task.isCancelled {
                    task.cancel()
                }
            }
        }
    }
}


