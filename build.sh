#!/bin/bash
# Builds PkMac.app (SwiftUI front-end + self-contained .NET engine with PKHeX.Core and plugins).
#
#   ./build.sh                  full build -> build/PkMac.app, build/PkMac.zip, build/PkMacEngine-osx-arm64.zip
#   ./build.sh --engine-only    only the engine pack
#   ./build.sh --install        also copies the app to /Applications
#
# Environment:
#   PKHEX_CORE=26.11.5     build against another PKHeX.Core (default: versions.json)
#   PKMAC_REPO=user/PkMac  GitHub repo used by the in-app updater
#   SKIP_VENDOR=1          don't refresh vendor/ sources
set -euo pipefail
cd "$(dirname "$0")"
# Local diagnostics hook (not used by CI): run .sync/diag.sh instead of building.
if [[ -f .sync/diag.sh ]]; then bash .sync/diag.sh; rc=$?; rm -f .sync/diag.sh; exit $rc; fi
ROOT="$(pwd)"
OUT="$ROOT/build"
ENGINE_ONLY=0; INSTALL=0
for a in "$@"; do
  case "$a" in
    --engine-only) ENGINE_ONLY=1 ;;
    --install) INSTALL=1 ;;
  esac
done

jq_get() { python3 -c "import json;print(json.load(open('versions.json'))$1)"; }
APP_VERSION="${APP_VERSION:-$(jq_get "['app']")}"
ENGINE_VERSION="${ENGINE_VERSION:-$(jq_get "['engine']")}"
CORE_VERSION="${PKHEX_CORE:-$(jq_get "['pkhexCore']")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%y%m%d%H%M)}"
if [[ -z "${PKMAC_REPO:-}" ]]; then
  PKMAC_REPO="$(git remote get-url origin 2>/dev/null | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##' || true)"
fi
PKMAC_REPO="${PKMAC_REPO:-JakeFrost86/PkMac}"

step() { printf "\n\033[1;35m▶ %s\033[0m\n" "$1"; }

# Locate dotnet (Homebrew, official installer or ~/.dotnet)
if ! command -v dotnet >/dev/null 2>&1; then
  for d in "$HOME/.dotnet" /usr/local/share/dotnet /opt/homebrew/bin; do
    [[ -x "$d/dotnet" ]] && export PATH="$d:$PATH" && break
  done
fi
command -v dotnet >/dev/null || { echo "❌ .NET 10 SDK non trovato. Installa da https://dotnet.microsoft.com/download/dotnet/10.0"; exit 1; }

mkdir -p "$OUT"

if [[ "${SKIP_VENDOR:-0}" != "1" ]]; then
  step "Sorgenti dei plugin (vendor/)"
  scripts/fetch-vendor.sh
fi

step "Motore .NET · PKHeX.Core $CORE_VERSION · engine $ENGINE_VERSION"
rm -rf "$OUT/engine"
dotnet publish Engine/PkMac.Engine/PkMac.Engine.csproj \
  -c Release -r osx-arm64 --self-contained true \
  -p:PKHeXCoreVersion="$CORE_VERSION" -p:PkMacEngineVersion="$ENGINE_VERSION" \
  -p:DebugType=none -p:GenerateDocumentationFile=false \
  -o "$OUT/engine" --nologo -v minimal
codesign --force --sign - "$OUT/engine/PkMacEngine" >/dev/null 2>&1 || true

step "Test di sicurezza del motore"
SELFTEST="$("$OUT/engine/PkMacEngine" --selftest ${TEST_SAVE:+"$TEST_SAVE"} || true)"
echo "$SELFTEST" | tail -1 | python3 -c "
import json,sys
r=json.loads(sys.stdin.read())
for c in r['checks']: print(('  ✅ ' if c['ok'] else '  ❌ ')+c['name']+'  '+str(c.get('detail') or ''))
v=r['versions']; print(f\"  core {v['core']} · alm {v['alm']} · engine {v['engine']}\")
sys.exit(0 if r['ok'] else 1)"

if [[ "${FEATURE_TEST:-0}" == "1" ]]; then
  step "Test degli editor (borsa, eventi, doni, blocchi, trasferimenti…)"
  "$OUT/engine/PkMacEngine" --featuretest ${TEST_SAVE:+"$TEST_SAVE"} || echo "⚠️  alcuni test degli editor non sono passati"
fi

python3 - "$OUT/engine/manifest.json" <<PY
import json,sys,subprocess
v=json.loads(subprocess.run(["$OUT/engine/PkMacEngine","--version"],capture_output=True,text=True).stdout.strip().splitlines()[-1])
json.dump({"engine":v["engine"],"core":v["core"],"alm":v["alm"],"source":"bundle"},open(sys.argv[1],"w"))
PY
rm -f "$OUT/PkMacEngine-osx-arm64.zip"
(cd "$OUT/engine" && ditto -c -k . "$OUT/PkMacEngine-osx-arm64.zip")

if [[ $ENGINE_ONLY == 1 ]]; then
  echo "✅ Pacchetto motore: $OUT/PkMacEngine-osx-arm64.zip"; exit 0
fi

step "App SwiftUI"
(cd App && swift build -c release --arch arm64 2>&1 | grep -Ev "^\[[0-9]+/[0-9]+\]" || true)
BIN_DIR="$(cd App && swift build -c release --arch arm64 --show-bin-path)"
[[ -x "$BIN_DIR/PkMac" ]] || { echo "❌ Compilazione Swift fallita"; (cd App && swift build -c release --arch arm64); exit 1; }

step "Pacchetto PkMac.app"
APP="$OUT/PkMac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PkMac" "$APP/Contents/MacOS/PkMac"
sed -e "s/__APP_VERSION__/$APP_VERSION/" -e "s/__BUILD_NUMBER__/$BUILD_NUMBER/" -e "s#__UPDATE_REPO__#$PKMAC_REPO#" App/Info.plist > "$APP/Contents/Info.plist"
cp App/Resources/pokeapi-forms.json App/Resources/pokeapi-cosmetic.json App/Resources/Logo.png App/Resources/Sphere.png "$APP/Contents/Resources/"
ditto App/Resources/Icons "$APP/Contents/Resources/Icons"
ditto App/Resources/Lang "$APP/Contents/Resources/Lang"
ditto "$OUT/engine" "$APP/Contents/Resources/Engine"

# Icon
ICONSET="$OUT/AppIcon.iconset"; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s assets/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) assets/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

step "Firma ad-hoc"
find "$APP/Contents/Resources/Engine" -type f \( -name "*.dylib" -o -name "PkMacEngine" \) -exec codesign --force --sign - {} \; 2>/dev/null
codesign --force --deep --sign - "$APP"
xattr -cr "$APP" 2>/dev/null || true

rm -f "$OUT/PkMac.zip"
ditto -c -k --keepParent "$APP" "$OUT/PkMac.zip"

if [[ $INSTALL == 1 ]]; then
  step "Installo in /Applications"
  rm -rf /Applications/PkMac.app
  ditto "$APP" /Applications/PkMac.app
fi

echo
echo "✅ PkMac $APP_VERSION pronto"
echo "   App:    $APP"
echo "   Zip:    $OUT/PkMac.zip"
echo "   Motore: $OUT/PkMacEngine-osx-arm64.zip (PKHeX.Core $CORE_VERSION)"
