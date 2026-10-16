import AppKit
import SwiftUI

struct NotchRootView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if vm.isExpanded {
                    ExpandedView()
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                } else {
                    CollapsedView()
                        .transition(.opacity)
                }
            }
            .frame(width: vm.isExpanded ? NotchMetrics.expandedSize.width : vm.collapsedSize.width,
                   height: vm.isExpanded ? NotchMetrics.expandedSize.height : vm.collapsedSize.height)
            .background(Color.black)
            .shadow(color: .black.opacity(vm.isExpanded ? 0.5 : 0), radius: 18, y: 8)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: vm.isExpanded ? 24 : 14,
                                              bottomTrailingRadius: vm.isExpanded ? 24 : 14))
            .overlay(
                UnevenRoundedRectangle(bottomLeadingRadius: vm.isExpanded ? 24 : 14,
                                       bottomTrailingRadius: vm.isExpanded ? 24 : 14)
                    .stroke(Color.white.opacity(vm.hasPhysicalNotch ? 0 : 0.25), lineWidth: 1)
            )
            .onHover { vm.setHover($0) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(vm.isExpanded ? .spring(response: 0.42, dampingFraction: 0.74)   // open: a little bounce
                                  : .spring(response: 0.28, dampingFraction: 0.95),  // close: quick and clean
                   value: vm.isExpanded)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Collapsed

struct CollapsedView: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var agents: AgentStore
    @EnvironmentObject var music: NowPlayingService
    @EnvironmentObject var reminders: RemindersStore
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var bluetooth: BluetoothService
    @EnvironmentObject var pomodoro: PomodoroTimer

    /// What the left wing says: a device change for a few seconds, then an imminent event, then the agent line.
    private var leftText: String {
        if let change = bluetooth.lastChange { return change }
        if let e = calendar.next, e.start.timeIntervalSinceNow < 15 * 60, e.start > Date() {
            return "\(e.title) in \(max(1, Int(e.start.timeIntervalSinceNow / 60))) min"
        }
        return agents.headline
    }

    /// Distinct agents with a session, busy ones first, at most three so the text still fits.
    private var iconSessions: [AgentSession] {
        var seen = Set<String>()
        let busyFirst = agents.orderedSessions.sorted { a, b in
            if a.isBusy != b.isBusy { return a.isBusy }
            return a.updatedAt > b.updatedAt
        }
        return Array(busyFirst.filter { seen.insert($0.agent.lowercased()).inserted }.prefix(3))
    }

    /// The session whose colour the right-hand working animation takes; nil when nobody is working.
    private var workingSession: AgentSession? {
        agents.orderedSessions.first { $0.status == "Working" }
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if let p = agents.pending.first {
                    AgentStatusIcon(agent: p.agent, status: "Waiting for approval", size: 14)
                } else if !agents.orderedSessions.isEmpty {
                    // One icon per agent that has a session; the busiest one first, the rest tucked behind it.
                    HStack(spacing: -5) {
                        ForEach(Array(iconSessions.enumerated()), id: \.element.id) { i, s in
                            AgentStatusIcon(agent: s.agent, status: s.status, size: 14)
                                .zIndex(Double(iconSessions.count - i))
                        }
                    }
                } else {
                    Circle().fill(Color.gray).frame(width: 7, height: 7)
                }
                Text(leftText)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.leading, 12)
            .frame(width: NotchMetrics.wingWidth, alignment: .leading)

            if vm.notchSize.width > 0 { Spacer().frame(width: vm.notchSize.width) } else { Spacer(minLength: 8) }

            HStack(spacing: 6) {
                if let s = workingSession {
                    WorkingIndicator(color: AgentIcon.accent(for: s.agent), height: 12)
                        .help("\(s.agent.capitalized) is working")
                }
                if pomodoro.phase != .idle && pomodoro.phase != .finished {
                    HStack(spacing: 3) {
                        Image(systemName: pomodoro.phase == .work ? "timer" : "cup.and.saucer.fill")
                        Text(pomodoro.clock).font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(pomodoro.phase == .work ? Color(red: 0.95, green: 0.4, blue: 0.35) : Color.green)
                    .opacity(pomodoro.isRunning ? 1 : 0.5)
                }
                if reminders.dueCount > 0 {
                    Image(systemName: "bell.badge.fill").foregroundStyle(.orange)
                }
                if let d = bluetooth.devices.first(where: { $0.isLowBattery }) {
                    HStack(spacing: 2) {
                        Image(systemName: d.icon)
                        Text("\(d.minBattery ?? 0)%").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.red)
                    .help("\(d.name) battery low")
                }
                if let art = music.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else if music.track != nil {
                    Image(systemName: music.isPlaying ? "music.note" : "pause.fill")
                }
            }
            .font(.system(size: 11))
            .padding(.trailing, 12)
            .frame(width: NotchMetrics.wingWidth, alignment: .trailing)
        }
        .foregroundStyle(.white)
    }
}

