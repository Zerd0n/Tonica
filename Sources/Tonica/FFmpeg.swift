import AppKit
import Foundation

struct ProcessResult {
    let status: Int32
    let stdout: Data
    let stderr: String
}

struct FFmpegError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class ProcessRegistry: @unchecked Sendable {
    static let shared = ProcessRegistry()
    private var processes: [ObjectIdentifier: Process] = [:]
    private let lock = NSLock()

    func add(_ p: Process) { lock.lock(); processes[ObjectIdentifier(p)] = p; lock.unlock() }
    func remove(_ p: Process) { lock.lock(); processes[ObjectIdentifier(p)] = nil; lock.unlock() }
    func terminateAll() {
        lock.lock(); let all = Array(processes.values); lock.unlock()
        all.forEach { if $0.isRunning { $0.terminate() } }
    }
}

enum FFmpeg {
    static var ffmpegPath: String? = locate("ffmpeg")
    static var ffprobePath: String? = locate("ffprobe")
    static var isAvailable: Bool { ffmpegPath != nil && ffprobePath != nil }

    private static var encoderList: String?

    static func relocate() {
        ffmpegPath = locate("ffmpeg")
        ffprobePath = locate("ffprobe")
        encoderList = nil
    }

    static func locate(_ name: String) -> String? {
        var dirs: [String] = []
        // сначала ищем ffmpeg внутри .app
        if let res = Bundle.main.resourcePath { dirs.append(res + "/ffmpeg/bin") }
        dirs += ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"]
        for dir in dirs {
            let path = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    static func hasEncoder(_ name: String) async -> Bool {
        if encoderList == nil, let ff = ffmpegPath {
            let r = try? await run(ff, ["-hide_banner", "-encoders"])
            encoderList = r.map { String(decoding: $0.stdout, as: UTF8.self) } ?? ""
        }
        return encoderList?.contains(" \(name) ") ?? false
    }

    // MARK: Запуск процесса

    static func run(_ exe: String, _ args: [String], onStdoutLine: ((String) -> Void)? = nil) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = args
                let outPipe = Pipe(), errPipe = Pipe()
                p.standardOutput = outPipe
                p.standardError = errPipe
                p.standardInput = FileHandle.nullDevice
                do { try p.run() } catch { cont.resume(throwing: error); return }
                ProcessRegistry.shared.add(p)

                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                var outData = Data()
                let handle = outPipe.fileHandleForReading
                if let onLine = onStdoutLine {
                    var buffer = Data()
                    while true {
                        let chunk = handle.availableData
                        if chunk.isEmpty { break }
                        outData.append(chunk)
                        buffer.append(chunk)
                        while let nl = buffer.firstIndex(of: 0x0A) {
                            let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
                            buffer.removeSubrange(buffer.startIndex...nl)
                            onLine(line)
                        }
                    }
                } else {
                    outData = handle.readDataToEndOfFile()
                }
                group.wait()
                p.waitUntilExit()
                ProcessRegistry.shared.remove(p)
                cont.resume(returning: ProcessResult(status: p.terminationStatus, stdout: outData,
                                                     stderr: String(decoding: errData, as: UTF8.self)))
            }
        }
    }

    static func lastErrorLine(_ stderr: String) -> String {
        let lines = stderr.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.last ?? tr("неизвестная ошибка ffmpeg", "unknown ffmpeg error")
    }

    // MARK: Анализ файла

    static func probe(_ track: Track) async throws {
        guard let probe = ffprobePath else { throw FFmpegError(message: tr("ffprobe не найден", "ffprobe was not found")) }
        let r = try await run(probe, ["-v", "error", "-print_format", "json", "-show_format", "-show_streams", track.url.path])
        guard r.status == 0,
              let json = try JSONSerialization.jsonObject(with: r.stdout) as? [String: Any] else {
            throw FFmpegError(message: tr("Не удалось прочитать файл: \(lastErrorLine(r.stderr))", "Could not read file: \(lastErrorLine(r.stderr))"))
        }
        let format = json["format"] as? [String: Any] ?? [:]
        let streams = json["streams"] as? [[String: Any]] ?? []

        guard let audio = streams.first(where: { $0["codec_type"] as? String == "audio" }) else {
            throw FFmpegError(message: tr("В файле нет аудиодорожки", "The file has no audio stream"))
        }

        var tagDict: [String: String] = [:]
        for source in [audio["tags"], format["tags"]] {
            for (k, v) in source as? [String: Any] ?? [:] {
                if let s = v as? String { tagDict[k.lowercased()] = s }
            }
        }

        let codec = audio["codec_name"] as? String ?? "?"
        let losslessCodecs: Set<String> = ["flac", "alac", "ape", "wavpack", "tta", "mlp", "truehd"]
        let bits = Int(audio["bits_per_raw_sample"] as? String ?? "") ?? (audio["bits_per_sample"] as? Int ?? 0)
        let sampleFmt = audio["sample_fmt"] as? String ?? ""
        var cover: (index: Int, codec: String)?
        for s in streams where s["codec_type"] as? String == "video" {
            let disp = s["disposition"] as? [String: Any] ?? [:]
            if (disp["attached_pic"] as? Int) == 1, let idx = s["index"] as? Int {
                cover = (idx, s["codec_name"] as? String ?? "")
                break
            }
        }

        var extracted: URL?
        if let cover { extracted = try? await extractCover(from: track.url, streamIndex: cover.index, codec: cover.codec) }
        let coverURL = extracted
        let tags = tagDict

        await MainActor.run {
            track.codec = codec
            track.duration = Double(format["duration"] as? String ?? "") ?? Double(audio["duration"] as? String ?? "") ?? 0
            track.sampleRate = Int(audio["sample_rate"] as? String ?? "") ?? 0
            track.channels = audio["channels"] as? Int ?? 0
            track.bitrate = Int(audio["bit_rate"] as? String ?? "") ?? Int(format["bit_rate"] as? String ?? "") ?? 0
            track.isLosslessSource = losslessCodecs.contains(codec) || codec.hasPrefix("pcm_")
            track.bitsPerSample = bits > 0 ? bits : (sampleFmt.hasPrefix("s16") ? 16 : (sampleFmt.hasPrefix("s32") ? 24 : 0))
            if let t = tags["title"], !t.isEmpty { track.title = t }
            track.artist = tags["artist"] ?? tags["album_artist"] ?? ""
            track.album = tags["album"] ?? ""
            track.extraTags = tags.filter { !["title", "artist", "album"].contains($0.key) && !ignoredTagKeys.contains($0.key) }
            track.embeddedCoverURL = coverURL
            track.refreshCoverImage()
            track.status = .ready
        }
    }

    static func extractCover(from url: URL, streamIndex: Int, codec: String) async throws -> URL {
        guard let ff = ffmpegPath else { throw FFmpegError(message: tr("ffmpeg не найден", "ffmpeg was not found")) }
        let ext = codec == "png" ? "png" : "jpg"
        let out = TempFiles.newURL(ext: ext)
        var args = ["-v", "error", "-y", "-i", url.path, "-map", "0:\(streamIndex)", "-frames:v", "1"]
        if codec == "mjpeg" || codec == "png" { args += ["-c:v", "copy"] } else { args += ["-q:v", "2"] }
        args += ["-update", "1", out.path]
        let r = try await run(ff, args)
        guard r.status == 0, FileManager.default.fileExists(atPath: out.path) else {
            throw FFmpegError(message: lastErrorLine(r.stderr))
        }
        return out
    }

    // MARK: Конвертация

    static func convert(_ track: Track, settings s: ConversionSettings, to output: URL,
                        progress: @escaping (Double) -> Void) async throws {
        guard let ff = ffmpegPath else { throw FFmpegError(message: tr("ffmpeg не найден", "ffmpeg was not found")) }
        let fmt = s.format

        let snapshot = await MainActor.run {
            (cover: track.removeCover ? nil : (track.newCoverURL ?? (s.keepCover ? track.embeddedCoverURL : nil)),
             tags: track.extraTags, title: track.title, artist: track.artist, album: track.album,
             bits: track.bitsPerSample, lossless: track.isLosslessSource, duration: track.duration)
        }
        let cover = fmt.supportsCover ? snapshot.cover : nil

        var a = ["-hide_banner", "-nostdin", "-y", "-i", track.url.path]
        if let cover { a += ["-i", cover.path] }
        a += ["-map", "0:a:0"]
        if let cover {
            a += ["-map", "1:v:0", "-c:v", "copy", "-disposition:v:0", "attached_pic"]
            if cover.pathExtension == "png" || fmt != .flac {
                a += ["-metadata:s:v", "comment=Cover (front)"]
            }
        }
        a += ["-map_metadata", "0"]
        for (k, v) in snapshot.tags { a += ["-metadata", "\(k)=\(v)"] }
        a += ["-metadata", "title=\(snapshot.title)", "-metadata", "artist=\(snapshot.artist)", "-metadata", "album=\(snapshot.album)"]

        let depth: Int = s.bitDepth != 0 ? s.bitDepth : ((snapshot.lossless && snapshot.bits >= 24) ? 24 : 16)

        switch fmt {
        case .mp3:
            a += ["-c:a", "libmp3lame", "-b:a", "\(s.bitrate)k", "-id3v2_version", "3", "-write_id3v1", "1"]
        case .aac:
            let enc = await hasEncoder("aac_at") ? "aac_at" : "aac"
            a += ["-c:a", enc, "-b:a", "\(s.bitrate)k"]
        case .alac:
            a += ["-c:a", "alac", "-sample_fmt", depth == 24 ? "s32p" : "s16p"]
        case .flac:
            a += ["-c:a", "flac", "-compression_level", "\(s.flacLevel)", "-sample_fmt", depth == 24 ? "s32" : "s16"]
        case .wav:
            a += ["-c:a", depth == 24 ? "pcm_s24le" : "pcm_s16le"]
        case .aiff:
            a += ["-c:a", depth == 24 ? "pcm_s24be" : "pcm_s16be", "-write_id3v2", "1"]
        case .opus:
            a += ["-c:a", "libopus", "-b:a", "\(s.bitrate)k", "-vbr", "on"]
        case .ogg:
            if await hasEncoder("libvorbis") {
                a += ["-c:a", "libvorbis", "-b:a", "\(s.bitrate)k"]
            } else {
                // нет libvorbis, используем встроенный vorbis (-q:a 0-10)
                let q = min(10, max(3, (s.bitrate - 64) / 32 + 2))
                a += ["-c:a", "vorbis", "-strict", "-2", "-q:a", "\(q)", "-ac", "2"]
            }
        }
        if fmt.isLossless, depth == 24, fmt == .flac || fmt == .alac {
            a += ["-bits_per_raw_sample", "24"]
        }
        if s.sampleRate > 0 { a += ["-ar", "\(s.sampleRate)"] }
        a += ["-progress", "pipe:1", "-nostats", output.path]

        let duration = snapshot.duration
        let r = try await run(ff, a) { line in
            guard duration > 0, line.hasPrefix("out_time_us="),
                  let us = Double(line.dropFirst("out_time_us=".count)) else { return }
            progress(min(1, us / 1_000_000 / duration))
        }
        if r.status != 0 {
            try? FileManager.default.removeItem(at: output)
            throw FFmpegError(message: r.status == 15 ? tr("Остановлено", "Stopped") : lastErrorLine(r.stderr))
        }
    }

    static func writeInPlace(_ track: Track) async throws {
        guard let ff = ffmpegPath else { throw FFmpegError(message: tr("ffmpeg не найден", "ffmpeg was not found")) }
        let ext = track.url.pathExtension.lowercased()
        let snapshot = await MainActor.run {
            (cover: track.effectiveCoverURL, tags: track.extraTags, title: track.title, artist: track.artist, album: track.album)
        }
        let canCover = coverCapableExtensions.contains(ext)
        if snapshot.cover != nil, !canCover {
            throw FFmpegError(message: tr("Формат .\(ext) не поддерживает обложки — сконвертируйте в MP3, M4A или FLAC", "The .\(ext) format does not support cover art — convert to MP3, M4A or FLAC"))
        }

        let tmp = track.url.deletingLastPathComponent()
            .appendingPathComponent(".tonica-\(UUID().uuidString.prefix(8)).\(ext)")
        var a = ["-hide_banner", "-nostdin", "-y", "-i", track.url.path]
        if let cover = snapshot.cover { a += ["-i", cover.path] }
        a += ["-map", "0:a"]
        if snapshot.cover != nil { a += ["-map", "1:v:0", "-disposition:v:0", "attached_pic"] }
        a += ["-c", "copy", "-map_metadata", "0"]
        for (k, v) in snapshot.tags { a += ["-metadata", "\(k)=\(v)"] }
        a += ["-metadata", "title=\(snapshot.title)", "-metadata", "artist=\(snapshot.artist)", "-metadata", "album=\(snapshot.album)"]
        if ext == "mp3" { a += ["-id3v2_version", "3"] }
        if ext == "aif" || ext == "aiff" { a += ["-write_id3v2", "1"] }
        a.append(tmp.path)

        let r = try await run(ff, a)
        guard r.status == 0 else {
            try? FileManager.default.removeItem(at: tmp)
            throw FFmpegError(message: lastErrorLine(r.stderr))
        }
        _ = try FileManager.default.replaceItemAt(track.url, withItemAt: tmp)
    }
}

enum TempFiles {
    static let dir: URL = {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("Tonica", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static func newURL(ext: String) -> URL {
        dir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    }

    // jpeg/png сохраняем как есть, остальное перегоняем в jpeg
    static func storeImage(data: Data) throws -> URL {
        let bytes = [UInt8](data.prefix(8))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            let url = newURL(ext: "jpg"); try data.write(to: url); return url
        }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            let url = newURL(ext: "png"); try data.write(to: url); return url
        }
        guard let image = NSImage(data: data) else { throw FFmpegError(message: tr("Не удалось открыть изображение", "Could not open the image")) }
        return try storeImage(image)
    }

    static func storeImage(_ image: NSImage) throws -> URL {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) else {
            throw FFmpegError(message: tr("Не удалось преобразовать изображение", "Could not convert the image"))
        }
        let url = newURL(ext: "jpg")
        try jpeg.write(to: url)
        return url
    }

    static func cleanup() { try? FileManager.default.removeItem(at: dir) }
}
