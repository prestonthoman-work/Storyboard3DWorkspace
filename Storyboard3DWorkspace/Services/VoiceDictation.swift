//
//  VoiceDictation.swift
//  Storyboard3DWorkspace
//

import AVFoundation
import Speech

/// Speech-to-text for shot notes: talk, and the words appear as you say them.
@Observable
final class VoiceDictation {
    enum State: Equatable {
        case idle
        case starting
        case listening
        case failed(String)
    }

    private(set) var state: State = .idle
    /// What's been heard since `start`.
    private(set) var transcript = ""

    var isActive: Bool { state == .starting || state == .listening }

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var onUpdate: ((String) -> Void)?

    /// Starts listening. `onUpdate` receives the full transcript so far each time it changes.
    func start(onUpdate: @escaping (String) -> Void) async {
        guard !isActive else { return }
        state = .starting
        transcript = ""
        self.onUpdate = onUpdate

        guard await Self.requestSpeechAccess() else {
            state = .failed("Allow speech recognition in Settings to dictate notes.")
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            state = .failed("Allow microphone access in Settings to dictate notes.")
            return
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            state = .failed("Dictation isn't available right now.")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            self.request = request

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            // The throwing replacement for the deprecated installTap. It's NS_REFINED_FOR_SWIFT
            // with no Swift overlay in this SDK, so it imports as "__installTap" with a leftover
            // `error: ()` label; switch to the overlay's name once Apple ships it.
            try input.__installTap(onBus: 0, bufferSize: 1024, format: format, error: (),
                                   block: Self.makeTap(for: request))
            engine.prepare()
            try engine.start()

            task = recognizer.recognitionTask(with: request, resultHandler: Self.makeResultHandler { [weak self] text, isFinal, error in
                self?.handle(text: text, isFinal: isFinal, error: error)
            })
            state = .listening
        } catch {
            teardown()
            state = .failed("The microphone couldn't start.")
        }
    }

    /// Stops listening; the transcript so far is kept.
    func stop() {
        guard isActive else { return }
        request?.endAudio()
        teardown()
        state = .idle
    }

    private func handle(text: String?, isFinal: Bool, error: Error?) {
        if let text {
            transcript = text
            onUpdate?(text)
        }
        if isFinal || error != nil {
            teardown()
            if state == .listening { state = .idle }
        }
    }

    private func teardown() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Audio and recognition callbacks arrive on background threads. These are built outside
    // the main actor so they don't inherit its isolation; results hop back to it.

    private nonisolated static func makeTap(for request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    private nonisolated static func makeResultHandler(
        _ deliver: @escaping @MainActor (String?, Bool, Error?) -> Void
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            Task { @MainActor in deliver(text, isFinal, error) }
        }
    }

    private nonisolated static func requestSpeechAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
