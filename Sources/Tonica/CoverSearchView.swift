import SwiftUI

struct CoverSearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let targets: [Track]

    @State private var query = ""
    @State private var size: CoverSize = .large
    @State private var results: [CoverResult] = []
    @State private var selected: CoverResult?
    @State private var searching = false
    @State private var applying = false
    @State private var searchedOnce = false
    @State private var error: String?

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(tr("Исполнитель, альбом или название трека", "Artist, album or track title"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(search)
                Picker("", selection: $size) {
                    ForEach(CoverSize.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 120)
                .help(tr("Размер скачиваемой обложки", "Downloaded cover size"))
                Button(tr("Искать", "Search"), action: search)
                    .keyboardShortcut(.defaultAction)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || searching)
            }
            .padding(14)

            Divider()

            ZStack {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(results) { r in
                            ResultCell(result: r, isSelected: selected == r)
                                .onTapGesture { selected = r }
                                .onTapGesture(count: 2) { selected = r; apply() }
                        }
                    }
                    .padding(16)
                }
                if searching {
                    ProgressView(tr("Ищу обложки…", "Searching for covers…"))
                } else if searchedOnce && results.isEmpty {
                    ContentUnavailableView(tr("Ничего не найдено", "No Results"), systemImage: "photo.on.rectangle.angled",
                                           description: Text(tr("Попробуйте написать только исполнителя и альбом", "Try searching for just the artist and album")))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                if let error { Text(error).foregroundStyle(.red).lineLimit(2) }
                else {
                    Text(targets.count == 1 ? tr("Для: \(targets[0].title)", "For: \(targets[0].title)") : tr("Для \(targets.count) треков", "For \(targets.count) tracks"))
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button(tr("Отмена", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button {
                    apply()
                } label: {
                    if applying { ProgressView().controlSize(.small).padding(.horizontal, 20) }
                    else { Text(tr("Применить обложку", "Apply Cover")) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected == nil || applying)
            }
            .padding(14)
        }
        .frame(width: 820, height: 620)
        .onAppear {
            query = initialQuery()
            search()
        }
    }

    private func initialQuery() -> String {
        guard let t = targets.first else { return "" }
        let allSameAlbum = !t.album.isEmpty && targets.allSatisfy { $0.album == t.album }
        if targets.count > 1 && allSameAlbum { return "\(t.artist) \(t.album)" }
        if !t.artist.isEmpty { return "\(t.artist) \(t.title)" }
        return t.title.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: " - ", with: " ")
    }

    private func search() {
        let q = query
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        searching = true
        error = nil
        selected = nil
        Task {
            let found = await CoverSearch.search(q, size: size)
            results = found
            selected = found.first
            searching = false
            searchedOnce = true
        }
    }

    private func apply() {
        guard let r = selected, !applying else { return }
        applying = true
        error = nil
        Task {
            do {
                let url = try await CoverSearch.download(r.fullURL)
                model.setCover(url, for: targets)
                dismiss()
            } catch {
                // большого размера может не быть, пробуем превью
                if let fallback = try? await CoverSearch.download(r.thumbURL) {
                    model.setCover(fallback, for: targets)
                    dismiss()
                } else {
                    self.error = tr("Не удалось скачать: \(error.localizedDescription)", "Download failed: \(error.localizedDescription)")
                }
            }
            applying = false
        }
    }
}

private struct ResultCell: View {
    let result: CoverResult
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: result.thumbURL) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(1, contentMode: .fill)
                case .failure: Rectangle().fill(.quaternary).overlay(Image(systemName: "xmark"))
                default: Rectangle().fill(.quaternary).overlay(ProgressView().controlSize(.small))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 4)
            )
            .overlay(alignment: .topTrailing) {
                Text(result.source)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(6)
            }
            Text(result.title).font(.callout.weight(.medium)).lineLimit(1)
            Text(result.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}
