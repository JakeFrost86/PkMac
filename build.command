#!/bin/bash
# Compila PkMac e apre l'app. Il log completo finisce in build.log
cd "$(dirname "$0")"
echo "▶ Compilo PkMac… (log in $(pwd)/build.log)"
TEST_SAVE="${TEST_SAVE:-$HOME/Downloads/FireRed_i.sav}" ./build.sh "$@" 2>&1 | tee build.log
STATUS=${PIPESTATUS[0]}
echo "EXIT=$STATUS" >> build.log
if [[ $STATUS == 0 ]]; then
  open build/PkMac.app
fi
