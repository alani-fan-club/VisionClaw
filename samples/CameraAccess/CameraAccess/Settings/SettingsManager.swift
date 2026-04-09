import Foundation

final class SettingsManager {
  static let shared = SettingsManager()

  private let defaults = UserDefaults.standard

  private enum Key: String {
    case hasCompletedSetup
    case geminiAPIKey
    case openClawHost
    case openClawPort
    case openClawHookToken
    case openClawGatewayToken
    case geminiSystemPrompt
    case webrtcSignalingURL
    case speakerOutputEnabled
    case videoStreamingEnabled
    case proactiveNotificationsEnabled
    case wakeWord
    case silenceTimeoutSeconds
    case visionTriggerPhrases
    case agentAutoStart
    case ttsVoiceIdentifier
    case ttsRate
    case elevenLabsAPIKey
    case elevenLabsVoiceId
  }

  private init() {}

  // MARK: - Setup

  var hasCompletedSetup: Bool {
    get { defaults.bool(forKey: Key.hasCompletedSetup.rawValue) }
    set { defaults.set(newValue, forKey: Key.hasCompletedSetup.rawValue) }
  }

  // MARK: - Gemini

  var geminiAPIKey: String {
    get { defaults.string(forKey: Key.geminiAPIKey.rawValue) ?? Secrets.geminiAPIKey }
    set { defaults.set(newValue, forKey: Key.geminiAPIKey.rawValue) }
  }

  var geminiSystemPrompt: String {
    get { defaults.string(forKey: Key.geminiSystemPrompt.rawValue) ?? GeminiConfig.defaultSystemInstruction }
    set { defaults.set(newValue, forKey: Key.geminiSystemPrompt.rawValue) }
  }

  // MARK: - OpenClaw

  var openClawHost: String {
    get { defaults.string(forKey: Key.openClawHost.rawValue) ?? Secrets.openClawHost }
    set { defaults.set(newValue, forKey: Key.openClawHost.rawValue) }
  }

  var openClawPort: Int {
    get {
      let stored = defaults.integer(forKey: Key.openClawPort.rawValue)
      return stored != 0 ? stored : Secrets.openClawPort
    }
    set { defaults.set(newValue, forKey: Key.openClawPort.rawValue) }
  }

  var openClawHookToken: String {
    get { defaults.string(forKey: Key.openClawHookToken.rawValue) ?? Secrets.openClawHookToken }
    set { defaults.set(newValue, forKey: Key.openClawHookToken.rawValue) }
  }

  var openClawGatewayToken: String {
    get { defaults.string(forKey: Key.openClawGatewayToken.rawValue) ?? Secrets.openClawGatewayToken }
    set { defaults.set(newValue, forKey: Key.openClawGatewayToken.rawValue) }
  }

  // MARK: - WebRTC

  var webrtcSignalingURL: String {
    get { defaults.string(forKey: Key.webrtcSignalingURL.rawValue) ?? Secrets.webrtcSignalingURL }
    set { defaults.set(newValue, forKey: Key.webrtcSignalingURL.rawValue) }
  }

  // MARK: - Audio

  var speakerOutputEnabled: Bool {
    get { defaults.bool(forKey: Key.speakerOutputEnabled.rawValue) }
    set { defaults.set(newValue, forKey: Key.speakerOutputEnabled.rawValue) }
  }

  // MARK: - Video

  var videoStreamingEnabled: Bool {
    get { defaults.object(forKey: Key.videoStreamingEnabled.rawValue) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.videoStreamingEnabled.rawValue) }
  }

  // MARK: - Notifications

  var proactiveNotificationsEnabled: Bool {
    get { defaults.object(forKey: Key.proactiveNotificationsEnabled.rawValue) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.proactiveNotificationsEnabled.rawValue) }
  }

  // MARK: - Agent

  var wakeWord: String {
    get { defaults.string(forKey: Key.wakeWord.rawValue) ?? "hey claude" }
    set { defaults.set(newValue, forKey: Key.wakeWord.rawValue) }
  }

  var silenceTimeoutSeconds: Double {
    get {
      let stored = defaults.double(forKey: Key.silenceTimeoutSeconds.rawValue)
      return stored != 0 ? stored : 30.0
    }
    set { defaults.set(newValue, forKey: Key.silenceTimeoutSeconds.rawValue) }
  }

  var visionTriggerPhrases: [String] {
    get {
      defaults.stringArray(forKey: Key.visionTriggerPhrases.rawValue)
        ?? ["what am I looking at", "what do you see", "describe this", "look at this"]
    }
    set { defaults.set(newValue, forKey: Key.visionTriggerPhrases.rawValue) }
  }

  var agentAutoStart: Bool {
    get { defaults.object(forKey: Key.agentAutoStart.rawValue) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.agentAutoStart.rawValue) }
  }

  var ttsVoiceIdentifier: String? {
    get { defaults.string(forKey: Key.ttsVoiceIdentifier.rawValue) }
    set { defaults.set(newValue, forKey: Key.ttsVoiceIdentifier.rawValue) }
  }

  var ttsRate: Float {
    get {
      let stored = defaults.float(forKey: Key.ttsRate.rawValue)
      return stored != 0 ? stored : 0.52
    }
    set { defaults.set(newValue, forKey: Key.ttsRate.rawValue) }
  }

  // MARK: - ElevenLabs

  var elevenLabsAPIKey: String {
    get { defaults.string(forKey: Key.elevenLabsAPIKey.rawValue) ?? "" }
    set { defaults.set(newValue, forKey: Key.elevenLabsAPIKey.rawValue) }
  }

  var elevenLabsVoiceId: String {
    get { defaults.string(forKey: Key.elevenLabsVoiceId.rawValue) ?? "jfIS2w2yJi0grJZPyEsk" }
    set { defaults.set(newValue, forKey: Key.elevenLabsVoiceId.rawValue) }
  }

  // MARK: - Reset

  func resetAll() {
    for key in [Key.hasCompletedSetup, .geminiAPIKey, .geminiSystemPrompt, .openClawHost, .openClawPort,
                .openClawHookToken, .openClawGatewayToken, .webrtcSignalingURL,
                .speakerOutputEnabled, .videoStreamingEnabled,
                .proactiveNotificationsEnabled, .wakeWord, .silenceTimeoutSeconds,
                .visionTriggerPhrases, .agentAutoStart, .ttsVoiceIdentifier, .ttsRate,
                .elevenLabsAPIKey, .elevenLabsVoiceId] {
      defaults.removeObject(forKey: key.rawValue)
    }
  }
}
