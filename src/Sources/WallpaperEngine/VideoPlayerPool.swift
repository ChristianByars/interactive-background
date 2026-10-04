import AVFoundation
import WallpaperCore

/// What an `AVPlayerLooper` may be built with for a loaded duration.
/// `AVPlayerLooper` raises an uncatchable ObjC exception on a zero duration or an empty or
/// out-of-bounds range, so every looper goes through `compute`.
enum LooperRange: Equatable {
    /// Zero, negative or non-numeric duration: never build a looper.
    case unplayable
    /// Loop the whole item (`timeRange: .invalid`).
    case whole
    /// Loop this sub-range; non-empty and inside `0...duration`.
    case trimmed(CMTimeRange)

    static func compute(duration: CMTime, settings: VideoSettings) -> LooperRange {
        guard duration.isNumeric, duration > .zero else { return .unplayable }
        guard let trim = settings.loopRange(duration: duration.seconds) else { return .whole }
        let wanted = CMTimeRange(
            start: CMTime(seconds: trim.lowerBound, preferredTimescale: 600),
            end: CMTime(seconds: trim.upperBound, preferredTimescale: 600))
        let bounds = CMTimeRange(start: .zero, duration: duration)
        let clipped = CMTimeRangeGetIntersection(wanted, otherRange: bounds)
        guard clipped.isValid, clipped.duration.isNumeric, clipped.duration > .zero else { return .whole }
        return .trimmed(clipped)
    }

    var timeRange: CMTimeRange {
        if case .trimmed(let range) = self { return range }
        return .invalid
    }
}

/// One `AVQueuePlayer` + `AVPlayerLooper` per item, shared by every display showing it
/// (each display adds its own `AVPlayerLayer`). Plays while any attached display is unpaused.
@MainActor
final class VideoPlayerPool {
    private final class Entry {
        let itemID: String
        let player = AVQueuePlayer()
        var fileURL: URL
        var asset: AVURLAsset
        var settings: VideoSettings
        var duration: CMTime?
        var looper: AVPlayerLooper?
        var appliedRange: LooperRange?
        var attached: Set<DisplayID> = []
        var paused: Set<DisplayID> = []
        var failed = false
        /// Bumped on every reload and on teardown so a late duration load or looper status is dropped.
        var generation = 0
        var loadTask: Task<Void, Never>?
        var statusObservation: NSKeyValueObservation?
        var failureObserver: NSObjectProtocol?

        init(itemID: String, fileURL: URL, settings: VideoSettings) {
            self.itemID = itemID
            self.fileURL = fileURL
            self.asset = AVURLAsset(url: fileURL)
            self.settings = settings
        }

        var shouldPlay: Bool { looper != nil && !failed && !attached.subtracting(paused).isEmpty }
    }

    private var entries: [String: Entry] = [:]

    /// Called once per failed item (load error, zero duration, looper or item failure).
    var onFailure: ((String) -> Void)?

