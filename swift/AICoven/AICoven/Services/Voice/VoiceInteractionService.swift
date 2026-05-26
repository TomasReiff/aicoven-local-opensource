import Foundation
import AVFoundation
import MediaPlayer
import SwiftWhisper

@MainActor
class VoiceInteractionService: ObservableObject, AudioCaptureDelegate {
    @Published var isListening = false
    @Published var isSpeaking = false
    @Published var currentText = ""
    @Published var isDownloadingModel = false
    @Published var audioLevel: Float = 0.0 // For "Voice Pulse"

    private let audioCaptureService = AudioCaptureService()
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var whisper: Whisper?
    private var audioData = [Float]()

    // Config
    private let systemPrompt = "Jsi užitečný a stručný asistent. Mluv vždy česky. Odpovídej přirozeně a krátce. Pokud neznáš odpověď, přiznej to."

    init() {
        audioCaptureService.delegate = self
        setupAudioSession()
        setupRemoteCommands()
        setupRouteChangeObserver()
        Task {
            await initializeWhisper()
        }
    }

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            Task { @MainActor in
                self.toggleInteraction()
            }
            return .success
        }
    }

    private func setupRouteChangeObserver() {
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
                return
            }

            if reason == .oldDeviceUnavailable {
                // Headphones disconnected
                Task { @MainActor in
                    self?.stopEverything()
                }
            }
        }
    }

    private func initializeWhisper() async {
        isDownloadingModel = true
        defer { isDownloadingModel = false }

        // This should download and initialize the model on first launch
        // Using "base" multilingual model
        let modelURL = await downloadWhisperModel(name: "base")
        whisper = Whisper(fromFileURL: modelURL)
    }

    private func downloadWhisperModel(name: String) async -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelURL = documentsURL.appendingPathComponent("whisper-\(name).bin")

        if FileManager.default.fileExists(atPath: modelURL.path) {
            return modelURL
        }

        // Download logic (simplified placeholder, should use actual download from a reliable source like HuggingFace)
        // Since we need an actual model, let's assume we download from a known ggml location.
        // For production, you'd want a robust download manager here.
        let remoteURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(name).bin")!

        do {
            let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
            try FileManager.default.moveItem(at: tempURL, to: modelURL)
        } catch {
            print("Failed to download Whisper model: \(error)")
        }

        return modelURL
    }

    func toggleInteraction() {
        if isSpeaking {
            stopSpeaking()
            startListening()
        } else if isListening {
            stopListening()
            processAudioAndGenerateResponse()
        } else {
            startListening()
        }
    }

    func startListening() {
        stopSpeaking()
        audioData.removeAll()
        do {
            try audioCaptureService.start()
            isListening = true
        } catch {
            print("Failed to start listening: \(error)")
        }
    }

    func stopListening() {
        audioCaptureService.stop()
        isListening = false
    }

    func stopSpeaking() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    func stopEverything() {
        stopListening()
        stopSpeaking()
    }

    private func processAudioAndGenerateResponse() {
        guard !audioData.isEmpty, let whisper = whisper else { return }

        Task {
            do {
                let segments = try await whisper.transcribe(audioFrames: audioData)
                let text = segments.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

                guard !text.isEmpty else { return }

                self.currentText = text
                await generateLLMResponse(for: text)
            } catch {
                print("Transcription error: \(error)")
            }
        }
    }

    var activeThread: Thread?

    private func generateLLMResponse(for text: String) async {
        isSpeaking = true
        var fullResponse = ""
        var currentSentence = ""

        do {
            if let thread = activeThread {
                // Setup system prompt override for this generation
                // Force active model to Qwen2.5-3B-Instruct (4-bit quantized)
                UserDefaults.standard.set("mlx-community/Qwen2.5-3B-Instruct-4bit", forKey: "MLXModelManager.activeModelID")
                UserDefaults.standard.set("mlx", forKey: "StrixAI.GlobalProvider")

                // We inject the system instruction directly into the context or message since streamMessage doesn't accept overrides directly
                let systemPrompt = "Jsi užitečný a stručný asistent. Mluv vždy česky. Odpovídej přirozeně a krátce. Pokud neznáš odpověď, přiznej to."
                let combinedMessage = "\(systemPrompt)\n\nUživatel říká: \(text)"

                let stream = try await ChatService.shared.streamMessage(
                    threadId: thread.id,
                    message: combinedMessage,
                    attachments: nil
                )

                for try await event in stream {
                    switch event {
                    case .content(let chunk):
                        fullResponse += chunk
                        currentSentence += chunk

                        if currentSentence.contains(".") || currentSentence.contains("?") || currentSentence.contains("!") {
                            let sentenceToSpeak = currentSentence
                            currentSentence = ""
                            DispatchQueue.main.async {
                                self.currentText = fullResponse
                                self.synthesize(text: sentenceToSpeak)
                            }
                        }
                    default: break
                    }
                }

                if !currentSentence.isEmpty {
                    let sentenceToSpeak = currentSentence
                    DispatchQueue.main.async {
                        self.currentText = fullResponse
                        self.synthesize(text: sentenceToSpeak)
                    }
                }

            } else {
                let mockResponse = "Nemám aktivní vlákno."
                DispatchQueue.main.async {
                    self.currentText = mockResponse
                    self.synthesize(text: mockResponse)
                }
            }
        } catch {
            print("Error generating response: \(error)")
            DispatchQueue.main.async {
                self.synthesize(text: "Omlouvám se, došlo k chybě.")
            }
        }
    }

    private func synthesize(text: String) {
        let utterance = AVSpeechUtterance(string: text)
        // Use premium Czech voice "Zuzana" if available, else default Czech
        if let zuzanaVoice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language == "cs-CZ" && $0.name.contains("Zuzana") && $0.quality == .premium }) {
            utterance.voice = zuzanaVoice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "cs-CZ")
        }

        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        speechSynthesizer.speak(utterance)
    }

    // MARK: - AudioCaptureDelegate

    nonisolated func audioCaptureService(_ service: AudioCaptureService, didCaptureBuffer buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        let frames = Array(UnsafeBufferPointer(start: channelData, count: frameLength))

        Task { @MainActor in
            self.audioData.append(contentsOf: frames)

            // Calculate level for UI pulse
            var rms: Float = 0
            vDSP_measqv(channelData, 1, &rms, vDSP_Length(frameLength))
            self.audioLevel = rms

            if self.isSpeaking {
                // Interruption logic: If we detect significant audio while speaking, interrupt
                if rms > 0.05 { // Interruption threshold
                    self.stopSpeaking()
                    self.startListening()
                }
            }
        }
    }

    nonisolated func audioCaptureServiceDidDetectSpeechStart(_ service: AudioCaptureService) {
        Task { @MainActor in
            // Handle speech start if needed
        }
    }

    nonisolated func audioCaptureServiceDidDetectSpeechEnd(_ service: AudioCaptureService) {
        Task { @MainActor in
            if self.isListening {
                self.stopListening()
                self.processAudioAndGenerateResponse()
            }
        }
    }
}
