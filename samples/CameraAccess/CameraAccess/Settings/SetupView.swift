import SwiftUI

struct SetupView: View {
  private let settings = SettingsManager.shared
  var onComplete: () -> Void

  @State private var currentStep = 0
  @State private var geminiAPIKey = ""
  @State private var openClawHost = ""
  @State private var openClawPort = "443"
  @State private var openClawHookToken = ""
  @State private var openClawGatewayToken = ""
  @State private var webrtcSignalingURL = ""
  @State private var elevenLabsAPIKey = ""
  @State private var elevenLabsVoiceId = "jfIS2w2yJi0grJZPyEsk"

  private let totalSteps = 4

  var body: some View {
    VStack(spacing: 0) {
      // Progress indicator
      HStack(spacing: 8) {
        ForEach(0..<totalSteps, id: \.self) { step in
          Capsule()
            .fill(step <= currentStep ? Color.blue : Color.gray.opacity(0.3))
            .frame(height: 4)
        }
      }
      .padding(.horizontal, 24)
      .padding(.top, 16)

      // Step content
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          switch currentStep {
          case 0:
            welcomeStep
          case 1:
            geminiStep
          case 2:
            openClawStep
          case 3:
            extrasStep
          default:
            EmptyView()
          }
        }
        .padding(24)
      }

      Spacer()

