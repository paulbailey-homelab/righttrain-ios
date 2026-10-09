#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

project_path="${repo_root}/RightTrain.xcodeproj"
archive_path="${RIGHTTRAIN_ARCHIVE_PATH:-${repo_root}/tmp/ios/RightTrain-TestFlight.xcarchive}"
export_path="${RIGHTTRAIN_EXPORT_PATH:-${repo_root}/tmp/ios/testflight-export}"
export_options="${RIGHTTRAIN_EXPORT_OPTIONS_PLIST:-${repo_root}/TestFlightExportOptions.plist}"

configuration="${RIGHTTRAIN_CONFIGURATION:-Release}"
api_base_url="${RIGHTTRAIN_API_BASE_URL:-https://api.righttrain.app}"

build_settings=(
  "RIGHTTRAIN_API_BASE_URL=${api_base_url}"
  "RIGHTTRAIN_APNS_ENVIRONMENT=production"
)

if [[ -n "${RIGHTTRAIN_DEVELOPMENT_TEAM:-}" ]]; then
  build_settings+=("RIGHTTRAIN_DEVELOPMENT_TEAM=${RIGHTTRAIN_DEVELOPMENT_TEAM}")
fi

if [[ -n "${RIGHTTRAIN_BUNDLE_IDENTIFIER:-}" ]]; then
  build_settings+=("RIGHTTRAIN_BUNDLE_IDENTIFIER=${RIGHTTRAIN_BUNDLE_IDENTIFIER}")
fi

if [[ -n "${RIGHTTRAIN_MARKETING_VERSION:-}" ]]; then
  build_settings+=("MARKETING_VERSION=${RIGHTTRAIN_MARKETING_VERSION}")
fi

if [[ -n "${RIGHTTRAIN_BUILD_NUMBER:-}" ]]; then
  build_settings+=("CURRENT_PROJECT_VERSION=${RIGHTTRAIN_BUILD_NUMBER}")
fi

mkdir -p "$(dirname "${archive_path}")" "${export_path}"

xcodebuild \
  -project "${project_path}" \
  -scheme RightTrain \
  -configuration "${configuration}" \
  -destination "generic/platform=iOS" \
  -archivePath "${archive_path}" \
  "${build_settings[@]}" \
  clean archive

xcodebuild \
  -exportArchive \
  -archivePath "${archive_path}" \
  -exportOptionsPlist "${export_options}" \
  -exportPath "${export_path}"
