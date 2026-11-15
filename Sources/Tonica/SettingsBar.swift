import SwiftUI

struct SettingsBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let fmt = model.settings.format

        HStack(alignment: .center, spacing: 18) {
            Picker("Формат:", selection: $model.settings.format) {
                Section("Без потерь") {
                    ForEach(OutputFormat.allCases.filter(\.isLossless)) { Text($0.title).tag($0) }
                }
                Section("Сжатие с потерями") {
                    ForEach(OutputFormat.allCases.filter { !$0.isLossless }) { Text($0.title).tag($0) }
                }
            }
            .frame(width: 270)
            .onChange(of: model.settings.format) { _, new in
                if !new.bitrates.contains(model.settings.bitrate) { model.settings.bitrate = new.defaultBitrate }
            }

            if !fmt.bitrates.isEmpty {
                Picker("Битрейт:", selection: $model.settings.bitrate) {
                    ForEach(fmt.bitrates, id: \.self) { Text("\($0) кбит/с").tag($0) }
                }
                .frame(width: 180)
            } else {
                Picker("Разрядность:", selection: $model.settings.bitDepth) {
                    Text("Авто").tag(0)
                    Text("16 бит").tag(16)
                    Text("24 бит").tag(24)
                }
                .frame(width: 180)
                .help("«Авто» сохраняет 24 бита у hi‑res исходников, иначе 16 бит")
            }

            Picker("Частота:", selection: $model.settings.sampleRate) {
                Text("Как в исходнике").tag(0)
                Text("44,1 кГц").tag(44100)
                Text("48 кГц").tag(48000)
                if fmt.isLossless {
                    Text("88,2 кГц").tag(88200)
                    Text("96 кГц").tag(96000)
                }
            }
            .frame(width: 210)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)

        HStack(spacing: 14) {
            Picker("Сохранять:", selection: $model.settings.location) {
                Text("Рядом с исходником").tag(OutputLocation.nextToSource)
                Text(model.settings.outputFolder?.lastPathComponent ?? "В папку…").tag(OutputLocation.customFolder)
            }
            .frame(width: 290)
            .onChange(of: model.settings.location) { _, new in
                if new == .customFolder, model.settings.outputFolder == nil { model.chooseOutputFolder() }
                if model.settings.outputFolder == nil { model.settings.location = .nextToSource }
            }
            Button("Папка…") { model.chooseOutputFolder() }

            Toggle("Сохранять обложку исходника", isOn: $model.settings.keepCover)
                .disabled(!fmt.supportsCover)
                .help(fmt.supportsCover ? "Переносить встроенную обложку в новый файл" : "\(fmt.title) не поддерживает обложки")
            Toggle("Перезаписывать файлы", isOn: $model.settings.overwrite)
                .help("Иначе к имени добавляется номер")

            Spacer(minLength: 0)

            if model.tracks.contains(where: { $0.outputURL != nil }) && !model.isConverting {
                Button("Показать результат") { model.revealOutputs() }
            }

            if model.isConverting {
                ProgressView(value: model.overallProgress).frame(width: 120)
                Button(role: .cancel) { model.stop() } label: { Label("Стоп", systemImage: "stop.fill") }
                    .controlSize(.large)
            } else {
                Button { model.convertAll() } label: {
                    Label(model.selection.isEmpty ? "Конвертировать все" : "Конвертировать выбранные (\(model.selection.count))",
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
