import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var dropTargeted = false
    @State private var coverSearchTargets: [Track]?

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if !model.ffmpegAvailable { FFmpegMissingBanner() }
            HSplitView {
                trackList
                    .frame(minWidth: 560)
                InspectorView(onSearchCover: { coverSearchTargets = $0 })
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
            }
            Divider()
            SettingsBar()
        }
        .toolbar {
            ToolbarItemGroup {
                Button { model.openFilesPanel() } label: { Label(tr("Добавить", "Add"), systemImage: "plus") }
                    .help(tr("Добавить файлы или папки (⌘O)", "Add files or folders (⌘O)"))
                Button { model.removeSelected() } label: { Label(tr("Убрать", "Remove"), systemImage: "minus") }
                    .disabled(model.selection.isEmpty || model.isConverting)
                    .help(tr("Убрать выбранные из списка", "Remove selected tracks"))
                Button { model.removeAll() } label: { Label(tr("Очистить", "Clear"), systemImage: "trash") }
                    .disabled(model.tracks.isEmpty || model.isConverting)
                    .help(tr("Очистить список", "Clear the list"))
                Button { coverSearchTargets = model.selectedTracks } label: {
                    Label(tr("Найти обложку", "Find Cover"), systemImage: "photo.badge.magnifyingglass")
                }
                .disabled(model.selection.isEmpty)
                .help(tr("Найти обложку в интернете для выбранных треков", "Find cover art online for selected tracks"))
            }
        }
        .sheet(item: Binding(
            get: { coverSearchTargets.map { CoverSearchTargets(tracks: $0) } },
            set: { coverSearchTargets = $0?.tracks }
        )) { targets in
            CoverSearchView(targets: targets.tracks)
        }
        .alert("Tonica", isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private var trackList: some View {
        @Bindable var model = model
        return ZStack {
            Table(model.tracks, selection: $model.selection) {
                TableColumn("") { t in
                    CoverThumb(image: t.coverImage, size: 34)
                }
                .width(42)
                TableColumn(tr("Название", "Title")) { t in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.title).lineLimit(1)
                        Text(t.fileName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .width(min: 160, ideal: 240)
                TableColumn(tr("Исполнитель", "Artist")) { t in Text(t.artist).lineLimit(1) }
                    .width(min: 80, ideal: 140)
                TableColumn(tr("Формат", "Format")) { t in
                    Text(t.status == .loading ? "…" : t.formatDescription)
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 110, ideal: 170)
                TableColumn(tr("Время", "Duration")) { t in
                    Text(t.durationText).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
                .width(52)
                TableColumn(tr("Статус", "Status")) { t in StatusCell(track: t) }
                    .width(min: 90, ideal: 120)
            }
            .contextMenu(forSelectionType: Track.ID.self) { ids in
                let targets = model.tracks.filter { ids.contains($0.id) }
                Button(tr("Найти обложку…", "Find Cover…")) { coverSearchTargets = targets }
                Button(tr("Выбрать обложку из файла…", "Choose Cover File…")) { model.chooseCoverFile(for: targets) }
                Button(tr("Вставить обложку из буфера", "Paste Cover from Clipboard")) { model.pasteCover(for: targets) }
                Button(tr("Убрать обложку", "Remove Cover")) { model.removeCover(for: targets) }
                Divider()
                Button(tr("Записать обложку и теги в файл", "Write Cover and Tags to File")) { model.writeInPlace(targets) }
                Divider()
                Button(tr("Показать в Finder", "Show in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting(targets.map { $0.outputURL ?? $0.url })
                }
            }

            if model.tracks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "waveform.badge.plus")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(.secondary)
                    Text(tr("Перетащите сюда музыку или папки", "Drop music or folders here"))
                        .font(.title3)
                    Text(tr("MP3, M4A, FLAC, ALAC, WAV, AIFF, OGG, Opus и другие", "MP3, M4A, FLAC, ALAC, WAV, AIFF, OGG, Opus and more"))
                        .foregroundStyle(.secondary)
                    Button(tr("Выбрать файлы…", "Choose Files…")) { model.openFilesPanel() }
                        .controlSize(.large)
                }
                .allowsHitTesting(true)
            }

            if dropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .background(Color.accentColor.opacity(0.08))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            loadURLs(from: providers) { model.add(urls: $0) }
            return true
        }
    }
}

struct CoverSearchTargets: Identifiable {
    let id = UUID()
    let tracks: [Track]
}

func loadURLs(from providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
    let group = DispatchGroup()
    var urls: [URL] = []
    let lock = NSLock()
    for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        group.enter()
        _ = p.loadObject(ofClass: URL.self) { url, _ in
            if let url { lock.lock(); urls.append(url); lock.unlock() }
            group.leave()
        }
    }
    group.notify(queue: .main) {
        let sorted = urls.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        MainActor.assumeIsolated { completion(sorted) }
    }
}

struct CoverThumb: View {
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "music.note").foregroundStyle(.secondary)
                        .font(.system(size: size * 0.4))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(3, size * 0.08)))
    }
}

struct StatusCell: View {
    let track: Track

    var body: some View {
        switch track.status {
        case .loading:
            ProgressView().controlSize(.small)
        case .ready:
            if track.hasPendingCoverChange {
                Label(tr("Новая обложка", "New Cover"), systemImage: "photo").foregroundStyle(.blue).font(.callout)
            } else {
                Text(tr("Готов", "Ready")).foregroundStyle(.secondary)
            }
        case .converting:
            ProgressView(value: track.progress).progressViewStyle(.linear)
        case .done:
            Label(tr("Готово", "Done"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let msg):
            Label(tr("Ошибка", "Error"), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .help(msg)
        }
    }
}

struct FFmpegMissingBanner: View {
    @Environment(AppModel.self) private var model
    private let command = "brew install ffmpeg"

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("Не найден ffmpeg — без него конвертация не работает", "ffmpeg was not found — conversion is unavailable")).bold()
                Text(tr("Установите ffmpeg в Терминале командой: ", "Install ffmpeg in Terminal: ")) + Text(command).font(.body.monospaced()) + Text(tr(" (нужен Homebrew: brew.sh)", " (requires Homebrew: brew.sh)"))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(tr("Скопировать команду", "Copy Command")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            }
            Button(tr("Проверить снова", "Check Again")) { model.recheckFFmpeg() }
        }
        .padding(12)
        .background(.orange.opacity(0.12))
    }
}
