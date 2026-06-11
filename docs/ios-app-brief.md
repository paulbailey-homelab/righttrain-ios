# RightTrain iOS App Brief

This document is prompt context for extending the existing native iPhone client
against the current RightTrain backend. The app already exists in
`ios/RightTrain/`; new iOS work should build on that project rather than
starting a new client.

## Product Shape

RightTrain is a backend-led UK rail journey tracking product focused on:

- station search using CRS-facing UK rail semantics
- direct-window recommendations for "what should I take?"
- monitored direct windows with active guidance
- itinerary subscriptions for journeys with changes
- APNs alerts and Live Activity updates
- feedback capture for beta trust signals
- StoreKit-backed entitlement sync

The backend owns timetable, realtime overlay, recommendation, entitlement, and
alert decisions. The iOS app should stay a thin SwiftUI client over the OpenAPI
contract.

## Current Backend Responsibilities

- stores static timetable and reference data in Postgres
- stores normalized realtime overlays in Postgres and Valkey
- ingests Darwin replay or live broker traffic
- polls S3 for newer reference, timetable, update, and fixed-link files
- exposes station, journey, window, itinerary, notification, billing, feedback,
  and account APIs
- evaluates subscriptions asynchronously and records notification state
- drains notification outbox rows to file, webhook, or direct APNs delivery
- records APNs alert, Live Activity update, and Live Activity push-to-start
  tokens per backend environment
- verifies and syncs StoreKit transaction and notification state

## Runtime Services

- `api`: HTTP API for auth, search, journey detail, monitored windows,
  itineraries, billing, feedback, docs, health, and ops.
- `ingest`: reference/timetable import, Darwin replay, live broker consumer,
  and S3 import poller.
- `alerts`: subscription evaluation, notification creation, APNs/outbox
  delivery, and retention maintenance.
- `frontend`: internal Svelte workspace for browser-based development and ops
  workflows.

The system is eventually consistent. The app should assume:

- timetable freshness and realtime freshness are separate concerns
- realtime fields can appear after the initial timetable-based result
- subscription notifications and Live Activity updates are derived
  asynchronously by workers
- APNs and StoreKit behavior depends on the client-supplied runtime environment

## Client-Facing API Surface

Use `docs/openapi.yaml` as the source of truth. Important route groups are:

### Health And Docs

- `GET /healthz`
- `GET /readyz`
- `GET /metrics`
- `GET /openapi.yaml`
- `GET /swagger`

### Auth And Account

- `POST /v1/auth/device/challenge`
- `POST /v1/auth/device/register`
- `GET /v1/me`
- `DELETE /v1/me`

### Search And Journey Discovery

- `GET /v1/stations?query={text}&limit={n}`
- `GET /v1/stations/direct-destinations`
- `GET /v1/journeys/direct`
- `GET /v1/journeys/direct/{serviceId}`
- `GET /v1/journeys/plan`
- `GET /v1/windows/direct/recommendations`

### Monitored Windows And Itineraries

- `POST /v1/windows/direct/subscriptions`
- `GET /v1/windows/direct/subscriptions/active`
- `GET /v1/windows/direct/subscriptions/{windowSubscriptionID}`
- `DELETE /v1/windows/direct/subscriptions/{windowSubscriptionID}`
- `POST /v1/itinerary-subscriptions`
- `GET /v1/itinerary-subscriptions/active`
- `GET /v1/itinerary-subscriptions/{itinerarySubscriptionID}`
- `DELETE /v1/itinerary-subscriptions/{itinerarySubscriptionID}`

### Notifications And Device Tokens

- `GET /v1/subscriptions/stream`
- notification list/detail routes for subscriptions, windows, and itineraries
- `PUT /v1/devices/{clientDeviceID}/apns/alert-token`
- `PUT /v1/devices/{clientDeviceID}/apns/live-activity-push-to-start-token`
- Live Activity token routes under active window and itinerary subscriptions

### Billing, Feedback, And Routines

- `GET /v1/billing/products`
- `POST /v1/billing/storekit/sync`
- `POST /v1/billing/storekit/notifications`
- `POST /v1/feedback`
- `GET /v1/commute/routines`
- routine create/update/delete routes

## Recommended iOS Extension Points

Build new native work around these existing flows:

1. Keep device registration App Attest-backed and persist bearer sessions in the keychain.
2. Use station typeahead with CRS as the user-facing station identifier.
3. Prefer direct-window recommendations for the main commuter flow.
4. Keep monitored-window active guidance as the primary logged-in home state.
5. Use Live Activities for glanceable recommendation, platform, timing, and disruption state.
6. Send APNs token updates whenever alert, push-to-start, or Live Activity tokens rotate.
7. Sync StoreKit transactions after purchase, restore, launch, and transaction updates.
8. Capture feedback from active guidance and notification history.

## Domain Model The App Should Expect

- `Station`: CRS, TPL, display name, and optional operator metadata.
- `DirectWindowRecommendation`: ranked train option with timing, platform,
  cancellation, confidence, and scoring context.
- `WindowSubscription`: user-owned monitored departure window with selected or
  pinned train state.
- `JourneyDetail`: full stop list with scheduled and realtime fields.
- `Itinerary`: one or more legs with transfer and realtime state.
- `SubscriptionNotification`: timestamped attention or state-update event.
- `User`: account/session state plus entitlement limits.
- `BillingProduct`: StoreKit product metadata and entitlement tier.

## UX Constraints

- Use UK rail semantics and the `Europe/London` timezone.
- Treat CRS as the visible station identifier.
- Treat train identity as RID plus service date where available.
- Prefer explicit delay, cancellation, platform, interchange, and recommendation
  wording over generic "service update" copy.
- Keep the primary recommendation glanceable in under one second.
- Treat stale realtime data as a user-facing confidence state, not a silent
  implementation detail.
- Expect SSE for active subscription updates rather than WebSockets.

## Operational Assumptions

- User-owned resources require a bearer session when backend auth is enabled.
- Debug simulator App Attest bypass is allowed only for configured local or LAN
  API hosts and must stay off for production-facing deployments.
- APNs tokens are stored with `sandbox` or `production`; TestFlight and App
  Store builds should register production tokens.
- StoreKit sandbox entitlement behavior is controlled server-side and may be
  limited to configured beta users.
- The notification outbox can deliver directly to APNs; file and webhook modes
  remain useful for local development and integration testing.
- API and frontend hosting are intentionally decoupled.

## Prompt Seed

When generating iOS work, frame the task as:

"Extend the existing SwiftUI iPhone app for UK rail journey tracking against the
RightTrain API. Preserve the App Attest device session model, keychain session
storage, OpenAPI-driven networking, monitored-window guidance, APNs token
registration, Live Activities, StoreKit entitlement sync, and Europe/London rail
semantics. New UI should make recommendation, platform, timing, cancellation,
interchange, and stale-data states explicit without duplicating backend-owned
decision logic."