      // Navigation buttons
      HStack {
        if currentStep > 0 {
          Button("Back") {
            withAnimation { currentStep -= 1 }
          }
          .foregroundColor(.secondary)
        }

        Spacer()

        if currentStep == 0 {
          Button(action: { withAnimation { currentStep += 1 } }) {
            Text("Get Started")
              .fontWeight(.semibold)
              .foregroundColor(.white)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 14)
              .background(Color.blue)
              .cornerRadius(12)
          }
        } else if currentStep < totalSteps - 1 {
          Button(action: { withAnimation { currentStep += 1 } }) {
            Text(stepHasContent ? "Next" : "Skip")
              .fontWeight(.semibold)
              .foregroundColor(.white)
              .padding(.horizontal, 32)
              .padding(.vertical, 14)
              .background(currentStep == 1 && geminiAPIKey.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color.blue)
              .cornerRadius(12)
          }
          .disabled(currentStep == 1 && geminiAPIKey.trimmingCharacters(in: .whitespaces).isEmpty)
        } else {
          Button(action: finishSetup) {
            Text("Finish Setup")
              .fontWeight(.semibold)
              .foregroundColor(.white)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 14)
              .background(Color.blue)
              .cornerRadius(12)
          }
        }
      }
      .padding(24)
    }
    .background(Color(.systemBackground))
  }

  private var stepHasContent: Bool {
    switch currentStep {
    case 1:
      return !geminiAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
    case 2:
      return !openClawHost.trimmingCharacters(in: .whitespaces).isEmpty
        || !openClawGatewayToken.trimmingCharacters(in: .whitespaces).isEmpty
    case 3:
      return !elevenLabsAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
        || !webrtcSignalingURL.trimmingCharacters(in: .whitespaces).isEmpty
    default:
      return true
    }
  }

  // MARK: - Steps

  private var welcomeStep: some View {
    VStack(spacing: 20) {
      Spacer().frame(height: 40)

      Image(systemName: "eye.circle.fill")
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 80, height: 80)
        .foregroundColor(.blue)

      Text("Welcome to VisionClaw")
        .font(.largeTitle)
        .fontWeight(.bold)

      Text("Let's get you set up. We'll walk through the configuration needed to connect to your AI services.")
        .font(.body)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)

      VStack(alignment: .leading, spacing: 12) {
        SetupBullet(icon: "sparkles", text: "Gemini API key (required)")
        SetupBullet(icon: "server.rack", text: "OpenClaw gateway (optional)")
        SetupBullet(icon: "waveform", text: "ElevenLabs voice & WebRTC (optional)")
      }
      .padding(.top, 8)
    }
  }

  private var geminiStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Gemini API Key")
        .font(.title2)
        .fontWeight(.bold)

      Text("Required. This powers the AI vision and voice assistant. Get a free key from Google AI Studio.")
        .font(.subheadline)
        .foregroundColor(.secondary)

      TextField("Enter your Gemini API key", text: $geminiAPIKey)
        .autocapitalization(.none)
        .disableAutocorrection(true)
        .font(.system(.body, design: .monospaced))
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)

      Link("Get API key from Google AI Studio",
           destination: URL(string: "https://aistudio.google.com/apikey")!)
        .font(.footnote)
    }
  }

  private var openClawStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("OpenClaw Gateway")
          .font(.title2)
          .fontWeight(.bold)
        Spacer()
        Text("Optional")
          .font(.caption)
          .foregroundColor(.secondary)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(Color(.tertiarySystemBackground))
          .cornerRadius(4)
      }

      Text("Connect to an OpenClaw instance on your Mac for agentic tool-calling. Skip this if you don't use OpenClaw.")
        .font(.subheadline)
        .foregroundColor(.secondary)

      VStack(alignment: .leading, spacing: 6) {
        Text("Setup Requirements")
          .font(.caption)
          .fontWeight(.semibold)
          .foregroundColor(.orange)
        Text("• Tailscale must be installed with **DNS Management enabled** (Tailscale → Preferences → Use Tailscale DNS)")
          .font(.caption)
          .foregroundColor(.secondary)
        Text("• Run `tailscale serve --bg --https=443 http://127.0.0.1:18789` on your Mac to expose the gateway over HTTPS")
          .font(.caption)
          .foregroundColor(.secondary)
        Text("• Use port **443** with your MagicDNS hostname (not 18789)")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      .padding(12)
      .background(Color(.secondarySystemBackground))
      .cornerRadius(8)

      Group {
        SetupTextField(label: "Host", placeholder: "https://your-mac.tail12345.ts.net", text: $openClawHost, keyboardType: .URL)
        SetupTextField(label: "Port", placeholder: "443", text: $openClawPort, keyboardType: .numberPad)
        SetupTextField(label: "Hook Token", placeholder: "Your hook token", text: $openClawHookToken)
        SetupTextField(label: "Gateway Token", placeholder: "Your gateway auth token", text: $openClawGatewayToken)
      }
    }
  }

  private var extrasStep: some View {
    VStack(alignment: .leading, spacing: 24) {
      // ElevenLabs section
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          Text("ElevenLabs TTS")
            .font(.title2)
            .fontWeight(.bold)
          Spacer()
          Text("Optional")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(4)
        }

        Text("Use high-quality streaming voice synthesis. Leave blank to use the built-in system voice.")
          .font(.subheadline)
          .foregroundColor(.secondary)

        SetupTextField(label: "API Key", placeholder: "ElevenLabs API key", text: $elevenLabsAPIKey)
        SetupTextField(label: "Voice ID", placeholder: "jfIS2w2yJi0grJZPyEsk", text: $elevenLabsVoiceId)
      }

      Divider()

      // WebRTC section
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          Text("WebRTC Streaming")
            .font(.title2)
            .fontWeight(.bold)
          Spacer()
          Text("Optional")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(4)
        }

        Text("Share your glasses' live POV in a browser. Requires running the included signaling server.")
          .font(.subheadline)
          .foregroundColor(.secondary)

        SetupTextField(label: "Signaling URL", placeholder: "wss://your-server.example.com", text: $webrtcSignalingURL, keyboardType: .URL)
      }
    }
  }

  // MARK: - Actions

  private func finishSetup() {
    settings.geminiAPIKey = geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

    let host = openClawHost.trimmingCharacters(in: .whitespacesAndNewlines)
    if !host.isEmpty { settings.openClawHost = host }
    if let port = Int(openClawPort.trimmingCharacters(in: .whitespacesAndNewlines)) {
      settings.openClawPort = port
    }
    let hookToken = openClawHookToken.trimmingCharacters(in: .whitespacesAndNewlines)
    if !hookToken.isEmpty { settings.openClawHookToken = hookToken }
    let gatewayToken = openClawGatewayToken.trimmingCharacters(in: .whitespacesAndNewlines)
    if !gatewayToken.isEmpty { settings.openClawGatewayToken = gatewayToken }

    let elKey = elevenLabsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    if !elKey.isEmpty { settings.elevenLabsAPIKey = elKey }
    let voiceId = elevenLabsVoiceId.trimmingCharacters(in: .whitespacesAndNewlines)
    if !voiceId.isEmpty { settings.elevenLabsVoiceId = voiceId }

    let signalingURL = webrtcSignalingURL.trimmingCharacters(in: .whitespacesAndNewlines)
    if !signalingURL.isEmpty { settings.webrtcSignalingURL = signalingURL }

    settings.hasCompletedSetup = true
    onComplete()
  }
}

// MARK: - Helper Views

private struct SetupBullet: View {
  let icon: String
  let text: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .foregroundColor(.blue)
        .frame(width: 24)
      Text(text)
        .font(.subheadline)
    }
  }
}

private struct SetupTextField: View {
  let label: String
  let placeholder: String
  @Binding var text: String
  var keyboardType: UIKeyboardType = .default

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.caption)
        .foregroundColor(.secondary)
      TextField(placeholder, text: $text)
        .autocapitalization(.none)
        .disableAutocorrection(true)
        .keyboardType(keyboardType)
        .font(.system(.body, design: .monospaced))
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
  }
}
