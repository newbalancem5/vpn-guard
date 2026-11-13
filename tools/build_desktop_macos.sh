#!/bin/sh
# Developer-signed desktop build. Does not install or activate any filter.
set -eu
: "${VPN_GUARD_TEAM:?Set VPN_GUARD_TEAM to your paid Apple Developer team ID}"
: "${VPN_GUARD_BUNDLE_PREFIX:?Set a unique VPN_GUARD_BUNDLE_PREFIX (reverse DNS)}"
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT/apps/desktop"
flutter build macos --debug --config-only --no-pub
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug \
  -derivedDataPath "$ROOT/build/desktop-signed" \
  DEVELOPMENT_TEAM="$VPN_GUARD_TEAM" BUNDLE_PREFIX="$VPN_GUARD_BUNDLE_PREFIX" \
  CODE_SIGN_IDENTITY='Apple Development' \
  VPN_GUARD_HOST_ENTITLEMENTS=Runner/SystemFilter.entitlements \
  VPN_GUARD_FILTER_ENTITLEMENTS=../../../macos/Filter/Filter.entitlements \
  -allowProvisioningUpdates build
