#!/usr/bin/env bash
set -euo pipefail

POD_HOME="/opt/homebrew/Cellar/cocoapods/1.16.2_2/libexec"
RUBY_BIN="/opt/homebrew/opt/ruby/bin"

if [[ ! -d "$POD_HOME" ]]; then
  echo "[pod-fix] ❌ CocoaPods libexec not found: $POD_HOME" >&2
  exit 1
fi

if [[ ! -x "$RUBY_BIN/ruby" || ! -x "$RUBY_BIN/gem" ]]; then
  echo "[pod-fix] ❌ Homebrew Ruby not found at $RUBY_BIN" >&2
  exit 1
fi

echo "[pod-fix] CocoaPods libexec: $POD_HOME"
ls -ld "$POD_HOME"

export GEM_HOME="$POD_HOME"
DEFAULT_GEM_PATH="$("$RUBY_BIN/ruby" -e 'print Gem.default_path.join(":")' 2>/dev/null || true)"
if [[ -n "$DEFAULT_GEM_PATH" ]]; then
  export GEM_PATH="$POD_HOME:$DEFAULT_GEM_PATH"
else
  export GEM_PATH="$POD_HOME"
fi
export PATH="$RUBY_BIN:/opt/homebrew/bin:$PATH"

"$RUBY_BIN/gem" install minitest --no-document
"$RUBY_BIN/gem" list minitest

try_pod() {
  local out
  out="$(pod --version 2>&1 || true)"
  echo "$out"
  if echo "$out" | rg -q "Could not find '"; then
    echo "$out" | sed -n "s/.*Could not find '\\([^']*\\)'.*/\\1/p" | head -n 1
    return 2
  fi
  return 0
}

for i in {1..5}; do
  missing="$(try_pod)"
  if [[ $? -eq 0 ]]; then
    exit 0
  fi
  if [[ -z "${missing:-}" ]]; then
    echo "[pod-fix] ❌ pod failed with an unexpected error"
    exit 1
  fi
  echo "[pod-fix] Installing missing gem: $missing"
  "$RUBY_BIN/gem" install "$missing" --no-document
done

echo "[pod-fix] ❌ pod still failing after installing missing gems."
exit 1
