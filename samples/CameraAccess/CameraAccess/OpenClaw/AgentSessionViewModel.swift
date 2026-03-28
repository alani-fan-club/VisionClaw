import Foundation
import UIKit

// MARK: - Agent Mode

enum AgentMode: String {
  case passive   // Listening for wake word + notifications only
  case active    // Full conversation with OpenClaw agent
  case vision    // Handed off to Gemini for camera query
}

// MARK: - AgentSessionViewModel

@MainActor
class AgentSessionViewModel: ObservableObject {

  // MARK: - Published State

  @Published var mode: AgentMode = .passive
  @Published var isRunning: Bool = false
  @Published var userTranscript: String = ""
  @Published var agentResponse: String = ""
  @Published var errorMessage: String?
  @Published var isOpenClawConnected: Bool = false
  @Published var isEventStreamConnected: Bool = false

  // MARK: - Owned Components

  private let audioManager = AudioManager()
  private let speechService = SpeechService()
  private let ttsService = TTSService()
  private let wakeWordDetector = WakeWordDetector()
  private let voiceActivityDetector = VoiceActivityDetector()
  private let openClawBridge = OpenClawBridge()
  private let eventClient = OpenClawEventClient()

  /// Gemini is created lazily — only when the user triggers a vision query.
  private var geminiSessionVM: GeminiSessionViewModel?

  // MARK: - Internal State

  private var pendingTranscript: String = ""
  private var speechAuthGranted: Bool = false
  private var streamingMode: StreamingMode = .glasses
  private var isWaitingForAgent: Bool = false  // true while waiting for OpenClaw response or TTS

  /// Timer to stop SpeechService in passive mode if no wake word is detected
  /// after VAD reports end of utterance.
  private var passiveWakeWordTimer: Timer?

  private let acknowledgments = ["Yes?", "I'm here.", "Listening.", "Go ahead."]

  // MARK: - Start Session

  func startSession(streamingMode: StreamingMode) {
    guard !isRunning else {
      NSLog("[Agent] startSession called but already running")
      return
    }

    NSLog("[Agent] Starting session (streamingMode=%@)", streamingMode == .glasses ? "glasses" : "iPhone")
    self.streamingMode = streamingMode

    // Apply settings
    let settings = SettingsManager.shared
    wakeWordDetector.wakePhrase = settings.wakeWord
    ttsService.voiceIdentifier = settings.ttsVoiceIdentifier
    voiceActivityDetector.sessionTimeoutSeconds = settings.silenceTimeoutSeconds

    // Set up audio session and start capture
    do {
      try audioManager.setupAudioSession(useIPhoneMode: streamingMode == .iPhone)
      try audioManager.startCapture()
      NSLog("[Agent] Audio capture started")
    } catch {
      errorMessage = "Audio setup failed: \(error.localizedDescription)"
      NSLog("[Agent] Audio setup failed: %@", error.localizedDescription)
      return
    }

    // Wire audio buffers to speech recognition (always flowing)
    audioManager.onAudioBufferCaptured = { [weak self] buffer in
      self?.speechService.appendAudioBuffer(buffer)
    }

    // Wire audio RMS to voice activity detector
    audioManager.onVoiceActivity = { [weak self] rms in
      self?.voiceActivityDetector.processRMS(rms)
    }

    // Configure ElevenLabs TTS (Liam — young British male)
    ttsService.elevenLabsApiKey = "YOUR_ELEVENLABS_API_KEY"
    ttsService.audioPlayback = { [weak self] data in
      self?.audioManager.playAudio(data: data)
    }
    NSLog("[Agent] ElevenLabs TTS configured (voice: Liam)")

    // Wire TTS speaking state to manage conversation flow
    ttsService.onSpeakingStateChanged = { [weak self] isSpeaking in
      guard let self else { return }
      self.audioManager.isMutedForTTS = isSpeaking

      if isSpeaking {
        // Pause VAD so session timeout doesn't fire during TTS playback
        self.voiceActivityDetector.reset()
        NSLog("[Agent] TTS playing — VAD paused, mic muted")
      } else {
        // TTS finished — restart speech recognition fresh and resume VAD
        if self.mode == .active {
          self.isWaitingForAgent = false
          self.speechService.stopRecognition()
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.isRunning, self.mode == .active else { return }
            self.speechService.startRecognition()
            self.voiceActivityDetector.reset()
            NSLog("[Agent] TTS done — speech restarted, ready for next utterance")
          }
        }
      }
    }

