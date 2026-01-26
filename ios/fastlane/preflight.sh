#!/usr/bin/env bash
set -euo pipefail

# fastlane snapshot preflight for Nextdeck
# Checks simulator service, runtime/device availability, and a minimal XCTest boot.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAPFILE="$ROOT_DIR/fastlane/Snapfile"

# Prefer local pod wrapper + Homebrew Ruby/CocoaPods if available.
export PATH="$ROOT_DIR/fastlane/bin:/opt/homebrew/opt/ruby/bin:/opt/homebrew/bin:$PATH"
unset GEM_HOME
unset GEM_PATH

fail() {
  echo "[preflight] ❌ $*" >&2
  exit 1
}

info() {
  echo "[preflight] $*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

require_cmd xcodebuild
require_cmd xcrun
require_cmd rg

# If pod wrapper defines a GEM_HOME, align GEM_HOME/GEM_PATH to it,
# but keep Ruby's default gem path so bundled gems (e.g. base64) are visible.
POD_WRAPPER="$(command -v pod || true)"
if [[ -n "${POD_WRAPPER}" && -f "${POD_WRAPPER}" ]]; then
  POD_GEM_HOME="$(rg -n '^GEM_HOME=' "$POD_WRAPPER" --no-filename 2>/dev/null | sed -E 's/^GEM_HOME=\"?([^"]+)\"?.*/\1/' | head -n 1 || true)"
  if [[ -n "${POD_GEM_HOME}" ]]; then
    export GEM_HOME="${POD_GEM_HOME}"
    if command -v ruby >/dev/null 2>&1; then
      DEFAULT_GEM_PATH="$(ruby -e 'print Gem.default_path.join(":")' 2>/dev/null || true)"
      if [[ -n "${DEFAULT_GEM_PATH}" ]]; then
        export GEM_PATH="${POD_GEM_HOME}:${DEFAULT_GEM_PATH}"
      else
        export GEM_PATH="${POD_GEM_HOME}"
      fi
    else
      export GEM_PATH="${POD_GEM_HOME}"
    fi
  fi
fi

if ! command -v fastlane >/dev/null 2>&1; then
  info "fastlane not found in PATH. That's ok for preflight, but screenshots will fail unless it's installed."
fi

info "Xcode: $(xcodebuild -version | tr '\n' ' ' | sed 's/  */ /g')"
info "PATH: $PATH"
info "pod: $(command -v pod || echo 'not found')"
info "ruby: $(command -v ruby || echo 'not found')"

if command -v pod >/dev/null 2>&1; then
  if ! pod --version >/tmp/fastlane_preflight_pod.log 2>&1; then
    info "pod --version failed; output:"
    tail -n 20 /tmp/fastlane_preflight_pod.log | sed 's/^/  /'
    fail "CocoaPods is present but not runnable. Fix pod before continuing."
  fi
fi

# Flutter build (optional but recommended for Runner.app + assets)
if command -v flutter >/dev/null 2>&1; then
  if [[ -f "$ROOT_DIR/../pubspec.yaml" ]]; then
    if [[ "${SKIP_FLUTTER_BUILD:-0}" -ne 1 ]]; then
      info "Flutter: $(flutter --version | head -n 1)"
      info "Running: flutter build ios --simulator --debug"
      (cd "$ROOT_DIR/.." && flutter build ios --simulator --debug) >/tmp/fastlane_preflight_flutter.log 2>&1 || {
        info "flutter build failed; showing last 60 lines from /tmp/fastlane_preflight_flutter.log"
        tail -n 60 /tmp/fastlane_preflight_flutter.log | sed 's/^/  /'
        fail "Flutter build failed. Fix Flutter build errors before running fastlane screenshots."
      }
    else
      info "Skipping Flutter build (SKIP_FLUTTER_BUILD=1)"
    fi
  fi
fi

# Parse Snapfile (simple Ruby DSL; we only grab obvious values)
DEVICE_NAME=$(rg 'devices\(\[' "$SNAPFILE" -n --no-filename | \
  while read -r line; do
    line_num="$(echo "$line" | sed -E 's/(:).*//')"
    awk -v ln="$line_num" 'NR>=ln && NR<=ln+10' "$SNAPFILE" | \
      rg -o '"[^"]+"' --no-filename | head -n 1 | tr -d '"'
    break
  done) || true

RUNTIME_VERSION=$(rg 'ios_version\("[^"]+"\)' "$SNAPFILE" --no-filename | sed -E 's/.*"([^"]+)".*/\1/' | head -n 1) || true
SCHEME=$(rg 'scheme\("[^"]+"\)' "$SNAPFILE" --no-filename | sed -E 's/.*"([^"]+)".*/\1/' | head -n 1) || true

