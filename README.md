# justQuit

justQuit is a small native macOS app that closes all currently open regular apps while automatically leaving menu bar and background apps alone.

## What it does

- Detects currently running apps using `NSWorkspace`.
- Skips menu bar or background apps by default.
- Lets you protect any regular app with a GUI toggle.
- Saves your protected app list between launches.

## Build

```bash
cd /Users/agrajawijayawardane/Documents/Playground/QuitKeeper
chmod +x build.sh
./build.sh
open justQuit.app
```

The app bundle is created at:

`/Users/agrajawijayawardane/Documents/Playground/QuitKeeper/justQuit.app`