// MARK: - Expanded

struct ExpandedView: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var agents: AgentStore
    @EnvironmentObject var reminders: RemindersStore
    @EnvironmentObject var shelf: ShelfStore
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: vm.hasPhysicalNotch ? vm.notchSize.height : 8)
            HStack(spacing: 2) {
                ForEach(NotchTab.allCases) { tab in
                    Button { vm.selectedTab = tab } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                            if vm.selectedTab == tab { Text(tab.rawValue) }
                            if let badge = badge(for: tab) {
                                Text("\(badge)")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Color.orange, in: Capsule())
                            }
                        }
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(vm.selectedTab == tab ? Color.white.opacity(0.18) : .clear, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(tab.rawValue)
                }
                Spacer()
                Button { vm.collapse() } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.plain).opacity(0.6)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            Divider().overlay(Color.white.opacity(0.15))
            Group {
                switch vm.selectedTab {
                case .agents: AgentsTab()
                case .music: MusicTab()
                case .clipboard: ClipboardTab()
                case .reminders: RemindersTab()
                case .calendar: CalendarTab()
                case .focus: FocusTab()
                case .notes: NotesTab()
                case .shelf: ShelfTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(.white)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(6)
                    .overlay(Text("Drop to keep on the shelf").font(.system(size: 13, weight: .semibold)))
                    .background(Color.black.opacity(0.5))
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            let ok = shelf.add(providers: providers)
            if ok { vm.selectedTab = .shelf }
            return ok
        }
        .onChange(of: dropTargeted) { _, on in if on { vm.selectedTab = .shelf } }
    }

    private func badge(for tab: NotchTab) -> Int? {
        switch tab {
        case .agents: return agents.pending.isEmpty ? nil : agents.pending.count
        case .reminders: return reminders.dueCount == 0 ? nil : reminders.dueCount
        case .shelf: return shelf.items.isEmpty ? nil : shelf.items.count
        default: return nil
        }
    }
}

// MARK: - Agents

struct AgentsTab: View {
    @EnvironmentObject var agents: AgentStore
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                AccountUsageHeader()
                ForEach(agents.pending) { p in PendingCard(decision: p) }
                if agents.pending.isEmpty && agents.orderedSessions.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "terminal").font(.system(size: 26)).opacity(0.5)
                        Text("No agent sessions yet").font(.system(size: 12))
                        Text("Install the Claude Code hooks from Settings, then start a session.")
                            .font(.system(size: 11)).opacity(0.6).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 40)
                }
                ForEach(agents.orderedSessions) { s in
                    SessionRow(session: s)
                        .contextMenu {
                            Button("Open terminal") { agents.focusTerminal(s); vm.collapse() }.disabled(s.terminal == nil)
                        }
                        .simultaneousGesture(TapGesture(count: 2).onEnded { agents.focusTerminal(s); vm.collapse() })
                        .help(s.terminal == nil ? "" : "Double-click to open the terminal running this session")
                }
            }
            .padding(12)
        }
    }
}

struct PendingCard: View {
    @EnvironmentObject var agents: AgentStore
    let decision: PendingDecision

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                AgentStatusIcon(agent: decision.agent, status: "Waiting for approval", size: 18)
                Text("\(decision.agent.capitalized) wants to run \(decision.toolName)")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(decision.createdAt, style: .relative).font(.system(size: 10)).opacity(0.5)
            }
            if decision.questions.isEmpty {
                Text(decision.summary)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                HStack {
                    Button("Deny") { agents.decide(decision, allow: false) }
                        .buttonStyle(.bordered).tint(.red)
                    Button("Allow") { agents.decide(decision, allow: true) }
                        .buttonStyle(.borderedProminent).tint(.green)
                    Button("Allow \(decision.toolName) for this session") { agents.decide(decision, allow: true, forSession: true) }
                        .buttonStyle(.bordered).tint(.green).font(.system(size: 11))
                    Spacer()
                    Button("Decide in terminal") { agents.dismiss(decision) }
                        .buttonStyle(.plain).font(.system(size: 11)).opacity(0.6)
                }
            } else {
                ForEach(decision.questions) { q in
                    Text(q.text).font(.system(size: 12))
                    HStack {
                        ForEach(q.options, id: \.self) { option in
                            Button(option) { agents.decide(decision, allow: true, answers: [q.text: option]) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                Button("Answer in terminal") { agents.dismiss(decision) }
                    .buttonStyle(.plain).font(.system(size: 11)).opacity(0.6)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.5)))
    }
}

