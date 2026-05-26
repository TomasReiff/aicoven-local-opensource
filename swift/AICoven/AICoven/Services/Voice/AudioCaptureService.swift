import Foundation
import AVFoundation
import Accelerate

protocol AudioCaptureDelegate: AnyObject {
    func audioCaptureService(_ service: AudioCaptureService, didCaptureBuffer buffer: AVAudioPCMBuffer)
    func audioCaptureServiceDidDetectSpeechStart(_ service: AudioCaptureService)
    func audioCaptureServiceDidDetectSpeechEnd(_ service: AudioCaptureService)
}

class AudioCaptureService {
    private let audioEngine = AVAudioEngine()
    weak var delegate: AudioCaptureDelegate?

    // VAD parameters
    private let silenceThreshold: Float = 0.01 // Adjust based on testing
    private let requiredSilenceDuration: TimeInterval = 1.5
    private var lastSpeechTime: Date?
    private var isSpeaking = false

    // Whisper expects 16kHz mono audio
    private let targetSampleRate: Double = 16000

    func start() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker])
        try audioSession.setActive(true)

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetSampleRate, channels: 1, interleaved: false) else {
            throw NSError(domain: "AudioCaptureService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create target format"])
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw NSError(domain: "AudioCaptureService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter"])
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }

            // Convert buffer to 16kHz mono
            let capacity = AVAudioFrameCount(converter.maximumOutputCapacity(forInputCapacity: buffer.frameCapacity))
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

            var error: NSError?
            var allComponentsProcessed = false
            let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                if allComponentsProcessed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                allComponentsProcessed = true
                outStatus.pointee = .haveData
                return buffer
            }

            if status == .error || error != nil {
                return
            }

            self.processBuffer(convertedBuffer)
        }

        try audioEngine.start()
    }

    func stop() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isSpeaking = false
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)

        // Calculate RMS power
        var rms: Float = 0
        vDSP_measqv(channelData, 1, &rms, vDSP_Length(frameLength))

        let now = Date()

        if rms > silenceThreshold {
            if !isSpeaking {
                isSpeaking = true
                DispatchQueue.main.async {
                    self.delegate?.audioCaptureServiceDidDetectSpeechStart(self)
                }
            }
            lastSpeechTime = now
        } else if isSpeaking {
            if let lastSpeech = lastSpeechTime, now.timeIntervalSince(lastSpeech) > requiredSilenceDuration {
                isSpeaking = false
                DispatchQueue.main.async {
                    self.delegate?.audioCaptureServiceDidDetectSpeechEnd(self)
                }
            }
        }

        if isSpeaking || lastSpeechTime?.timeIntervalSinceNow ?? -1 > -requiredSilenceDuration {
            DispatchQueue.main.async {
                self.delegate?.audioCaptureService(self, didCaptureBuffer: buffer)
            }
        }
    }
}
