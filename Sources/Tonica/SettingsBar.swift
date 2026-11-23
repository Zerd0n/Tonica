import SwiftUI

struct SettingsBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let fmt = model.settings.format

        HStack(alignment: .center, spacing: 18) {
            Picker(tr("Формат:", "Format:"), selection: $model.settings.format) {
                Section(tr("Без потерь", "Lossless")) {
                    ForEach(OutputFormat.allCases.filter(\.isLossless)) { Text($0.title).tag($0) }
                }
                Section(tr("Сжатие с потерями", "Lossy")) {
                    ForEach(OutputFormat.allCases.filter { !$0.isLossless }) { Text($0.title).tag($0) }
                }
            }
            .frame(width: 270)
            .onChange(of: model.settings.format) { _, new in
                if !new.bitrates.contains(model.settings.bitrate) { model.settings.bitrate = new.defaultBitrate }
            }

            if !fmt.bitrates.isEmpty {
                Picker(tr("Битрейт:", "Bitrate:"), selection: $model.settings.bitrate) {
                    ForEach(fmt.bitrates, id: \.self) { Text("\($0) \(tr("кбит/с", "kbps"))").tag($0) }
                }
                .frame(width: 180)
            } else {
                Picker(tr("Разрядность:", "Bit depth:"), selection: $model.settings.bitDepth) {
                    Text(tr("Авто", "Auto")).tag(0)
                    Text(tr("16 бит", "16 bit")).tag(16)
                    Text(tr("24 бит", "24 bit")).tag(24)
                }
                .frame(width: 180)
                .help(tr("«Авто» сохраняет 24 бита у hi‑res исходников, иначе 16 бит", "Auto keeps 24-bit depth for hi-res sources, otherwise 16-bit"))
            }

            Picker(tr("Частота:", "Sample rate:"), selection: $model.settings.sampleRate) {
                Text(tr("Как в исходнике", "Same as source")).tag(0)
                Text(tr("44,1 кГц", "44.1 kHz")).tag(44100)
                Text(tr("48 кГц", "48 kHz")).tag(48000)
                if fmt.isLossless {
                    Text(tr("88,2 кГц", "88.2 kHz")).tag(88200)
                    Text(tr("96 кГц", "96 kHz")).tag(96000)
                }
            }
            .frame(width: 210)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)

        HStack(spacing: 14) {
            Picker(tr("Сохранять:", "Save to:"), selection: $model.settings.location) {
                Text(tr("Рядом с исходником", "Next to source")).tag(OutputLocation.nextToSource)
                Text(model.settings.outputFolder?.lastPathComponent ?? tr("В папку…", "Choose folder…")).tag(OutputLocation.customFolder)
            }
            .frame(width: 290)
            .onChange(of: model.settings.location) { _, new in
                if new == .customFolder, model.settings.outputFolder == nil { model.chooseOutputFolder() }
                if model.settings.outputFolder == nil { model.settings.location = .nextToSource }
            }
            Button(tr("Папка…", "Folder…")) { model.chooseOutputFolder() }

            Toggle(tr("Сохранять обложку исходника", "Keep original cover"), isOn: $model.settings.keepCover)
                .disabled(!fmt.supportsCover)
                .help(fmt.supportsCover ? tr("Переносить встроенную обложку в новый файл", "Copy the embedded cover to the new file") : tr("\(fmt.title) не поддерживает обложки", "\(fmt.title) does not support cover art"))
            Toggle(tr("Перезаписывать файлы", "Overwrite files"), isOn: $model.settings.overwrite)
                .help(tr("Иначе к имени добавляется номер", "Otherwise a number is added to the filename"))

            Spacer(minLength: 0)

            if model.tracks.contains(where: { $0.outputURL != nil }) && !model.isConverting {
                Button(tr("Показать результат", "Show Result")) { model.revealOutputs() }
            }

            if model.isConverting {
                ProgressView(value: model.overallProgress).frame(width: 120)
                Button(role: .cancel) { model.stop() } label: { Label(tr("Стоп", "Stop"), systemImage: "stop.fill") }
                    .controlSize(.large)
            } else {
                Button { model.convertAll() } label: {
                    Label(model.selection.isEmpty ? tr("Конвертировать все", "Convert All") : tr("Конвертировать выбранные (\(model.selection.count))", "Convert Selected (\(model.selection.count))"),
                          systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.tracks.isEmpty || !model.ffmpegAvailable)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}
