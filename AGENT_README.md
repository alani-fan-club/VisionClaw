# Agent README — VisionClaw

This file is for AI coding agents (Claude Code, Cursor, etc.) helping users set up, modify, or extend this fork of the Meta Wearables DAT sample app.

It covers:
1. **What this fork is and how it differs from upstream**
2. **What was changed and why**
3. **How to help a user get this running end-to-end**
4. **Common pitfalls you should not repeat**

---

## 1. What this fork is

VisionClaw is a fork of the [Meta Wearables DAT iOS](https://github.com/facebook/meta-wearables-dat-ios) and DAT Android sample apps (`CameraAccess` / `CameraAccessAndroid`). The upstream samples demonstrate streaming video and audio from Meta Ray-Ban smart glasses.

This fork adds:
- A **Gemini Live** voice + vision conversation loop on top of the glasses stream
- An **OpenClaw** agentic backend so the model can take real actions (send messages, search the web, manage lists, control smart home)
- An **ElevenLabs** TTS path for high-quality voice synthesis
- A **WebRTC** streaming mode that lets a browser viewer see the glasses POV in real time
- A first-run **Setup** wizard and an in-app **Settings** screen so users can configure all of the above without editing source code

The two app targets are mirrors of each other in different languages — keep them in sync when you make user-facing changes.

---

## 2. What was changed (and why) versus the upstream sample

If you are touching one of these areas, you should understand the reason behind the existing design before changing it.

### 2.1 Configurable secrets with sensible fallbacks
**What:** A `SettingsManager` (UserDefaults on iOS, SharedPreferences on Android) stores all credentials and config. Each getter falls back to the corresponding `Secrets.swift` / `Secrets.kt` constant if no user value has been set.

**Why:** The upstream sample hardcodes the Gemini API key in source. That is fine for a single developer but not for distribution. With this two-layer setup:
- Devs cloning the repo can pre-fill `Secrets.swift` (gitignored) and skip the setup wizard
- End users who install a packaged build go through the Setup wizard and never touch source

**Files:** `Settings/SettingsManager.swift`, `settings/SettingsManager.kt`, `Secrets.swift.example`, `Secrets.kt.example`

### 2.2 First-run Setup wizard
**What:** `SetupView.swift` (iOS) and `SetupScreen.kt` (Android). A four-step flow: Welcome → Gemini API key (required) → OpenClaw (optional) → ElevenLabs + WebRTC (optional). Gated by a `hasCompletedSetup` boolean in `SettingsManager`. Shown by `MainAppView` (iOS) / `CameraAccessScaffold` (Android) before the home screen.

**Why:** Without this, a user installing a packaged build hits the home screen, taps "Start", and gets confusing errors because no API key is configured. The wizard makes the required setup obvious.

**Important:** the OpenClaw step contains a callout box about Tailscale DNS Management — do not remove it. See section 2.4.

### 2.3 ElevenLabs key promoted from hardcoded to configurable
**What:** `AgentSessionViewModel.swift` previously hardcoded `ttsService.elevenLabsApiKey = "sk_..."`. It now reads from `SettingsManager.shared.elevenLabsAPIKey` and falls back to system TTS if no key is set.

**Why:** Same as 2.1 — hardcoded keys leak when shipping.

**System TTS voice selection (when ElevenLabs is not used):** `TTSService.resolveVoice()` (in `OpenClaw/TTSService.swift`) automatically picks the **highest-quality English Siri voice** installed on the device — typically a Siri Enhanced or Premium voice. The default behavior is intentional, not arbitrary; do not "improve" this by hardcoding a specific voice unless the user asks for it.

If the user wants a **specific** voice (e.g. Siri Voice 2 male UK, or one of the Premium voices), set `SettingsManager.shared.ttsVoiceIdentifier` to a voice identifier string like `"com.apple.voice.premium.en-GB.Serena"`. The full list of installed voices is logged on first TTS call (look for `[TTS] Available: ...` lines in the Xcode console).

There is currently no UI surface for picking the voice — if the user wants one, add a picker to `SettingsView.swift` that lists `AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }` sorted by quality, and writes the selection to `settings.ttsVoiceIdentifier`. Mirror it on Android with `TextToSpeech.getVoices()`.

**Documentation references:**
- [`AVSpeechSynthesisVoice` (Apple)](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoice) — voice identifiers, quality levels, language codes
- [`AVSpeechSynthesisVoiceQuality`](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoicequality) — `.default`, `.enhanced`, `.premium`
- [Customizing spoken content (Apple HIG)](https://developer.apple.com/documentation/avfaudio/speech_synthesis) — best practices for utterance configuration
- Users must download Siri Enhanced/Premium voices manually under **Settings → Accessibility → Spoken Content → Voices** before they can be selected. Note this in any user-facing voice picker.

### 2.4 OpenClaw transport is now HTTPS-via-Tailscale only
**What:** The default `openClawPort` is `443` and `openClawHost` is expected to be a Tailscale MagicDNS hostname like `https://your-mac.your-tailnet.ts.net`. The user runs `tailscale serve --bg --https=443 http://127.0.0.1:18789` on their Mac to expose the local OpenClaw gateway over HTTPS with a real TLS cert.

**Why this matters — read carefully before "fixing" this:**
- iOS App Transport Security blocks plain `http://` to raw IP addresses
- On iOS 26+, `NSAllowsArbitraryLoads` is **not reliably honored** for raw IP addresses, even after a clean reinstall. We verified the plist makes it into the built bundle and ATS still blocks the connection
- Tailscale's WireGuard tunnel encrypts the link but does **not** add TLS at the application layer, so plain `http://` over Tailscale is still rejected by ATS
- The OpenClaw gateway itself does not speak HTTPS on its own port (18789)
- `tailscale serve` puts a Tailscale-signed TLS cert in front of the gateway on port 443. This is the only path that satisfies ATS without code-level hacks

**Do NOT** try to "fix" the connection by:
- Setting `NSAllowsArbitraryLoads` and assuming it works on iOS 26 (it doesn't, for raw IPs)
- Adding a `URLSessionDelegate` that accepts arbitrary server trust (the ATS gate fires before TLS handshake — the delegate is never called)
- Adding `NSExceptionDomains` for a hardcoded IP (defeats the whole point of distributing the app)
- Switching to `URLSessionConfiguration.ephemeral` (does not bypass ATS)
- Stripping HTTPS and "auto-upgrading" to HTTP (you'll loop right back to ATS errors)

If a user reports the OpenClaw gateway is unreachable, the answer is almost always one of:
1. Tailscale DNS Management is not enabled on their device (Tailscale → Preferences → **Use Tailscale DNS**)
2. They haven't run `tailscale serve` on the Mac
3. Tailscale Serve is not enabled on their tailnet (one-click enable at https://login.tailscale.com/admin/settings/general)
4. They entered the raw IP instead of the MagicDNS hostname
5. They left the port at `18789` instead of `443`

### 2.5 Audio format mismatch crash fix
**What:** `AudioManager.startCapture()` previously read `inputNode.outputFormat(forBus: 0)` and passed it to `installTap`. After an audio route change, this could return a stale 48 kHz format while the actual hardware was at 16 kHz, and the resulting `installTap` call threw an uncatchable Objective-C exception that crashed the app.

The fix: read both `inputFormat(forBus: 0)` (real hardware format) and `outputFormat(forBus: 0)`, prefer the hardware format if they disagree, and validate it is non-zero before installing the tap. If the format is invalid, throw a Swift error instead of letting the Obj-C exception propagate.

**Why:** This used to crash whenever a Bluetooth device connected/disconnected mid-session. It's an upstream bug, not something we introduced.

### 2.6 Removed personal data from Info.plist
**What:** The upstream Info.plist had an `NSExceptionDomains` entry hardcoding the original developer's Tailscale IP. That has been removed in favor of the standard `NSAllowsLocalNetworking` + `NSAllowsArbitraryLoads` pair.

**Why:** Personal data shouldn't ship in source. The standard ATS keys are kept because they cover the `.local` Bonjour case for users who choose not to use Tailscale (though OpenClaw still requires HTTPS).

### 2.7 Bundle identifier is `com.example.VisionClaw`
**What:** The PRODUCT_BUNDLE_IDENTIFIER in `project.pbxproj` is set to `com.example.VisionClaw`.

**Why:** This is a placeholder. Apple will not sign `com.example.*` for development. **Every user (including you, if you're helping someone build locally) must change this to a unique identifier under their own developer team before building.** This is the single most likely cause of a build failure on first run.

---

## 3. End-to-end setup checklist for helping a user

When a user asks you to help them get this running, walk them through these in order. Do not skip steps even if they "seem obvious" — every step here exists because something broke without it.

### 3.1 Prerequisites
- macOS with Xcode 16+ (this fork has been tested against the iOS 26 SDK)
- A Mac on the same Tailscale tailnet as the user's phone, if they want OpenClaw
- A Meta developer account configured for the DAT SDK (only needed for the actual glasses, not phone mode)
- A [Gemini API key](https://aistudio.google.com/apikey) (free tier is fine)

### 3.2 iOS build
1. Open `samples/CameraAccess/CameraAccess.xcodeproj` in Xcode
2. **Change the bundle identifier** in Signing & Capabilities to something unique under their team (e.g. `com.theirname.VisionClaw`). This is the #1 cause of build failures
3. Select their iPhone as target, hit Run
4. On first launch, the Setup wizard will ask for the Gemini API key. They can skip OpenClaw and ElevenLabs

### 3.3 Android build
1. Open `samples/CameraAccessAndroid/` in Android Studio
2. Add a `github_token=...` line to `local.properties` with a Personal Access Token that has `read:packages` scope (the DAT SDK is on GitHub Packages and requires auth even for public repos)
3. Hit Run

### 3.4 OpenClaw (only if the user wants agentic actions)
This is the part most likely to go sideways. Walk through it carefully:

1. Make sure OpenClaw is installed and the gateway is enabled in `~/.openclaw/openclaw.json`:
   ```json
   "gateway": {
     "port": 18789,
     "bind": "lan",
     "auth": { "mode": "token", "token": "..." },
     "http": { "endpoints": { "chatCompletions": { "enabled": true } } }
   }
   ```
2. Restart the gateway: `openclaw gateway restart`
3. Verify it's reachable locally: `curl http://localhost:18789/v1/chat/completions` (a 405 is fine — it means it's responding)
4. **Confirm Tailscale DNS Management is enabled** on the user's Mac AND phone — Tailscale → Preferences → "Use Tailscale DNS" must be on. Without this, MagicDNS hostnames will not resolve and HTTPS certs won't work.
5. Enable Tailscale Serve on their tailnet at https://login.tailscale.com/admin/settings/general (one-click)
6. Run `tailscale serve --bg --https=443 http://127.0.0.1:18789`. This puts an HTTPS proxy in front of the gateway. Verify with `tailscale serve status`.
7. Get the user's MagicDNS hostname with `tailscale status` (look for the local node line)
8. In the app's Setup wizard (or Settings screen), enter:
   - **Host:** `https://<their-magicdns-hostname>` (e.g. `https://johns-mac.tail12345.ts.net`)
   - **Port:** `443`
   - **Gateway Token:** the token from `openclaw.json`

### 3.5 Verifying it works
- Tap "Start on iPhone", tap the AI button, speak. You should hear Gemini respond.
- If OpenClaw is configured, ask the model to do something agentic ("add milk to my shopping list"). Watch the Xcode console for `[OpenClaw] Gateway reachable (HTTP 405)` and `[OpenClawWS] Connected and authenticated`.
- If you see `Error -1022` (ATS) or `Error -1200` (TLS) in the logs, the OpenClaw transport is misconfigured — go back to step 3.4 and verify each item.

---

## 4. Common pitfalls — do not repeat these

These are mistakes a previous agent (me, in an earlier session) made. Save the user time by not making them again.

### "I'll just add an ATS exception for the user's IP"
You can't. The user's IP is set at runtime. Hardcoding any IP defeats distribution. The Tailscale-via-`tailscale serve` path exists specifically to avoid this.

### "I'll add a URLSessionDelegate that bypasses TLS validation"
ATS rejects the request before the TLS handshake even starts. Your delegate's `didReceive challenge:` will never be called. This wastes time and doesn't fix anything.

### "I'll auto-upgrade `http://` to `https://` in the host string"
The OpenClaw gateway speaks plain HTTP on its native port. Auto-upgrading just changes a `-1022` ATS error into a `-1200` TLS error because the gateway has no cert. The fix is `tailscale serve`, not string substitution.

### "I'll switch the URLSession to ephemeral configuration"
Has no effect on ATS. ATS is a system-level policy applied to the URL itself, not the session.

### "I'll set `NSAllowsArbitraryLoads = true` and call it done"
On iOS 26+ with raw IP destinations, this is **not reliably honored**, even after a full clean and reinstall. The plist will be correct in the built bundle and the connection will still be blocked. We verified this empirically. The Tailscale-with-MagicDNS approach is the only one we got working.

### "I'll add the Tailscale hostname as a runtime migration in the app init"
Don't. That's how a previous version of this code ended up with the original developer's personal hostname baked into source. If you find code that does this, delete it.

### "Tests are failing, I'll just bypass them"
The repo has no automated tests right now. Don't add `--no-verify` or skip CI hooks. If a build fails, the cause is almost always the bundle identifier (see 2.7).

### "The user said the app crashes on a Bluetooth route change — let me wrap startCapture in a try/catch"
Already handled in 2.5. The Obj-C exception is uncatchable from Swift. The fix is at the format-validation level, not exception handling.

---

## 5. When the user wants to add a new configurable setting

Pattern to follow (mirror on both platforms):

1. Add a `case yourSetting` to the `Key` enum in `SettingsManager`
2. Add a getter/setter pair following the existing pattern (UserDefaults/SharedPreferences with a fallback default or `Secrets` constant)
3. Add the field to the reset list in `resetAll()`
4. Add a section/field to `SettingsView.swift` and `SettingsScreen.kt`
5. If it's required to use the app, also add it to the Setup wizard step
6. Read it via `SettingsManager.shared.yourSetting` from wherever it's used — never hardcode the value at the call site

---

## 6. File-level orientation

```
samples/
├── CameraAccess/                          ← iOS app
│   ├── CameraAccess/
│   │   ├── CameraAccessApp.swift         ← @main entry
│   │   ├── Secrets.swift                 ← gitignored, fallback values
│   │   ├── Secrets.swift.example         ← template for distribution
│   │   ├── Settings/
│   │   │   ├── SettingsManager.swift     ← UserDefaults wrapper, all config lives here
│   │   │   ├── SettingsView.swift        ← in-app settings screen (gear icon)
│   │   │   └── SetupView.swift           ← first-run wizard
│   │   ├── Views/MainAppView.swift       ← navigation root, gates on hasCompletedSetup
│   │   ├── Gemini/                       ← Gemini Live WebSocket client + audio
│   │   ├── OpenClaw/                     ← agent loop, OpenClaw HTTP/WS clients, TTS
│   │   └── WebRTC/                       ← optional POV streaming
│   └── server/                            ← optional Node.js WebRTC signaling server
│
└── CameraAccessAndroid/                   ← Android app (mirror of iOS)
    └── app/src/main/java/.../cameraaccess/
        ├── MainActivity.kt               ← entry, initializes SettingsManager
        ├── Secrets.kt                    ← gitignored
        ├── Secrets.kt.example
        ├── settings/SettingsManager.kt
        ├── ui/
        │   ├── CameraAccessScaffold.kt   ← navigation root, gates on hasCompletedSetup
        │   ├── SettingsScreen.kt
        │   └── SetupScreen.kt
        ├── gemini/                       ← mirror of iOS Gemini/
        └── openclaw/                     ← mirror of iOS OpenClaw/
```

When making cross-cutting changes, change both platforms in the same PR.
