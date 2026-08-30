#!/usr/bin/env bash
# Build knvtop.plasmoid -- a zip of com.daevid.knvtop/'s contents with
# metadata.json at the zip root, the format store.kde.org and Plasma's
# "Install from local file" both expect.
#
# Uses `git archive` (not a raw zip/tar) so only files actually tracked in
# git end up in the package -- .ruff_cache/, __pycache__/, and any other
# local dev cruft are excluded automatically without needing to duplicate
# .gitignore's rules here.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(python3 -c "import json; print(json.load(open('$repo_root/com.daevid.knvtop/metadata.json'))['KPlugin']['Version'])")"
out="$repo_root/knvtop-${version}.plasmoid"

cd "$repo_root"
git archive --format=zip -o "$out" HEAD:com.daevid.knvtop

echo "Built: $out"
unzip -l "$out"
