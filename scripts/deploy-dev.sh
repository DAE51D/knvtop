#!/usr/bin/env bash
# Deploy the working tree to the live Plasma install and stamp it with a
# build timestamp, so the widget's About page (Settings -> About) shows
# exactly which build is running:
#
#     knvtop 1.3.0+20261016.1905.a8414a5-dirty
#
# Only the *installed copy's* metadata.json is stamped. The source tree's
# Version stays a clean "1.3.0" (what build-plasmoid.sh packages and what
# AGENTS.md says to bump), so release builds never carry a timestamp.
#
# Stamp format: <Version>+<YYYYMMDD>.<HHMM>.<git short sha>[-dirty]
#   -dirty = uncommitted changes in the tree, i.e. the sha alone does not
#            identify what you deployed.
#
# plasmashell reads metadata when it loads the applet, so a running widget
# keeps its old stamp/QML until plasmashell restarts. Pass --restart to do
# that for you (it re-instantiates every widget and flashes the panel).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$repo_root/com.daevid.knvtop"
dest="${KNVTOP_DEST:-$HOME/.local/share/plasma/plasmoids/com.daevid.knvtop}"

sha="$(git -C "$repo_root" rev-parse --short HEAD 2>/dev/null || echo nogit)"
if [[ -n "$(git -C "$repo_root" status --porcelain -- com.daevid.knvtop service 2>/dev/null)" ]]; then
    sha="${sha}-dirty"
fi
stamp="$(date +%Y%m%d.%H%M).${sha}"

mkdir -p "$dest"
rsync -a --delete --exclude '__pycache__' "$src/" "$dest/"

python3 - "$dest/metadata.json" "$stamp" <<'PY'
import json
import sys

path, stamp = sys.argv[1], sys.argv[2]
with open(path) as f:
    meta = json.load(f)
meta["KPlugin"]["Version"] = f"{meta['KPlugin']['Version']}+{stamp}"
with open(path, "w") as f:
    json.dump(meta, f, indent=4)
    f.write("\n")
print("Deployed to", path, "->", meta["KPlugin"]["Version"])
PY

if [[ "${1:-}" == "--restart" ]]; then
    systemctl --user restart plasma-plasmashell.service
    echo "plasmashell restarted"
else
    echo "Not restarting plasmashell; run with --restart (or restart it yourself) to load this build."
fi
