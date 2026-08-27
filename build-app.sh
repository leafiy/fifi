#!/bin/sh
# Builds Fifi.app in an ignored, Spotlight-excluded build directory.
# Requires macOS with the Xcode command line tools (xcode-select --install).
# The flow lives in ../leafiy-ui/scripts/macos-app-build-common.sh (ADR-0012);
# this file only declares the app. UNIVERSAL=1 builds one app for both CPUs.
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"

APP_SLUG="fifi"
APP_EXECUTABLE_PRODUCT="fifi"
APP_ICON_SOURCE="fifi.png"
MENU_ICON_SOURCE="Sources/Fifi/Resources/fifi.png"
BUILD_COMMON="../leafiy-ui/scripts/macos-app-build-common.sh"
[ -r "$BUILD_COMMON" ] || { echo "error: shared macOS build policy not found: $BUILD_COMMON"; exit 1; }
. "$BUILD_COMMON"
leafiy_build_app_main "$@"
