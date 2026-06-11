# TestFlight Readiness

This runbook covers the controlled RightTrain TestFlight beta from archive creation through external tester support.

## Release Build

Release archives use:

- API base URL: `https://api.righttrain.app`
- APNs environment: `production`
- Bundle identifier default: `com.righttrain.ios`
- Live Activity extension bundle identifier: `$(RIGHTTRAIN_BUNDLE_IDENTIFIER).liveactivity`
- Signing team default: `CV8JK3JKZX`

Override the team, bundle identifier, version, or build number without editing the Xcode project:

```sh
RIGHTTRAIN_DEVELOPMENT_TEAM=ABCDE12345 \
RIGHTTRAIN_BUNDLE_IDENTIFIER=com.example.righttrain \
RIGHTTRAIN_MARKETING_VERSION=0.1.0 \
RIGHTTRAIN_BUILD_NUMBER=42 \
ios/RightTrain/scripts/archive-testflight.sh
```

The script archives `RightTrain` for a generic iOS device and uploads the export to App Store Connect using `ios/RightTrain/TestFlightExportOptions.plist`. It requires an Apple developer account configured in Xcode with access to the target App Store Connect app record.

## Xcode Cloud Workflow

Use Xcode Cloud as the primary beta-distribution path. It keeps signing, archive export, App Store Connect upload, and TestFlight distribution inside Apple's toolchain.

Recommended workflow:

1. Open `ios/RightTrain/RightTrain.xcodeproj` in Xcode.
2. Configure Xcode Cloud for the `RightTrain` scheme and App Store Connect app record.
3. Create a manually started workflow named `TestFlight`.
4. Use the `Release` configuration and archive for iOS.
5. Enable App Store Connect/TestFlight distribution after archive success.
6. Set the next Xcode Cloud build number above any existing App Store Connect build.
7. Start the workflow only after the target commit has passed iOS tests.

Workflow assumptions:

- The app bundle identifier exists in Apple Developer and App Store Connect.
- App Attest, Push Notifications, and Live Activities are enabled for the app and extension identifiers.
- The Xcode Cloud workflow has permission to manage signing for the app and Live Activity extension.
- The Release build settings retain `RIGHTTRAIN_API_BASE_URL=https://api.righttrain.app` and `RIGHTTRAIN_APNS_ENVIRONMENT=production`.

Keep `ios/RightTrain/scripts/archive-testflight.sh` as a local fallback when an operator needs to archive from Xcode on a Mac with the right signing account.

## External Tester Smoke Test

Before adding external testers:

1. Install the TestFlight build on a non-development iPhone.
2. Complete App Attest-backed device registration and verify the session persists after force quit and relaunch.
3. Search two stations and create one journey watch.
4. Allow notifications and confirm the device token is registered against the production APNs environment.
5. Start a Live Activity from an active journey watch and confirm it updates or ends when the watch is deleted.
6. Use Settings to open privacy, terms, and support links.
7. Delete the account and confirm local state, active window, APNs token, and Live Activity state are cleared.

## TestFlight Metadata

Use this copy in App Store Connect for beta review and tester onboarding.

- Beta app description: "RightTrain helps UK rail beta testers monitor a departure window and choose the first catchable direct train by current arrival. The beta uses live timetable, realtime, APNs, and Live Activity feeds, so alerts may be late, incomplete, or wrong during data outages."
- What to test: "Open the app, create one monitored direct journey window, allow notifications, review journey recommendations, and report any wrong, late, confusing, or missing alerts."
- Feedback email: `support@righttrain.app`
- Support URL: `https://righttrain.app/support`
- Privacy policy URL: `https://righttrain.app/privacy`
- Test account: not required. The app creates an App Attest-backed device session on first launch.
- Review notes: "The app is a controlled rail-alert beta. It creates an App Attest-backed device session and asks for notification permission to test the core push-alert flow. The free beta entitlement allows one active monitored journey window."

Privacy summary for TestFlight review:

- Account data: app user identifier, App Attest identity metadata, session metadata, and optional recovery/support contact data when provided.
- User content: selected origin, destination, departure window, active journey watch, and feedback sent through support.
- Device data: APNs alert token, Live Activity token, app version, build number, bundle identifier, device model, OS version, and APNs environment.
- Diagnostics: Apple crash reports, system logs emitted through `os.Logger`, and operational backend logs.
- Tracking: no cross-app tracking or advertising identifiers.

## Incident Runbook

### Timetable Freshness

Symptoms: missing services, stale schedules, unexpected empty recommendations, or timetable importer lag.

Triage:

1. Check importer logs for latest reference and timetable filenames.
2. Confirm the selected S3 timetable prefix contains current files.
3. Inspect import metadata and service counts for the active timetable.
4. Compare a reported missing service against the latest Darwin timetable source.

Mitigation:

- Pause tester expansion while stale timetable data is active.
- Re-run the timetable/reference importer after confirming source files.
- If source data is stale, add a beta status note and ask testers to verify station boards.

Recovery:

- Confirm new recommendations are created from the fresh timetable.
- Record the stale interval, affected routes, source filenames, and tester-facing impact.

### Realtime Ingest Outage

Symptoms: platform changes do not appear, departures remain unreported, recommendations do not reflect cancellations, or realtime lag increases.

Triage:

1. Check Darwin transport connectivity and subscriber logs.
2. Check decoder anomaly counts and raw message ingest timestamps.
3. Verify realtime cache writes and active-window refresh behavior.
4. Compare a live National Rail departure board against app state for a known route.

Mitigation:

- Keep the app available but treat alerts as degraded.
- Post a beta status note that realtime alerts may lag.
- Restart the ingest worker only after confirming credentials and broker connectivity.

Recovery:

- Confirm fresh realtime messages update journeys and active windows.
- Audit any alerts emitted during the outage and note false, late, or missing alerts.

### APNs Failure

Symptoms: active watches refresh in app but push alerts or Live Activity updates do not arrive.

Triage:

1. Confirm device tokens are registered with `production` for TestFlight builds.
2. Check APNs provider responses for invalid token, bad topic, auth, payload, or rate-limit errors.
3. Verify alert outbox rows are created and delivered or retried.
4. Confirm the app bundle ID and Live Activity extension topic match the App Store Connect app.

Mitigation:

- Ask testers to open the app for active-window status until APNs delivery recovers.
- Suppress repeated retries for invalid tokens.
- Rebuild only if the bundle ID, entitlements, or APNs environment is wrong.

Recovery:

- Send a low-risk test alert to an internal device.
- Confirm alert token and Live Activity token registration still work after reinstall.

### False-Alert Escalation

Symptoms: tester reports a wrong recommended train, incorrect delay/platform/cancellation, or confusing alert copy.

Triage:

1. Capture tester, device build, route, time window, alert text, and screenshot.
2. Pull the active-window recommendation payload and alert outbox entry.
3. Compare timetable, realtime, scoring reasons, and National Rail state at the alert time.
4. Classify the cause as source data, ingest lag, scoring bug, copy ambiguity, or APNs duplicate/stale delivery.

Mitigation:

- If alerts are actively misleading, pause alert delivery for affected route patterns.
- Reply to the tester with the known limitation and ask them to verify station boards.
- Create a follow-up issue with the payload, source messages, and expected behavior.

Recovery:

- Add a regression test when the cause is code or scoring behavior.
- Update onboarding or alert copy when the cause is beta reliability expectation mismatch.
