import SwiftUI
import UniformTypeIdentifiers

struct InspectorView: View {
    @Environment(AppModel.self) private var model
    let onSearchCover: ([Track]) -> Void
    @State private var coverDropTargeted = false

    var body: some View {
        let targets = model.selectedTracks
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if targets.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "sidebar.right").font(.system(size: 36, weight: .light))
                        Text(tr("Выберите трек, чтобы изменить обложку и теги", "Select a track to edit its cover and tags"))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    coverSection(targets)
                    if targets.count == 1, let t = targets.first {
                        TagEditor(track: t)
                        infoSection(t)
                    } else {
                        Text(tr("Выбрано треков: \(targets.count). Обложка будет применена ко всем.", "Selected tracks: \(targets.count). The cover will be applied to all."))
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        model.writeInPlace(targets)
                    } label: {
                        Label(tr("Записать в исходный файл", "Write to Original File"), systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(model.isConverting)
                    .help(tr("Сохранить обложку и теги в сам файл, без конвертации", "Save cover and tags to the original file without conversion"))
                }
            }
            .padding(16)
        }
        .background(.background.secondary)
    }

    @ViewBuilder
    private func coverSection(_ targets: [Track]) -> some View {
        let image = targets.first?.coverImage
        ZStack {
            CoverThumb(image: image, size: 260)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
            if coverDropTargeted {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .frame(width: 260, height: 260)
            }
        }
        .frame(maxWidth: .infinity)
        .onDrop(of: [.image, .fileURL], isTargeted: $coverDropTargeted) { providers in
            handleImageDrop(providers, targets: targets)
        }
        .help(tr("Перетащите сюда картинку, чтобы сделать её обложкой", "Drop an image here to use it as the cover"))
        .contextMenu {
            if let t = targets.first, t.effectiveCoverURL != nil {
                Button(tr("Сохранить картинку как…", "Save Image As…")) { model.saveCoverImage(of: t) }
            }
        }

        if let img = image, let rep = img.representations.first {
            Text("\(rep.pixelsWide) × \(rep.pixelsHigh) px")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }

        Button { onSearchCover(targets) } label: {
            Label(tr("Найти обложку в интернете", "Find Cover Online"), systemImage: "magnifyingglass").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)

        HStack {
            Button { model.chooseCoverFile(for: targets) } label: { Label(tr("Файл…", "File…"), systemImage: "folder") }
            Button { model.pasteCover(for: targets) } label: { Label(tr("Вставить", "Paste"), systemImage: "doc.on.clipboard") }
            Menu {
                Button(tr("Убрать обложку", "Remove Cover")) { model.removeCover(for: targets) }
                Button(tr("Вернуть исходную", "Restore Original")) { model.revertCover(for: targets) }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
    }

    private func handleImageDrop(_ providers: [NSItemProvider], targets: [Track]) -> Bool {
        guard let p = providers.first else { return false }
        if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url, let data = try? Data(contentsOf: url) else { return }
                Task { @MainActor in model.setCover(imageData: data, for: targets) }
            }
            return true
        }
        p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            guard let data else { return }
            Task { @MainActor in model.setCover(imageData: data, for: targets) }
        }
        return true
    }

    private func infoSection(_ t: Track) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tr("Файл", "File")).font(.headline)
            Text(t.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if t.status != .loading {
                Text(t.formatDescription + (t.channels > 0 ? " · \(t.channels == 1 ? tr("моно", "mono") : t.channels == 2 ? tr("стерео", "stereo") : "\(t.channels) \(tr("кан.", "ch."))")" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if case .failed(let msg) = t.status {
                Text(msg).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            if let out = t.outputURL {
                Button(tr("Показать результат в Finder", "Show Result in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([out]) }
                    .buttonStyle(.link).font(.caption)
            }
        }
    }
}

struct TagEditor: View {
    @Bindable var track: Track

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Теги", "Tags")).font(.headline)
            LabeledField(tr("Название", "Title"), text: $track.title)
            LabeledField(tr("Исполнитель", "Artist"), text: $track.artist)
            LabeledField(tr("Альбом", "Album"), text: $track.album)
            if let year = track.extraTags["date"] ?? track.extraTags["year"] {
                Text(tr("Год: \(year)", "Year: \(year)")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct LabeledField: View {
    let label: String
    @Binding var text: String
    init(_ label: String, text: Binding<String>) { self.label = label; self._text = text }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: $text).textFieldStyle(.roundedBorder).labelsHidden()
        }
    }
}
