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
                        Text("Выберите трек, чтобы изменить обложку и теги")
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
                        Text("Выбрано треков: \(targets.count). Обложка будет применена ко всем.")
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        model.writeInPlace(targets)
                    } label: {
                        Label("Записать в исходный файл", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(model.isConverting)
                    .help("Сохранить обложку и теги в сам файл, без конвертации")
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
        .help("Перетащите сюда картинку, чтобы сделать её обложкой")
        .contextMenu {
            if let t = targets.first, t.effectiveCoverURL != nil {
                Button("Сохранить картинку как…") { model.saveCoverImage(of: t) }
            }
        }

        if let img = image, let rep = img.representations.first {
            Text("\(rep.pixelsWide) × \(rep.pixelsHigh) px")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }

        Button { onSearchCover(targets) } label: {
            Label("Найти обложку в интернете", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)

        HStack {
            Button { model.chooseCoverFile(for: targets) } label: { Label("Файл…", systemImage: "folder") }
            Button { model.pasteCover(for: targets) } label: { Label("Вставить", systemImage: "doc.on.clipboard") }
            Menu {
                Button("Убрать обложку") { model.removeCover(for: targets) }
                Button("Вернуть исходную") { model.revertCover(for: targets) }
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
            Text("Файл").font(.headline)
            Text(t.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if t.status != .loading {
                Text(t.formatDescription + (t.channels > 0 ? " · \(t.channels == 1 ? "моно" : t.channels == 2 ? "стерео" : "\(t.channels) кан.")" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if case .failed(let msg) = t.status {
                Text(msg).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            if let out = t.outputURL {
                Button("Показать результат в Finder") { NSWorkspace.shared.activateFileViewerSelecting([out]) }
                    .buttonStyle(.link).font(.caption)
            }
        }
    }
}

struct TagEditor: View {
    @Bindable var track: Track

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Теги").font(.headline)
            LabeledField("Название", text: $track.title)
            LabeledField("Исполнитель", text: $track.artist)
            LabeledField("Альбом", text: $track.album)
            if let year = track.extraTags["date"] ?? track.extraTags["year"] {
                Text("Год: \(year)").font(.caption).foregroundStyle(.secondary)
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
