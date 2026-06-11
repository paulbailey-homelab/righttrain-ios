#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/ios/RightTrain/RightTrain.xcodeproj}"
SCHEME="${SCHEME:-RightTrain}"
CONFIGURATION="${CONFIGURATION:-Debug}"
BUNDLE_ID="${BUNDLE_ID:-com.righttrain.ios}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17 Pro}"
SIMULATOR_UDID="${SIMULATOR_UDID:-}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/ios/RightTrain/DerivedData/ScreenshotCapture}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/design/review-screenshots/$(date +%F-%H%M%S)}"
SCREENSHOT_TYPE="${SCREENSHOT_TYPE:-jpeg}"
SCREENSHOT_EXT="${SCREENSHOT_EXT:-jpg}"
APP_LAUNCH_DELAY="${APP_LAUNCH_DELAY:-2}"
LIVE_ACTIVITY_DELAY="${LIVE_ACTIVITY_DELAY:-3}"
HOME_DELAY="${HOME_DELAY:-1}"
LOCK_DELAY="${LOCK_DELAY:-1}"
DYNAMIC_ISLAND_LONG_PRESS_SECONDS="${DYNAMIC_ISLAND_LONG_PRESS_SECONDS:-0.8}"
DYNAMIC_ISLAND_CLICK_X_OFFSET="${DYNAMIC_ISLAND_CLICK_X_OFFSET:-0}"
DYNAMIC_ISLAND_CLICK_Y_OFFSET="${DYNAMIC_ISLAND_CLICK_Y_OFFSET:-120}"
DYNAMIC_ISLAND_HOST_X="${DYNAMIC_ISLAND_HOST_X:-}"
DYNAMIC_ISLAND_HOST_Y="${DYNAMIC_ISLAND_HOST_Y:-}"
SIMULATOR_HOME_METHOD="${SIMULATOR_HOME_METHOD:-springboard}"
SIMULATOR_LOCK_METHOD="${SIMULATOR_LOCK_METHOD:-shortcut}"
OPEN_SIMULATOR="${OPEN_SIMULATOR:-1}"
SKIP_BUILD="${SKIP_BUILD:-0}"
CAPTURE_APP="${CAPTURE_APP:-1}"
CAPTURE_LIVE_ACTIVITY="${CAPTURE_LIVE_ACTIVITY:-1}"

APP_SURFACES=(
  "01-signed-out|signedOut"
  "02-pinned-empty|empty"
  "03-pinned-search|window"
  "04-pinned-direct-journey|journey"
  "05-pinned-direct-platform-unknown|platformUnknown"
  "06-pinned-direct-platform-changed|platformChanged"
  "07-pinned-direct-stale-data|staleData"
  "08-pinned-direct-offline|offline"
  "09-pinned-direct-cancelled|cancelled"
  "10-pinned-direct-on-board|onboard"
  "11-pinned-itinerary-planning|itineraryPlanning"
  "12-pinned-itinerary-change|itinerary"
  "13-pinned-itinerary-final-leg|itineraryFinal"
  "14-shared-journey|sharedJourney"
  "15-commutes|commute"
  "16-plan-initial|plan"
  "17-settings|settings"
  "18-search-results-direct|search"
  "19-search-results-direct-pinned-return|searchPinned"
  "20-search-results-all-routes|itinerarySearch"
  "21-search-results-all-routes-pinned-return|itinerarySearchPinned"
  "22-us1-first-screen-manual-setup|firstScreenManual"
  "23-us1-first-screen-active-direct|firstScreenDirect"
  "24-us1-first-screen-active-itinerary|firstScreenItinerary"
  "25-us1-first-screen-stale-data|firstScreenStale"
  "26-us1-first-screen-offline|firstScreenOffline"
  "27-us2-setup-manual|us2SetupManual"
  "28-us2-setup-routine-prefill|us2SetupRoutine"
  "29-us2-setup-one-off-direct|us2SetupDirect"
  "30-us2-setup-connection-sensitive|us2SetupConnection"
  "31-us2-results-direct|us2ResultsDirect"
  "32-us2-results-with-changes|us2ResultsChanges"
  "33-us3-push-platform-change|us3PushPlatformChange"
  "34-us3-push-unavailable|us3PushUnavailable"
  "35-us3-permission-denied|us3PermissionDenied"
  "36-us4-onboarding|us4Onboarding"
  "37-us4-signed-out|us4SignedOut"
  "38-us4-settings|us4Settings"
  "39-us4-feedback|us4Feedback"
  "40-us4-journey-detail|us4JourneyDetail"
  "41-us4-shared-journey|us4SharedJourney"
  "42-us4-shared-expired|us4SharedExpired"
  "43-us4-shared-unavailable|us4SharedUnavailable"
)

