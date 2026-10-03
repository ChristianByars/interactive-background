import AVFoundation
import CoreVideo
import Foundation

/// Generates tiny fixture files at runtime so no binaries are committed.
enum TestVideo {
    struct WriterError: Error { let message: String }

    /// Writes a real H.264 `.mov` with `frames` solid-colour frames at `fps`.
    static func make(
        at url: URL, frames: Int = 30, fps: Int = 30,
        size: CGSize = CGSize(width: 64, height: 64)
    ) async throws {
        try? FileManager.default.removeItem(at: url)
        let width = Int(size.width) & ~1, height = Int(size.height) & ~1
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ])
        guard writer.canAdd(input) else { throw WriterError(message: "cannot add input") }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? WriterError(message: "startWriting failed")
        }
        writer.startSession(atSourceTime: .zero)

        for i in 0..<frames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }
            let buffer = try makeBuffer(width: width, height: height, shade: UInt8(i * 7 % 256))
            let time = CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps))
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw writer.error ?? WriterError(message: "append failed at frame \(i)")
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? WriterError(message: "finishWriting status \(writer.status.rawValue)")
        }
    }

    private static func makeBuffer(width: Int, height: Int, shade: UInt8) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard let buffer else { throw WriterError(message: "pixel buffer") }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<height {
                let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
                for x in 0..<width {
                    row[x * 4] = shade
                    row[x * 4 + 1] = UInt8(truncatingIfNeeded: x * 4)
                    row[x * 4 + 2] = UInt8(truncatingIfNeeded: y * 4)
                    row[x * 4 + 3] = 255
                }
            }
        }
        return buffer
    }

    /// A `.mov` that is just random bytes (unplayable).
    @discardableResult
    static func makeBadMov(at url: URL, bytes: Int = 4096) throws -> URL {
        var data = Data(count: bytes)
        for i in 0..<bytes { data[i] = UInt8.random(in: 0...255) }
        try data.write(to: url)
        return url
    }

    /// A plain text file (wrong format).
    @discardableResult
    static func makeNotes(at url: URL) throws -> URL {
        try Data("just some notes".utf8).write(to: url)
        return url
    }
}

/// A unique temp directory, removed on deinit.
final class TempDir {
    let url: URL
    init(_ label: String = "ImportTests") {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }

    func file(_ name: String) -> URL { url.appendingPathComponent(name) }
    func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(relative).path)
    }
}