struct SessionRow: View {
    @EnvironmentObject var agents: AgentStore
    let session: AgentSession
    @State private var showTimeline = false
    @State private var reply = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                AgentStatusIcon(agent: session.agent, status: session.status, size: 20)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(session.title).font(.system(size: 12, weight: .semibold))
                        if let b = session.branch {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.triangle.branch")
                                Text(b).lineLimit(1)
                            }
                            .font(.system(size: 10)).opacity(0.55)
                        }
                        Spacer()
                        if session.status == "Working" {
                            WorkingIndicator(color: AgentIcon.accent(for: session.agent), bars: 3, height: 9, barWidth: 2)
                        }
                        Text(session.status).font(.system(size: 10)).opacity(0.6)
                        Text(duration).font(.system(size: 10, design: .monospaced)).opacity(0.4)
                        if session.terminal != nil {
                            Image(systemName: "arrow.up.forward.app").font(.system(size: 10)).opacity(0.5)
                        }
                        Button { showTimeline.toggle() } label: {
                            Image(systemName: showTimeline ? "chevron.up" : "chevron.down").font(.system(size: 10))
                        }
                        .buttonStyle(.plain).opacity(0.5)
                    }
                    if !session.activity.isEmpty {
                        Text(session.activity).font(.system(size: 11)).opacity(0.85).lineLimit(2)
                    }
                    if !session.lastPrompt.isEmpty {
                        Text(session.lastPrompt).font(.system(size: 10)).opacity(0.45).lineLimit(1)
                    }
                    if !session.autoAllowed.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.shield")
                            Text("Auto-allowing " + session.autoAllowed.joined(separator: ", "))
                            Button("Stop") { agents.clearAutoAllowed(session) }.buttonStyle(.plain).underline()
                        }
                        .font(.system(size: 10)).foregroundStyle(.green.opacity(0.9))
                    }
                }
            }
            if showTimeline {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(session.timeline.reversed()) { e in
                        HStack(spacing: 6) {
                            Text(e.at, format: .dateTime.hour().minute().second()).font(.system(size: 9, design: .monospaced)).opacity(0.4)
                            Text(e.text).font(.system(size: 10)).opacity(0.75).lineLimit(1)
                        }
                    }
                    if session.timeline.isEmpty { Text("Nothing yet").font(.system(size: 10)).opacity(0.4) }
                }
                .padding(.leading, 30)
            }
            if !session.isBusy {
                HStack(spacing: 6) {
                    TextField("Reply to \(session.agent.capitalized)…", text: $reply)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        .onSubmit { sendReply() }
                    Button { sendReply() } label: { Image(systemName: "paperplane.fill") }
                        .buttonStyle(.plain).opacity(reply.isEmpty ? 0.3 : 0.9).disabled(reply.isEmpty)
                }
                .padding(.leading, 30)
                if !session.replyHint.isEmpty {
                    Text(session.replyHint).font(.system(size: 10)).foregroundStyle(.orange).padding(.leading, 30)
                }
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func sendReply() {
        guard !reply.isEmpty else { return }
        agents.send(reply, to: session)
        reply = ""
    }

    private var duration: String {
        let secs = Int(Date().timeIntervalSince(session.startedAt))
        if secs < 60 { return "\(secs)s" }
        if secs < 3600 { return "\(secs / 60)m" }
        return "\(secs / 3600)h \((secs % 3600) / 60)m"
    }

    private var color: Color {
        switch session.status {
        case "Working": return .green
        case "Waiting for you", "Waiting for approval": return .orange
        case "Failed": return .red
        default: return .gray
        }
    }
}

// MARK: - Music

struct MusicTab: View {
    @EnvironmentObject var music: NowPlayingService

