import AVKit
import SwiftUI
import WallpaperCore

/// Modal trim editor. AVPlayerView's own trimming bar provides OK/Cancel; the sheet closes
/// when it finishes. It plays its own AVPlayer, never the wallpaper's.
struct TrimSheet: View {
    let url: URL
    let duration: Double
    /// The trim currently applied (already normalized), used to pre-fill the editor.
    let currentTrim: ClosedRange<Double>?
    /// Called with the new trim, nil meaning the whole video.
    let onSave: (ClosedRange<Double>?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phase = TrimPhase.loading

    var body: some View {
        ZStack {
            TrimPlayerView(url: url, currentTrim: currentTrim, onPhase: { phase = $0 }) { outcome in
                if case .ok(let start, let end) = outcome {
                    onSave(TrimRange.normalized(start: start, end: end, duration: duration))
                }
                dismiss()
            }
            if phase != .trimming { overlay }
        }
        .frame(width: 640, height: 400)
    }

    @ViewBuilder private var overlay: some View {
        VStack(spacing: 12) {
            switch phase {
            case .loading:
                ProgressView()
            case .unavailable:
                Text("This video can't be trimmed here").font(.headline)
            case .failed(let message):
                Text("The video couldn't be loaded").font(.headline)
                Text(message).font(.callout).foregroundStyle(.secondary)
            case .trimming:
                EmptyView()
            }
            // The AVKit bar has its own Cancel; this one covers every other state.
            Button(phase == .loading ? "Cancel" : "Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

enum TrimPhase: Equatable {
    case loading, trimming, unavailable
    case failed(String)
}

enum TrimOutcome {
    /// Raw seconds; NaN where AVKit reported no valid time.
    case ok(start: Double, end: Double)
    case cancel
}

/// AVPlayerView that reports when it joins a window (beginTrimming needs one).
private final class TrimPlayerNSView: AVPlayerView {
    var onWindow: (() -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onWindow?() }
    }
}

private struct TrimPlayerView: NSViewRepresentable {
    let url: URL
    let currentTrim: ClosedRange<Double>?
    let onPhase: (TrimPhase) -> Void
    let onFinish: (TrimOutcome) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, currentTrim: currentTrim, onPhase: onPhase, onFinish: onFinish)
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = TrimPlayerNSView()
        view.controlsStyle = .inline
        view.player = context.coordinator.player
        context.coordinator.attach(view)
        view.onWindow = { [weak coordinator = context.coordinator] in coordinator?.tryBeginTrimming() }
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    @MainActor final class Coordinator: NSObject {
        let player: AVPlayer
        private let item: AVPlayerItem
        private let currentTrim: ClosedRange<Double>?
        private let onPhase: (TrimPhase) -> Void
        private let onFinish: (TrimOutcome) -> Void
        private weak var playerView: AVPlayerView?
        private var statusObservation: NSKeyValueObservation?
        private var retryTask: Task<Void, Never>?
        private var started = false
        private var finished = false

        init(url: URL, currentTrim: ClosedRange<Double>?,
             onPhase: @escaping (TrimPhase) -> Void, onFinish: @escaping (TrimOutcome) -> Void) {
            item = AVPlayerItem(asset: AVURLAsset(url: url))
            player = AVPlayer(playerItem: item)
            self.currentTrim = currentTrim
            self.onPhase = onPhase
            self.onFinish = onFinish
            super.init()
            statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in self?.tryBeginTrimming() }
            }
        }

        func attach(_ view: AVPlayerView) { playerView = view }

        /// Called on item status change and when the view gets a window; starts trimming
        /// exactly once, only when all three preconditions hold.
        func tryBeginTrimming() {
            guard !started, !finished else { return }
            switch item.status {
            case .failed:
                started = true
                onPhase(.failed(item.error?.localizedDescription ?? "Unknown error"))
            case .readyToPlay:
                guard let view = playerView, view.window != nil else { return }
                started = true
                beginWhenAble(view, attempts: 20)
            default:
                break
            }
        }

        /// AVPlayerView may flip canBeginTrimming a moment after the item is ready,
        /// so poll briefly before giving up.
        private func beginWhenAble(_ view: AVPlayerView, attempts: Int) {
            if view.canBeginTrimming {
                prefill()
                onPhase(.trimming)
                view.beginTrimming { [weak self] result in
                    Task { @MainActor in self?.finish(result) }
                }
            } else if attempts > 0 {
                retryTask = Task { @MainActor [weak self, weak view] in
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled, let self, let view else { return }
                    self.beginWhenAble(view, attempts: attempts - 1)
                }
            } else {
                onPhase(.unavailable)
            }
        }

        /// Unverified without a human: if AVKit ignores these, the editor opens on the full range.
        private func prefill() {
            guard let currentTrim else { return }
            item.reversePlaybackEndTime = CMTime(seconds: currentTrim.lowerBound, preferredTimescale: 600)
            item.forwardPlaybackEndTime = CMTime(seconds: currentTrim.upperBound, preferredTimescale: 600)
        }

        private func finish(_ result: AVPlayerViewTrimResult) {
            guard !finished else { return }
            finished = true
            switch result {
            case .okButton:
                onFinish(.ok(start: Self.seconds(item.reversePlaybackEndTime),
                             end: Self.seconds(item.forwardPlaybackEndTime)))
            default:
                onFinish(.cancel)
            }
        }

        private static func seconds(_ time: CMTime) -> Double {
            time.isValid && time.isNumeric ? time.seconds : .nan
        }

        func teardown() {
            finished = true
            retryTask?.cancel()
            statusObservation?.invalidate()
            statusObservation = nil
            player.pause()
            player.replaceCurrentItem(with: nil)
            playerView?.player = nil
        }
    }
}
