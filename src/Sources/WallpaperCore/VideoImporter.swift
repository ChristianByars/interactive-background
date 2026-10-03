import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImportError: Error, Equatable, Sendable {
    /// Payload: the file name.
    case unsupportedFormat(String)
    /// Payload: the file name.
    case notPlayable(String)
    case insufficientSpace(needed: Int64)
    /// Payload: the failure reason.
    case copyFailed(String)

    /// User-facing text. `name` is used by the cases whose payload is not the file name.
    public func message(forFile name: String) -> String {
        switch self {
        case .unsupportedFormat(let file):
            return "\(file) isn't a format macOS can play. Use MP4, MOV or M4V."
        case .notPlayable(let file):
            return "\(file) can't be played (unsupported codec or copy-protected)."
        case .insufficientSpace(let needed):
            let size = ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)
            return "Not enough space to copy \(name) (needs \(size))."
        case .copyFailed(let reason):
            return "Copying \(name) failed: \(reason)"
        }
    }

    /// User-facing text for cases that carry the file name themselves.
    public var message: String { message(forFile: "the file") }
}

public struct ImportEnvironment: Sendable {
    public var availableCapacity: @Sendable (URL) throws -> Int64
    public var copy: @Sendable (URL, URL) throws -> Void
    /// `(video, destination JPEG)`.
    public var makeThumbnail: @Sendable (URL, URL) async throws -> Void

    public init(
        availableCapacity: @escaping @Sendable (URL) throws -> Int64,
        copy: @escaping @Sendable (URL, URL) throws -> Void,
        makeThumbnail: @escaping @Sendable (URL, URL) async throws -> Void
    ) {
        self.availableCapacity = availableCapacity
        self.copy = copy
        self.makeThumbnail = makeThumbnail
    }

    public static let live = ImportEnvironment(
        availableCapacity: { url in
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage ?? Int64.max
        },
        copy: { src, dst in try FileManager.default.copyItem(at: src, to: dst) },
        makeThumbnail: { video, destination in
            try await writeThumbnail(of: video, to: destination)
        })
}

private struct ThumbnailError: Error {}

private func writeThumbnail(of video: URL, to destination: URL) async throws {
    let asset = AVURLAsset(url: video)
    let duration = try await asset.load(.duration).seconds
    let seconds = duration.isFinite && duration > 0 ? min(1.0, duration / 2) : 0
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 480, height: 480)
    let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
    guard let dest = CGImageDestinationCreateWithURL(
        destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw ThumbnailError() }
    CGImageDestinationAddImage(
        dest, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { throw ThumbnailError() }
}

/// `root` may not exist yet on a fresh install; volume queries need an existing path.
private func nearestExistingAncestor(of url: URL) -> URL {
    var candidate = url
    while !FileManager.default.fileExists(atPath: candidate.path) {
        let parent = candidate.deletingLastPathComponent()
        if parent.path == candidate.path { break }
        candidate = parent
    }
    return candidate
}

private func uniqueName(_ base: String, avoiding taken: Set<String>) -> String {
    guard taken.contains(base) else { return base }
    var n = 2
    while taken.contains("\(base) \(n)") { n += 1 }
    return "\(base) \(n)"
}

/// Imports one video into `<root>/Videos/<uuid>/`. Never auto-applies; the caller adds the item.
public func importVideo(
    from src: URL,
    root: URL,
    existingNames: Set<String>,
    environment: ImportEnvironment = .live,
    progress: @Sendable (Double) -> Void
) async throws -> WallpaperItem {
    let fileName = src.lastPathComponent
    let fm = FileManager.default

    // 1. Format check.
    guard let type = UTType(filenameExtension: src.pathExtension), type.conforms(to: .movie) else {
        throw ImportError.unsupportedFormat(fileName)
    }

    // 2. Playability: playable, not DRM-protected, and has a video track.
    let asset = AVURLAsset(url: src)
    do {
        let (playable, _, protected) = try await asset.load(.isPlayable, .duration, .hasProtectedContent)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard playable, !protected, !tracks.isEmpty else { throw ImportError.notPlayable(fileName) }
    } catch {
        throw ImportError.notPlayable(fileName)
    }

    // 3. Free space.
    let total = (try? src.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
    do {
        let available = try environment.availableCapacity(nearestExistingAncestor(of: root))
        if available < total { throw ImportError.insufficientSpace(needed: total) }
    } catch let error as ImportError {
        throw error
    } catch {
        throw ImportError.copyFailed(error.localizedDescription)
    }

    // 4. Copy into a fresh folder; any failure from here removes the whole folder.
    let id = UUID().uuidString
    let folder = root.appendingPathComponent("Videos/\(id)", isDirectory: true)
    let final = folder.appendingPathComponent(fileName)
    let partial = folder.appendingPathComponent(fileName + ".partial")
    do {
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        progress(0)

        // The blocking copy runs off the cooperative pool; we poll the .partial size meanwhile.
        let done = LockedFlag()
        let copyTask = Task.detached(priority: .utility) { () -> Result<Void, Error> in
            defer { done.set() }
            return Result { try environment.copy(src, partial) }
        }
        var ticks = 0
        while !done.isSet {
            try? await Task.sleep(for: .milliseconds(20))
            ticks += 1
            if ticks % 10 == 0, total > 0, !done.isSet,
               let size = (try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize) {
                progress(min(Double(size) / Double(total), 1))
            }
        }
        do { try await copyTask.value.get() } catch { throw ImportError.copyFailed(error.localizedDescription) }
        do { try fm.moveItem(at: partial, to: final) } catch {
            throw ImportError.copyFailed(error.localizedDescription)
        }
        progress(1)

        // 5. Thumbnail; failure is not fatal.
        let thumb = folder.appendingPathComponent("thumb.jpg")
        do { try await environment.makeThumbnail(final, thumb) } catch {
            try? fm.removeItem(at: thumb)
        }
    } catch {
        try? fm.removeItem(at: folder)
        throw error
    }

    let base = src.deletingPathExtension().lastPathComponent
    return WallpaperItem(
        id: id, name: uniqueName(base, avoiding: existingNames),
        source: .video(path: "Videos/\(id)/\(fileName)"), settings: VideoSettings())
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}
