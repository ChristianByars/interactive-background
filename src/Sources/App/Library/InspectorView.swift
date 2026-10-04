import AVFoundation
import SwiftUI
import WallpaperCore

/// Settings for the item shown on the selected display.
struct InspectorView: View {
    let model: AppModel

    private var item: WallpaperItem? {
        guard let display = model.selectedDisplay else { return nil }
        let id = model.store.resolve(display: display, main: model.mainDisplayID)
        return model.store.items.first { $0.id == id }
    }

    var body: some View {
        if let item {
            // New identity per item resets the name draft, duration and dialogs.
            ItemInspector(model: model, item: item).id(item.id)
        } else {
            Text("No wallpaper selected")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ItemInspector: View {
    let model: AppModel
    let item: WallpaperItem

    @State private var nameDraft: String
    @State private var duration: Double?
    @State private var confirmRemove = false
    @State private var showTrimSheet = false

    init(model: AppModel, item: WallpaperItem) {
        self.model = model
        self.item = item
        _nameDraft = State(initialValue: item.name)
    }

    private var isMissing: Bool { model.store.missingIDs.contains(item.id) }

    /// Read from the store, not `item`, so rapid slider events never build on a stale copy.
    private var settings: VideoSettings {
        model.store.items.first { $0.id == item.id }?.settings ?? VideoSettings()
    }

    private var videoURL: URL? { model.store.videoURL(for: item) }

    private func binding<T>(_ keyPath: WritableKeyPath<VideoSettings, T>) -> Binding<T> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                var updated = settings
                updated[keyPath: keyPath] = value
                model.updateSettings(itemID: item.id, updated)
            })
    }

    var body: some View {
        Form {
            Section("Name") { nameSection }
            if item.isBuiltin {
                Section { Label("Built-in", systemImage: "lock").foregroundStyle(.secondary) }
            } else {
                if isMissing {
                    Section { Label("File missing", systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
                Group {
                    Section("Video") { videoSection }
                    Section("Sound") { soundSection }
                    Section("Loop range") { loopSection }
                }
                .disabled(isMissing)
                Section {
                    Button("Remove from library…", role: .destructive) { confirmRemove = true }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Remove “\(item.name)” from the library?", isPresented: $confirmRemove
        ) {
            Button("Remove", role: .destructive) { model.remove(itemID: item.id) }
        } message: {
            Text("The imported copy of the video is deleted. The original file is not touched.")
        }
        .sheet(isPresented: $showTrimSheet) {
            if let url = videoURL, let duration {
                TrimSheet(url: url, duration: duration,
                          currentTrim: settings.loopRange(duration: duration)) { trim in
                    var updated = settings
                    updated.trim = trim
                    model.updateSettings(itemID: item.id, updated)
                }
            }
        }
        .task(id: item.id) { await loadDuration() }
        .onChange(of: item.name) { _, name in nameDraft = name }
    }

    // MARK: Sections

    @ViewBuilder private var nameSection: some View {
        if item.isBuiltin {
            Text(item.name)
        } else {
            TextField("Name", text: $nameDraft)
                .labelsHidden()
                .onSubmit(commitName)
        }
    }

    @ViewBuilder private var videoSection: some View {
        Picker("Fit", selection: binding(\.fit)) {
            ForEach(FitMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }
        .pickerStyle(.segmented)
        LabeledContent("Speed") {
            HStack {
                Slider(value: binding(\.speed), in: VideoSettings.speedRange, step: 0.05)
                Text(String(format: "%.2f×", settings.speed))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }

    @ViewBuilder private var soundSection: some View {
        Toggle("Sound", isOn: binding(\.audioEnabled))
        LabeledContent("Volume") {
            Slider(value: binding(\.volume), in: VideoSettings.volumeRange)
        }
        .disabled(!settings.audioEnabled)
    }

    @ViewBuilder private var loopSection: some View {
        let range = duration.flatMap { settings.loopRange(duration: $0) }
        if let duration, let range {
            TrimBar(range: range, duration: duration)
            Text("\(TrimBar.format(range.lowerBound)) – \(TrimBar.format(range.upperBound))")
                .font(.callout.monospacedDigit())
        } else if duration == nil, let trim = settings.trim {
            // Duration unavailable: show the stored trim without a bar.
            Text("\(TrimBar.format(trim.lowerBound)) – \(TrimBar.format(trim.upperBound))")
                .font(.callout.monospacedDigit())
        } else {
            Text("Whole video").foregroundStyle(.secondary)
        }
        HStack {
            Button("Edit trim…") { showTrimSheet = true }
                .disabled(duration == nil || videoURL == nil)
            Button("Reset") {
                var updated = settings
                updated.trim = nil
                model.updateSettings(itemID: item.id, updated)
            }
            .disabled(settings.trim == nil)
        }
    }

    // MARK: Actions

    private func commitName() {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            nameDraft = item.name
        } else {
            model.rename(itemID: item.id, to: name)
            nameDraft = name
        }
    }

    private func loadDuration() async {
        duration = nil
        guard !isMissing, let url = videoURL else { return }
        guard let time = try? await AVURLAsset(url: url).load(.duration) else { return }
        let seconds = time.seconds
        if seconds.isFinite, seconds > 0 { duration = seconds }
    }
}
