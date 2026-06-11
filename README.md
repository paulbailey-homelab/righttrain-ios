# RightTrain iOS

Native SwiftUI iPhone app shell for the RightTrain TestFlight beta.

## Project

- Xcode project: `ios/RightTrain/RightTrain.xcodeproj`
- Scheme: `RightTrain`
- Minimum iOS: 17.0
- Release API base URL: `https://api.righttrain.app`
- Debug API base URL: `https://clearsignal-api.lan.dreamshake.net`

Open `RightTrain.xcodeproj` directly in Xcode. `RightTrain/Info.plist` reads `RightTrainAPIBaseURL` from the `RIGHTTRAIN_API_BASE_URL` build setting, so API targets can change per build without editing source files.

Debug builds default to `https://clearsignal-api.lan.dreamshake.net`, which works for devices and simulators on the homelab network. Override `RIGHTTRAIN_API_BASE_URL` in Xcode build settings, a scheme action, or the `xcodebuild` command line for staging or ad hoc builds. Release builds default to `https://api.righttrain.app`, which is used for TestFlight and App Store archives.

## Feature Surface

- Anonymous device registration via Apple App Attest: `POST /v1/auth/device/challenge` followed by `POST /v1/auth/device/register`
- Keychain-backed bearer session persistence plus `/v1/me` refresh on launch
- Station typeahead via `GET /v1/stations`
- Direct window recommendation via `GET /v1/windows/direct/recommendations`
- Monitored window creation, refresh, and deletion via `/v1/windows/direct/subscriptions`
- Active window detail showing recommendation, timing, platform, and disruption state
- Journey share links from active direct windows or itineraries, with public
  shared-journey deep links at `righttrain://journey-shares/{shareID}`
- Redesigned live guidance surfaces that prioritize manual plan-and-monitor
  setup when no journey is active, then route, status, timing, platform,
  freshness, and next action once monitoring exists
- Consistent onboarding, signed-out, settings, feedback, journey detail, and
  shared-link presentation using the same rail labels and action-needed
  product language
- Notification permission onboarding plus APNs alert-token registration via `PUT /v1/devices/{clientDeviceID}/apns/alert-token` (deleted on sign-out)
- Live Activity update and push-to-start token registration/deletion as monitored-window activities start, switch, and end

## Visual Redesign Implementation Context

The completed redesign feature is tracked in `specs/003-ios-visual-redesign/`.
Use `spec.md` for user value and success criteria, `plan.md` for technical
scope, `contracts/ios-redesign-ui-contract.md` for observable surface rules,
and `quickstart.md` for build, XCTest, screenshot, and product acceptance
validation. The core product stance is manual plan-and-monitor first when no
journey is active, active guidance first once monitoring exists, and
action-needed-only push/Live Activity interruptions. The screenshot evidence
checklist lives at `design/review-screenshots/ios-redesign-checklist.md`.

## Local Build

```sh
xcodebuild \
  -project ios/RightTrain/RightTrain.xcodeproj \
  -scheme RightTrain \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

To point a local or staging build at another API without editing code:

```sh
xcodebuild \
  -project ios/RightTrain/RightTrain.xcodeproj \
  -scheme RightTrain \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  RIGHTTRAIN_API_BASE_URL=https://api.righttrain.app \
  build
```

Run unit tests with any available iPhone simulator:

```sh
SIMULATOR_UDID="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ && /Shutdown|Booted/ { print $2; exit }')"
xcodebuild \
  -project ios/RightTrain/RightTrain.xcodeproj \
  -scheme RightTrain \
  -destination "id=${SIMULATOR_UDID}" \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## Visual Review Screenshots

Regenerate the app and Live Activity review gallery from the repository root:

```sh
make ios-screenshots
```

The command writes screenshots and an `index.html` gallery under `design/review-screenshots/`. See `docs/righttrain-screenshot-capture.md` for simulator permissions, Live Activity variants, and tuning options.
The redesign app-only pass currently captures 43 in-app states covering the
baseline app, first-screen guidance, setup/results, push entry, onboarding,
settings, feedback, detail, and shared-link views.

For TestFlight, the Release configuration points at `https://api.righttrain.app` and registers APNs tokens with the `production` environment. The app, Live Activity extension, and test bundle derive their identifiers from `RIGHTTRAIN_BUNDLE_IDENTIFIER`, so a beta bundle can be produced without editing source:

```sh
RIGHTTRAIN_DEVELOPMENT_TEAM=ABCDE12345 \
RIGHTTRAIN_BUNDLE_IDENTIFIER=com.example.righttrain \
RIGHTTRAIN_MARKETING_VERSION=0.1.0 \
RIGHTTRAIN_BUILD_NUMBER=42 \
ios/RightTrain/scripts/archive-testflight.sh
```

The script writes archives under `tmp/ios/` and uses `ios/RightTrain/TestFlightExportOptions.plist` for App Store Connect upload. See `docs/testflight-readiness.md` for TestFlight metadata, privacy/support copy, and live-data incident handling.

## Xcode Cloud Upload

Use Xcode Cloud as the primary automated TestFlight path:

- Configure a workflow from Xcode for `RightTrain.xcodeproj` and the `RightTrain` scheme.
- Use a manually started workflow for controlled beta uploads.
- Set the action to archive the `Release` configuration for iOS.
- Enable App Store Connect/TestFlight distribution after a successful archive.
- Confirm the workflow uses the App Store Connect app whose bundle identifier matches `RIGHTTRAIN_BUNDLE_IDENTIFIER`.

The Release configuration already points at `https://api.righttrain.app` and production APNs, so Xcode Cloud does not need repository secrets for the standard beta build.

## APNs Environment Routing

APNs tokens are registered with the backend environment configured for the build. `RightTrainAPNsEnvironment` is populated from `RIGHTTRAIN_APNS_ENVIRONMENT` in `Info.plist`; the app maps `sandbox` or `development` to the backend `sandbox` value and `production` to `production`.

`RightTrain/RightTrain.entitlements` enables Push Notifications for both Debug and Release. Debug sets `APS_ENVIRONMENT=development` and `RIGHTTRAIN_APNS_ENVIRONMENT=sandbox`; Release sets both APNs values to production. TestFlight and App Store archives use the Release configuration, so they register alert, Live Activity update, and Live Activity push-to-start tokens with `production`. The backend stores the environment per token and routes payloads to the matching APNs endpoint.

Apple App Attest is used for anonymous account registration; it does not require an explicit entitlement key but does need the app to be code-signed with a real provisioning profile. Xcode debug builds on real devices emit `development` attestations; TestFlight and App Store builds emit `production` attestations. Debug simulator builds emit a development-only simulator payload only when `RIGHTTRAIN_API_BASE_URL` points at `clearsignal-api.lan.dreamshake.net`, `localhost`, `127.0.0.1`, or `::1`; the API must also have `APP_ATTEST_SIMULATOR_BYPASS=true` and include the request host in `APP_ATTEST_SIMULATOR_BYPASS_HOSTS`. The backend's `APP_ATTEST_ALLOWED_ENVIRONMENTS` config drives which real App Attest environments are accepted (production-only by default).

## Backend Compatibility

The iOS app targets the monitored-window API added after the older web-only direct journey flow. If the app can search stations but shows `Backend Update Required`, the backend you pointed it at is still serving an older OpenAPI contract with `/v1/journeys/direct` but without:

- `GET /v1/windows/direct/recommendations`
- `POST /v1/windows/direct/subscriptions`

Deploy a backend image built from a commit that includes those endpoints before testing monitored window creation.
