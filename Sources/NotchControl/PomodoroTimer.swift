import Foundation

/// Pomodoro: work rounds separated by short breaks, a long break every few rounds.
final class PomodoroTimer: ObservableObject {
    enum Phase: String { case idle, work, shortBreak, longBreak, finished
        var title: String {
            switch self {
            case .idle: return "Ready"
            case .work: return "Focus"
            case .shortBreak: return "Short break"
            case .longBreak: return "Long break"
            case .finished: return "All rounds done"
            }
        }
    }

    enum Key {
        static let work = "pomodoro.workMinutes", shortBreak = "pomodoro.breakMinutes", longBreak = "pomodoro.longBreakMinutes"
        static let roundsPerSet = "pomodoro.roundsPerSet", target = "pomodoro.targetRounds"
        static let doneCount = "pomodoro.doneCount", doneDate = "pomodoro.doneDate"
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var isRunning = false
    @Published private(set) var completedRounds = 0       // this set of rounds (resets with Reset)
    @Published private(set) var completedToday = 0

    var onPhaseChange: ((Phase) -> Void)?

    private var endDate: Date?
    private var pausedRemaining: TimeInterval?
    private var timer: Timer?
    private let d = UserDefaults.standard

    // Settings
    var workMinutes: Int { get { max(1, d.integer(forKey: Key.work)) } set { d.set(newValue, forKey: Key.work); objectWillChange.send() } }
    var breakMinutes: Int { get { max(1, d.integer(forKey: Key.shortBreak)) } set { d.set(newValue, forKey: Key.shortBreak); objectWillChange.send() } }
    var longBreakMinutes: Int { get { max(1, d.integer(forKey: Key.longBreak)) } set { d.set(newValue, forKey: Key.longBreak); objectWillChange.send() } }
    var roundsPerSet: Int { get { max(1, d.integer(forKey: Key.roundsPerSet)) } set { d.set(newValue, forKey: Key.roundsPerSet); objectWillChange.send() } }
    var targetRounds: Int { get { max(1, d.integer(forKey: Key.target)) } set { d.set(newValue, forKey: Key.target); objectWillChange.send() } }

    init() {
        d.register(defaults: [Key.work: 25, Key.shortBreak: 5, Key.longBreak: 15, Key.roundsPerSet: 4, Key.target: 8])
        let today = Self.dayKey(Date())
        completedToday = d.string(forKey: Key.doneDate) == today ? d.integer(forKey: Key.doneCount) : 0
        remaining = TimeInterval(workMinutes * 60)
    }

    var phaseDuration: TimeInterval {
        switch phase {
        case .work, .idle, .finished: return TimeInterval(workMinutes * 60)
        case .shortBreak: return TimeInterval(breakMinutes * 60)
        case .longBreak: return TimeInterval(longBreakMinutes * 60)
        }
    }

    var progress: Double { phaseDuration > 0 ? 1 - remaining / phaseDuration : 0 }

    var clock: String {
        let r = max(0, Int(remaining.rounded()))
        return String(format: "%02d:%02d", r / 60, r % 60)
    }

    // MARK: Controls

    func startOrResume() {
        if phase == .idle || phase == .finished {
            if phase == .finished { completedRounds = 0 }
            begin(.work)
        } else if let p = pausedRemaining {
            endDate = Date().addingTimeInterval(p)
            pausedRemaining = nil
            run()
        }
    }

    func pause() {
        guard isRunning else { return }
        pausedRemaining = remaining
        timer?.invalidate(); timer = nil
        isRunning = false
    }

    func reset() {
        timer?.invalidate(); timer = nil
        isRunning = false
        pausedRemaining = nil
        endDate = nil
        completedRounds = 0
        phase = .idle
        remaining = TimeInterval(workMinutes * 60)
    }

    func skip() {
        guard phase != .idle, phase != .finished else { return }
        advance(countRound: false)
    }

    // MARK: Internals

    private func begin(_ p: Phase) {
        phase = p
        remaining = phaseDuration
        endDate = Date().addingTimeInterval(remaining)
        pausedRemaining = nil
        run()
        onPhaseChange?(p)
    }

    private func run() {
        timer?.invalidate()
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }

    private func tick() {
        guard let end = endDate else { return }
        remaining = end.timeIntervalSinceNow
        if remaining <= 0 {
            remaining = 0
            advance(countRound: true)
        }
    }

    private func advance(countRound: Bool) {
        timer?.invalidate(); timer = nil
        isRunning = false
        switch phase {
        case .work:
            if countRound {
                completedRounds += 1
                completedToday += 1
                d.set(completedToday, forKey: Key.doneCount)
                d.set(Self.dayKey(Date()), forKey: Key.doneDate)
            }
            if completedRounds >= targetRounds {
                phase = .finished
                remaining = 0
                onPhaseChange?(.finished)
            } else {
                begin(completedRounds % roundsPerSet == 0 ? .longBreak : .shortBreak)
            }
        case .shortBreak, .longBreak:
            begin(.work)
        default:
            break
        }
    }

    private static func dayKey(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }
}
