import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.slackWebhookURL) private var slackWebhookURL = ""
    @AppStorage(SettingsKey.slackNotifyApproval) private var slackNotifyApproval = true
    @AppStorage(SettingsKey.slackNotifyWaiting) private var slackNotifyWaiting = true
    @AppStorage(SettingsKey.slackNotifyFinished) private var slackNotifyFinished = false
    @AppStorage(SettingsKey.clipboardLimit) private var clipboardLimit = 50
    @AppStorage(SoundPlayer.enabledKey) private var soundsEnabled = true
    @AppStorage(SoundPlayer.volumeKey) private var soundVolume = 0.6

    @State private var hooksInstalled = HookInstaller.isInstalled()
    @State private var hookMessage = ""
    @State private var copilotInstalled = CopilotHookInstaller.isInstalled()
    @State private var copilotMessage = ""
    @State private var codexInstalled = CodexHookInstaller.isInstalled()
    @State private var codexMessage = ""
    @State private var geminiInstalled = GeminiHookInstaller.isInstalled()
    @State private var geminiMessage = ""
    @State private var slackMessage = ""
    @AppStorage(HotKey.enabledKey) private var hotkeyEnabled = true
    @AppStorage(HotKey.comboKey) private var hotkeyCombo = 0
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginMessage = ""

    var body: some View {
        Form {
            Section("General") {
                Toggle("Start NotchControl at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { try LaunchAtLogin.set(on); loginMessage = "" }
                        catch { loginMessage = "Failed: \(error.localizedDescription)"; launchAtLogin = LaunchAtLogin.isEnabled }
                    }
                if !loginMessage.isEmpty { Text(loginMessage).font(.caption).foregroundStyle(.secondary) }
                Toggle("Keyboard shortcut opens the notch", isOn: $hotkeyEnabled)
                    .onChange(of: hotkeyEnabled) { _, _ in NotificationCenter.default.post(name: .notchHotKeyChanged, object: nil) }
                Picker("Shortcut", selection: $hotkeyCombo) {
                    ForEach(HotKey.combos) { Text($0.title).tag($0.id) }
                }
                .disabled(!hotkeyEnabled)
                .onChange(of: hotkeyCombo) { _, _ in NotificationCenter.default.post(name: .notchHotKeyChanged, object: nil) }
            }
            Section("Claude Code") {
                LabeledContent("Hooks", value: hooksInstalled ? "Installed" : "Not installed")
                Text(HookInstaller.bridgePath).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                HStack {
                    Button(hooksInstalled ? "Reinstall hooks" : "Install hooks") {
                        do { try HookInstaller.install(); hookMessage = "Hooks written to ~/.claude/settings.json. Restart Claude Code sessions to pick them up." }
                        catch { hookMessage = "Failed: \(error.localizedDescription)" }
                        hooksInstalled = HookInstaller.isInstalled()
                    }
                    if hooksInstalled {
                        Button("Remove hooks") {
                            do { try HookInstaller.uninstall(); hookMessage = "Hooks removed." }
                            catch { hookMessage = "Failed: \(error.localizedDescription)" }
                            hooksInstalled = HookInstaller.isInstalled()
                        }
                    }
                }
                if !hookMessage.isEmpty { Text(hookMessage).font(.caption).foregroundStyle(.secondary) }
            }
            Section("GitHub Copilot CLI") {
                LabeledContent("Hooks", value: copilotInstalled ? "Installed" : "Not installed")
                Text(CopilotHookInstaller.fileURL.path).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                HStack {
                    Button(copilotInstalled ? "Reinstall hooks" : "Install hooks") {
                        do { try CopilotHookInstaller.install(); copilotMessage = "Hook file written. Start a new copilot session to pick it up." }
                        catch { copilotMessage = "Failed: \(error.localizedDescription)" }
                        copilotInstalled = CopilotHookInstaller.isInstalled()
                    }
                    if copilotInstalled {
                        Button("Remove hooks") {
                            do { try CopilotHookInstaller.uninstall(); copilotMessage = "Hooks removed." }
                            catch { copilotMessage = "Failed: \(error.localizedDescription)" }
                            copilotInstalled = CopilotHookInstaller.isInstalled()
                        }
                    }
                }
                if !copilotMessage.isEmpty { Text(copilotMessage).font(.caption).foregroundStyle(.secondary) }
            }
            Section("OpenAI Codex CLI") {
                LabeledContent("Hooks", value: codexInstalled ? "Installed" : "Not installed")
                Text(CodexHookInstaller.fileURL.path).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                HStack {
                    Button(codexInstalled ? "Reinstall hooks" : "Install hooks") {
                        do { try CodexHookInstaller.install(); codexMessage = "Hooks written. Run /hooks inside codex once to trust them." }
                        catch { codexMessage = "Failed: \(error.localizedDescription)" }
                        codexInstalled = CodexHookInstaller.isInstalled()
                    }
                    if codexInstalled {
                        Button("Remove hooks") {
                            do { try CodexHookInstaller.uninstall(); codexMessage = "Hooks removed." }
                            catch { codexMessage = "Failed: \(error.localizedDescription)" }
                            codexInstalled = CodexHookInstaller.isInstalled()
                        }
                    }
                }
                if !codexMessage.isEmpty { Text(codexMessage).font(.caption).foregroundStyle(.secondary) }
            }
            Section("Gemini CLI") {
                LabeledContent("Hooks", value: geminiInstalled ? "Installed" : "Not installed")
                Text(GeminiHookInstaller.fileURL.path).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                HStack {
                    Button(geminiInstalled ? "Reinstall hooks" : "Install hooks") {
                        do { try GeminiHookInstaller.install(); geminiMessage = "Hooks written. Start a new gemini session to pick them up." }
                        catch { geminiMessage = "Failed: \(error.localizedDescription)" }
                        geminiInstalled = GeminiHookInstaller.isInstalled()
                    }
                    if geminiInstalled {
                        Button("Remove hooks") {
                            do { try GeminiHookInstaller.uninstall(); geminiMessage = "Hooks removed." }
                            catch { geminiMessage = "Failed: \(error.localizedDescription)" }
                            geminiInstalled = GeminiHookInstaller.isInstalled()
                        }
                    }
                }
                Text("Gemini has no approval hook, so only status is shown.").font(.caption).foregroundStyle(.secondary)
                if !geminiMessage.isEmpty { Text(geminiMessage).font(.caption).foregroundStyle(.secondary) }
            }
            Section("Slack") {
                TextField("Incoming webhook URL (https://hooks.slack.com/services/…)", text: $slackWebhookURL)
                    .textFieldStyle(.roundedBorder)
                Toggle("Notify when an agent needs approval", isOn: $slackNotifyApproval)
                Toggle("Notify when an agent is waiting for my input", isOn: $slackNotifyWaiting)
                Toggle("Notify when an agent finishes", isOn: $slackNotifyFinished)
                HStack {
                    Button("Send test message") {
                        slackMessage = "Sending…"
                        SlackNotifier.post(":wave: NotchControl is connected.") { ok, detail in slackMessage = ok ? "Sent." : detail }
                    }
                    .disabled(SlackNotifier.webhookURL == nil)
                    Text(slackMessage).font(.caption).foregroundStyle(.secondary)
                }
                Text("Create a webhook at api.slack.com/apps → Incoming Webhooks. Reminders can also post here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Sounds") {
                Toggle("Play sounds", isOn: $soundsEnabled)
                HStack {
                    Text("Volume")
                    Slider(value: $soundVolume, in: 0...1)
                    Button { SoundPlayer.play(named: SoundPlayer.soundName(for: .approval)) } label: { Image(systemName: "speaker.wave.2") }
                }
                ForEach(SoundPlayer.Event.allCases) { event in
                    SoundRow(event: event)
                }
                .disabled(!soundsEnabled)
            }
            Section("Clipboard") {
                Stepper("Keep the last \(clipboardLimit) items", value: $clipboardLimit, in: 5...500, step: 5)
                Text("Entries marked as concealed by password managers are never stored.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 820)
    }
}

struct SoundRow: View {
    let event: SoundPlayer.Event
    @State private var selection: String

    init(event: SoundPlayer.Event) {
        self.event = event
        _selection = State(initialValue: SoundPlayer.soundName(for: event))
    }

    var body: some View {
        HStack {
            Picker(event.title, selection: $selection) {
                Text("None").tag(SoundPlayer.none)
                ForEach(SoundPlayer.systemSounds, id: \.self) { Text($0).tag($0) }
            }
            .onChange(of: selection) { _, new in
                UserDefaults.standard.set(new, forKey: event.key)
                SoundPlayer.play(named: new)
            }
            Button { SoundPlayer.play(named: selection) } label: { Image(systemName: "play.fill") }
                .buttonStyle(.borderless)
        }
    }
}