    var body: some View {
        HStack(spacing: 18) {
            Group {
                if let art = music.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: "music.note").font(.system(size: 36)).opacity(0.4)
                    }
                }
            }
            .frame(width: 150, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 6) {
                if let t = music.track {
                    Text(t.title).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                    Text(t.artist).font(.system(size: 13)).opacity(0.8).lineLimit(1)
                    Text(t.album).font(.system(size: 12)).opacity(0.5).lineLimit(1)
                    Text(t.source).font(.system(size: 10)).opacity(0.4).padding(.top, 2)
                } else {
                    Text("Nothing playing").font(.system(size: 15, weight: .semibold))
                    Text("Play something in Spotify or Music.").font(.system(size: 12)).opacity(0.6)
                }
                HStack(spacing: 18) {
                    Button { music.previous() } label: { Image(systemName: "backward.fill") }
                    Button { music.playPause() } label: {
                        Image(systemName: music.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 22))
                    }
                    Button { music.next() } label: { Image(systemName: "forward.fill") }
                }
                .buttonStyle(.plain)
                .font(.system(size: 16))
                .padding(.top, 8)
                .disabled(music.track == nil)
            }
            Spacer()
        }
        .padding(20)
    }
}

// MARK: - Clipboard

struct ClipboardTab: View {
    @EnvironmentObject var clipboard: ClipboardStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(clipboard.items.count) items").font(.system(size: 11)).opacity(0.6)
                Spacer()
                Button("Clear") { clipboard.clear() }
                    .buttonStyle(.plain).font(.system(size: 11)).opacity(0.7)
                    .disabled(clipboard.items.isEmpty)
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            ScrollView {
                LazyVStack(spacing: 4) {
                    if clipboard.items.isEmpty {
                        Text("Copy some text and it will show up here.")
                            .font(.system(size: 12)).opacity(0.5).padding(.top, 40)
                    }
                    ForEach(clipboard.items) { item in
                        ClipboardRow(item: item)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
    }
}

struct ClipboardRow: View {
    @EnvironmentObject var clipboard: ClipboardStore
    @State private var hovering = false
    let item: ClipboardStore.Item

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if clipboard.lastCopiedID == item.id {
                Text("Copied").font(.system(size: 10, weight: .semibold)).foregroundStyle(.green)
            } else if hovering {
                Button { clipboard.remove(item) } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                    .buttonStyle(.plain).opacity(0.6)
            }
        }
        .padding(8)
        .background(Color.white.opacity(hovering ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { clipboard.copy(item) }
        .onHover { hovering = $0 }
    }
}

// MARK: - Tasks (to-dos with optional reminders)

struct RemindersTab: View {
    @EnvironmentObject var reminders: RemindersStore
    @State private var title = ""
    @State private var remind = false
    @State private var due = Date().addingTimeInterval(15 * 60)
    @State private var notifySlack = true

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                HStack {
                    TextField("Add a task…", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Toggle("Remind me", isOn: $remind).toggleStyle(.checkbox).font(.system(size: 11))
                    Button("Add", action: add).buttonStyle(.borderedProminent)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if remind {
                    HStack(spacing: 6) {
                        quick("15 min", 15 * 60)
                        quick("1 hour", 60 * 60)
                        quick("Tomorrow 9:00", nil)
                        DatePicker("", selection: $due, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden().datePickerStyle(.compact).font(.system(size: 11))
                        Spacer()
                        Toggle("Slack", isOn: $notifySlack).toggleStyle(.checkbox).font(.system(size: 11))
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider().overlay(Color.white.opacity(0.1))
            ScrollView {
                LazyVStack(spacing: 4) {
                    if reminders.upcoming.isEmpty && reminders.doneToday.isEmpty {
                        Text("Nothing to do. Add a task above; tick \"Remind me\" to get pinged.")
                            .font(.system(size: 12)).opacity(0.5).padding(.top, 24)
                    }
                    ForEach(reminders.upcoming) { r in TaskRow(item: r) }
                    if !reminders.doneToday.isEmpty {
                        HStack {
                            Text("Done").font(.system(size: 10, weight: .semibold)).opacity(0.5)
                            Spacer()
                            Button("Clear") { reminders.clearDone() }.buttonStyle(.plain).font(.system(size: 10)).opacity(0.5)
                        }
                        .padding(.top, 6)
                        ForEach(reminders.doneToday) { r in TaskRow(item: r) }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
        }
    }

    private func quick(_ label: String, _ seconds: TimeInterval?) -> some View {
        Button(label) {
            if let seconds {
                due = Date().addingTimeInterval(seconds)
            } else {
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date().addingTimeInterval(86400))
                comps.hour = 9; comps.minute = 0
                due = Calendar.current.date(from: comps) ?? due
            }
        }
        .buttonStyle(.bordered).font(.system(size: 11))
    }

    private func add() {
        reminders.add(title: title, due: remind ? due : nil, notifySlack: remind && notifySlack)
        title = ""
    }
}

struct TaskRow: View {
    @EnvironmentObject var reminders: RemindersStore
    let item: RemindersStore.Reminder

    var body: some View {
        HStack(spacing: 8) {
            Button { reminders.toggleDone(item) } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : (item.fired ? "bell.badge.fill" : "circle"))
                    .foregroundStyle(item.done ? .green : (item.fired ? .orange : .white.opacity(0.6)))
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 12)).strikethrough(item.done).opacity(item.done ? 0.5 : 1)
                if let due = item.due, !item.done {
                    HStack(spacing: 6) {
                        Text(due, format: .dateTime.weekday(.abbreviated).hour().minute()).font(.system(size: 10)).opacity(0.5)
                        Text(due, style: .relative).font(.system(size: 10)).opacity(0.4)
                        if item.notifySlack { Image(systemName: "number").font(.system(size: 9)).opacity(0.5) }
                    }
                }
            }
            Spacer()
            Button { reminders.remove(item) } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                .buttonStyle(.plain).opacity(0.5)
        }
        .padding(8)
        .background(Color.white.opacity(item.fired && !item.done ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Focus (Pomodoro)

struct FocusTab: View {
    @EnvironmentObject var pomodoro: PomodoroTimer

    var body: some View {
        HStack(spacing: 24) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 8)
                Circle().trim(from: 0, to: pomodoro.progress)
                    .stroke(phaseColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: pomodoro.progress)
                VStack(spacing: 2) {
                    Text(pomodoro.clock).font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(pomodoro.phase.title).font(.system(size: 11)).opacity(0.6)
                }
            }
            .frame(width: 170, height: 170)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button(pomodoro.isRunning ? "Pause" : (pomodoro.phase == .idle || pomodoro.phase == .finished ? "Start" : "Resume")) {
                        pomodoro.isRunning ? pomodoro.pause() : pomodoro.startOrResume()
                    }
                    .buttonStyle(.borderedProminent).tint(phaseColor)
                    Button("Skip") { pomodoro.skip() }.buttonStyle(.bordered)
                        .disabled(pomodoro.phase == .idle || pomodoro.phase == .finished)
                    Button("Reset") { pomodoro.reset() }.buttonStyle(.bordered)
                }
                HStack(spacing: 4) {
                    ForEach(0..<pomodoro.targetRounds, id: \.self) { i in
                        Circle().fill(i < pomodoro.completedRounds ? phaseColor : Color.white.opacity(0.2)).frame(width: 8, height: 8)
                    }
                    Text("\(pomodoro.completedRounds)/\(pomodoro.targetRounds) rounds · \(pomodoro.completedToday) today")
                        .font(.system(size: 10)).opacity(0.6).padding(.leading, 4)
                }
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    setting("Focus", value: pomodoro.workMinutes, unit: "min", range: 5...90, step: 5) { pomodoro.workMinutes = $0 }
                    setting("Short break", value: pomodoro.breakMinutes, unit: "min", range: 1...30, step: 1) { pomodoro.breakMinutes = $0 }
                    setting("Long break", value: pomodoro.longBreakMinutes, unit: "min", range: 5...60, step: 5) { pomodoro.longBreakMinutes = $0 }
                    setting("Long break every", value: pomodoro.roundsPerSet, unit: "rounds", range: 2...8, step: 1) { pomodoro.roundsPerSet = $0 }
                    setting("Rounds per day", value: pomodoro.targetRounds, unit: "", range: 1...16, step: 1) { pomodoro.targetRounds = $0 }
                }
                .font(.system(size: 11))
                .disabled(pomodoro.phase != .idle && pomodoro.phase != .finished)
            }
            Spacer()
        }
        .padding(20)
    }

    private var phaseColor: Color {
        switch pomodoro.phase {
        case .work: return Color(red: 0.95, green: 0.4, blue: 0.35)
        case .shortBreak, .longBreak: return .green
        default: return Color(red: 0.85, green: 0.47, blue: 0.34)
        }
    }

    private func setting(_ label: String, value: Int, unit: String, range: ClosedRange<Int>, step: Int, set: @escaping (Int) -> Void) -> some View {
        GridRow {
            Text(label).opacity(0.7)
            HStack(spacing: 6) {
                Button { set(max(range.lowerBound, value - step)) } label: { Image(systemName: "minus") }.buttonStyle(.plain).opacity(0.7)
                Text("\(value) \(unit)").frame(minWidth: 60)
                Button { set(min(range.upperBound, value + step)) } label: { Image(systemName: "plus") }.buttonStyle(.plain).opacity(0.7)
            }
        }
    }
}

// MARK: - Account usage (subscription windows) shown at the top of Agents

struct AccountUsageHeader: View {
    @EnvironmentObject var account: AccountUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Plan usage" + (account.plan.map { " · \($0.capitalized)" } ?? "")).font(.system(size: 11, weight: .semibold)).opacity(0.8)
                Spacer()
                if let t = account.updatedAt { Text("updated \(t, style: .relative) ago").font(.system(size: 9)).opacity(0.4) }
                Button { account.refresh() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 10)) }
                    .buttonStyle(.plain).opacity(0.6)
            }
            switch account.state {
            case .ok where !account.windows.isEmpty, .loading where !account.windows.isEmpty:
                ForEach(account.windows) { w in
                    HStack(spacing: 8) {
                        Text(w.label).font(.system(size: 10)).frame(width: 120, alignment: .leading).opacity(0.75)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.1))
                                Capsule().fill(color(w.utilization)).frame(width: max(4, g.size.width * CGFloat(min(w.utilization, 100) / 100)))
                            }
                        }
                        .frame(height: 6)
                        Text("\(Int(w.utilization.rounded()))%").font(.system(size: 10, weight: .semibold)).frame(width: 34, alignment: .trailing)
                        if let r = w.resetsAt {
                            Text("resets \(r, style: .relative)").font(.system(size: 9)).opacity(0.45).frame(width: 110, alignment: .leading)
                        }
                    }
                }
            case .loading, .idle:
                Text("Loading plan usage…").font(.system(size: 10)).opacity(0.5)
            case .noCredentials:
                Text("No Claude Code login found. Sign in with `claude` to see plan usage.").font(.system(size: 10)).opacity(0.5)
            case .expired:
                Text("Claude Code login expired. Run `claude` once to refresh it.").font(.system(size: 10)).opacity(0.5)
            case .error(let msg):
                Text(msg).font(.system(size: 10)).opacity(0.5)
            case .ok:
                Text("No usage windows reported.").font(.system(size: 10)).opacity(0.5)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private func color(_ pct: Double) -> Color {
        pct >= 85 ? .red : (pct >= 60 ? .orange : .green)
    }
}