LIVE_ACTIVITY_SCENARIOS=(
  "window-on-time"
  "window-delayed"
  "window-platform-changed"
  "window-stale-data"
  "window-offline"
  "window-alternative-needed"
  "train-pre-departure"
  "train-on-board"
  "train-cancelled"
  "itinerary-planning"
  "itinerary-at-risk"
  "itinerary-cancelled"
  "leg-mid-journey"
  "leg-approaching-interchange"
  "leg-final"
)

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Captures RightTrain visual review screenshots using DEBUG preview launch arguments.

Options:
  --output DIR          Write screenshots to DIR.
  --simulator NAME      Simulator name to use when SIMULATOR_UDID is not set.
  --udid UDID           Simulator UDID to use.
  --skip-build          Reuse the existing built app from DERIVED_DATA_PATH.
  --app-only            Capture app screens only.
  --live-only           Capture Live Activity screens only.
  --help                Show this help.

Common environment overrides:
  OUTPUT_DIR, SIMULATOR_NAME, SIMULATOR_UDID, DERIVED_DATA_PATH,
  APP_LAUNCH_DELAY, LIVE_ACTIVITY_DELAY, DYNAMIC_ISLAND_CLICK_Y_OFFSET,
  DYNAMIC_ISLAND_HOST_X, DYNAMIC_ISLAND_HOST_Y, SIMULATOR_HOME_METHOD,
  SIMULATOR_LOCK_METHOD.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --simulator)
      SIMULATOR_NAME="$2"
      shift 2
      ;;
    --udid)
      SIMULATOR_UDID="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --app-only)
      CAPTURE_APP=1
      CAPTURE_LIVE_ACTIVITY=0
      shift
      ;;
    --live-only)
      CAPTURE_APP=0
      CAPTURE_LIVE_ACTIVITY=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

log() {
  printf '[screenshots] %s\n' "$*"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

fail_accessibility() {
  local detail="${1:-}"
  cat >&2 <<EOF
Simulator UI automation is blocked by macOS Accessibility permissions.

Live Activity lock-screen and expanded Dynamic Island captures need to drive
Simulator UI outside simctl's screenshot API. Grant Accessibility permission to
the terminal app running this script, then rerun the screenshot target:

  System Settings > Privacy & Security > Accessibility

Enable Terminal, iTerm, or Codex as appropriate.
EOF
  if [[ -n "$detail" ]]; then
    printf '\nOriginal automation error:\n%s\n' "$detail" >&2
  fi
  exit 1
}

ensure_system_events_access() {
  local output
  if output="$(osascript \
    -e 'tell application "Simulator" to activate' \
    -e 'delay 0.2' \
    -e 'tell application "System Events"' \
    -e 'tell process "Simulator" to get position of front window' \
    -e 'end tell' 2>&1 >/dev/null)"; then
    return
  fi
  fail_accessibility "$output"
}

resolve_simulator_udid() {
  if [[ -n "$SIMULATOR_UDID" ]]; then
    return
  fi

  SIMULATOR_UDID="$(
    xcrun simctl list devices available |
      awk -F '[()]' -v name="$SIMULATOR_NAME" '$0 ~ name && ($0 ~ /Booted/ || $0 ~ /Shutdown/) { print $2; exit }'
  )"

  if [[ -z "$SIMULATOR_UDID" ]]; then
    echo "Could not find an available simulator named '$SIMULATOR_NAME'." >&2
    echo "Set SIMULATOR_UDID or SIMULATOR_NAME and retry." >&2
    exit 1
  fi
}

boot_simulator() {
  log "Booting simulator $SIMULATOR_NAME ($SIMULATOR_UDID)"
  xcrun simctl boot "$SIMULATOR_UDID" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$SIMULATOR_UDID" -b

  if [[ "$OPEN_SIMULATOR" == "1" ]]; then
    open -a Simulator --args -CurrentDeviceUDID "$SIMULATOR_UDID" >/dev/null 2>&1 || open -a Simulator >/dev/null 2>&1 || true
    sleep 2
  fi
}

build_and_install() {
  if [[ "$SKIP_BUILD" != "1" ]]; then
    log "Building $SCHEME ($CONFIGURATION)"
    xcodebuild \
      -project "$PROJECT_PATH" \
      -scheme "$SCHEME" \
      -configuration "$CONFIGURATION" \
      -destination "id=$SIMULATOR_UDID" \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      CODE_SIGNING_ALLOWED=NO \
      build
  fi

  local app_path="$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}-iphonesimulator/${SCHEME}.app"
  if [[ ! -d "$app_path" ]]; then
    echo "Built app not found at $app_path" >&2
    echo "Set DERIVED_DATA_PATH or rerun without --skip-build." >&2
    exit 1
  fi

  log "Installing $app_path"
  xcrun simctl install "$SIMULATOR_UDID" "$app_path"
  xcrun simctl privacy "$SIMULATOR_UDID" grant notifications "$BUNDLE_ID" >/dev/null 2>&1 || true
}

