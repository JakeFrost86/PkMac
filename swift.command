#!/bin/bash
# Solo compilazione Swift (per iterare velocemente). Log in swift.log
cd "$(dirname "$0")/App"
swift build -c release --arch arm64 2>&1 | grep -E "error|warning: unre|Compiling|Build complete" > ../swift.log
echo "EXIT=${PIPESTATUS[0]}" >> ../swift.log
