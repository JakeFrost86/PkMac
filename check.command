#!/bin/bash
# Controlla gli strumenti necessari a compilare PkMac e scrive il risultato in toolchain.log
cd "$(dirname "$0")"
{
  echo "== macOS"; sw_vers
  echo "== Xcode"; xcodebuild -version 2>&1 | head -2; xcode-select -p
  echo "== Swift"; swift --version 2>&1 | head -2
  echo "== dotnet"; (command -v dotnet || ls ~/.dotnet/dotnet /usr/local/share/dotnet/dotnet 2>/dev/null)
  for d in dotnet ~/.dotnet/dotnet /usr/local/share/dotnet/dotnet; do command -v $d >/dev/null 2>&1 && { $d --list-sdks; break; }; done
  echo "== git"; git --version
  echo "== done"
} > toolchain.log 2>&1
osascript -e 'tell application "Terminal" to close (every window whose name contains "check.command")' >/dev/null 2>&1 &
exit 0
