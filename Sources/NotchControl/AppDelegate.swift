import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let vm = NotchViewModel()
    let agents = AgentStore()
    let music = NowPlayingService()
    let clipboard = ClipboardStore()
    let reminders = RemindersStore()
    let calendar = CalendarService()
    let bluetooth = BluetoothService()
    let account = AccountUsage()
    let pomodoro = PomodoroTimer()
    let bridge = BridgeServer()

    private var windowController: NotchWindowController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    let shelf = ShelfStore()
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGPIPE, SIG_IGN)
        UserDefaults.standard.register(defaults: [
            HotKey.enabledKey: true,
            HotKey.comboKey: 0,
            SettingsKey.slackNotifyApproval: true,
            SettingsKey.slackNotifyWaiting: true,
            SettingsKey.slackNotifyFinished: false,
            SettingsKey.clipboardLimit: 50,
        ])
        SoundPlayer.registerDefaults()
        DebugLog.log("launch from \(Bundle.main.bundleURL.path)")

        let root = NotchRootView()
            .environmentObject(vm)
            .environmentObject(agents)
            .environmentObject(music)
            .environmentObject(clipboard)
            .environmentObject(reminders)
            .environmentObject(calendar)
            .environmentObject(bluetooth)
            .environmentObject(account)
            .environmentObject(pomodoro)
            .environmentObject(shelf)
        windowController = NotchWindowController(vm: vm, content: AnyView(root))

        setupStatusItem()
        refreshHooksIfMoved()
        hotKey = HotKey { [weak self] in
            guard let self else { return }
            if self.vm.isExpanded { self.vm.collapse() } else { self.vm.expand(tab: self.vm.selectedTab, autoCollapseAfter: nil) }
        }
        NotificationCenter.default.addObserver(forName: .notchHotKeyChanged, object: nil, queue: .main) { [weak self] _ in self?.hotKey?.apply() }

        bridge.handler = { [weak self] event, respond in
            guard let self else { respond(nil); return }
            // Debug commands used by the build tooling.
            switch event["hook_event_name"] as? String {
            case "__expand":
                let tab = (event["tab"] as? String).flatMap { NotchTab(rawValue: $0) } ?? .agents
                self.vm.expand(tab: tab, autoCollapseAfter: nil)
                respond("{\"ok\":true}")
            case "__collapse":
                self.vm.collapse()
                respond("{\"ok\":true}")
            case "__focus":
                let id = event["session_id"] as? String ?? ""
                if let s = self.agents.orderedSessions.first(where: { id.isEmpty || $0.id == id }) {
                    self.agents.focusTerminal(s)
                    respond("{\"ok\":true,\"app\":\"\(s.terminal?.bundleID ?? "none")\",\"tty\":\"\(s.terminal?.tty ?? "none")\"}")
                } else { respond("{\"ok\":false}") }
            case "__usage":
                let w = self.account.windows.map { "\($0.id)=\(Int($0.utilization))%" }.joined(separator: ",")
                respond("{\"state\":\"\(self.account.state)\",\"plan\":\"\(self.account.plan ?? "")\",\"windows\":\"\(w)\"}")
            case "__snapshot":
                let url = AppPaths.supportDir.appendingPathComponent("snapshot.png")
                self.windowController?.snapshot(to: url)
                respond("{\"path\":\"\(url.path)\"}")
            default:
                self.agents.handle(event, respond: respond)
            }
        }
        do { try bridge.start() } catch { NSLog("NotchControl: bridge failed to start: \(error)") }

        agents.onEvent = { [weak self] event in self?.handleAgentEvent(event) }
        reminders.onFire = { [weak self] reminder in self?.fireReminder(reminder) }

        bluetooth.onConnect = { _ in SoundPlayer.play(.bluetooth) } // the pill shows "<device> connected" for 5 s

        music.start()
        clipboard.start()
        reminders.start()
        calendar.start()
        bluetooth.start()
        account.start()
        pomodoro.onPhaseChange = { [weak self] phase in
            guard let self else { return }
            switch phase {
            case .work: SoundPlayer.play(.focusStart); LocalNotifier.show(title: "Focus", body: "Round \(self.pomodoro.completedRounds + 1) of \(self.pomodoro.targetRounds). \(self.pomodoro.workMinutes) minutes.")
            case .shortBreak, .longBreak: SoundPlayer.play(.breakStart); self.vm.expand(tab: .focus, autoCollapseAfter: 6); LocalNotifier.show(title: phase.title, body: "Step away for a bit.")
            case .finished: SoundPlayer.play(.finished); self.vm.expand(tab: .focus, autoCollapseAfter: 8); LocalNotifier.show(title: "Pomodoro done", body: "\(self.pomodoro.targetRounds) rounds completed.")
            default: break
            }
        }
        LocalNotifier.requestPermission()
    }

    func applicationWillTerminate(_ notification: Notification) {
        bridge.stop()
    }

    // MARK: Status bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "NotchControl")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Notch", action: #selector(openNotch), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit NotchControl", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for m in menu.items { m.target = m.action == #selector(NSApplication.terminate(_:)) ? NSApp : self }
        item.menu = menu
        statusItem = item
    }

    @objc private func openNotch() { vm.expand(tab: vm.selectedTab, autoCollapseAfter: 10) }

    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 760),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "NotchControl Settings"
            w.contentView = NSHostingView(rootView: SettingsView())
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Events

    private func handleAgentEvent(_ event: AgentStore.Event) {
        let d = UserDefaults.standard
        switch event {
        case .needsApproval(let p):
            SoundPlayer.play(.approval)
            vm.expand(tab: .agents, autoCollapseAfter: nil)
            LocalNotifier.show(title: "\(p.agent.capitalized) needs approval", body: "\(p.toolName): \(p.summary)")
            if d.bool(forKey: SettingsKey.slackNotifyApproval) {
                SlackNotifier.post(":bell: *\(p.agent.capitalized)* wants to run `\(p.toolName)`\n```\(p.summary)```\nApprove it in the notch on your Mac.")
            }
        case .waitingForInput(let s):
            SoundPlayer.play(.waiting)
            vm.expand(tab: .agents, autoCollapseAfter: 8)
            LocalNotifier.show(title: "\(s.title) is waiting for you", body: s.lastPrompt)
            if d.bool(forKey: SettingsKey.slackNotifyWaiting) {
                SlackNotifier.post(":hourglass: *\(s.title)* is waiting for your input.")
            }
        case .finished(let s):
            SoundPlayer.play(.finished)
            if d.bool(forKey: SettingsKey.slackNotifyFinished) {
                let tail = s.lastMessage.isEmpty ? "" : "\n> " + s.lastMessage.prefix(300)
                SlackNotifier.post(":white_check_mark: *\(s.title)* finished.\(tail)")
            }
        case .failed(let s):
            SoundPlayer.play(.failed)
            vm.expand(tab: .agents, autoCollapseAfter: 6)
            LocalNotifier.show(title: "\(s.title) failed", body: s.activity)
            if d.bool(forKey: SettingsKey.slackNotifyFinished) {
                SlackNotifier.post(":x: *\(s.title)* stopped with an error.")
            }
        }
    }

    private func fireReminder(_ r: RemindersStore.Reminder) {
        SoundPlayer.play(.reminder)
        vm.expand(tab: .reminders, autoCollapseAfter: 12)
        LocalNotifier.show(title: "Reminder", body: r.title)
        if r.notifySlack {
            SlackNotifier.post(":alarm_clock: Reminder: \(r.title)")
        }
    }
}

