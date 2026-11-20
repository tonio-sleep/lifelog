import SwiftUI
import AVFoundation
import Speech

struct VoiceNoteResult {
    var url: URL
    var transcript: String
    var duration: TimeInterval
}

private enum VoiceError: LocalizedError {
    case noInput

    var errorDescription: String? {
        switch self {
        case .noInput: return "No microphone input is available right now."
        }
    }
}

/// Audio capture and speech recognition. Deliberately not main-actor isolated:
/// the audio tap and the recognizer call back on their own threads.
private final class RecordingPipeline: @unchecked Sendable {
    let url: URL
    var onTranscript: (@Sendable (String) -> Void)?

    private let engine = AVAudioEngine()
    private let recognizer: SFSpeechRecognizer?
    private let wantsTranscript: Bool
    private let onDeviceOnly: Bool
    private let lock = NSLock()

    private var file: AVAudioFile?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var committed = ""
    private var partial = ""
    private var running = false
    private var restarts = 0
    private var startedAt = Date()

    init(url: URL, transcribe: Bool, onDeviceOnly: Bool) {
        self.url = url
        self.wantsTranscript = transcribe
        self.onDeviceOnly = onDeviceOnly
        self.recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer()
    }

    static var onDeviceSupported: Bool {
        let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer()
        return recognizer?.supportsOnDeviceRecognition == true
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw VoiceError.noInput }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVEncoderBitRateKey: 128_000,
        ]
        let output = try AVAudioFile(forWriting: url, settings: settings)

        lock.lock()
        file = output
        running = true
        startedAt = Date()
        lock.unlock()

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.consume(buffer)
        }
        engine.prepare()
        try engine.start()
        beginRecognition()
    }

    private func consume(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        try? file?.write(from: buffer)
        request?.append(buffer)
        lock.unlock()
    }

    private func beginRecognition() {
        guard wantsTranscript, let recognizer, recognizer.isAvailable else { return }
        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        newRequest.requiresOnDeviceRecognition = onDeviceOnly
        lock.lock()
        guard running else { lock.unlock(); return }
        request = newRequest
        lock.unlock()
        task = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
            self?.handle(result: result, failed: error != nil, request: newRequest)
        }
    }

    private func handle(result: SFSpeechRecognitionResult?, failed: Bool, request current: SFSpeechAudioBufferRecognitionRequest) {
        var text: String?
        var restart = false
        lock.lock()
        if request === current {
            if let result {
                partial = result.bestTranscription.formattedString
                text = Self.join(committed, partial)
                if result.isFinal {
                    commitLocked()
                    restart = running
                }
            } else if failed {
                commitLocked()
                restart = running
            }
            if restart {
                restarts += 1
                if restarts > 60 { restart = false }
            }
        }
        lock.unlock()
        if let text { onTranscript?(text) }
        if restart {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.beginRecognition()
            }
        }
    }

    private func commitLocked() {
        if !partial.isEmpty {
            committed = Self.join(committed, partial)
            partial = ""
        }
        request = nil
    }

    private static func join(_ a: String, _ b: String) -> String {
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + " " + b
    }

    func stop() -> (transcript: String, duration: TimeInterval) {
        lock.lock()
        running = false
        let activeRequest = request
        let started = startedAt
        lock.unlock()

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        activeRequest?.endAudio()
        task?.cancel()
        task = nil

        lock.lock()
        let text = Self.join(committed, partial)
        file = nil
        request = nil
        lock.unlock()

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), Date().timeIntervalSince(started))
    }
}

// MARK: - Recorder

@MainActor
final class VoiceRecorder: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case finished
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var transcript = ""
    @Published private(set) var notice: String?
    @Published var transcribe = true
    @Published var allowServerTranscription = false

    let onDeviceSupported = RecordingPipeline.onDeviceSupported
    static let maxDuration: TimeInterval = 30 * 60

    private var pipeline: RecordingPipeline?
    private var timer: Task<Void, Never>?
    private var interruption: NSObjectProtocol?
    private(set) var fileURL: URL?
    private(set) var duration: TimeInterval = 0

    func start(permissions: PermissionCenter) async {
        guard phase == .idle || phase == .finished || isFailed else { return }
        discardFile()
        transcript = ""
        notice = nil
        elapsed = 0

        await permissions.refresh()
        guard await permissions.requestMicrophone() else {
            phase = .failed("Microphone access is off. Allow it in Settings to record voice notes.")
            return
        }

        var shouldTranscribe = transcribe
        if shouldTranscribe {
            if !(await permissions.requestSpeech()) {
                shouldTranscribe = false
                notice = "Speech recognition is off, so this will be audio only."
            } else if !onDeviceSupported && !allowServerTranscription {
                shouldTranscribe = false
                notice = "On-device transcription is not available for your language, so this will be audio only."
            }
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lifelog-voice-\(UUID().uuidString).m4a")
        let engine = RecordingPipeline(
            url: url,
            transcribe: shouldTranscribe,
            onDeviceOnly: onDeviceSupported
        )
        engine.onTranscript = { [weak self] text in
            Task { @MainActor in self?.transcript = text }
        }
        do {
            try engine.start()
        } catch {
            _ = engine.stop()
            try? FileManager.default.removeItem(at: url)
            phase = .failed("Could not start recording. \(error.localizedDescription)")
            return
        }
        pipeline = engine
        fileURL = url
        phase = .recording
        observeInterruptions()

        let started = Date()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self, self.phase == .recording else { return }
                self.elapsed = Date().timeIntervalSince(started)
                if self.elapsed >= Self.maxDuration {
                    self.stop()
                    return
                }
            }
        }
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    func stop() {
        guard phase == .recording, let pipeline else { return }
        let result = pipeline.stop()
        timer?.cancel()
        timer = nil
        removeObserver()
        self.pipeline = nil
        duration = result.duration
        elapsed = result.duration
        if !result.transcript.isEmpty { transcript = result.transcript }
        phase = .finished
    }

    func result() -> VoiceNoteResult? {
        guard phase == .finished, let fileURL else { return nil }
        return VoiceNoteResult(
            url: fileURL,
            transcript: transcript.trimmingCharacters(in: .whitespacesAndNewlines),
            duration: duration
        )
    }

    /// Stops any recording and removes the temporary file.
    func cancel() {
        if phase == .recording, let pipeline {
            _ = pipeline.stop()
        }
        pipeline = nil
        timer?.cancel()
        timer = nil
        removeObserver()
        discardFile()
        phase = .idle
    }

    /// Call after the file has been stored so it is not deleted twice.
    func releaseFile() {
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil
    }

    private func discardFile() {
        releaseFile()
    }

    private func observeInterruptions() {
        removeObserver()
        interruption = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in
                if raw == AVAudioSession.InterruptionType.began.rawValue {
                    self?.stop()
                }
            }
        }
    }

    private func removeObserver() {
        if let interruption { NotificationCenter.default.removeObserver(interruption) }
        interruption = nil
    }
}

