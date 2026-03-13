# justQuit

justQuit is a native macOS menu bar app that closes open apps while letting you protect the ones you want to keep running.

## What it does

- Detects running apps using `NSWorkspace`
- Lets you protect regular apps with toggles
- Lets you include or skip menu bar/background apps
- Supports countdowns, confirmations, profiles, notifications, and a global hotkey
- Checks for updates from a hosted update feed

## Build

```bash
cd /Users/agrajawijayawardane/Documents/Playground/QuitKeeper
chmod +x build.sh
./build.sh
open justQuit.app
```

Build outputs:

- `/Users/agrajawijayawardane/Documents/Playground/QuitKeeper/justQuit.app`
- `/Users/agrajawijayawardane/Documents/Playground/QuitKeeper/justQuit.zip`
- `/Users/agrajawijayawardane/Documents/Playground/QuitKeeper/justQuit.dmg`

## Updates

The hosted update feed for the app lives at `docs/update.json`.