    // Connect OpenClaw event client for real-time notifications
    if GeminiConfig.isOpenClawConfigured {
      eventClient.onNotification = { [weak self] text in
        guard let self else { return }
        NSLog("[Agent] Notification received: %@", String(text.prefix(100)))
        self.ttsService.speak(text)
      }
      eventClient.connect()
      NSLog("[Agent] Event client connecting")
    }

    // Wire partial transcripts — behavior depends on current mode
    speechService.onPartialTranscript = { [weak self] text in
      guard let self else { return }
      if self.mode == .passive {
        self.wakeWordDetector.processPartialTranscript(text)
      } else if self.mode == .active {
        self.userTranscript = text
        self.pendingTranscript = text
      }
    }

    // Wire final transcripts for active mode
    speechService.onFinalTranscript = { [weak self] text in
      guard let self else { return }
      guard self.mode == .active else { return }
      self.userTranscript = text
      self.pendingTranscript = text
    }

    // Wire wake word detection to transition to active mode
    wakeWordDetector.onWakeWordDetected = { [weak self] in
      guard let self else { return }
      NSLog("[Agent] Wake word detected, transitioning to active mode")
      self.cancelPassiveWakeWordTimer()
      self.transitionToActiveMode()
    }

    // Wire VAD callbacks
    wireVADCallbacks()

    // Request speech authorization and start recognition immediately
    speechService.requestAuthorization { [weak self] granted in
      guard let self else { return }
      self.speechAuthGranted = granted
      if granted {
        self.speechService.startRecognition()
        NSLog("[Agent] Speech recognition started (always-on)")
      } else {
        self.errorMessage = "Speech recognition authorization denied"
        NSLog("[Agent] Speech recognition authorization denied")
      }
    }

    // Start wake word detection and enter passive mode
    wakeWordDetector.startListening()
    voiceActivityDetector.reset()
    mode = .passive
    isRunning = true

    // Check OpenClaw connectivity
    Task {
      await openClawBridge.checkConnection()
      self.isOpenClawConnected = openClawBridge.connectionState == .connected
      openClawBridge.resetSession()
      NSLog("[Agent] OpenClaw connection checked, session ready")
    }

