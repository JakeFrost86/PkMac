#!/bin/bash
# PkMac for iPhone / iPhone Duo / iPad.
#   iOS/build.sh ipa                 -> build/ios/PkMac-iOS.ipa (unsigned, to sign with your own service)
#   iOS/build.sh simtest <save>...   -> runs the engine self-test in a headless iOS simulator
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
MODE="${1:-ipa}"; shift || true
export PATH="/opt/homebrew/bin:$PATH"
VERSION="$(python3 -c "import json;print(json.load(open('versions.json'))['app'])")"

# Screenshot of every display (iPhone Duo has a closed and an open screen).
shot() {
  local dev="$1" base="$2" d out
  out="$(xcrun simctl io "$dev" screenshot "$base.png" 2>&1)" && return 0
  # Several displays (iPhone Duo): the error lists them as --display=N.
  for d in $(echo "$out" | grep -oE -- '--display=[0-9]+' | sort -u); do
    xcrun simctl io "$dev" screenshot "$d" "$base-${d#--display=}.png" >/dev/null 2>&1
  done
  return 0
}

# Alternate home-screen icons (Settings › Aspetto), generated from the Mac icons; only redone when a source changes.
ICON_IDS="neon classica officina pixel floppy apertura finder matita scritta"
icons() { xcrun swift iOS/make_icons.swift $ICON_IDS || { echo "icone alternative non generate"; exit 1; }; }

gen() { icons; (cd iOS && xcodegen generate --quiet) || exit 1; }

case "$MODE" in
ipa)
  iOS/build_engine.sh device || exit 1
  gen
  echo "▶ App iOS (iphoneos)"
  xcodebuild -project iOS/PkMac.xcodeproj -scheme PkMac -configuration Release -sdk iphoneos \
    -derivedDataPath build/ios/dd MARKETING_VERSION="$VERSION" CODE_SIGNING_ALLOWED=NO -quiet build 2>&1 | grep -E "error|warning: .*PkMacIOS" | head -40
  APP="build/ios/dd/Build/Products/Release-iphoneos/PkMac.app"
  [[ -d "$APP" ]] || { echo "build fallita"; exit 1; }
  rm -rf build/ios/Payload; mkdir -p build/ios/Payload; cp -R "$APP" build/ios/Payload/
  (cd build/ios && rm -f PkMac-iOS.ipa && zip -qry PkMac-iOS.ipa Payload)
  echo "✅ build/ios/PkMac-iOS.ipa ($(du -sh build/ios/PkMac-iOS.ipa | cut -f1))"
  ;;
compile)
  # Compile check only (simulator), with every error listed.
  [[ -d build/ios/iphonesimulator/PkMacEngine.framework ]] || iOS/build_engine.sh simulator || exit 1
  gen
  xcodebuild -project iOS/PkMac.xcodeproj -scheme PkMac -configuration Debug -sdk iphonesimulator \
    -derivedDataPath build/ios/dd-sim SWIFT_COMPILATION_MODE=wholemodule build 2>&1 | grep -E "error:|\*\* BUILD" | sed "s|$ROOT/||" | sort -u | head -120
  ;;
