#!/usr/bin/env bash
set -euo pipefail

TARGET_W="${1:-1242}"
TARGET_H="${2:-2688}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_SRC="$ROOT_DIR/screenshots"
ALT_SRC="$ROOT_DIR/../screenshots"

SRC_DIR="${SCREENSHOT_DIR:-}"
if [[ -z "${SRC_DIR}" ]]; then
  if [[ -d "$DEFAULT_SRC" ]]; then
    SRC_DIR="$DEFAULT_SRC"
  elif [[ -d "$ALT_SRC" ]]; then
    SRC_DIR="$ALT_SRC"
  else
    echo "[resize] ❌ Screenshots directory not found." >&2
    exit 1
  fi
fi

OUT_DIR="${OUTPUT_DIR:-$SRC_DIR/screenshots_resized_${TARGET_W}x${TARGET_H}}"

if [[ ! -d "$SRC_DIR" ]]; then
  echo "[resize] ❌ Source dir not found: $SRC_DIR" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

echo "[resize] Source: $SRC_DIR"
echo "[resize] Output: $OUT_DIR"

process_file() {
  local file="$1"
  local width height
  width=$(sips -g pixelWidth -1 "$file" | awk -F': ' '{print $2}' | tr -d '[:space:]')
  height=$(sips -g pixelHeight -1 "$file" | awk -F': ' '{print $2}' | tr -d '[:space:]')

  if [[ -z "$width" || -z "$height" ]]; then
    echo "[resize] Skipping (no dimensions): $file"
    return
  fi

  local tw="$TARGET_W"
  local th="$TARGET_H"
  if [[ "$width" -gt "$height" ]]; then
    tw="$TARGET_H"
    th="$TARGET_W"
  fi

  local size
  size=$(python3 - <<PY
import math
w, h, tw, th = $width, $height, $tw, $th
scale = min(tw / w, th / h)
new_w = max(1, int(round(w * scale)))
new_h = max(1, int(round(h * scale)))
print(new_w, new_h)
PY
)
  local new_w new_h
  new_w=$(echo "$size" | awk '{print $1}')
  new_h=$(echo "$size" | awk '{print $2}')

  local rel="${file#$SRC_DIR/}"
  local out="$OUT_DIR/$rel"
  mkdir -p "$(dirname "$out")"

  local tmp
  tmp="$(mktemp)"

  local pad="FFFFFF"
  if echo "$file" | rg -qi "dark"; then
    pad="000000"
  fi

  sips -z "$new_h" "$new_w" "$file" --out "$tmp" >/dev/null
  sips -p "$th" "$tw" --padColor "$pad" "$tmp" --out "$out" >/dev/null
  rm -f "$tmp"
}

export -f process_file
export SRC_DIR TARGET_W TARGET_H OUT_DIR

while IFS= read -r -d '' f; do
  process_file "$f"
done < <(find "$SRC_DIR" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -print0)

echo "[resize] Done."
