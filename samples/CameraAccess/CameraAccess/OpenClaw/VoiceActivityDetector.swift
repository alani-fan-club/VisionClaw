import Foundation

// MARK: - VAD State

private enum VADState {
  case silence
  case speech
  case postSpeech
}

// MARK: - VoiceActivityDetector

@MainActor
class VoiceActivityDetector: ObservableObject {
  @Published var isSpeechDetected: Bool = false

  var onSpeechStarted: (() -> Void)?
  var onSpeechEnded: (() -> Void)?
  var onUtteranceTimeout: (() -> Void)?
  var onSessionTimeout: (() -> Void)?

  // Configurable thresholds
  var speechThreshold: Float = 0.015
  var utteranceTimeoutSeconds: Double = 1.5
  var sessionTimeoutSeconds: Double = 10.0

  // MARK: - Internal State

  private var state: VADState = .silence
  private var rmsHistory: [Float] = []
  private let rmsHistorySize = 5

  private var utteranceTimer: Timer?
  private var sessionTimer: Timer?

  // MARK: - Process RMS (called from audio thread)

  /// Called from AudioManager's audio capture thread.
  /// Dispatches all state changes to the main actor.
  nonisolated func processRMS(_ rms: Float) {
    Task { @MainActor [weak self] in
      self?.handleRMS(rms)
    }
  }

  // MARK: - Main Actor Processing

  private func handleRMS(_ rms: Float) {
    // Update rolling average
    rmsHistory.append(rms)
    if rmsHistory.count > rmsHistorySize {
      rmsHistory.removeFirst()
    }
    let averageRMS = rmsHistory.reduce(0, +) / Float(rmsHistory.count)

    let isSpeech = averageRMS > speechThreshold

    switch state {
    case .silence:
      if isSpeech {
        state = .speech
        isSpeechDetected = true
        cancelSessionTimer()
        NSLog("[VAD] Speech started (avgRMS=%.4f, threshold=%.4f)", averageRMS, speechThreshold)
        onSpeechStarted?()
      }

    case .speech:
      if isSpeech {
        // Still speaking — reset session timer if any
        cancelSessionTimer()
      } else {
        // Silence after speech — transition to post-speech
        state = .postSpeech
        NSLog("[VAD] Post-speech silence began (avgRMS=%.4f)", averageRMS)
        onSpeechEnded?()
        startUtteranceTimer()
        startSessionTimer()
      }

    case .postSpeech:
      if isSpeech {
        // Speech resumed — back to speech state
        state = .speech
        isSpeechDetected = true
        cancelUtteranceTimer()
        cancelSessionTimer()
        NSLog("[VAD] Speech resumed during post-speech (avgRMS=%.4f)", averageRMS)
      }
      // Otherwise stay in postSpeech, timers are running
    }
  }

  // MARK: - Reset

  func reset() {
    state = .silence
    isSpeechDetected = false
    rmsHistory.removeAll()
    cancelUtteranceTimer()
    cancelSessionTimer()
    NSLog("[VAD] Reset")
  }

  // MARK: - Utterance Timer

  private func startUtteranceTimer() {
    cancelUtteranceTimer()
    utteranceTimer = Timer.scheduledTimer(withTimeInterval: utteranceTimeoutSeconds, repeats: false) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        NSLog("[VAD] Utterance timeout (%.1fs silence after speech)", self.utteranceTimeoutSeconds)
        self.isSpeechDetected = false
        self.state = .silence
        self.onUtteranceTimeout?()
      }
    }
  }

  private func cancelUtteranceTimer() {
    utteranceTimer?.invalidate()
    utteranceTimer = nil
  }

  // MARK: - Session Timer

  private func startSessionTimer() {
    cancelSessionTimer()
    sessionTimer = Timer.scheduledTimer(withTimeInterval: sessionTimeoutSeconds, repeats: false) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        NSLog("[VAD] Session timeout (%.0fs continuous silence)", self.sessionTimeoutSeconds)
        self.isSpeechDetected = false
        self.state = .silence
        self.cancelUtteranceTimer()
        self.onSessionTimeout?()
      }
    }
  }

  private func cancelSessionTimer() {
    sessionTimer?.invalidate()
    sessionTimer = nil
  }
}
