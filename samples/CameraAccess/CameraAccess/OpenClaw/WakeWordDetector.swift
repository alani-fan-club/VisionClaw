import Foundation

@MainActor
class WakeWordDetector: ObservableObject {
  @Published var isListening: Bool = false

  var wakePhrase: String = "hey claude"
  var onWakeWordDetected: (() -> Void)?

  private var lastDetectionTime: Date = .distantPast
  private let debounceInterval: TimeInterval = 3.0

  // MARK: - Public

  func startListening() {
    isListening = true
    NSLog("[WakeWord] Started listening for \"%@\"", wakePhrase)
  }

  func stopListening() {
    isListening = false
    NSLog("[WakeWord] Stopped listening")
  }

  func reset() {
    lastDetectionTime = .distantPast
  }

  func processPartialTranscript(_ text: String) {
    guard isListening else { return }

    let normalised = text.lowercased()
    guard normalised.contains(wakePhrase.lowercased()) else { return }

    let now = Date()
    guard now.timeIntervalSince(lastDetectionTime) >= debounceInterval else {
      NSLog("[WakeWord] Ignored duplicate detection (debounce)")
      return
    }

    lastDetectionTime = now
    NSLog("[WakeWord] Detected wake phrase in transcript: \"%@\"", text)
    onWakeWordDetected?()
  }
}