terminate_app() {
  xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
}

launch_app() {
  xcrun simctl launch --terminate-running-process "$SIMULATOR_UDID" "$BUNDLE_ID" "$@" >/dev/null
}

capture_screenshot() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  xcrun simctl io "$SIMULATOR_UDID" screenshot --type="$SCREENSHOT_TYPE" "$file" >/dev/null
}

press_simulator_shortcut() {
  local key="$1"
  local modifiers="$2"
  local output

  if ! output="$(osascript \
    -e 'tell application "Simulator" to activate' \
    -e 'delay 0.2' \
    -e "tell application \"System Events\" to keystroke \"$key\" using {$modifiers}" 2>&1 >/dev/null)"; then
    fail_accessibility "$output"
  fi
}

go_home() {
  case "$SIMULATOR_HOME_METHOD" in
    springboard)
      xcrun simctl launch "$SIMULATOR_UDID" com.apple.springboard >/dev/null
      ;;
    shortcut)
      press_simulator_shortcut "h" "command down, shift down"
      ;;
    *)
      echo "Unsupported SIMULATOR_HOME_METHOD: $SIMULATOR_HOME_METHOD" >&2
      exit 2
      ;;
  esac
  sleep "$HOME_DELAY"
}

lock_device() {
  case "$SIMULATOR_LOCK_METHOD" in
    shortcut)
      press_simulator_shortcut "l" "command down"
      ;;
    *)
      echo "Unsupported SIMULATOR_LOCK_METHOD: $SIMULATOR_LOCK_METHOD" >&2
      exit 2
      ;;
  esac
  sleep "$LOCK_DELAY"
}

dynamic_island_point() {
  local output
  if [[ -n "$DYNAMIC_ISLAND_HOST_X" && -n "$DYNAMIC_ISLAND_HOST_Y" ]]; then
    printf '%s,%s\n' "$DYNAMIC_ISLAND_HOST_X" "$DYNAMIC_ISLAND_HOST_Y"
    return
  fi

  if ! output="$(osascript \
    -e 'tell application "Simulator" to activate' \
    -e 'delay 0.2' \
    -e 'tell application "System Events"' \
    -e 'tell process "Simulator"' \
    -e 'set frontmost to true' \
    -e 'set p to position of front window' \
    -e 'set s to size of front window' \
    -e 'end tell' \
    -e "set clickX to (item 1 of p) + ((item 1 of s) / 2) + $DYNAMIC_ISLAND_CLICK_X_OFFSET" \
    -e "set clickY to (item 2 of p) + $DYNAMIC_ISLAND_CLICK_Y_OFFSET" \
    -e 'return ((clickX as integer) as text) & "," & ((clickY as integer) as text)' \
    -e 'end tell' 2>&1)"; then
    fail_accessibility "$output"
  fi
  printf '%s\n' "$output"
}

long_press_host_point() {
  local x="$1"
  local y="$2"
  local duration="$3"
  local helper_base helper
  helper_base="$(mktemp "${TMPDIR:-/tmp}/righttrain-click.XXXXXX")"
  helper="$helper_base.swift"
  mv "$helper_base" "$helper"
  cat > "$helper" <<'SWIFT'
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 4,
      let x = Double(CommandLine.arguments[1]),
      let y = Double(CommandLine.arguments[2]),
      let duration = Double(CommandLine.arguments[3]) else {
    fputs("usage: click.swift x y duration\n", stderr)
    exit(2)
}

let point = CGPoint(x: x, y: y)
let source = CGEventSource(stateID: .hidSystemState)
let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)

down?.post(tap: .cghidEventTap)
Thread.sleep(forTimeInterval: duration)
up?.post(tap: .cghidEventTap)
SWIFT

  if ! xcrun swift "$helper" "$x" "$y" "$duration"; then
    rm -f "$helper"
    return 1
  fi
  rm -f "$helper"
}

expand_dynamic_island() {
  local point host_x host_y
  point="$(dynamic_island_point)"
  IFS=, read -r host_x host_y <<< "$point"
  long_press_host_point "$host_x" "$host_y" "$DYNAMIC_ISLAND_LONG_PRESS_SECONDS"
  sleep 1
}

capture_app_screens() {
  log "Capturing app screens"
  local entry name surface file

  for entry in "${APP_SURFACES[@]}"; do
    IFS='|' read -r name surface <<< "$entry"
    file="$OUTPUT_DIR/app/$name.$SCREENSHOT_EXT"
    log "App: $name"
    terminate_app
    launch_app --righttrain-preview --righttrain-preview-surface="$surface"
    sleep "$APP_LAUNCH_DELAY"
    capture_screenshot "$file"
  done
}

