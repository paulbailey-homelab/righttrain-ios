# RightTrain iOS Screenshot Capture

This workflow captures iOS review screenshots only. It does not capture or verify the web UI.

Use this document when an agent needs to regenerate screenshots under:

```text
design/review-screenshots/YYYY-MM-DD-HHMMSS/
```

Each run writes screenshots plus an `index.html` gallery.

For an iOS visual review, check the gallery against the states below. The review must cover first-screen manual setup, active direct and
itinerary guidance, stale/offline/platform states, action-needed push entry,
Live Activity surfaces, and shared/deep-link views.

## Which Target To Use

For normal app visual review, use the app-only target:

```sh
make ios-screenshots-app SIMULATOR_UDID=5485A22C-AF33-4C4B-9E7A-23B723B49952
```

This captures the 53 in-app preview states and only needs normal simulator access.

For Live Activity review only, use:

```sh
make ios-screenshots-live SIMULATOR_UDID=5485A22C-AF33-4C4B-9E7A-23B723B49952
```

For the full app plus Live Activity set, use the explicit full target:

```sh
make ios-screenshots-full SIMULATOR_UDID=5485A22C-AF33-4C4B-9E7A-23B723B49952
```

`make ios-screenshots` is kept as a legacy alias for `ios-screenshots-full`. Do not use it as shorthand for app screenshots.

## Requirements

- Xcode and Simulator must be installed.
- The default simulator is `iPhone 17 Pro`.
- Prefer the booted review simulator when available:

```text
5485A22C-AF33-4C4B-9E7A-23B723B49952
```

- Full and Live Activity captures require macOS Accessibility permission for the app running the command, usually Codex, Terminal, or iTerm:

```text
System Settings > Privacy & Security > Accessibility
```

App-only capture does not need Accessibility permission because it uses `xcrun simctl io screenshot`.

## Output Shape

App-only output should contain:

```text
app/01-signed-out.jpg
...
app/53-station-picker-nearby-unavailable.jpg
index.html
```

Full output should contain:

```text
app/                         53 screenshots
live-activity/lock-screen/   15 screenshots
live-activity/home-compact/  15 screenshots
live-activity/dynamic-expanded/ 15 screenshots
index.html
```

Verify a finished app-only run with:

```sh
find design/review-screenshots/YYYY-MM-DD-HHMMSS/app -maxdepth 1 -type f -name '*.jpg' | wc -l
test -f design/review-screenshots/YYYY-MM-DD-HHMMSS/index.html
```

Verify a finished full run with:

```sh
find design/review-screenshots/YYYY-MM-DD-HHMMSS/app -maxdepth 1 -type f -name '*.jpg' | wc -l
find design/review-screenshots/YYYY-MM-DD-HHMMSS/live-activity/lock-screen -maxdepth 1 -type f -name '*.jpg' | wc -l
find design/review-screenshots/YYYY-MM-DD-HHMMSS/live-activity/home-compact -maxdepth 1 -type f -name '*.jpg' | wc -l
find design/review-screenshots/YYYY-MM-DD-HHMMSS/live-activity/dynamic-expanded -maxdepth 1 -type f -name '*.jpg' | wc -l
test -f design/review-screenshots/YYYY-MM-DD-HHMMSS/index.html
```

Expected counts are `53`, `15`, `15`, and `15`.

The redesign may add more app or Live Activity preview states. If it does,
update `scripts/capture-review-screenshots.sh`, record the new
expected state list here, and keep the checklist in
`design/review-screenshots/ios-redesign-checklist.md` aligned with the gallery.

## Common Commands

Use a simulator by name instead of UDID:

```sh
make ios-screenshots-app IOS_SCREENSHOT_SIMULATOR="iPhone 17 Pro"
```

Write to a stable folder:

```sh
make ios-screenshots-app IOS_SCREENSHOT_OUTPUT_DIR="$PWD/design/review-screenshots/current"
```

Reuse the existing built app:

```sh
SKIP_BUILD=1 make ios-screenshots-app
```

Increase wait times if UI state is still loading:

```sh
APP_LAUNCH_DELAY=3 LIVE_ACTIVITY_DELAY=4 make ios-screenshots-full
```

The main Makefile variables are:

- `IOS_SCREENSHOT_OUTPUT_DIR`
- `IOS_SCREENSHOT_SIMULATOR`
- `IOS_SCREENSHOT_DERIVED_DATA`
- `SIMULATOR_UDID`

## What The Script Captures

The script is:

```text
scripts/capture-review-screenshots.sh
```

It builds the Debug simulator app unless `SKIP_BUILD=1`, installs it on the simulator, launches DEBUG preview states, captures screenshots, and generates the gallery.

App preview states:

- Signed out
- Empty Pinned tab
- Pinned search
- Pinned direct journey
- Pinned direct platform unknown
- Pinned direct platform changed
- Pinned direct stale data
- Pinned direct offline
- Pinned direct cancelled
- Pinned direct on-board state
- Pinned itinerary planning
- Pinned itinerary change
- Pinned itinerary final leg
- Shared journey
- Commutes
- Plan initial state
- Settings
- Direct search results
- Direct search results after pinning
- All-routes search results
- All-routes search results after pinning
- US1 first-screen manual setup, active direct, active itinerary, stale data,
  and offline states
- US2 manual setup, routine prefill, one-off direct setup, connection-sensitive
  setup, direct results, and routes-with-changes results
- US3 push platform change, push unavailable, and notification-permission
  denied states
- US4 onboarding, signed-out, settings, feedback, journey detail, shared
  journey, shared expired, and shared unavailable states
- Station picker search, selected origin, selected destination, cancel/back
  preservation, favourites, no favourites, nearest loading, nearest results,
  location denied, and nearby unavailable states

Live Activity scenarios:

- `window-on-time`
- `window-delayed`
- `window-platform-changed`
- `window-stale-data`
- `window-offline`
- `window-alternative-needed`
- `train-pre-departure`
- `train-on-board`
- `train-cancelled`
- `itinerary-planning`
- `itinerary-at-risk`
- `itinerary-cancelled`
- `leg-mid-journey`
- `leg-approaching-interchange`
- `leg-final`

Each Live Activity scenario is captured in:

- `live-activity/lock-screen/`
- `live-activity/home-compact/`
- `live-activity/dynamic-expanded/`

## Troubleshooting

If full or Live Activity capture fails with `osascript is not allowed assistive access`, grant Accessibility permission to the app running the command and rerun the target.

If the first Live Activity run shows a system permission sheet, allow Live Activities and rerun the target. The script attempts to grant notification permission with `simctl`, but a fresh simulator can still show the Live Activity prompt.

If the Dynamic Island expanded screenshots do not expand, adjust the click offset:

```sh
DYNAMIC_ISLAND_CLICK_Y_OFFSET=135 make ios-screenshots-live
```

If automatic Simulator window coordinate detection is unreliable, provide the host click point directly:

```sh
DYNAMIC_ISLAND_HOST_X=720 DYNAMIC_ISLAND_HOST_Y=160 make ios-screenshots-live
```

## Maintenance

When adding a new app review state:

1. Add the surface to `RightTrainPreviewLaunch.Surface`.
2. Add its fixture setup in `RightTrainPreviewLaunch`.
3. Add the `filename|surface` entry to `APP_SURFACES` in `capture-review-screenshots.sh`.

When adding a new Live Activity state:

1. Add the scenario to `LiveActivityPreviewScenario`.
2. Add the raw scenario name to `LIVE_ACTIVITY_SCENARIOS` in `capture-review-screenshots.sh`.
