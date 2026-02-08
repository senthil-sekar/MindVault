//
//  SpeechRecognitionService.swift
//  MindVault
//
//  Speech-to-text service using AVFoundation
//

import Foundation
import Speech
import AVFoundation

@MainActor
class SpeechRecognitionService: ObservableObject {
    static let shared = SpeechRecognitionService()
    
    @Published var isRecording = false
    @Published var recognizedText = ""
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    private init() {
        checkAuthorization()
    }
    
    // MARK: - Authorization
    func checkAuthorization() {
        authorizationStatus = SFSpeechRecognizer.authorizationStatus()
    }
    
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.authorizationStatus = status
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }
    
    // MARK: - Recording
    func startRecording() throws {
        // Cancel any ongoing recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw SpeechError.requestCreationFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Configure audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            Task { @MainActor in
                if let result = result {
                    self.recognizedText = result.bestTranscription.formattedString
                }
                
                if error != nil || result?.isFinal == true {
                    self.stopRecording()
                    
                    if let error = error {
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
        
        isRecording = true
        recognizedText = ""
        errorMessage = nil
    }
    
    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
    }
    
    // MARK: - Error
    enum SpeechError: LocalizedError {
        case requestCreationFailed
        case notAuthorized
        case recognizerUnavailable
        
        var errorDescription: String? {
            switch self {
            case .requestCreationFailed:
                return "Failed to create speech recognition request"
            case .notAuthorized:
                return "Speech recognition not authorized"
            case .recognizerUnavailable:
                return "Speech recognizer unavailable"
            }
        }
    }
}
