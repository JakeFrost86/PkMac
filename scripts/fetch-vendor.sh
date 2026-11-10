#!/bin/bash
# Fetches the plugin sources pinned in versions.json into vendor/.
#   scripts/fetch-vendor.sh            -> pinned refs
#   scripts/fetch-vendor.sh --latest   -> latest default branch (used by CI to test new plugin versions)
set -euo pipefail
cd "$(dirname "$0")/.."
LATEST=0
[[ "${1:-}" == "--latest" ]] && LATEST=1

mkdir -p vendor
python3 - "$LATEST" <<'PY'
import json, subprocess, sys, os
latest = sys.argv[1] == "1"
v = json.load(open("versions.json"))
for name, info in v["vendor"].items():
    dest = os.path.join("vendor", name)
    if not os.path.isdir(os.path.join(dest, ".git")):
        subprocess.run(["git", "clone", "--quiet", "--filter=blob:none", info["repo"], dest], check=True)
    subprocess.run(["git", "-C", dest, "fetch", "--quiet", "origin"], check=True)
    ref = "origin/HEAD" if latest else info["ref"]
    subprocess.run(["git", "-C", dest, "checkout", "--quiet", "--force", ref], check=True)
    sha = subprocess.run(["git", "-C", dest, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    print(f"  {name:18} {sha[:10]}")
PY