// MARK: - Calendar

struct CalendarTab: View {
    @EnvironmentObject var calendar: CalendarService

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                switch calendar.access {
                case .denied:
                    Text("Calendar access was denied. Allow it in System Settings → Privacy & Security → Calendars.")
                        .font(.system(size: 12)).opacity(0.6).multilineTextAlignment(.center).padding(.top, 30)
                case .unavailable:
                    Text("Calendar needs the app to run from NotchControl.app (run ./build.sh --install).")
                        .font(.system(size: 12)).opacity(0.6).multilineTextAlignment(.center).padding(.top, 30)
                case .unknown:
                    Text("Waiting for calendar permission…").font(.system(size: 12)).opacity(0.6).padding(.top, 30)
                case .granted:
                    if calendar.events.isEmpty {
                        Text("Nothing scheduled in the next two days.").font(.system(size: 12)).opacity(0.5).padding(.top, 30)
                    }
                    ForEach(calendar.events) { e in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .trailing, spacing: 2) {
                                if e.isAllDay {
                                    Text("All day").font(.system(size: 11, weight: .semibold))
                                } else {
                                    Text(e.start, format: .dateTime.hour().minute()).font(.system(size: 11, weight: .semibold))
                                    Text(e.end, format: .dateTime.hour().minute()).font(.system(size: 10)).opacity(0.5)
                                }
                                Text(e.start, format: .dateTime.weekday(.abbreviated)).font(.system(size: 9)).opacity(0.4)
                            }
                            .frame(width: 52, alignment: .trailing)
                            RoundedRectangle(cornerRadius: 2).fill(e.end > Date() && e.start <= Date() ? Color.green : Color.white.opacity(0.3))
                                .frame(width: 3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(e.calendar).font(.system(size: 10)).opacity(0.5)
                                    if let loc = e.location, !loc.isEmpty {
                                        Text("· " + loc).font(.system(size: 10)).opacity(0.5).lineLimit(1)
                                    }
                                }
                            }
                            Spacer()
                            if let link = e.meetingURL {
                                Button {
                                    NSWorkspace.shared.open(link)
                                } label: {
                                    HStack(spacing: 3) { Image(systemName: "video.fill"); Text("Join") }
                                        .font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(e.start.timeIntervalSinceNow < 10 * 60 ? Color.green.opacity(0.8) : Color.white.opacity(0.15), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            if !e.isAllDay && e.start > Date() {
                                Text(e.start, style: .relative).font(.system(size: 10)).opacity(0.4)
                            }
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Notes

struct NotesTab: View {
    @AppStorage("notes.text") private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextEditor(text: $text)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Text("Saved automatically").font(.system(size: 10)).opacity(0.4)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                }.buttonStyle(.plain).font(.system(size: 10)).opacity(0.7).disabled(text.isEmpty)
                Button("Clear") { text = "" }.buttonStyle(.plain).font(.system(size: 10)).opacity(0.7).disabled(text.isEmpty)
            }
        }
        .padding(12)
    }
}

