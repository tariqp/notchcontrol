import AppKit
import Foundation

/// Polls Spotify and Music through AppleScript and fetches album artwork.
final class NowPlayingService: ObservableObject {
    struct Track: Equatable {
        var title: String
        var artist: String
        var album: String
        var source: String      // "Spotify" or "Music"
        var artworkURL: String?
    }

    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?

    private var timer: Timer?
    private let queue = DispatchQueue(label: "notchcontrol.nowplaying")
    private var artworkTask: Task<Void, Never>?

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.poll() }
    }

    func poll() {
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.query()
            DispatchQueue.main.async { self.apply(result.track, playing: result.playing) }
        }
    }

    // MARK: Controls

    func playPause() { control("playpause") }
    func next() { control("next track") }
    func previous() { control("previous track") }

    private func control(_ verb: String) {
        guard let app = track?.source ?? firstRunningPlayer() else { return }
        queue.async { [weak self] in
            guard let self else { return }
            _ = self.runAppleScript("tell application \"\(app)\" to \(verb)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.poll() }
        }
    }

    // MARK: Query

    private func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private func firstRunningPlayer() -> String? {
        if isRunning("com.spotify.client") { return "Spotify" }
        if isRunning("com.apple.Music") { return "Music" }
        return nil
    }

    private func query() -> (track: Track?, playing: Bool) {
        if isRunning("com.spotify.client") {
            let script = """
            tell application "Spotify"
                set st to player state as string
                if st is "stopped" then return "stopped"
                return st & linefeed & (name of current track) & linefeed & (artist of current track) & linefeed & (album of current track) & linefeed & (artwork url of current track)
            end tell
            """
            if let out = runAppleScript(script), let parsed = parse(out, source: "Spotify") { return parsed }
        }
        if isRunning("com.apple.Music") {
            let script = """
            tell application "Music"
                set st to player state as string
                if st is "stopped" then return "stopped"
                return st & linefeed & (name of current track) & linefeed & (artist of current track) & linefeed & (album of current track)
            end tell
            """
            if let out = runAppleScript(script), let parsed = parse(out, source: "Music") { return parsed }
        }
        return (nil, false)
    }

    private func parse(_ output: String, source: String) -> (track: Track?, playing: Bool)? {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let state = lines.first, state != "stopped", lines.count >= 4 else { return nil }
        let track = Track(title: lines[1], artist: lines[2], album: lines[3], source: source,
                          artworkURL: lines.count > 4 && !lines[4].isEmpty ? lines[4] : nil)
        return (track, state == "playing")
    }

    private func runAppleScript(_ script: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        input.fileHandleForWriting.write(script.data(using: .utf8)!)
        try? input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines)
    }

    // MARK: Apply + artwork

    @MainActor
    private func setArtwork(_ image: NSImage?, for t: Track) {
        if track == t { artwork = image }
    }

    private func apply(_ newTrack: Track?, playing: Bool) {
        isPlaying = playing
        guard newTrack != track else { return }
        track = newTrack
        artwork = nil
        artworkTask?.cancel()
        guard let t = newTrack else { return }
        artworkTask = Task { [weak self] in
            let image = await ArtworkLookup.image(for: t)
            guard !Task.isCancelled else { return }
            await self?.setArtwork(image, for: t)
        }
    }
}

/// Album artwork: the player's own URL when it offers one, otherwise the public iTunes Search API.
enum ArtworkLookup {
    private static var cache: [String: NSImage] = [:]
    private static var misses = Set<String>()
    private static let lock = NSLock()

    static func image(for track: NowPlayingService.Track) async -> NSImage? {
        let key = "\(track.artist)|\(track.album)|\(track.title)".lowercased()
        switch cached(key) {
        case .hit(let image): return image
        case .miss: return nil
        case .unknown: break
        }

        var image: NSImage?
        if let direct = track.artworkURL, let url = URL(string: direct) {
            image = await download(url)
        }
        if image == nil, !track.album.isEmpty {
            image = await search(term: "\(track.artist) \(track.album)", entity: "album", artist: track.artist)
        }
        if image == nil, !track.title.isEmpty {
            image = await search(term: "\(track.artist) \(track.title)", entity: "song", artist: track.artist)
        }

        remember(key, image)
        return image
    }

    private enum CacheState { case hit(NSImage), miss, unknown }

    private static func cached(_ key: String) -> CacheState {
        lock.lock(); defer { lock.unlock() }
        if let image = cache[key] { return .hit(image) }
        return misses.contains(key) ? .miss : .unknown
    }

    private static func remember(_ key: String, _ image: NSImage?) {
        lock.lock(); defer { lock.unlock() }
        if let image { cache[key] = image } else { misses.insert(key) }
    }

    private static func search(term: String, entity: String, artist: String) async -> NSImage? {
        guard var comps = URLComponents(string: "https://itunes.apple.com/search") else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "limit", value: "5"),
        ]
        guard let url = comps.url else { return nil }
        let response = try? await URLSession.shared.data(from: url)
        guard let data = response?.0,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let results = json["results"] as? [[String: Any]], !results.isEmpty else { return nil }
        let match = results.first { ($0["artistName"] as? String)?.caseInsensitiveCompare(artist) == .orderedSame } ?? results[0]
        guard let small = match["artworkUrl100"] as? String,
              let url = URL(string: small.replacingOccurrences(of: "100x100", with: "600x600")) else { return nil }
        return await download(url)
    }

    private static func download(_ url: URL) async -> NSImage? {
        let response = try? await URLSession.shared.data(from: url)
        return response.flatMap { NSImage(data: $0.0) }
    }
}