shots)
  # shots <save> <section>...  -> screenshots of the real app on iPhone and iPad simulators (build/ios/shots)
  SAVE="$1"; shift
  [[ -d build/ios/iphonesimulator/PkMacEngine.framework ]] || iOS/build_engine.sh simulator || exit 1
  gen
  xcodebuild -project iOS/PkMac.xcodeproj -scheme PkMac -configuration Debug -sdk iphonesimulator \
    -derivedDataPath build/ios/dd-sim -quiet build 2>&1 | grep -E "error" | head -20
  APP="build/ios/dd-sim/Build/Products/Debug-iphonesimulator/PkMac.app"
  mkdir -p build/ios/shots; rm -f build/ios/shots/*.png
  IFS='|' read -ra MODELS <<< "${SHOT_DEVICES:-iPhone 17 (|iPad Air 11-inch}"
  for MODEL in "${MODELS[@]}"; do
    DEV="$(xcrun simctl list devices available | grep -m1 "$MODEL" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
    [[ -n "$DEV" ]] || { echo "nessun simulatore per $MODEL"; continue; }
    TAG="$(echo "$MODEL" | tr -dc 'A-Za-z0-9')"
    echo "▶ $MODEL ($DEV)"
    xcrun simctl boot "$DEV" 2>/dev/null || true
    xcrun simctl bootstatus "$DEV" -b >/dev/null 2>&1
    xcrun simctl ui "$DEV" appearance dark 2>/dev/null || true
    xcrun simctl install "$DEV" "$APP" || exit 1
    DOCS="$(xcrun simctl get_app_container "$DEV" app.pkmac.ios data)/Documents"
    mkdir -p "$DOCS"; cp "$SAVE" "$DOCS/"
    NAME="$(basename "$SAVE")"
    SIMCTL_CHILD_PKMAC_LANG=it xcrun simctl launch --terminate-running-process "$DEV" app.pkmac.ios >/dev/null
    sleep 9; shot "$DEV" "build/ios/shots/$TAG-welcome"
    for SEC in "${@:-boxes}"; do
      # Section names, or: select / tab-<summary|stats|moves|origin|ribbons> (Pokémon sheet),
      # sheet-<create|showdown|settings>.
      SELECT=0; TAB=""; SHEET=""; SETPAGE=""; LABEL="$SEC"
      case "$SEC" in
        select) SEC=boxes; SELECT=1 ;;
        tab-*) TAB="${SEC#tab-}"; SEC=boxes; SELECT=1 ;;
        sheet-*) SHEET="${SEC#sheet-}"; SEC=boxes ;;
        settings-*) SHEET=settings; SETPAGE="${SEC#settings-}"; SEC=boxes ;;
      esac
      SIMCTL_CHILD_PKMAC_OPEN="$NAME" SIMCTL_CHILD_PKMAC_SECTION="$SEC" SIMCTL_CHILD_PKMAC_SELECT="$SELECT" \
        SIMCTL_CHILD_PKMAC_TAB="$TAB" SIMCTL_CHILD_PKMAC_SHEET="$SHEET" SIMCTL_CHILD_PKMAC_SETTINGS="$SETPAGE" \
        xcrun simctl launch --terminate-running-process "$DEV" app.pkmac.ios >/dev/null
      SEC="$LABEL"
      sleep 15; shot "$DEV" "build/ios/shots/$TAG-$SEC"
    done
    xcrun simctl terminate "$DEV" app.pkmac.ios 2>/dev/null || true
    xcrun simctl shutdown "$DEV" 2>/dev/null || true
  done
  ls build/ios/shots
  ;;
simtest)
  iOS/build_engine.sh simulator || exit 1
  gen
  echo "▶ App iOS (simulatore)"
  xcodebuild -project iOS/PkMac.xcodeproj -scheme PkMac -configuration Debug -sdk iphonesimulator \
    -derivedDataPath build/ios/dd-sim -quiet build 2>&1 | grep -E "error" | head -40
  APP="build/ios/dd-sim/Build/Products/Debug-iphonesimulator/PkMac.app"
  [[ -d "$APP" ]] || { echo "build simulatore fallita"; exit 1; }
  DEV="$(xcrun simctl list devices available | grep -m1 "iPhone 17 (" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
  echo "▶ Simulatore $DEV (senza finestra)"
  xcrun simctl boot "$DEV" 2>/dev/null || true
  xcrun simctl bootstatus "$DEV" -b >/dev/null 2>&1
  xcrun simctl uninstall "$DEV" app.pkmac.ios 2>/dev/null || true
  xcrun simctl install "$DEV" "$APP" || exit 1
  DOCS="$(xcrun simctl get_app_container "$DEV" app.pkmac.ios data)/Documents"
  mkdir -p "$DOCS"
  for SAVE in "$@"; do
    cp "$SAVE" "$DOCS/"
    NAME="$(basename "$SAVE")"
    rm -f "$DOCS/selftest.txt"
    echo "── $NAME"
    SIMCTL_CHILD_PKMAC_SELFTEST="$NAME" xcrun simctl launch --terminate-running-process "$DEV" app.pkmac.ios >/dev/null
    for i in $(seq 1 90); do [[ -f "$DOCS/selftest.txt" ]] && break; sleep 2; done
    cat "$DOCS/selftest.txt" 2>/dev/null || { echo "nessun risultato (crash?)"; ls ~/Library/Logs/DiagnosticReports | grep -i pkmac | tail -3; }
    xcrun simctl terminate "$DEV" app.pkmac.ios 2>/dev/null || true
  done
  xcrun simctl shutdown "$DEV" 2>/dev/null || true
  ;;
esac
