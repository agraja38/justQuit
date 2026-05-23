# justQuit for Windows

`justQuit for Windows` is a native Windows tray app based on the macOS `justQuit` app.

It keeps the same core behavior:

- detects currently running apps
- quits regular apps by default
- lets you protect apps from quitting
- keeps background-style apps skipped unless you explicitly include them
- saves settings
- restores the most recent quit session
- supports a global `Ctrl+Alt+J` hotkey

Profiles, confirmation before quitting many apps, and countdown before quitting are justQuit Pro features. Activate them with a `justquit-pro` license key from the shared license key generator.

Created by Agraja.

## Build

Requirements:

- .NET 8 SDK

Commands:

```powershell
dotnet build
dotnet run
```

When running from the unified justQuit repo root:

```powershell
dotnet build .\Windows\justQuit.Windows.csproj
dotnet run --project .\Windows\justQuit.Windows.csproj
```

## Build installers

Requirements:

- .NET 8 SDK
- Inno Setup 6

```powershell
powershell -ExecutionPolicy Bypass -File .\build-installer.ps1
```

Generated installers:

- `installer\output\justQuit-Setup-x64.exe`
- `installer\output\justQuit-Setup-ARM64.exe`

## Publish a release

```powershell
powershell -ExecutionPolicy Bypass -File .\publish-release.ps1 -Version 1.2.23
```

## Direct downloads

- [Latest x64 installer](https://github.com/agraja38/app-update-feeds/releases/download/justquit-windows-v1.2.23/justQuit-Setup-x64.exe)
- [Latest ARM64 installer](https://github.com/agraja38/app-update-feeds/releases/download/justquit-windows-v1.2.23/justQuit-Setup-ARM64.exe)

## Notes

- Windows does not expose a direct equivalent of macOS bundle identifiers, so settings and profiles use executable paths as the stable app identity.
- Background apps are approximated from top-level windows that are not standard Alt-Tab style windows. Apps without closeable windows remain skipped.