    NSLog("[Agent] Session started in passive mode (VAD monitoring, speech OFF)")
  }

  // MARK: - Stop Session

  func stopSession() {
    NSLog("[Agent] Stopping session")

    cancelPassiveWakeWordTimer()

    // Stop Gemini if active
    if let gemini = geminiSessionVM {
      gemini.stopSession()
      geminiSessionVM = nil
    }

    wakeWordDetector.stopListening()
    voiceActivityDetector.reset()
    speechService.stopRecognition()
    ttsService.stop()
    eventClient.disconnect()
    audioManager.stopCapture()

    mode = .passive
    isRunning = false
    isOpenClawConnected = false
    isEventStreamConnected = false
    userTranscript = ""
    agentResponse = ""
    pendingTranscript = ""
    errorMessage = nil

    NSLog("[Agent] Session stopped")
  }

  // MARK: - Video Frame Forwarding

  func sendVideoFrameIfThrottled(image: UIImage) {
    guard mode == .vision, let gemini = geminiSessionVM else { return }
    gemini.sendVideoFrameIfThrottled(image: image)
  }

  // MARK: - VAD Wiring

  private func wireVADCallbacks() {
    voiceActivityDetector.onSpeechStarted = { [weak self] in
      guard let self else { return }
      // STT runs always-on. VAD speech detection is used only for
      // active mode utterance/session timeouts, not for gating STT.
    }

    voiceActivityDetector.onSpeechEnded = { [weak self] in
      guard let self else { return }
      // No immediate action — wait for utterance or session timeout
    }

    voiceActivityDetector.onUtteranceTimeout = { [weak self] in
      guard let self else { return }
      guard self.mode == .active, !self.isWaitingForAgent else { return }

      let text = self.pendingTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
      self.pendingTranscript = ""
      guard !text.isEmpty else { return }

      NSLog("[Agent] Utterance complete — sending: %@", String(text.prefix(120)))
      self.isWaitingForAgent = true
      self.sendToOpenClaw(text)
    }

    voiceActivityDetector.onSessionTimeout = { [weak self] in
      guard let self else { return }
      // Don't timeout while waiting for agent response or TTS playback
      guard self.mode == .active, !self.isWaitingForAgent, !self.ttsService.isSpeaking else { return }

      NSLog("[Agent] Session timeout (%.0fs silence), returning to passive",
            self.voiceActivityDetector.sessionTimeoutSeconds)
      self.transitionToPassiveMode()
    }
  }

  // MARK: - Passive Mode Speech Management

  /// Start SpeechService temporarily to listen for wake word after VAD detects speech.
  private func startSpeechForPassiveWakeWord() {
    speechService.startRecognition()

    // Safety timer: if no wake word detected within 5 seconds, stop speech
    cancelPassiveWakeWordTimer()
    passiveWakeWordTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, self.mode == .passive else { return }
        NSLog("[Agent] Passive wake word safety timer — stopping SpeechService")
        self.stopSpeechForPassiveWakeWord()
      }
    }
  }

  /// Stop SpeechService when returning to VAD-only passive monitoring.
  private func stopSpeechForPassiveWakeWord() {
    cancelPassiveWakeWordTimer()
    speechService.stopRecognition()
    wakeWordDetector.reset()
    NSLog("[Agent] SpeechService stopped, back to VAD-only passive monitoring")
  }

  private func cancelPassiveWakeWordTimer() {
    passiveWakeWordTimer?.invalidate()
    passiveWakeWordTimer = nil
  }

  // MARK: - Send to OpenClaw

  private func sendToOpenClaw(_ text: String) {
    // Check for vision trigger phrases before sending to OpenClaw
    if containsVisionTrigger(text) {
      transitionToVisionMode(query: text)
      return
    }

    NSLog("[Agent] Sending to OpenClaw: %@", String(text.prefix(120)))
    Task { @MainActor [weak self] in
      guard let self, self.mode == .active else { return }
      let response = await self.openClawBridge.sendMessage(text)
      guard self.mode == .active else { return }

      if let response {
        self.agentResponse = response
        NSLog("[Agent] Agent response: %@", String(response.prefix(200)))
        self.ttsService.speak(response)
      } else {
        NSLog("[Agent] No response from OpenClaw")
        self.ttsService.speak("Sorry, I didn't get a response.")
      }
    }
  }

  // MARK: - Mode Transitions

  private func transitionToActiveMode() {
    guard mode == .passive else {
      NSLog("[Agent] Cannot transition to active — current mode is %@", mode.rawValue)
      return
    }

    mode = .active
    userTranscript = ""
    agentResponse = ""
    pendingTranscript = ""

    // Stop wake word listening
    wakeWordDetector.stopListening()
    cancelPassiveWakeWordTimer()

    // Ensure SpeechService is running continuously in active mode
    audioManager.onAudioBufferCaptured = { [weak self] buffer in
      self?.speechService.appendAudioBuffer(buffer)
    }
    if !speechService.isRecognizing {
      speechService.startRecognition()
    }

    // Reset VAD so session timeout starts fresh
    voiceActivityDetector.reset()

    // Play acknowledgment
    let ack = acknowledgments.randomElement() ?? "Yes?"
    ttsService.speak(ack)

    NSLog("[Agent] Entered active mode")
  }

  private func transitionToPassiveMode() {
    NSLog("[Agent] Transitioning to passive mode")

    // Stop any ongoing TTS
    ttsService.stop()

    // Clean restart of speech recognition to avoid stale state
    speechService.stopRecognition()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self, self.isRunning else { return }
      self.speechService.startRecognition()
      NSLog("[Agent] Speech recognition restarted for passive mode")
    }

    // Clear UI state
    userTranscript = ""
    agentResponse = ""
    pendingTranscript = ""

    // Reset VAD and wake word detector
    voiceActivityDetector.reset()
    wakeWordDetector.reset()

    // Resume wake word listening
    wakeWordDetector.startListening()

    mode = .passive
    NSLog("[Agent] Entered passive mode")
  }

  private func transitionToVisionMode(query: String) {
    guard mode == .active else {
      NSLog("[Agent] Cannot transition to vision — current mode is %@", mode.rawValue)
      return
    }

    NSLog("[Agent] Transitioning to vision mode (query: %@)", String(query.prefix(80)))
    mode = .vision

    // Announce the handoff
    ttsService.speak("Let me take a look...")

    // Pause speech recognition while Gemini is active
    speechService.pauseRecognition()

    // Create Gemini session lazily
    if geminiSessionVM == nil {
      geminiSessionVM = GeminiSessionViewModel()
      NSLog("[Agent] Created GeminiSessionViewModel")
    }

    guard let gemini = geminiSessionVM else { return }
    gemini.streamingMode = streamingMode

    Task { @MainActor [weak self] in
      guard let self else { return }

      await gemini.startSession()

      if gemini.isGeminiActive {
        NSLog("[Agent] Gemini session started for vision query")

        // Send the user's query as text to Gemini
        // Gemini will process it along with incoming video frames
        // Wait for Gemini to produce a response, then hand back

        // Observe Gemini's AI transcript for a response
        self.observeGeminiResponse()
      } else {
        NSLog("[Agent] Gemini session failed to start")
        self.ttsService.speak("Sorry, I couldn't start the camera.")
        self.finishVisionHandoff(response: nil)
      }
    }
  }

  private func observeGeminiResponse() {
    // Poll for Gemini's response — the session will receive video frames
    // from the caller via sendVideoFrameIfThrottled and produce a transcript.
    Task { @MainActor [weak self] in
      guard let self, let gemini = self.geminiSessionVM else { return }

      // Wait for Gemini to produce an AI transcript (poll at 500ms intervals)
      var waitCount = 0
      let maxWait = 60  // 30 seconds max
      var lastTranscript = ""

      while waitCount < maxWait {
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard self.mode == .vision else { break }

        let currentTranscript = gemini.aiTranscript
        if !currentTranscript.isEmpty && currentTranscript == lastTranscript {
          // Transcript stabilized — Gemini has finished responding
          NSLog("[Agent] Gemini vision response: %@", String(currentTranscript.prefix(200)))
          self.finishVisionHandoff(response: currentTranscript)
          return
        }
        lastTranscript = currentTranscript
        waitCount += 1
      }

      // Timeout or mode changed
      if self.mode == .vision {
        NSLog("[Agent] Gemini vision timed out")
        self.finishVisionHandoff(response: gemini.aiTranscript.isEmpty ? nil : gemini.aiTranscript)
      }
    }
  }

  private func finishVisionHandoff(response: String?) {
    NSLog("[Agent] Finishing vision handoff")

    // Stop Gemini
    geminiSessionVM?.stopSession()

    // Speak the result if we got one
    if let response, !response.isEmpty {
      agentResponse = response
      ttsService.speak(response)
    }

    // Resume speech recognition
    speechService.resumeRecognition()

    // Return to active mode — reset VAD for fresh session timeout
    mode = .active
    voiceActivityDetector.reset()

    NSLog("[Agent] Returned to active mode after vision handoff")
  }

  // MARK: - Vision Trigger Detection

  private func containsVisionTrigger(_ text: String) -> Bool {
    let lowered = text.lowercased()
    for phrase in SettingsManager.shared.visionTriggerPhrases {
      if lowered.contains(phrase.lowercased()) {
        NSLog("[Agent] Vision trigger detected: \"%@\"", phrase)
        return true
      }
    }
    return false
  }
}
