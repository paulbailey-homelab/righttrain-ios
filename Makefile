SCHEME ?= RightTrain
PROJECT ?= RightTrain.xcodeproj
TEST_DESTINATION ?= platform=iOS Simulator,name=iPhone 17 Pro
TAG_REMOTE ?= origin
TAG_PREFIX ?= v
TESTFLIGHT_BRANCH ?= testflight
TESTFLIGHT_BASE_BRANCH ?= main
TESTFLIGHT_REMOTE ?= origin
TESTFLIGHT_INTERNAL_BRANCH ?= testflight-internal
TESTFLIGHT_INTERNAL_BASE_BRANCH ?= main
TESTFLIGHT_INTERNAL_REMOTE ?= origin
IOS_SCREENSHOT_SCRIPT ?= $(CURDIR)/scripts/capture-review-screenshots.sh
IOS_SCREENSHOT_OUTPUT_DIR ?= $(CURDIR)/design/review-screenshots/$(shell date +%F-%H%M%S)
IOS_SCREENSHOT_SIMULATOR ?= iPhone 17 Pro
IOS_SCREENSHOT_DERIVED_DATA ?= $(CURDIR)/DerivedData/ScreenshotCapture

.PHONY: build test tag-patch testflight testflight-internal ios-screenshots ios-screenshots-full ios-screenshots-app ios-screenshots-live

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(TEST_DESTINATION)' CODE_SIGNING_ALLOWED=NO test

tag-patch:
	@git fetch --tags $(TAG_REMOTE)
	@latest=$$(git tag --list '$(TAG_PREFIX)*' | sed -nE 's/^$(TAG_PREFIX)([0-9]+)\.([0-9]+)\.([0-9]+)$$/\1 \2 \3/p' | sort -n -k1,1 -k2,2 -k3,3 | tail -n 1); \
	if [ -z "$$latest" ]; then \
		echo "No $(TAG_PREFIX)X.Y.Z tags found"; \
		exit 1; \
	fi; \
	set -- $$latest; \
	next="$(TAG_PREFIX)$$1.$$2.$$(( $$3 + 1 ))"; \
	echo "Creating $$next"; \
	git tag "$$next"; \
	git push $(TAG_REMOTE) "$$next"

testflight:
	@set -e; \
	git switch $(TESTFLIGHT_BRANCH); \
	trap 'git switch $(TESTFLIGHT_BASE_BRANCH)' EXIT; \
	git merge $(TESTFLIGHT_BASE_BRANCH); \
	git push $(TESTFLIGHT_REMOTE) $(TESTFLIGHT_BRANCH)

testflight-internal:
	@set -e; \
	git switch $(TESTFLIGHT_INTERNAL_BRANCH); \
	trap 'git switch $(TESTFLIGHT_INTERNAL_BASE_BRANCH)' EXIT; \
	git merge $(TESTFLIGHT_INTERNAL_BASE_BRANCH); \
	git push $(TESTFLIGHT_INTERNAL_REMOTE) $(TESTFLIGHT_INTERNAL_BRANCH)

ios-screenshots: ios-screenshots-full

ios-screenshots-full:
	OUTPUT_DIR="$(IOS_SCREENSHOT_OUTPUT_DIR)" SIMULATOR_NAME="$(IOS_SCREENSHOT_SIMULATOR)" SIMULATOR_UDID="$(SIMULATOR_UDID)" DERIVED_DATA_PATH="$(IOS_SCREENSHOT_DERIVED_DATA)" "$(IOS_SCREENSHOT_SCRIPT)"

ios-screenshots-app:
	OUTPUT_DIR="$(IOS_SCREENSHOT_OUTPUT_DIR)" SIMULATOR_NAME="$(IOS_SCREENSHOT_SIMULATOR)" SIMULATOR_UDID="$(SIMULATOR_UDID)" DERIVED_DATA_PATH="$(IOS_SCREENSHOT_DERIVED_DATA)" "$(IOS_SCREENSHOT_SCRIPT)" --app-only

ios-screenshots-live:
	OUTPUT_DIR="$(IOS_SCREENSHOT_OUTPUT_DIR)" SIMULATOR_NAME="$(IOS_SCREENSHOT_SIMULATOR)" SIMULATOR_UDID="$(SIMULATOR_UDID)" DERIVED_DATA_PATH="$(IOS_SCREENSHOT_DERIVED_DATA)" "$(IOS_SCREENSHOT_SCRIPT)" --live-only
