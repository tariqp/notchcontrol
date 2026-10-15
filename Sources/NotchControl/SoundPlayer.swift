import AppKit
import Foundation

/// Plays macOS system sounds for app events. Sounds and volume are chosen in Settings.
enum SoundPlayer {
    enum Event: String, CaseIterable, Identifiable {
        case approval, waiting, finished, failed, reminder, bluetooth, focusStart, breakStart
        var id: String { rawValue }

        var title: String {
            switch self {
            case .approval: return "Agent asks for permission"
            case .waiting: return "Agent is waiting for you"
            case .finished: return "Agent finished"
            case .failed: return "Agent failed"
            case .reminder: return "Reminder is due"
            case .bluetooth: return "Bluetooth device connected"
            case .focusStart: return "Pomodoro: focus round starts"
            case .breakStart: return "Pomodoro: break starts"
            }
        }

        var defaultSound: String {
            switch self {
            case .approval: return "Ping"
            case .waiting: return "Purr"
            case .finished: return "Hero"
            case .failed: return "Basso"
            case .reminder: return "Glass"
            case .bluetooth: return "Pop"
            case .focusStart: return "Blow"
            case .breakStart: return "Submarine"
            }
        }

        var key: String { "sound.\(rawValue)" }
    }

    static let enabledKey = "soundsEnabled"
    static let volumeKey = "soundVolume"
    static let none = "None"

    /// Names of the sounds shipped with macOS, e.g. Glass, Ping, Hero.
    static let systemSounds: [String] = {
        let dir = "/System/Library/Sounds"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return files.filter { $0.hasSuffix(".aiff") }.map { ($0 as NSString).deletingPathExtension }.sorted()
    }()

    static func registerDefaults() {
        var defaults: [String: Any] = [enabledKey: true, volumeKey: 0.6]
        for e in Event.allCases { defaults[e.key] = e.defaultSound }
        UserDefaults.standard.register(defaults: defaults)
    }

    static func soundName(for event: Event) -> String {
        UserDefaults.standard.string(forKey: event.key) ?? event.defaultSound
    }

    static func play(_ event: Event) {
        let d = UserDefaults.standard
        guard d.bool(forKey: enabledKey) else { return }
        play(named: soundName(for: event))
    }

    /// Plays a sound by name right away (used for previews in Settings too).
    static func play(named name: String) {
        guard name != none, let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.volume = Float(UserDefaults.standard.double(forKey: volumeKey))
        sound.play()
    }
}
