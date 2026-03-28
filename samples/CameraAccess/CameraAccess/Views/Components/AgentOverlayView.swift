import SwiftUI

// MARK: - Agent Overlay View

/// Overlay for the Agent session UI, showing mode indicator, transcripts,
/// and connection status. Designed for dark backgrounds with white text.
struct AgentOverlayView: View {
  @ObservedObject var agentVM: AgentSessionViewModel

  var body: some View {
    VStack(spacing: 0) {
      // Top bar: mode pill + connection indicators
      HStack(spacing: 8) {
        AgentModePill(mode: agentVM.mode)

        Spacer()

        ConnectionDot(
          label: "OpenClaw",
          isConnected: agentVM.isOpenClawConnected
        )

        ConnectionDot(
          label: "Events",
          isConnected: agentVM.isEventStreamConnected
        )
      }

      Spacer()

      // Bottom area: transcript + response
      VStack(spacing: 8) {
        if !agentVM.userTranscript.isEmpty || !agentVM.agentResponse.isEmpty {
          AgentTranscriptView(
            userText: agentVM.userTranscript,
            agentText: agentVM.agentResponse
          )
        }

        if agentVM.mode == .active {
          ListeningIndicator()
        }
      }
      .padding(.bottom, 80)
    }
    .padding(.all, 24)
  }
}

// MARK: - Agent Mode Pill

struct AgentModePill: View {
  let mode: AgentMode

  var body: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(modeColor)
        .frame(width: 8, height: 8)
      Text(mode.rawValue.capitalized)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.white)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(modeColor.opacity(0.25))
    .overlay(
      RoundedRectangle(cornerRadius: 16)
        .stroke(modeColor.opacity(0.5), lineWidth: 1)
    )
    .cornerRadius(16)
  }

  private var modeColor: Color {
    switch mode {
    case .passive: return .gray
    case .active: return .green
    case .vision: return .blue
    }
  }
}

// MARK: - Connection Dot

struct ConnectionDot: View {
  let label: String
  let isConnected: Bool

  var body: some View {
    HStack(spacing: 4) {
      Circle()
        .fill(isConnected ? Color.green : Color.red.opacity(0.7))
        .frame(width: 6, height: 6)
      Text(label)
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(.white.opacity(0.6))
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(Color.black.opacity(0.5))
    .cornerRadius(10)
  }
}

// MARK: - Agent Transcript View

struct AgentTranscriptView: View {
  let userText: String
  let agentText: String

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 8) {
          if !userText.isEmpty {
            HStack(alignment: .top, spacing: 6) {
              Image(systemName: "person.fill")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.5))
                .padding(.top, 2)
              Text(userText)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
            }
          }

          if !agentText.isEmpty {
            HStack(alignment: .top, spacing: 6) {
              Image(systemName: "brain.fill")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.8))
                .padding(.top, 2)
              Text(agentText)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .id("agentBottom")
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxHeight: 160)
      .onChange(of: agentText) { _ in
        withAnimation {
          proxy.scrollTo("agentBottom", anchor: .bottom)
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(Color.black.opacity(0.6))
    .cornerRadius(12)
  }
}

// MARK: - Listening Indicator

struct ListeningIndicator: View {
  @State private var animating = false

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "mic.fill")
        .foregroundColor(.green)
        .font(.system(size: 14))

      HStack(spacing: 3) {
        ForEach(0..<3, id: \.self) { index in
          Circle()
            .fill(Color.green)
            .frame(width: 6, height: 6)
            .scaleEffect(animating ? 1.0 : 0.4)
            .animation(
              .easeInOut(duration: 0.6)
                .repeatForever(autoreverses: true)
                .delay(Double(index) * 0.2),
              value: animating
            )
        }
      }

      Text("Listening")
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.white.opacity(0.7))
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(Color.black.opacity(0.5))
    .cornerRadius(20)
    .onAppear { animating = true }
    .onDisappear { animating = false }
  }
}
