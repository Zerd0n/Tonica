import AppKit
import Foundation
import Observation

enum OutputFormat: String, CaseIterable, Identifiable {
    case mp3, aac, alac, flac, wav, aiff, opus, ogg

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mp3: "MP3"
        case .aac: "AAC (M4A)"
        case .alac: "Apple Lossless (ALAC)"
        case .flac: "FLAC"
        case .wav: "WAV"
        case .aiff: "AIFF"
        case .opus: "Opus"
        case .ogg: "Ogg Vorbis"
        }
    }

    var fileExtension: String {
        switch self {
        case .mp3: "mp3"
        case .aac, .alac: "m4a"
        case .flac: "flac"
        case .wav: "wav"
        case .aiff: "aiff"
        case .opus: "opus"
        case .ogg: "ogg"
        }
    }

    var isLossless: Bool {
        switch self {
        case .alac, .flac, .wav, .aiff: true
        default: false
        }
    }

    var supportsCover: Bool {
        switch self {
        case .mp3, .aac, .alac, .flac, .aiff: true
        default: false
        }
    }

    var bitrates: [Int] {
        switch self {
        case .mp3: [128, 192, 256, 320]
        case .aac: [128, 192, 256, 320]
        case .opus: [96, 128, 160, 192, 256]
        case .ogg: [128, 192, 256, 320]
        default: []
        }
    }

    var defaultBitrate: Int {
        switch self {
        case .opus: 160
        case .aac: 256
        default: 320
        }
    }
}

enum OutputLocation: String, CaseIterable, Identifiable {
    case nextToSource, customFolder
    var id: String { rawValue }
}

struct ConversionSettings {
    var format: OutputFormat = .flac
    var bitrate: Int = 320
    var sampleRate: Int = 0      // 0 = как в исходнике
    var bitDepth: Int = 0        // 0 = авто
    var flacLevel: Int = 8
    var location: OutputLocation = .nextToSource
    var outputFolder: URL?
    var overwrite = false
    var keepCover = true
}

enum TrackStatus: Equatable {
    case loading, ready, converting, done, failed(String)
}

let supportedAudioExtensions: Set<String> = [
    "mp3", "m4a", "m4b", "mp4", "aac", "alac", "flac", "wav", "wave", "aif", "aiff",
    "aifc", "ogg", "oga", "opus", "wma", "ape", "wv", "dsf", "dff", "caf", "mka", "webm", "ac3", "tta",
]

let coverCapableExtensions: Set<String> = ["mp3", "m4a", "m4b", "mp4", "flac", "aif", "aiff"]

let ignoredTagKeys: Set<String> = [
    "encoder", "major_brand", "minor_version", "compatible_brands", "creation_time",
    "handler_name", "vendor_id", "encoded_by", "itunsmpb", "itunnorm", "itunes_cddb_ids",
]

@Observable
final class Track: Identifiable {
    let id = UUID()
    let url: URL

    var codec = ""
    var duration: Double = 0
    var sampleRate = 0
    var bitsPerSample = 0
    var bitrate = 0
    var channels = 0
    var isLosslessSource = false

    var title = ""
    var artist = ""
    var album = ""
    var extraTags: [String: String] = [:]

    var embeddedCoverURL: URL?
    var newCoverURL: URL?
    var removeCover = false
    var coverImage: NSImage?

    var status: TrackStatus = .loading
    var progress: Double = 0
    var outputURL: URL?

    init(url: URL) {
        self.url = url
        self.title = url.deletingPathExtension().lastPathComponent
    }

    var fileName: String { url.lastPathComponent }

    var effectiveCoverURL: URL? {
        if removeCover { return nil }
        return newCoverURL ?? embeddedCoverURL
    }

    var hasPendingCoverChange: Bool { newCoverURL != nil || (removeCover && embeddedCoverURL != nil) }

    func refreshCoverImage() {
        coverImage = effectiveCoverURL.flatMap { NSImage(contentsOf: $0) }
    }

    var formatDescription: String {
        var parts = [codec.hasPrefix("pcm_") ? "PCM" : codec.uppercased()]
        if sampleRate > 0 {
            let khz = Double(sampleRate) / 1000
            parts.append(khz.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(khz)) \(tr("кГц", "kHz"))" : String(format: "%.1f %@", khz, tr("кГц", "kHz")))
        }
        if isLosslessSource, bitsPerSample > 0 {
            parts.append("\(bitsPerSample) \(tr("бит", "bit"))")
        } else if bitrate > 0 {
            parts.append("\(bitrate / 1000) \(tr("кбит/с", "kbps"))")
        }
        return parts.joined(separator: " · ")
    }

    var durationText: String {
        guard duration > 0 else { return "—" }
        let s = Int(duration.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
