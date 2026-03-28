import AVFoundation
import Foundation

class TTSService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
  @Published var isSpeaking: Bool = false

  var onSpeakingStateChanged: ((Bool) -> Void)?
  var voiceIdentifier: String?

  // MARK: - ElevenLabs Configuration

  /// When set, ElevenLabs streaming TTS is used as the primary voice.
  /// When nil, falls back to Apple AVSpeechSynthesizer.
  var elevenLabsApiKey: String?

  /// ElevenLabs voice ID. Default is "Liam" (young British male).
  var elevenLabsVoiceId: String = "jfIS2w2yJi0grJZPyEsk"

  /// Callback to play PCM audio data. Wire this to AudioManager.playAudio(data:).
  var audioPlayback: ((Data) -> Void)?

  // MARK: - Apple TTS

  private let synthesizer = AVSpeechSynthesizer()

  // MARK: - Queue

  private var utteranceQueue: [String] = []
  private var isProcessingQueue = false

  // MARK: - ElevenLabs State

  private var currentTask: URLSessionDataTask?
  private var speakingTimer: Timer?

  override init() {
    super.init()
    synthesizer.delegate = self
    NSLog("[TTS] Service initialized")
  }

  // MARK: - Public

  func speak(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    utteranceQueue.append(trimmed)
    NSLog("[TTS] Queued utterance (%d in queue)", utteranceQueue.count)
    processQueue()
  }

  func stop() {
    utteranceQueue.removeAll()

    // Cancel ElevenLabs request if in-flight
    currentTask?.cancel()
    currentTask = nil
    speakingTimer?.invalidate()
    speakingTimer = nil

    // Stop Apple TTS if speaking
    if synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
    }

    isProcessingQueue = false
    updateSpeakingState(false)
    NSLog("[TTS] Stopped speaking, queue cleared")
  }

  // MARK: - Queue Processing

  private func processQueue() {
    guard !isProcessingQueue, !utteranceQueue.isEmpty else { return }
    isProcessingQueue = true

    let text = utteranceQueue.removeFirst()

    if let apiKey = elevenLabsApiKey, !apiKey.isEmpty, audioPlayback != nil {
      speakWithElevenLabs(text: text, apiKey: apiKey)
    } else {
      speakWithApple(text: text)
    }
  }

  // MARK: - ElevenLabs Streaming TTS

  private func speakWithElevenLabs(text: String, apiKey: String) {
    let urlString = "https://api.elevenlabs.io/v1/text-to-speech/\(elevenLabsVoiceId)/stream?output_format=pcm_24000"
    guard let url = URL(string: urlString) else {
      NSLog("[TTS] ElevenLabs: invalid URL")
      finishElevenLabsUtterance()
      return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: Any] = [
      "text": text,
      "model_id": "eleven_turbo_v2_5"
    ]

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    } catch {
      NSLog("[TTS] ElevenLabs: failed to serialize request body: %@", error.localizedDescription)
      finishElevenLabsUtterance()
      return
    }

    NSLog("[TTS] ElevenLabs speaking: %@", String(text.prefix(80)))
    updateSpeakingState(true)

    let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      DispatchQueue.main.async {
        guard let self else { return }

        if let error = error as NSError?, error.code == NSURLErrorCancelled {
          NSLog("[TTS] ElevenLabs: request cancelled")
          return
        }

        if let error {
          NSLog("[TTS] ElevenLabs error: %@", error.localizedDescription)
          self.finishElevenLabsUtterance()
          return
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
          NSLog("[TTS] ElevenLabs HTTP %d", httpResponse.statusCode)
          if let data {
            let body = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
            NSLog("[TTS] ElevenLabs response: %@", body)
          }
          self.finishElevenLabsUtterance()
          return
        }

        guard let data, !data.isEmpty else {
          NSLog("[TTS] ElevenLabs: empty response")
          self.finishElevenLabsUtterance()
          return
        }

        NSLog("[TTS] ElevenLabs received %d bytes of PCM audio", data.count)

        // Feed PCM data to audio playback
        self.audioPlayback?(data)

        // Estimate playback duration: bytes / (sampleRate * bytesPerSample)
        // 24kHz, 16-bit mono = 48000 bytes per second
        let durationSeconds = Double(data.count) / 48000.0
        let bufferSeconds = 0.3 // small buffer for scheduling latency
        let totalWait = durationSeconds + bufferSeconds

        NSLog("[TTS] ElevenLabs estimated playback: %.1fs (+ %.1fs buffer)", durationSeconds, bufferSeconds)

        // Schedule end-of-speaking after estimated playback
        self.speakingTimer?.invalidate()
        self.speakingTimer = Timer.scheduledTimer(withTimeInterval: totalWait, repeats: false) { [weak self] _ in
          guard let self else { return }
          self.speakingTimer = nil
          self.finishElevenLabsUtterance()
        }
      }
    }

    currentTask = task
    task.resume()
  }

  private func finishElevenLabsUtterance() {
    currentTask = nil
    isProcessingQueue = false

    if utteranceQueue.isEmpty {
      updateSpeakingState(false)
    } else {
      processQueue()
    }
  }

  // MARK: - Apple AVSpeechSynthesizer (Fallback)

  private func speakWithApple(text: String) {
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = resolveVoice()
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    utterance.pitchMultiplier = 1.0
    utterance.preUtteranceDelay = 0.05

    NSLog("[TTS] Apple speaking: %@", String(text.prefix(80)))
    synthesizer.speak(utterance)
  }

  private var cachedVoice: AVSpeechSynthesisVoice?
  private var hasLoggedVoices = false

  private func resolveVoice() -> AVSpeechSynthesisVoice? {
    if let cached = cachedVoice { return cached }

    // Log available voices once to help debug
    if !hasLoggedVoices {
      hasLoggedVoices = true
      let enVoices = AVSpeechSynthesisVoice.speechVoices()
        .filter { $0.language.hasPrefix("en") }
        .sorted { $0.quality.rawValue > $1.quality.rawValue }
      for v in enVoices.prefix(10) {
        NSLog("[TTS] Available: %@ quality=%d id=%@", v.name, v.quality.rawValue, v.identifier)
      }
    }

    // Prefer explicit voice identifier if set
    if let identifier = voiceIdentifier,
       let voice = AVSpeechSynthesisVoice(identifier: identifier) {
      NSLog("[TTS] Using configured voice: %@", identifier)
      cachedVoice = voice
      return voice
    }

    // Find the highest quality English voice available (any region)
    let enVoices = AVSpeechSynthesisVoice.speechVoices()
      .filter { $0.language.hasPrefix("en") }
      .sorted { $0.quality.rawValue > $1.quality.rawValue }

    if let best = enVoices.first, best.quality.rawValue >= 2 {
      NSLog("[TTS] Using best available voice: %@ (quality=%d)", best.name, best.quality.rawValue)
      cachedVoice = best
      return best
    }

    // Fall back to default English voice
    let fallback = AVSpeechSynthesisVoice(language: "en-US")
    NSLog("[TTS] Using default en-US voice")
    cachedVoice = fallback
    return fallback
  }

  // MARK: - Speaking State

  private func updateSpeakingState(_ speaking: Bool) {
    if isSpeaking != speaking {
      isSpeaking = speaking
      onSpeakingStateChanged?(speaking)
      NSLog("[TTS] Speaking state: %@", speaking ? "true" : "false")
    }
  }

  // MARK: - AVSpeechSynthesizerDelegate

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
    DispatchQueue.main.async { [weak self] in
      self?.updateSpeakingState(true)
    }
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.isProcessingQueue = false
      if self.utteranceQueue.isEmpty {
        self.updateSpeakingState(false)
      } else {
        self.processQueue()
      }
    }
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.isProcessingQueue = false
      self.updateSpeakingState(false)
    }
  }
}