    /// `paused` is the display's pause state at attach time, so a display joining a globally
    /// paused item never causes a play/pause flicker on the shared player.
    func acquire(itemID: String, fileURL: URL, settings: VideoSettings, displayID: DisplayID,
                 paused: Bool = false) -> AVQueuePlayer {
        if let entry = entries[itemID] {
            entry.attached.insert(displayID)
            if paused { entry.paused.insert(displayID) } else { entry.paused.remove(displayID) }
            if entry.fileURL != fileURL {
                // Same item, new file: reload on the same player so existing layers keep working.
                Log.playback.notice("pool \(itemID, privacy: .public): file changed, reloading")
                entry.fileURL = fileURL
                entry.asset = AVURLAsset(url: fileURL)
                entry.settings = settings
                load(entry)
                applyPlayerSettings(entry)
            } else if entry.settings != settings {
                apply(itemID: itemID, settings: settings)
            } else {
                updatePlayback(entry)
            }
            Log.playback.info("pool \(itemID, privacy: .public): display \(displayID, privacy: .public) attached (\(entry.attached.count) total)")
            return entry.player
        }

        let entry = Entry(itemID: itemID, fileURL: fileURL, settings: settings)
        entry.attached.insert(displayID)
        if paused { entry.paused.insert(displayID) }
        entry.player.preventsDisplaySleepDuringVideoPlayback = false
        // actionAtItemEnd is managed by the looper; do not override it.
        entry.failureObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] note in
            let item = note.object as? AVPlayerItem
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            MainActor.assumeIsolated {
                // The looper plays copies of its template item, so match against those.
                guard let self, let item, let entry = self.entries[itemID],
                      entry.looper?.loopingPlayerItems.contains(item) == true else { return }
                self.fail(entry, "item failed to play to end: \(error?.localizedDescription ?? "unknown")")
            }
        }
        entries[itemID] = entry
        applyPlayerSettings(entry)
        load(entry)
        Log.playback.notice("pool \(itemID, privacy: .public): created for display \(displayID, privacy: .public)")
        return entry.player
    }

    func release(itemID: String, displayID: DisplayID) {
        guard let entry = entries[itemID] else { return }
        entry.attached.remove(displayID)
        entry.paused.remove(displayID)
        guard entry.attached.isEmpty else {
            updatePlayback(entry)
            return
        }
        entry.generation += 1
        entry.loadTask?.cancel()
        removeLooper(entry)
        entry.player.pause()
        if let observer = entry.failureObserver { NotificationCenter.default.removeObserver(observer) }
        entry.failureObserver = nil
        entries.removeValue(forKey: itemID)
        Log.playback.notice("pool \(itemID, privacy: .public): torn down")
    }

    func apply(itemID: String, settings: VideoSettings) {
        guard let entry = entries[itemID] else { return }
        entry.settings = settings
        applyPlayerSettings(entry)
        // While the duration is still loading, the load picks up `entry.settings` when it lands.
        guard !entry.failed, let duration = entry.duration, entry.looper != nil else { return }
        if LooperRange.compute(duration: duration, settings: settings) != entry.appliedRange {
            buildLooper(entry)
        }
    }

    func setPaused(itemID: String, displayID: DisplayID, paused: Bool) {
        guard let entry = entries[itemID], entry.attached.contains(displayID) else { return }
        if paused { entry.paused.insert(displayID) } else { entry.paused.remove(displayID) }
        updatePlayback(entry)
    }

    func isPaused(itemID: String, displayID: DisplayID) -> Bool {
        entries[itemID]?.paused.contains(displayID) ?? false
    }

    // MARK: Private

    private func applyPlayerSettings(_ entry: Entry) {
        let player = entry.player
        player.defaultRate = Float(entry.settings.speed)
        player.isMuted = !entry.settings.audioEnabled
        player.volume = Float(entry.settings.volume)
        // defaultRate does not change an item that is already playing.
        if entry.shouldPlay { player.play() }
    }

    private func load(_ entry: Entry) {
        entry.generation += 1
        let generation = entry.generation
        entry.loadTask?.cancel()
        removeLooper(entry)
        entry.duration = nil
        entry.failed = false
        let asset = entry.asset
        entry.loadTask = Task { [weak self, weak entry] in
            do {
                let duration = try await asset.load(.duration)
                guard let self, let entry, self.isCurrent(entry, generation) else { return }
                entry.duration = duration
                self.buildLooper(entry)
            } catch {
                guard let self, let entry, self.isCurrent(entry, generation) else { return }
                self.fail(entry, "duration load failed: \(error.localizedDescription)")
            }
        }
    }

    private func isCurrent(_ entry: Entry, _ generation: Int) -> Bool {
        entries[entry.itemID] === entry && entry.generation == generation
    }

    /// Builds (or rebuilds, on a trim change) the looper on the entry's existing player.
    private func buildLooper(_ entry: Entry) {
        guard let duration = entry.duration else { return }
        let range = LooperRange.compute(duration: duration, settings: entry.settings)
        guard range != .unplayable else {
            fail(entry, "duration \(duration.seconds) s is not playable")
            return
        }
        removeLooper(entry)
        let looper = AVPlayerLooper(
            player: entry.player, templateItem: AVPlayerItem(asset: entry.asset), timeRange: range.timeRange)
        entry.looper = looper
        entry.appliedRange = range
        let generation = entry.generation
        let itemID = entry.itemID
        entry.statusObservation = looper.observe(\.status, options: [.initial, .new]) { @Sendable [weak self] looper, _ in
            guard looper.status == .failed else { return }
            let message = looper.error?.localizedDescription ?? "unknown"
            let looperID = ObjectIdentifier(looper)
            // KVO can fire on any thread; handle it on the main actor, and only for the current looper.
            Task { @MainActor [weak self] in
                guard let self, let entry = self.entries[itemID], entry.generation == generation,
                      let current = entry.looper, ObjectIdentifier(current) == looperID else { return }
                self.fail(entry, "looper failed: \(message)")
            }
        }
        Log.playback.notice("pool \(itemID, privacy: .public): looper ready, duration \(duration.seconds, format: .fixed(precision: 2)) s, range \(Self.describe(range), privacy: .public), speed \(entry.settings.speed, format: .fixed(precision: 2))x, audio \(entry.settings.audioEnabled ? "on" : "off", privacy: .public)")
        updatePlayback(entry)
    }

    private func removeLooper(_ entry: Entry) {
        entry.statusObservation?.invalidate()
        entry.statusObservation = nil
        entry.looper?.disableLooping()
        entry.looper = nil
        entry.appliedRange = nil
        entry.player.removeAllItems()
    }

    private func updatePlayback(_ entry: Entry) {
        let wasPlaying = entry.player.rate != 0
        if entry.shouldPlay {
            entry.player.play()
        } else {
            entry.player.pause()  // the layer keeps showing the current frame
        }
        if wasPlaying != entry.shouldPlay {
            Log.playback.info("pool \(entry.itemID, privacy: .public): \(entry.shouldPlay ? "playing" : "paused", privacy: .public) (\(entry.attached.count) attached, \(entry.paused.count) paused)")
        }
    }

    private func fail(_ entry: Entry, _ reason: String) {
        guard !entry.failed else { return }
        entry.failed = true
        entry.loadTask?.cancel()
        removeLooper(entry)
        entry.player.pause()
        Log.playback.error("pool \(entry.itemID, privacy: .public): \(reason, privacy: .public)")
        onFailure?(entry.itemID)
    }

    private static func describe(_ range: LooperRange) -> String {
        switch range {
        case .unplayable: return "unplayable"
        case .whole: return "whole"
        case .trimmed(let r): return String(format: "%.2f-%.2f s", r.start.seconds, r.end.seconds)
        }
    }
}