if [[ -z "${DEVICE_NAME:-}" ]]; then
  DEVICE_NAME=$(rg -o '"[^"]+"' "$SNAPFILE" --no-filename | head -n 1 | tr -d '"') || true
fi

if [[ -z "${DEVICE_NAME:-}" ]]; then
  DEVICE_NAME="iPhone 17 Pro"
fi
if [[ -z "${RUNTIME_VERSION:-}" ]]; then
  RUNTIME_VERSION="26.2"
fi
if [[ -z "${SCHEME:-}" ]]; then
  SCHEME="Runner"
fi

info "Snapfile: device='$DEVICE_NAME', iOS='$RUNTIME_VERSION', scheme='$SCHEME'"

# Ensure CoreSimulator is responsive
if ! xcrun simctl list runtimes >/dev/null 2>&1; then
  fail "CoreSimulatorService not responding. Try restarting Simulator or rebooting macOS."
fi

if ! xcrun simctl list runtimes | rg -q "iOS ${RUNTIME_VERSION}"; then
  info "Available runtimes:"
  xcrun simctl list runtimes | sed 's/^/  /'
  fail "Missing iOS runtime ${RUNTIME_VERSION}. Install it via Xcode > Settings > Platforms."
fi

# Ensure device exists
if ! xcrun simctl list devices | rg -q "${DEVICE_NAME} \(.*\)"; then
  info "Known devices:"
  xcrun simctl list devices | sed 's/^/  /'
  fail "Device '${DEVICE_NAME}' not found. Create it in Simulator or update Snapfile devices." 
fi

# Boot the device (quietly)
DEVICE_UDID=$(xcrun simctl list devices | rg "${DEVICE_NAME} \(" -m 1 | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/')
if [[ -z "${DEVICE_UDID:-}" ]]; then
  fail "Could not resolve UDID for device '${DEVICE_NAME}'."
fi

info "Booting ${DEVICE_NAME} (${DEVICE_UDID})"
xcrun simctl boot "$DEVICE_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$DEVICE_UDID" -b

# Verify scheme exists
if ! xcodebuild -list -workspace "$ROOT_DIR/Runner.xcworkspace" | rg -q "Schemes:"; then
  fail "Unable to read schemes from Runner.xcworkspace."
fi
if ! xcodebuild -list -workspace "$ROOT_DIR/Runner.xcworkspace" | rg -q "\b${SCHEME}\b"; then
  info "Schemes available:"
  xcodebuild -list -workspace "$ROOT_DIR/Runner.xcworkspace" | sed 's/^/  /'
  fail "Scheme '${SCHEME}' not found."
fi

# Minimal XCTest boot (no tests), just to validate runner launch
info "Running minimal XCTest boot check (build-for-testing + test-without-building)..."
set +e
xcodebuild -workspace "$ROOT_DIR/Runner.xcworkspace" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=${DEVICE_NAME},OS=${RUNTIME_VERSION}" \
  -disable-concurrent-destination-testing \
  -derivedDataPath /tmp/fastlane_preflight_derived \
  build-for-testing \
  >/tmp/fastlane_preflight.log 2>&1
BUILD_STATUS=$?

if [[ $BUILD_STATUS -eq 0 ]]; then
  xcodebuild -workspace "$ROOT_DIR/Runner.xcworkspace" \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,name=${DEVICE_NAME},OS=${RUNTIME_VERSION}" \
    -only-testing:RunnerUITests/RunnerUITestsLaunchTests/testLaunch \
    -disable-concurrent-destination-testing \
    -derivedDataPath /tmp/fastlane_preflight_derived \
    test-without-building \
    >>/tmp/fastlane_preflight.log 2>&1
  STATUS=$?
else
  STATUS=$BUILD_STATUS
fi
set -e

if [[ $STATUS -ne 0 ]]; then
  info "xcodebuild failed; showing last 60 lines from /tmp/fastlane_preflight.log"
  tail -n 60 /tmp/fastlane_preflight.log | sed 's/^/  /'
  if rg -q "XCTestDevices" /tmp/fastlane_preflight.log; then
    info "Hint: XCTest device set looks stale. Try:"
    info "  rm -rf ~/Library/Developer/XCTestDevices"
    info "  xcrun simctl shutdown all"
  fi
  fail "XCTest runner failed. Resolve simulator/XCTest issues before running fastlane screenshots."
fi

info "✅ Preflight OK. You can run: fastlane screenshots"
