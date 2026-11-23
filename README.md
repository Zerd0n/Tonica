# Tonica

[English](#english) | [Русский](#русский)

## English

Music converter for macOS. Converts tracks between formats, adds cover art and can find covers online.

### Features

- Formats: FLAC, ALAC, WAV, AIFF, MP3, AAC (m4a), Opus, Ogg Vorbis
- Bitrate, bit depth (16/24-bit) and sample rate settings
- Batch conversion, drop in a whole folder
- Cover art: from a file, the clipboard, drag and drop, or search (Apple Music and Deezer), up to 3000×3000
- Tag editing (title, artist, album)
- Write cover art and tags into the original file without re-encoding
- Russian and English interface; choose a language in the Language menu

### Installation

Download `Tonica-1.0.dmg` from [Releases](../../releases), open it and drag Tonica to Applications.

The app isn't signed with an Apple developer certificate, so macOS may block it on first launch. In that case right-click Tonica → Open, or go to System Settings → Privacy & Security → Open Anyway.

### Building

Requires macOS 14+, Xcode (or Command Line Tools) and ffmpeg:

```bash
brew install ffmpeg
./scripts/build.sh
```

`Tonica.app` and the `.dmg` end up in `dist/`. ffmpeg and its libraries are copied into the app bundle, so other Macs don't need it installed.

## Русский

Конвертер музыки для macOS. Перегоняет треки между форматами, умеет ставить обложки и сам ищет их в интернете.

### Возможности

- Форматы: FLAC, ALAC, WAV, AIFF, MP3, AAC (m4a), Opus, Ogg Vorbis
- Выбор битрейта, разрядности (16/24 бит) и частоты дискретизации
- Пакетная конвертация, можно закинуть целую папку
- Обложки: из файла, из буфера обмена, перетаскиванием или поиском (Apple Music и Deezer), до 3000×3000
- Редактирование тегов (название, исполнитель, альбом)
- Запись обложки и тегов в исходный файл без перекодирования
- Русский и английский интерфейс; язык выбирается в меню «Язык»

### Установка

Скачать `Tonica-1.0.dmg` из [Releases](../../releases), открыть и перетащить Tonica в «Программы».

Приложение не подписано сертификатом Apple, поэтому при первом запуске macOS может его заблокировать. Тогда: правый клик по Tonica → «Открыть», либо Системные настройки → Конфиденциальность и безопасность → «Всё равно открыть».

### Сборка

Нужны macOS 14+, Xcode (или Command Line Tools) и ffmpeg:

```bash
brew install ffmpeg
./scripts/build.sh
```

Готовые `Tonica.app` и `.dmg` появятся в `dist/`. ffmpeg вместе с библиотеками копируется внутрь приложения, так что на других маках его ставить не нужно.
