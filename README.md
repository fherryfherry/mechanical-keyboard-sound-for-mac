# Mechanical Keyboard Sound For Mac

macOS menu bar app that plays mechanical keyboard sounds globally while you type.

## Features

- Runs from the macOS menu bar
- Plays keyboard press and release sounds globally
- Multiple keyboard sound profiles
- Adjustable volume up to 200%
- Optional key press HUD overlay
- Optional combo phrase overlay while typing fast
- Optional mouse / touchpad click sound
- Remembers last settings automatically
- Can launch at login

## Requirements

- macOS 14.0 or later
- Accessibility permission
- Input Monitoring permission

## Install

### Option 1: Run from Xcode

1. Open `Mechanical Sound For Mac.xcodeproj`
2. Select the `Mechanical Sound For Mac` scheme
3. Build and run

### Option 2: Install to Applications

Use the helper script:

```bash
chmod +x scripts/install_debug_app.sh
./scripts/install_debug_app.sh
```

If `/Applications` requires admin permission:

```bash
sudo ./scripts/install_debug_app.sh
```

This installs the app to `/Applications` and also creates a zip in the `scripts/` folder.

## Permissions

To make keyboard sounds work globally outside the app:

1. Launch the app from `/Applications`
2. Open the menu bar app
3. Click `Request Permission`
4. Enable the app in:
   - `Privacy & Security > Accessibility`
   - `Privacy & Security > Input Monitoring`
5. Quit and reopen the app

## Sharing The App

Right now the app is intended for direct sharing as a `.zip`.

Important:

- The app is not yet Developer ID signed and notarized
- On another Mac, Gatekeeper may block it at first
- The receiver may need to:
  - move the app into `/Applications`
  - right click the app and choose `Open`
  - or use `Open Anyway` in `System Settings > Privacy & Security`

If quarantine blocks the app, this command may help:

```bash
xattr -dr com.apple.quarantine "/Applications/Mechanical Sound For Mac.app"
```

## Build

CLI build:

```bash
xcodebuild -project "Mechanical Sound For Mac.xcodeproj" \
  -scheme "Mechanical Sound For Mac" \
  -configuration Debug \
  -derivedDataPath /tmp/MechanicalSoundDerivedData \
  build
```

## Project Structure

- `Mechanical Sound For Mac/KeyboardMonitor.swift`
  Global keyboard and pointer monitoring, permissions, persisted settings
- `Mechanical Sound For Mac/KeyboardSoundEngine.swift`
  Audio loading and playback
- `Mechanical Sound For Mac/Mechanical_Sound_For_MacApp.swift`
  Menu bar app and permission helper UI
- `Mechanical Sound For Mac/KeyPressOverlayController.swift`
  Floating HUD and combo overlay
- `Mechanical Sound For Mac/audio/`
  Sound profiles and samples

## Notes

- For best permission reliability, always run the installed app from `/Applications`
- Testing only from temporary debug paths may break macOS permission registration
