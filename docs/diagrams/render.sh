#!/bin/sh
# Render docs/*.mmd to PNG with mermaid-cli (brew install mermaid-cli).
# mmdc needs a headless Chrome: set MMDC_BROWSER to one, or this uses
# Playwright's chrome-headless-shell if it's installed (PLAYWRIGHT_BROWSERS_PATH,
# or Playwright's default cache on macOS or Linux).
set -eu
cd "$(dirname "$0")"
pw_cache=${PLAYWRIGHT_BROWSERS_PATH:-}
if [ -z "$pw_cache" ]; then
    if [ "$(uname)" = Darwin ]; then
        pw_cache="$HOME/Library/Caches/ms-playwright"
    else
        pw_cache="${XDG_CACHE_HOME:-$HOME/.cache}/ms-playwright"
    fi
fi
browser=${MMDC_BROWSER:-$(ls -d "$pw_cache"/chromium_headless_shell-*/chrome-headless-shell-*/chrome-headless-shell 2>/dev/null | tail -1)}
cfg=$(mktemp)
trap 'rm -f "$cfg"' EXIT
if [ -n "$browser" ]; then
    printf '{"executablePath": "%s"}\n' "$browser" >"$cfg"
else
    echo '{}' >"$cfg"   # fall back to puppeteer's own cache
fi
for f in *.mmd; do
    mmdc -q -p "$cfg" -i "$f" -o "${f%.mmd}.png" -t dark -b "#1e1e2e" -s 2
    echo "rendered ${f%.mmd}.png"
done
