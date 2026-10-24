import AppKit
import SwiftUI

/// Reads the current track from Music.app and Spotify over AppleScript.
/// (MediaRemote is closed to third-party apps on modern macOS.)
final class NowPlayingService: ObservableObject {
    enum Source: String {
        case spotify = "com.spotify.client"
        case music = "com.apple.Music"
    }

    struct Track: Equatable {
        var title: String
        var artist: String
        var album: String
        var artworkURL: String
        var duration: Double
    }

    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var source: Source?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: Color = .white
    @Published private(set) var position: Double = 0
    @Published private(set) var positionDate = Date()

    private let queue = DispatchQueue(label: "island.nowplaying")
    private var scripts: [Source: NSAppleScript] = [:]
    private var timer: Timer?

    func start() {
        poll()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func currentPosition(at date: Date) -> Double {
        guard let track else { return 0 }
        let p = position + (isPlaying ? date.timeIntervalSince(positionDate) : 0)
        return min(max(0, p), track.duration)
    }

    #if DEBUG
    func setPreview(_ track: Track, playing: Bool) {
        self.track = track; isPlaying = playing; source = .music; position = track.duration / 3
    }
    #endif

    // MARK: Controls

    func playPause() {
        send("playpause")
        position = currentPosition(at: Date())
        positionDate = Date()
        isPlaying.toggle()
    }
    func seek(to seconds: Double) {
        position = seconds
        positionDate = Date()
        send("set player position to \(seconds)")
    }

    func next() { send("next track") }
    func previous() { send("previous track") }

    func openSource() {
        guard let source,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.rawValue) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func send(_ command: String) {
        guard let source else { return }
        queue.async { [weak self] in
            var err: NSDictionary?
            NSAppleScript(source: "tell application id \"\(source.rawValue)\" to \(command)")?.executeAndReturnError(&err)
            if let err { NSLog("NotchIsland: '\(command)' failed: \(err)") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.poll() }
        }
    }

    // MARK: Polling

    private struct Snapshot {
        var source: Source
        var playing: Bool
        var track: Track?
        var position: Double
    }

    private func poll() {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let candidates = [Source.spotify, .music].filter { running.contains($0.rawValue) }
        queue.async { [weak self] in
            guard let self else { return }
            var best: Snapshot?
            for source in candidates {
                guard let snap = self.fetch(source), snap.track != nil else { continue }
                if snap.playing { best = snap; break }
                if best == nil { best = snap }
            }
            DispatchQueue.main.async { self.apply(best) }
        }
    }

    private func script(for source: Source) -> NSAppleScript? {
        if let s = scripts[source] { return s }
        let durationExpr = source == .spotify ? "(duration of ct) / 1000" : "duration of ct"
        let artExpr = source == .spotify ? "artwork url of ct" : "\"\""
        let src = """
        tell application id "\(source.rawValue)"
            set s to player state as string
            if s is "stopped" then return {s}
            set ct to current track
            return {s, name of ct, artist of ct, album of ct, \(artExpr), \(durationExpr), player position}
        end tell
        """
        guard let s = NSAppleScript(source: src) else { return nil }
        var err: NSDictionary?
        guard s.compileAndReturnError(&err) else { return nil }
        scripts[source] = s
        return s
    }

    private func fetch(_ source: Source) -> Snapshot? {
        guard let script = script(for: source) else { return nil }
        var err: NSDictionary?
        let d = script.executeAndReturnError(&err)
        if err != nil || d.numberOfItems < 1 { return nil }
        let state = d.atIndex(1)?.stringValue ?? "stopped"
        guard d.numberOfItems >= 7 else { return Snapshot(source: source, playing: false, track: nil, position: 0) }
        let track = Track(title: d.atIndex(2)?.stringValue ?? "",
                          artist: d.atIndex(3)?.stringValue ?? "",
                          album: d.atIndex(4)?.stringValue ?? "",
                          artworkURL: d.atIndex(5)?.stringValue ?? "",
                          duration: Self.number(d.atIndex(6)))
        return Snapshot(source: source, playing: state == "playing", track: track, position: Self.number(d.atIndex(7)))
    }

    private static func number(_ d: NSAppleEventDescriptor?) -> Double {
        guard let d else { return 0 }
        if let s = d.stringValue, let v = Double(s.replacingOccurrences(of: ",", with: ".")) { return v }
        return d.doubleValue
    }

    private func apply(_ snap: Snapshot?) {
        guard let snap, let newTrack = snap.track else {
            if track != nil || isPlaying {
                withAnimation(IslandModel.spring) { track = nil; isPlaying = false; source = nil; artwork = nil }
            }
            return
        }
        let changed = newTrack.title != track?.title || newTrack.album != track?.album || snap.source != source
        withAnimation(IslandModel.spring) {
            source = snap.source
            track = newTrack
            isPlaying = snap.playing
        }
        position = snap.position
        positionDate = Date()
        if changed { loadArtwork(source: snap.source, track: newTrack) }
    }

    private func loadArtwork(source: Source, track: Track) {
        let deliver: (NSImage?) -> Void = { [weak self] image in
            DispatchQueue.main.async {
                guard let self, self.track?.title == track.title else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.artwork = image
                    self.accent = image?.vibrantAverageColor.map(Color.init(nsColor:)) ?? .white
                }
            }
        }
        if source == .spotify, let url = URL(string: track.artworkURL) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                deliver(data.flatMap(NSImage.init(data:)))
            }.resume()
        } else if source == .music {
            queue.async {
                var err: NSDictionary?
                let d = NSAppleScript(source: "tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track")?
                    .executeAndReturnError(&err)
                deliver(err == nil ? d.flatMap { NSImage(data: $0.data) } : nil)
            }
        } else {
            deliver(nil)
        }
    }
}

extension NSImage {
    /// Average colour of the artwork, pushed bright enough to read on black.
    var vibrantAverageColor: NSColor? {
        guard let tiff = tiffRepresentation, let ci = CIImage(data: tiff),
              let filter = CIFilter(name: "CIAreaAverage",
                                    parameters: [kCIInputImageKey: ci, kCIInputExtentKey: CIVector(cgRect: ci.extent)]),
              let out = filter.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()])
            .render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                    format: .RGBA8, colorSpace: nil)
        let c = NSColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.usingColorSpace(.deviceRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: min(1, s * 1.2), brightness: max(b, 0.75), alpha: 1)
    }
}