// MARK: - Sheet

struct VoiceNoteSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = VoiceRecorder()
    @State private var consumed = false
    let onFinish: (VoiceNoteResult) -> Void
    var autoStart = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Space.xl) {
                Spacer(minLength: Space.lg)
                Text(timeString(recorder.elapsed))
                    .font(.system(size: 56, weight: .light, design: .serif).monospacedDigit())
                    .foregroundStyle(Palette.ink)
                    .accessibilityLabel("Recording time \(timeString(recorder.elapsed))")

                recordButton

                statusText

                if recorder.phase == .recording || !recorder.transcript.isEmpty {
                    transcriptView
                }

                if recorder.phase == .idle, !recorder.onDeviceSupported {
                    Toggle("Transcribe with Apple's servers", isOn: $recorder.allowServerTranscription)
                        .font(Typeface.caption)
                        .padding(.horizontal, Space.page)
                    InfoLine(text: "Your language can't be transcribed on this device. If you turn this on, audio is sent to Apple to be turned into text. Recording itself never leaves your device.", symbol: "exclamationmark.shield")
                        .padding(.horizontal, Space.page)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .paperScreen()
            .navigationTitle("Voice note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        recorder.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { finish() }
                        .fontWeight(.semibold)
                        .disabled(recorder.phase != .finished)
                }
            }
        }
        .interactiveDismissDisabled(recorder.phase == .recording)
        .task {
            if autoStart, recorder.phase == .idle {
                await recorder.start(permissions: env.permissions)
            }
        }
        .onDisappear { if !consumed { recorder.cancel() } }
    }

    private var recordButton: some View {
        Button {
            Task {
                switch recorder.phase {
                case .recording: recorder.stop()
                default: await recorder.start(permissions: env.permissions)
                }
            }
        } label: {
            ZStack {
                Circle().fill(Palette.accent).frame(width: 84, height: 84)
                if recorder.phase == .recording {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Palette.onAccent)
                        .frame(width: 26, height: 26)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(.title).weight(.regular))
                        .foregroundStyle(Palette.onAccent)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(recorder.phase == .recording ? "Stop recording" : (recorder.phase == .finished ? "Record again" : "Start recording"))
    }

    @ViewBuilder
    private var statusText: some View {
        VStack(spacing: Space.sm) {
            switch recorder.phase {
            case .idle:
                Text("Tap to record. Audio is encrypted on this device.")
                    .font(Typeface.label).foregroundStyle(Palette.inkSecondary)
            case .recording:
                Text("Recording…").font(Typeface.label).foregroundStyle(Palette.accent)
            case .finished:
                Text("Ready to add. Tap the button to record again.")
                    .font(Typeface.label).foregroundStyle(Palette.inkSecondary)
            case .failed(let message):
                PermissionNotice(message: message)
                    .padding(.horizontal, Space.page)
            }
            if let notice = recorder.notice {
                Text(notice).font(Typeface.caption).foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.page)
            }
        }
    }

    private var transcriptView: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Transcript").font(Typeface.micro).textCase(.uppercase).tracking(1).foregroundStyle(Palette.inkTertiary)
            if recorder.phase == .finished {
                TextEditor(text: $recorder.transcript)
                    .font(Typeface.reading)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120, maxHeight: 220)
            } else {
                ScrollView {
                    Text(recorder.transcript.isEmpty ? "Listening…" : recorder.transcript)
                        .font(Typeface.reading)
                        .foregroundStyle(recorder.transcript.isEmpty ? Palette.inkTertiary : Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }
        }
        .surface()
        .padding(.horizontal, Space.page)
    }

    private func finish() {
        guard let result = recorder.result() else { return }
        consumed = true
        onFinish(result)
        dismiss()
    }

    private func timeString(_ value: TimeInterval) -> String {
        let total = Int(value)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