// MARK: - Shelf

struct ShelfTab: View {
    @EnvironmentObject var shelf: ShelfStore

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 8)]

    var body: some View {
        VStack(spacing: 6) {
            if shelf.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 26)).opacity(0.5)
                    Text("Drop files on the notch to keep them here").font(.system(size: 12))
                    Text("Drag them out again into any app.").font(.system(size: 11)).opacity(0.6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(shelf.items) { item in
                            VStack(spacing: 4) {
                                Image(nsImage: item.icon).resizable().frame(width: 40, height: 40)
                                Text(item.name).font(.system(size: 10)).lineLimit(2).multilineTextAlignment(.center)
                            }
                            .frame(width: 84, height: 72)
                            .padding(4)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                            .onDrag { NSItemProvider(object: item.url as NSURL) }
                            .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
                            .contextMenu {
                                Button("Open") { NSWorkspace.shared.open(item.url) }
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                                Button("Copy path") {
                                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.url.path, forType: .string)
                                }
                                Divider()
                                Button("Remove from shelf") { shelf.remove(item) }
                            }
                            .help(item.url.path)
                        }
                    }
                    .padding(12)
                }
                HStack {
                    Text("\(shelf.items.count) item\(shelf.items.count == 1 ? "" : "s") · drag out to use").font(.system(size: 10)).opacity(0.4)
                    Spacer()
                    Button("Clear") { shelf.clear() }.buttonStyle(.plain).font(.system(size: 10)).opacity(0.7)
                }
                .padding(.horizontal, 12).padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Bluetooth

struct BluetoothTab: View {
    @EnvironmentObject var bluetooth: BluetoothService

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                if bluetooth.devices.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "wave.3.right").font(.system(size: 26)).opacity(0.5)
                        Text("No Bluetooth devices connected").font(.system(size: 12)).opacity(0.6)
                    }
                    .padding(.top, 30)
                }
                ForEach(bluetooth.devices) { d in
                    HStack(spacing: 12) {
                        Image(systemName: d.icon).font(.system(size: 18)).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.name).font(.system(size: 12, weight: .medium))
                            Text(d.kind).font(.system(size: 10)).opacity(0.5)
                        }
                        Spacer()
                        if let b = d.batterySummary {
                            HStack(spacing: 4) {
                                Image(systemName: batteryIcon(d.battery ?? d.batteryLeft ?? 100))
                                Text(b)
                            }
                            .font(.system(size: 11))
                            .opacity(0.8)
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
                if let change = bluetooth.lastChange {
                    Text(change).font(.system(size: 10)).opacity(0.4).padding(.top, 6)
                }
            }
            .padding(12)
        }
    }

    private func batteryIcon(_ level: Int) -> String {
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
