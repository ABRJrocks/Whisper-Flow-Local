#!/bin/bash
# Build FlowLocal.app from the SPM executable, sign it, and place it in build/.
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN_IDENTITY="${FLOWLOCAL_SIGN_IDENTITY:-Apple Development: Abdul Rafay (6ZJ47FNNCB)}"
APP="build/FlowLocal.app"
METALLIB="Vendor/mlx.metallib"
# MLX metallib: SwiftPM cannot compile Metal shaders (mlx-swift#349); we ship the
# official library from the mlx-metal wheel, version-matched to the vendored MLX.
METALLIB_URL="https://files.pythonhosted.org/packages/51/bc/987cb99e3aafb296aa11ce5133838a10eae8447edd53168d0804d4fb3a14/mlx_metal-0.31.1-py3-none-macosx_26_0_arm64.whl"

if [ ! -f "$METALLIB" ]; then
    echo "Fetching mlx.metallib (mlx-metal 0.31.1 wheel)…"
    TMP=$(mktemp -d)
    curl -sL -o "$TMP/mlx_metal.whl" "$METALLIB_URL"
    unzip -o -q "$TMP/mlx_metal.whl" -d "$TMP/x"
    mkdir -p Vendor
    cp "$TMP/x/mlx/lib/mlx.metallib" "$METALLIB"
    rm -rf "$TMP"
fi

# App icon: render + pack once; Resources/AppIcon.icns is committed thereafter.
if [ ! -f "Resources/AppIcon.icns" ]; then
    echo "Rendering app icon…"
    swift Scripts/make-icon.swift /tmp/flowlocal-icon.png
    ICONSET=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET"
    for s in 16 32 128 256 512; do
        sips -z $s $s /tmp/flowlocal-icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        d=$((s*2)); sips -z $d $d /tmp/flowlocal-icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    mkdir -p Resources
    iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi

swift build -c release
# Colocate the metallib for `swift run`/direct-binary workflows too.
cp "$METALLIB" .build/release/mlx.metallib
mkdir -p .build/debug && cp "$METALLIB" .build/debug/mlx.metallib 2>/dev/null || true

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/FlowLocal "$APP/Contents/MacOS/FlowLocal"
# MLX looks for mlx.metallib next to the executable first.
cp "$METALLIB" "$APP/Contents/MacOS/mlx.metallib"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# SPM resource bundles (GRDB, swift-transformers, …) — Bundle.module checks Resources.
for bundle in .build/release/*.bundle; do
    [ -d "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>FlowLocal</string>
    <key>CFBundleIdentifier</key><string>com.local.flowlocal</string>
    <key>CFBundleName</key><string>FlowLocal</string>
    <key>CFBundleDisplayName</key><string>FlowLocal</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>FlowLocal uses the microphone to transcribe your speech entirely on this Mac.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>FlowLocal transcribes speech on-device. Nothing leaves this Mac.</string>
</dict>
</plist>
PLIST

# Stable identity is REQUIRED: ad-hoc signatures change every build, which makes the
# TCC Accessibility grant go stale — the app then can't read focus or synthesize Cmd+V.
ENTITLEMENTS_FILE=$(mktemp)
cat > "$ENTITLEMENTS_FILE" <<'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key><true/>
    <key>com.apple.security.cs.disable-library-validation</key><true/>
</dict>
</plist>
ENTITLEMENTS

if ! codesign --force --deep --sign "$SIGN_IDENTITY" --options runtime --entitlements "$ENTITLEMENTS_FILE" "$APP"; then
    echo "ERROR: signing with '$SIGN_IDENTITY' failed." >&2
    echo "Refusing ad-hoc fallback: it breaks the Accessibility permission on every rebuild." >&2
    echo "Set FLOWLOCAL_SIGN_IDENTITY to an identity from: security find-identity -v -p codesigning" >&2
    rm -f "$ENTITLEMENTS_FILE"
    exit 1
fi
rm -f "$ENTITLEMENTS_FILE"
codesign --verify --deep --strict "$APP"

echo "Built and signed: $APP"
# Keep the /Applications copy current so the user always launches the latest build.
if [ -d "/Applications/FlowLocal.app" ]; then
    ditto "$APP" "/Applications/FlowLocal.app"
    echo "Updated /Applications/FlowLocal.app"
fi
