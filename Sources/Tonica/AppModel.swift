import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    var tracks: [Track] = []
    var selection = Set<Track.ID>()
    var settings = ConversionSettings()
    var isConverting = false
    var ffmpegAvailable = FFmpeg.isAvailable
    var alertMessage: String?
    private var stopRequested = false
    private let stopFlag = StopFlag()

    var selectedTracks: [Track] { tracks.filter { selection.contains($0.id) } }

    var overallProgress: Double {
        let active = tracks.filter { $0.status == .converting || $0.status == .done }
        guard !active.isEmpty else { return 0 }
        return active.reduce(0) { $0 + ($1.status == .done ? 1 : $1.progress) } / Double(active.count)
    }

    func recheckFFmpeg() {
        FFmpeg.relocate()
        ffmpegAvailable = FFmpeg.isAvailable
        if ffmpegAvailable { tracks.filter { $0.status == .loading }.forEach(load) }
    }

    // MARK: Добавление файлов

    func add(urls: [URL]) {
        let existing = Set(tracks.map(\.url.standardizedFileURL))
        var new: [Track] = []
        for url in urls.flatMap(expand) where !existing.contains(url.standardizedFileURL) {
            if new.contains(where: { $0.url == url }) { continue }
            new.append(Track(url: url))
        }
        tracks += new
        if ffmpegAvailable { new.forEach(load) }
    }

    private func expand(_ url: URL) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return [] }
        if !isDir.boolValue {
            return supportedAudioExtensions.contains(url.pathExtension.lowercased()) ? [url] : []
        }
        let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var files: [URL] = []
        while let f = e?.nextObject() as? URL {
            if supportedAudioExtensions.contains(f.pathExtension.lowercased()) { files.append(f) }
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func load(_ track: Track) {
        track.status = .loading
        Task {
            do { try await FFmpeg.probe(track) } catch { track.status = .failed(error.localizedDescription) }
        }
    }

    func openFilesPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.audio, .folder, .mpeg4Movie]
        panel.message = tr("Выберите аудиофайлы или папки с музыкой", "Choose audio files or folders containing music")
        if panel.runModal() == .OK { add(urls: panel.urls) }
    }

    func removeSelected() {
        guard !isConverting else { return }
        tracks.removeAll { selection.contains($0.id) }
        selection.removeAll()
    }

    func removeAll() {
        guard !isConverting else { return }
        tracks.removeAll()
        selection.removeAll()
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = tr("Выбрать", "Choose")
        if panel.runModal() == .OK, let url = panel.url {
            settings.outputFolder = url
            settings.location = .customFolder
        }
    }

    // MARK: Обложки

    func setCover(_ url: URL, for targets: [Track]) {
        for t in targets {
            t.newCoverURL = url
            t.removeCover = false
            t.refreshCoverImage()
        }
    }

    func setCover(imageData: Data, for targets: [Track]) {
        do { setCover(try TempFiles.storeImage(data: imageData), for: targets) } catch { alertMessage = error.localizedDescription }
    }

    func chooseCoverFile(for targets: [Track]) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = tr("Выберите изображение для обложки", "Choose an image for the cover")
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        setCover(imageData: data, for: targets)
    }

    func pasteCover(for targets: [Track]) {
        let pb = NSPasteboard.general
        if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
            setCover(imageData: data, for: targets)
        } else if let url = (pb.readObjects(forClasses: [NSURL.self]) as? [URL])?.first,
                  let data = try? Data(contentsOf: url) {
            setCover(imageData: data, for: targets)
        } else {
            alertMessage = tr("В буфере обмена нет изображения", "There is no image on the clipboard")
        }
    }

    func removeCover(for targets: [Track]) {
        for t in targets {
            t.newCoverURL = nil
            t.removeCover = true
            t.refreshCoverImage()
        }
    }

    func revertCover(for targets: [Track]) {
        for t in targets {
            t.newCoverURL = nil
            t.removeCover = false
            t.refreshCoverImage()
        }
    }

    func saveCoverImage(of track: Track) {
        guard let src = track.effectiveCoverURL else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(track.artist.isEmpty ? track.title : track.artist + " - " + track.album).\(src.pathExtension)"
        if panel.runModal() == .OK, let url = panel.url {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.copyItem(at: src, to: url)
        }
    }

    func writeInPlace(_ targets: [Track]) {
        guard !isConverting else { return }
        isConverting = true
        Task {
            var errors: [String] = []
            for t in targets where t.status != .loading {
                t.status = .converting
                t.progress = 0
                do {
                    try await FFmpeg.writeInPlace(t)
                    if let cover = t.effectiveCoverURL { t.embeddedCoverURL = cover } else { t.embeddedCoverURL = nil }
                    t.newCoverURL = nil
                    t.removeCover = false
                    t.outputURL = t.url
                    t.status = .done
                } catch {
                    t.status = .failed(error.localizedDescription)
                    errors.append("\(t.fileName): \(error.localizedDescription)")
                }
            }
            isConverting = false
            if !errors.isEmpty { alertMessage = errors.joined(separator: "\n") }
        }
    }

    // MARK: Конвертация

    func convertAll() {
        let queue = (selection.isEmpty ? tracks : selectedTracks).filter {
            if case .loading = $0.status { return false }
            if case .failed(let msg) = $0.status, msg.hasPrefix("В файле нет") || msg.hasPrefix("Не удалось прочитать") || msg.hasPrefix("The file has no audio stream") || msg.hasPrefix("Could not read file") { return false }
            return true
        }
        guard !queue.isEmpty, !isConverting else { return }
        if settings.location == .customFolder, settings.outputFolder == nil {
            chooseOutputFolder()
            guard settings.outputFolder != nil else { return }
        }
        isConverting = true
        stopRequested = false
        stopFlag.set(false)
        let stopFlag = self.stopFlag
        queue.forEach { $0.status = .converting; $0.progress = 0; $0.outputURL = nil }

        let s = settings
        let limit = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
        var reserved = Set<String>()
        let jobs: [(Track, URL)] = queue.map { t in
            let out = outputURL(for: t, settings: s, reserved: reserved)
            reserved.insert(out.path)
            return (t, out)
        }

        Task {
            await withTaskGroup(of: Void.self) { group in
                var iterator = jobs.makeIterator()
                func addNext() -> Bool {
                    guard !stopFlag.value, let (track, out) = iterator.next() else { return false }
                    group.addTask { await Self.runJob(track, out, s) }
                    return true
                }
                for _ in 0..<limit { if !addNext() { break } }
                while await group.next() != nil { _ = addNext() }
            }
            for t in queue where t.status == .converting { t.status = .ready; t.progress = 0 }
            isConverting = false
            let done = queue.filter { $0.status == .done }.count
            if done > 0, !stopRequested { NSSound(named: "Glass")?.play() }
        }
    }

    private nonisolated static func runJob(_ track: Track, _ out: URL, _ s: ConversionSettings) async {
        do {
            try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await FFmpeg.convert(track, settings: s, to: out) { p in
                Task { @MainActor in track.progress = p }
            }
            await MainActor.run { track.status = .done; track.progress = 1; track.outputURL = out }
        } catch {
            await MainActor.run { track.status = .failed(error.localizedDescription) }
        }
    }

    func stop() {
        stopRequested = true
        stopFlag.set(true)
        ProcessRegistry.shared.terminateAll()
    }

    private func outputURL(for t: Track, settings s: ConversionSettings, reserved: Set<String>) -> URL {
        let dir = s.location == .customFolder ? (s.outputFolder ?? t.url.deletingLastPathComponent()) : t.url.deletingLastPathComponent()
        let base = t.url.deletingPathExtension().lastPathComponent
        let ext = s.format.fileExtension
        var candidate = dir.appendingPathComponent(base).appendingPathExtension(ext)
        let fm = FileManager.default
        func taken(_ u: URL) -> Bool {
            u.standardizedFileURL == t.url.standardizedFileURL || reserved.contains(u.path)
                || (!s.overwrite && fm.fileExists(atPath: u.path))
        }
        var n = 2
        while taken(candidate) {
            candidate = dir.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    func revealOutputs() {
        let urls = tracks.compactMap(\.outputURL)
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }
}

final class StopFlag: @unchecked Sendable {
    private var flag = false
    private let lock = NSLock()
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    func set(_ v: Bool) { lock.lock(); flag = v; lock.unlock() }
}
