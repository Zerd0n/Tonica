#!/bin/zsh
# сборка Tonica.app и dmg в dist/
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
APP_NAME=Tonica
VERSION=1.1
DIST=$ROOT/dist
BUILD=$ROOT/.build/package
APP=$BUILD/$APP_NAME.app

echo "==> Компиляция"
swift build -c release
BIN=$(swift build -c release --show-bin-path)/$APP_NAME

rm -rf "$BUILD"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIST"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

echo "==> Иконка"
ICONSET=$BUILD/AppIcon.iconset; mkdir -p "$ICONSET"
swift scripts/make_icon.swift "$BUILD/icon.png"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz "$BUILD/icon.png" --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
  sips -z $((sz*2)) $((sz*2)) "$BUILD/icon.png" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>local.tonica.app</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleDevelopmentRegion</key><string>ru</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Audio</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array><string>public.audio</string><string>public.folder</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

echo "==> Встраиваю ffmpeg"
FF_DIR=$APP/Contents/Resources/ffmpeg
mkdir -p "$FF_DIR/bin" "$FF_DIR/lib"
FFMPEG_SRC=$(command -v ffmpeg || true)
if [[ -z "$FFMPEG_SRC" ]]; then
  echo "ffmpeg не найден, собираю без него"
  rm -rf "$FF_DIR"
else
  python3 - "$FF_DIR" "$(realpath "$(command -v ffmpeg)")" "$(realpath "$(command -v ffprobe)")" <<'PY'
import os, shutil, subprocess, sys
dest, bins = sys.argv[1], sys.argv[2:]
libdir = os.path.join(dest, "lib")

def deps(path):
    out = subprocess.run(["otool", "-L", path], capture_output=True, text=True).stdout.splitlines()[1:]
    return [l.strip().split(" (")[0] for l in out]

def is_external(d):
    return d.startswith("/opt/homebrew") or d.startswith("/usr/local")

libs, todo = {}, list(bins)
while todo:
    f = todo.pop()
    for d in deps(f):
        if is_external(d):
            real = os.path.realpath(d)
            name = os.path.basename(d)
            if name not in libs:
                libs[name] = real
                todo.append(real)

def fix(target, is_bin):
    os.chmod(target, 0o755)
    prefix = "@executable_path/../lib/" if is_bin else "@loader_path/"
    for d in deps(target):
        if is_external(d):
            subprocess.run(["install_name_tool", "-change", d, prefix + os.path.basename(d), target],
                           check=True, stderr=subprocess.DEVNULL)

for name, real in libs.items():
    t = os.path.join(libdir, name)
    shutil.copy2(real, t)
    os.chmod(t, 0o755)
    subprocess.run(["install_name_tool", "-id", "@loader_path/" + name, t], check=True, stderr=subprocess.DEVNULL)
    fix(t, False)
for b in bins:
    t = os.path.join(dest, "bin", os.path.basename(b))
    shutil.copy2(b, t)
    fix(t, True)
print(f"   {len(libs)} библиотек скопировано")
PY
  # ad-hoc подпись, без неё macos не запустит бинарники
  find "$FF_DIR" -type f \( -name "*.dylib" -o -perm +111 \) -exec codesign --force --sign - {} \; 2>/dev/null
  "$FF_DIR/bin/ffmpeg" -hide_banner -version | head -1
fi

echo "==> Подпись приложения"
codesign --force --sign - "$APP/Contents/MacOS/$APP_NAME"
codesign --force --sign - "$APP"

echo "==> Создание DMG"
STAGE=$BUILD/dmg; rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG=$DIST/$APP_NAME-$VERSION.dmg
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null

if command -v osascript >/dev/null; then
  osascript -l JavaScript -e "ObjC.import('AppKit'); \$.NSWorkspace.sharedWorkspace.setIconForFileOptions(\$.NSImage.alloc.initWithContentsOfFile('$BUILD/icon.png'), '$DMG', 0)" >/dev/null 2>&1 || true
fi

rm -rf "$DIST/$APP_NAME.app"; cp -R "$APP" "$DIST/"
echo "==> Готово"
ls -lh "$DMG"
