import Foundation
import Speech

class SpeechService: ObservableObject {
  var onPartialTranscript: ((String) -> Void)?
  var onFinalTranscript: ((String) -> Void)?

  @Published var isRecognizing: Bool = false

  private let speechRecognizer: SFSpeechRecognizer?
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var isPaused: Bool = false
  private var isExplicitlyStopped: Bool = true

  /// Serial queue that protects all mutable recognition state.
  /// Audio buffers arrive from AudioManager's dispatch queue; start/stop are
  /// called from the main thread.  Everything funnels through this queue.
  private let queue = DispatchQueue(label: "speech.recognition")

  /// Timer used to detect Apple's ~60 s on-device recognition limit so we
  /// can transparently restart the request.
  private var restartTimer: DispatchSourceTimer?
  private let recognitionDuration: TimeInterval = 55  // restart slightly before the 60 s ceiling

  // MARK: - Init

  init(locale: Locale = .current) {
    self.speechRecognizer = SFSpeechRecognizer(locale: locale)
    self.speechRecognizer?.defaultTaskHint = .dictation
  }

  // MARK: - Authorization

  func requestAuthorization(completion: @escaping (Bool) -> Void) {
    SFSpeechRecognizer.requestAuthorization { status in
      let granted = status == .authorized
      if granted {
        NSLog("[Speech] Authorization granted")
      } else {
        NSLog("[Speech] Authorization denied (status=%ld)", status.rawValue)
      }
      DispatchQueue.main.async { completion(granted) }
    }
  }

  // MARK: - Public API

  func startRecognition() {
    queue.async {
      self.isExplicitlyStopped = false
      self._startRecognition()
    }
  }

  func stopRecognition() {
    queue.async {
      self.isExplicitlyStopped = true
      self._stopRecognition(restart: false)
    }
  }

  func pauseRecognition() {
    queue.async {
      guard !self.isPaused else { return }
      self.isPaused = true
      NSLog("[Speech] Recognition paused")
    }
  }

  func resumeRecognition() {
    queue.async {
      guard self.isPaused else { return }
      self.isPaused = false
      NSLog("[Speech] Recognition resumed")
    }
  }

  /// Called from AudioManager's `onAudioBufferCaptured` callback.
  /// Thread-safe — buffers are dispatched onto the internal serial queue.
  func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
    queue.async {
      guard !self.isPaused, let request = self.recognitionRequest else { return }
      request.append(buffer)
    }
  }

  // MARK: - Internal (always called on `queue`)

  private func _startRecognition() {
    guard let speechRecognizer, speechRecognizer.isAvailable else {
      NSLog("[Speech] Recognizer unavailable")
      return
    }

    // Tear down any existing task before creating a new one
    _tearDownCurrentTask()

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = true
    self.recognitionRequest = request

    NSLog("[Speech] Starting on-device recognition")

    recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
      guard let self else { return }

      self.queue.async {
        if let result {
          let text = result.bestTranscription.formattedString
          if result.isFinal {
            NSLog("[Speech] Final: %@", String(text.prefix(120)))
            DispatchQueue.main.async { self.onFinalTranscript?(text) }
          } else {
            DispatchQueue.main.async { self.onPartialTranscript?(text) }
          }
        }

        if let error {
          let nsError = error as NSError
          // Code 1110 = "No speech detected" — this is normal, not a real error
          if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
            NSLog("[Speech] No speech detected, restarting")
          } else {
            NSLog("[Speech] Recognition error: %@", error.localizedDescription)
          }
          // Restart unless we were explicitly stopped
          if !self.isExplicitlyStopped {
            self._restartRecognition()
          }
          return
        }

        if let result, result.isFinal, !self.isExplicitlyStopped {
          // Apple finished the utterance — restart to keep listening
          self._restartRecognition()
        }
      }
    }

    _scheduleRestartTimer()

    DispatchQueue.main.async {
      self.isRecognizing = true
    }
  }

  private func _stopRecognition(restart: Bool) {
    _cancelRestartTimer()
    _tearDownCurrentTask()
    recognitionRequest = nil

    if !restart {
      NSLog("[Speech] Recognition stopped")
      DispatchQueue.main.async {
        self.isRecognizing = false
      }
    }
  }

  private func _restartRecognition() {
    NSLog("[Speech] Restarting recognition")
    _stopRecognition(restart: true)
    _startRecognition()
  }

  private func _tearDownCurrentTask() {
    recognitionTask?.cancel()
    recognitionTask = nil
    recognitionRequest?.endAudio()
    recognitionRequest = nil
  }

  // MARK: - Restart Timer

  /// Schedule a timer that restarts recognition before Apple's ~60 s limit.
  private func _scheduleRestartTimer() {
    _cancelRestartTimer()
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + recognitionDuration)
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      NSLog("[Speech] Recognition duration limit approaching, restarting")
      self._restartRecognition()
    }
    timer.resume()
    restartTimer = timer
  }

  private func _cancelRestartTimer() {
    restartTimer?.cancel()
    restartTimer = nil
  }
}