extension AppDelegate {
    /// Hook entries embed the bridge path. If the app moved (e.g. ~/Applications → /Applications via Homebrew),
    /// rewrite the installed entries so agents keep reaching us.
    func refreshHooksIfMoved() {
        let current = HookInstaller.bridgePath
        func stale(_ url: URL) -> Bool {
            guard let text = try? String(contentsOf: url, encoding: .utf8), text.contains(HookInstaller.marker) else { return false }
            // The command quotes the path, so match it quoted: "/Applications/…" must not match "~/Applications/…".
            return !text.contains("\"\(current)\"")
        }
        if stale(HookInstaller.settingsURL) { try? HookInstaller.install(); DebugLog.log("refreshed Claude hooks for \(current)") }
        if stale(CodexHookInstaller.fileURL) { try? CodexHookInstaller.install(); DebugLog.log("refreshed Codex hooks") }
        if stale(CopilotHookInstaller.fileURL) { try? CopilotHookInstaller.install(); DebugLog.log("refreshed Copilot hooks") }
        if stale(GeminiHookInstaller.fileURL) { try? GeminiHookInstaller.install(); DebugLog.log("refreshed Gemini hooks") }
    }
}

extension Notification.Name {
    static let notchHotKeyChanged = Notification.Name("NotchControl.hotKeyChanged")
}
