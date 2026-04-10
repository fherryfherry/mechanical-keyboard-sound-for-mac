#!/bin/sh
set -eu

PROJECT="Mechanical Sound For Mac.xcodeproj"
SCHEME="Mechanical Sound For Mac"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/MechanicalSoundDerivedData}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-Debug}"
APP_NAME="Mechanical Sound For Mac.app"
ZIP_NAME="Mechanical Sound For Mac.zip"
SOURCE_APP="$DERIVED_DATA_PATH/Build/Products/$BUILD_CONFIGURATION/$APP_NAME"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

install_root="${1:-/Applications}"
destination_app="$install_root/$APP_NAME"
destination_zip="$SCRIPT_DIR/$ZIP_NAME"

echo "Building $APP_NAME into $DERIVED_DATA_PATH..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$BUILD_CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

if [ ! -d "$SOURCE_APP" ]; then
  echo "Build completed but app bundle was not found at:"
  echo "  $SOURCE_APP"
  exit 1
fi

if [ ! -d "$install_root" ]; then
  echo "Creating install directory:"
  echo "  $install_root"
  mkdir -p "$install_root"
fi

echo "Installing app to:"
echo "  $destination_app"
rm -rf "$destination_app"
cp -R "$SOURCE_APP" "$destination_app"

echo
echo "Creating distributable zip:"
echo "  $destination_zip"
rm -f "$destination_zip"
ditto -c -k --keepParent "$destination_app" "$destination_zip"

echo
echo "Installed successfully."
echo "Run it from:"
echo "  $destination_app"
echo
echo "Share this zip if needed:"
echo "  $destination_zip"
echo
echo "Next steps:"
echo "1. Open the app from Applications."
echo "2. Use the menu bar app to open Accessibility and Input Monitoring settings."
echo "3. Grant both permissions, then quit and reopen the same installed app."
