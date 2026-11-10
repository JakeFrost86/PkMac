#!/bin/bash
# Builds PkMacEngine.framework: the PkMac engine (PKHeX.Core + plugins) compiled with NativeAOT for
# iOS/iPadOS, loaded by the app in its own process.
#   iOS/build_engine.sh [device|simulator]   -> build/ios/<sdk>/PkMacEngine.framework
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
KIND="${1:-device}"
case "$KIND" in
  device) RID=ios-arm64; SDK=iphoneos ;;
  simulator) RID=iossimulator-arm64; SDK=iphonesimulator ;;
  *) echo "uso: $0 [device|simulator]"; exit 2 ;;
esac
MIN_IOS="${IOS_TARGET:-17.0}"
for d in "$HOME/.dotnet" /usr/local/share/dotnet /opt/homebrew/bin; do [[ -x "$d/dotnet" ]] && export PATH="$d:$PATH"; done
jq_get() { python3 -c "import json;print(json.load(open('versions.json'))$1)"; }
CORE="${PKHEX_CORE:-$(jq_get "['pkhexCore']")}"
ENGINE_VERSION="$(jq_get "['engine']")"
OUT="$ROOT/build/ios/$SDK"
FW="$OUT/PkMacEngine.framework"

echo "▶ Motore iOS ($RID) · PKHeX.Core $CORE"
rm -rf "$OUT/publish"
# Default obj/bin folders: overriding them breaks the restore of the NativeAOT runtime pack.
dotnet publish Engine/PkMac.Engine.Native/PkMac.Engine.Native.csproj -c Release -r "$RID" \
  -p:PKHeXCoreVersion="$CORE" -p:PkMacEngineVersion="$ENGINE_VERSION" \
  -o "$OUT/publish" --nologo -v quiet -clp:NoSummary
DYLIB="$OUT/publish/PkMacEngine.dylib"
[[ -f "$DYLIB" ]] || { echo "PkMacEngine.dylib non trovato"; exit 1; }

rm -rf "$FW"; mkdir -p "$FW"
cp "$DYLIB" "$FW/PkMacEngine"
install_name_tool -id @rpath/PkMacEngine.framework/PkMacEngine "$FW/PkMacEngine"
cat > "$FW/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>PkMacEngine</string>
  <key>CFBundleIdentifier</key><string>app.pkmac.engine</string>
  <key>CFBundleName</key><string>PkMacEngine</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>$ENGINE_VERSION</string>
  <key>CFBundleVersion</key><string>$ENGINE_VERSION</string>
  <key>MinimumOSVersion</key><string>$MIN_IOS</string>
</dict></plist>
PLIST
echo "✅ $FW ($(du -sh "$FW" | cut -f1))"
