//
//  TextToSpeechService.swift
//  MindVault
//
//  Text-to-speech service using AVFoundation
//

import Foundation
import AVFoundation

@MainActor
class TextToSpeechService: NSObject, ObservableObject {
    static let shared = TextToSpeechService()
    
    @Published var isSpeaking = false
    @Published var currentSpeechRate: Float = 0.5
    @Published var currentVoice: AVSpeechSynthesisVoice?
    
    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    
    override private init() {
        super.init()
        synthesizer.delegate = self
        
        // Set default voice to a high-quality English voice
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            currentVoice = voice
        }
    }
    
    // MARK: - Speech Control
    func speak(_ text: String, rate: Float? = nil, voice: AVSpeechSynthesisVoice? = nil) {
        // Stop any current speech
        stop()
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate ?? currentSpeechRate
        utterance.voice = voice ?? currentVoice ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        currentUtterance = utterance
        
        // Configure audio session
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
        
        synthesizer.speak(utterance)
        isSpeaking = true
    }
    
    func pause() {
        synthesizer.pauseSpeaking(at: .immediate)
    }
    
    func resume() {
        synthesizer.continueSpeaking()
    }
    
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        currentUtterance = nil
        isSpeaking = false
    }
    
    // MARK: - Voice Selection
    static var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.starts(with: "en") }
            .sorted { $0.name < $1.name }
    }
    
    func setVoice(_ voice: AVSpeechSynthesisVoice) {
        currentVoice = voice
    }
    
    func setSpeechRate(_ rate: Float) {
        currentSpeechRate = min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension TextToSpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = true
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            currentUtterance = nil
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            currentUtterance = nil
        }
    }
}
