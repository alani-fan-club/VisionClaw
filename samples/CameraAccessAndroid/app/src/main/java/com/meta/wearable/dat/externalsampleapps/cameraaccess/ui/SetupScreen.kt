package com.meta.wearable.dat.externalsampleapps.cameraaccess.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.meta.wearable.dat.externalsampleapps.cameraaccess.settings.SettingsManager

private const val TOTAL_STEPS = 4

@Composable
fun SetupScreen(
    onComplete: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var currentStep by remember { mutableIntStateOf(0) }
    var geminiAPIKey by remember { mutableStateOf("") }
    var openClawHost by remember { mutableStateOf("") }
    var openClawPort by remember { mutableStateOf("443") }
    var openClawHookToken by remember { mutableStateOf("") }
    var openClawGatewayToken by remember { mutableStateOf("") }
    var webrtcSignalingURL by remember { mutableStateOf("") }

    fun finishSetup() {
        SettingsManager.geminiAPIKey = geminiAPIKey.trim()

        val host = openClawHost.trim()
        if (host.isNotEmpty()) SettingsManager.openClawHost = host
        openClawPort.trim().toIntOrNull()?.let { SettingsManager.openClawPort = it }
        val hookToken = openClawHookToken.trim()
        if (hookToken.isNotEmpty()) SettingsManager.openClawHookToken = hookToken
        val gatewayToken = openClawGatewayToken.trim()
        if (gatewayToken.isNotEmpty()) SettingsManager.openClawGatewayToken = gatewayToken

        val signalingURL = webrtcSignalingURL.trim()
        if (signalingURL.isNotEmpty()) SettingsManager.webrtcSignalingURL = signalingURL

        SettingsManager.hasCompletedSetup = true
        onComplete()
    }

    Surface(modifier = modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .systemBarsPadding()
                .navigationBarsPadding(),
        ) {
            // Progress bar
            LinearProgressIndicator(
                progress = { (currentStep + 1).toFloat() / TOTAL_STEPS },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 24.dp, vertical = 16.dp),
            )

            // Step content
            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 24.dp),
            ) {
                AnimatedContent(targetState = currentStep, label = "setup_step") { step ->
                    when (step) {
                        0 -> WelcomeStep()
                        1 -> GeminiStep(
                            apiKey = geminiAPIKey,
                            onApiKeyChange = { geminiAPIKey = it },
                        )
                        2 -> OpenClawStep(
                            host = openClawHost,
                            onHostChange = { openClawHost = it },
                            port = openClawPort,
                            onPortChange = { openClawPort = it },
                            hookToken = openClawHookToken,
                            onHookTokenChange = { openClawHookToken = it },
                            gatewayToken = openClawGatewayToken,
                            onGatewayTokenChange = { openClawGatewayToken = it },
                        )
                        3 -> WebRTCStep(
                            signalingURL = webrtcSignalingURL,
                            onSignalingURLChange = { webrtcSignalingURL = it },
                        )
                    }
                }
            }

            // Navigation buttons
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (currentStep > 0) {
                    TextButton(onClick = { currentStep-- }) {
                        Text("Back")
                    }
                } else {
                    Spacer(modifier = Modifier.size(1.dp))
                }

                when {
                    currentStep == 0 -> {
                        Button(
                            onClick = { currentStep++ },
                            shape = RoundedCornerShape(12.dp),
                        ) {
                            Text("Get Started")
                        }
                    }
                    currentStep < TOTAL_STEPS - 1 -> {
                        Button(
                            onClick = { currentStep++ },
                            enabled = currentStep != 1 || geminiAPIKey.trim().isNotEmpty(),
                            shape = RoundedCornerShape(12.dp),
                        ) {
                            Text(if (currentStep == 1) "Next" else "Skip")
                        }
                    }
                    else -> {
                        Button(
                            onClick = { finishSetup() },
                            shape = RoundedCornerShape(12.dp),
                        ) {
                            Text("Finish Setup")
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun WelcomeStep() {
    Column(
        modifier = Modifier.fillMaxWidth().padding(top = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        Icon(
            imageVector = Icons.Default.Visibility,
            contentDescription = null,
            modifier = Modifier.size(80.dp),
            tint = MaterialTheme.colorScheme.primary,
        )

        Text(
            text = "Welcome to VisionClaw",
            style = MaterialTheme.typography.headlineLarge,
        )

        Text(
            text = "Let's get you set up. We'll walk through the configuration needed to connect to your AI services.",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            BulletItem("Gemini API key (required)")
            BulletItem("OpenClaw gateway (optional)")
            BulletItem("WebRTC streaming (optional)")
        }
    }
}

@Composable
private fun GeminiStep(
    apiKey: String,
    onApiKeyChange: (String) -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Gemini API Key", style = MaterialTheme.typography.headlineSmall)
        Text(
            "Required. This powers the AI vision and voice assistant. Get a free key from Google AI Studio.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        SetupMonoTextField(
            value = apiKey,
            onValueChange = onApiKeyChange,
            label = "API Key",
            placeholder = "Enter your Gemini API key",
        )
    }
}

@Composable
private fun OpenClawStep(
    host: String,
    onHostChange: (String) -> Unit,
    port: String,
    onPortChange: (String) -> Unit,
    hookToken: String,
    onHookTokenChange: (String) -> Unit,
    gatewayToken: String,
    onGatewayTokenChange: (String) -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("OpenClaw Gateway", style = MaterialTheme.typography.headlineSmall)
            OptionalBadge()
        }
        Text(
            "Connect to an OpenClaw instance on your Mac for agentic tool-calling. Skip this if you don't use OpenClaw.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Surface(
            color = MaterialTheme.colorScheme.surfaceVariant,
            shape = RoundedCornerShape(8.dp),
        ) {
            Column(
                modifier = Modifier.padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(
                    "Setup Requirements",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.tertiary,
                )
                Text(
                    "• Tailscale must be installed with DNS Management enabled (Tailscale → Preferences → Use Tailscale DNS)",
                    style = MaterialTheme.typography.bodySmall,
                )
                Text(
                    "• Run `tailscale serve --bg --https=443 http://127.0.0.1:18789` on your Mac to expose the gateway over HTTPS",
                    style = MaterialTheme.typography.bodySmall,
                )
                Text(
                    "• Use port 443 with your MagicDNS hostname (not 18789)",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }

        SetupMonoTextField(value = host, onValueChange = onHostChange, label = "Host", placeholder = "https://your-mac.tail12345.ts.net", keyboardType = KeyboardType.Uri)
        SetupMonoTextField(value = port, onValueChange = onPortChange, label = "Port", placeholder = "443", keyboardType = KeyboardType.Number)
        SetupMonoTextField(value = hookToken, onValueChange = onHookTokenChange, label = "Hook Token", placeholder = "Your hook token")
        SetupMonoTextField(value = gatewayToken, onValueChange = onGatewayTokenChange, label = "Gateway Token", placeholder = "Your gateway auth token")
    }
}

@Composable
private fun WebRTCStep(
    signalingURL: String,
    onSignalingURLChange: (String) -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("WebRTC Streaming", style = MaterialTheme.typography.headlineSmall)
            OptionalBadge()
        }
        Text(
            "Share your glasses' live POV in a browser. Requires running the included signaling server.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        SetupMonoTextField(
            value = signalingURL,
            onValueChange = onSignalingURLChange,
            label = "Signaling URL",
            placeholder = "wss://your-server.example.com",
            keyboardType = KeyboardType.Uri,
        )

        Spacer(modifier = Modifier.height(16.dp))

        Text(
            "You can always change these settings later from the gear icon on the home screen.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

// MARK: - Helper Composables

@Composable
private fun BulletItem(text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            text = "\u2022",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(end = 12.dp),
        )
        Text(text, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun OptionalBadge() {
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant,
        shape = RoundedCornerShape(4.dp),
    ) {
        Text(
            text = "Optional",
            style = MaterialTheme.typography.labelSmall,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
        )
    }
}

@Composable
private fun SetupMonoTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    placeholder: String,
    keyboardType: KeyboardType = KeyboardType.Text,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label) },
        placeholder = { Text(placeholder) },
        modifier = Modifier.fillMaxWidth(),
        textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
    )
}
