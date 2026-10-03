import Foundation
import Observation

public struct PendingImport: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let fileName: String
    public var progress: Double
}

/// Imports videos one at a time, in the order they were enqueued.
@MainActor @Observable
public final class ImportQueue {
    public private(set) var pending: [PendingImport] = []
    public private(set) var errors: [String] = []
    @ObservationIgnored public var onImported: (WallpaperItem) -> Void

    @ObservationIgnored private let root: URL
    @ObservationIgnored private let existingNames: () -> Set<String>
    @ObservationIgnored private let environment: ImportEnvironment
    @ObservationIgnored private var urls: [UUID: URL] = [:]
    @ObservationIgnored private var worker: Task<Void, Never>?

    public init(
        root: URL,
        existingNames: @escaping () -> Set<String>,
        environment: ImportEnvironment = .live,
        onImported: @escaping (WallpaperItem) -> Void
    ) {
        self.root = root
        self.existingNames = existingNames
        self.environment = environment
        self.onImported = onImported
    }

    public func enqueue(_ newURLs: [URL]) {
        for url in newURLs {
            let entry = PendingImport(id: UUID(), fileName: url.lastPathComponent, progress: 0)
            pending.append(entry)
            urls[entry.id] = url
        }
        guard worker == nil, !pending.isEmpty else { return }
        worker = Task { [weak self] in await self?.drain() }
    }

    public func dismissErrors() { errors.removeAll() }

    /// Suspends until everything enqueued so far has finished.
    public func waitUntilIdle() async {
        while let task = worker { await task.value }
    }

    private func drain() async {
        var imported = Set<String>()
        while let entry = pending.first, let url = urls[entry.id] {
            let taken = existingNames().union(imported)
            let accessing = url.startAccessingSecurityScopedResource()
            do {
                let item = try await importVideo(
                    from: url, root: root, existingNames: taken, environment: environment,
                    progress: { [weak self] value in
                        Task { @MainActor in self?.setProgress(value, for: entry.id) }
                    })
                imported.insert(item.name)
                onImported(item)
            } catch let error as ImportError {
                errors.append(error.message(forFile: entry.fileName))
            } catch {
                errors.append("Importing \(entry.fileName) failed: \(error.localizedDescription)")
            }
            if accessing { url.stopAccessingSecurityScopedResource() }
            urls[entry.id] = nil
            pending.removeAll { $0.id == entry.id }
        }
        worker = nil
    }

    private func setProgress(_ value: Double, for id: UUID) {
        guard let i = pending.firstIndex(where: { $0.id == id }) else { return }
        pending[i].progress = max(pending[i].progress, value)
    }
}