start_live_activity() {
  local scenario="$1"
  terminate_app
  launch_app --righttrain-live-activity-preview="$scenario"
  sleep "$LIVE_ACTIVITY_DELAY"
}

end_live_activities() {
  terminate_app
  launch_app --righttrain-live-activity-preview=end
  sleep 1
  terminate_app
}

capture_live_activity_screens() {
  log "Capturing Live Activity screens"
  local scenario

  for scenario in "${LIVE_ACTIVITY_SCENARIOS[@]}"; do
    log "Live Activity: $scenario"
    end_live_activities
    start_live_activity "$scenario"

    go_home
    capture_screenshot "$OUTPUT_DIR/live-activity/home-compact/$scenario.$SCREENSHOT_EXT"

    expand_dynamic_island
    capture_screenshot "$OUTPUT_DIR/live-activity/dynamic-expanded/$scenario.$SCREENSHOT_EXT"

    lock_device
    capture_screenshot "$OUTPUT_DIR/live-activity/lock-screen/$scenario.$SCREENSHOT_EXT"
  done

  end_live_activities
}

html_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  printf '%s' "$value"
}

write_gallery_section() {
  local title="$1"
  local folder="$2"
  shift 2
  local names=("$@")
  local name file

  {
    printf '<section>\n<h2>%s</h2>\n<div class="grid">\n' "$(html_escape "$title")"
    for name in "${names[@]}"; do
      file="$folder/$name.$SCREENSHOT_EXT"
      if [[ -f "$OUTPUT_DIR/$file" ]]; then
        printf '<figure><img src="%s" alt="%s"><figcaption>%s</figcaption></figure>\n' \
          "$(html_escape "$file")" "$(html_escape "$name")" "$(html_escape "$name")"
      fi
    done
    printf '</div>\n</section>\n'
  } >> "$OUTPUT_DIR/index.html"
}

generate_gallery() {
  log "Writing gallery"
  mkdir -p "$OUTPUT_DIR"
  cat > "$OUTPUT_DIR/index.html" <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>RightTrain Review Screenshots</title>
<style>
body { margin: 0; background: #f5f7f9; color: #111; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
header { padding: 32px; border-bottom: 1px solid #dfe5ea; background: #fff; }
h1 { margin: 0 0 8px; font-size: 28px; }
p { margin: 0; color: #68707a; }
section { padding: 28px 32px; }
h2 { margin: 0 0 18px; font-size: 20px; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 18px; align-items: start; }
figure { margin: 0; padding: 12px; background: #fff; border: 1px solid #dfe5ea; border-radius: 8px; }
img { width: 100%; height: auto; display: block; border-radius: 6px; background: #eef2f5; }
figcaption { margin-top: 10px; font-size: 13px; color: #4f5963; overflow-wrap: anywhere; }
</style>
</head>
<body>
<header>
<h1>RightTrain Review Screenshots</h1>
<p>Generated $(date) into $(html_escape "$OUTPUT_DIR").</p>
</header>
HTML

  local app_names=()
  local entry name surface
  for entry in "${APP_SURFACES[@]}"; do
    IFS='|' read -r name surface <<< "$entry"
    app_names+=("$name")
  done

  write_gallery_section "App screens" "app" "${app_names[@]}"
  write_gallery_section "Live Activity - Lock Screen" "live-activity/lock-screen" "${LIVE_ACTIVITY_SCENARIOS[@]}"
  write_gallery_section "Live Activity - Dynamic Island compact" "live-activity/home-compact" "${LIVE_ACTIVITY_SCENARIOS[@]}"
  write_gallery_section "Live Activity - Dynamic Island expanded" "live-activity/dynamic-expanded" "${LIVE_ACTIVITY_SCENARIOS[@]}"

  cat >> "$OUTPUT_DIR/index.html" <<HTML
</body>
</html>
HTML
}

main() {
  require_command xcrun
  require_command xcodebuild
  if [[ "$CAPTURE_LIVE_ACTIVITY" == "1" ]]; then
    require_command osascript
  fi

  resolve_simulator_udid
  boot_simulator
  if [[ "$CAPTURE_LIVE_ACTIVITY" == "1" && ( "$SIMULATOR_LOCK_METHOD" == "shortcut" || -z "$DYNAMIC_ISLAND_HOST_X" || -z "$DYNAMIC_ISLAND_HOST_Y" ) ]]; then
    ensure_system_events_access
  fi
  build_and_install

  mkdir -p "$OUTPUT_DIR"

  if [[ "$CAPTURE_APP" == "1" ]]; then
    capture_app_screens
  fi

  if [[ "$CAPTURE_LIVE_ACTIVITY" == "1" ]]; then
    capture_live_activity_screens
  fi

  generate_gallery
  log "Done: $OUTPUT_DIR"
  log "Gallery: $OUTPUT_DIR/index.html"
}

main "$@"
