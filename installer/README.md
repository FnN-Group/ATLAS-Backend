# ATLAS Backend Installer

Installer builds use Inno Setup to create a Windows `.exe` installer.

## Requirements
- Flutter SDK
- Inno Setup 6 (`ISCC.exe` available on PATH or installed in the standard location)

## Build
```powershell
.\installer\build_installer.ps1
```

You can also run:
```bat
build-installer.cmd
```

## Options
- `-SkipFlutterBuild` to skip `flutter build windows --release`
- `-SkipFlutterClean` to reuse the existing Flutter build output without cleaning first
- `-SkipInnoCompile` to only stage files into `dist\ATLAS-Backend`
- `-BunVersion` to override the bundled Bun version (default: `1.3.5`)

## Output
- `dist\ATLAS Backend Setup-<version>.exe`

## Notes
- The installer runs elevated, installs into `Program Files`, and bundles the VC++ runtime installer.
- Backend files are staged next to the GUI so `getInstallationRoot()` and `getBackendRoot()` still resolve correctly after install.
- Bun is bundled under `tools\bun\bun.exe` so the backend runs without a separate Bun install.
- The EXE installer will try to remove an older MSI-based ATLAS Backend install before continuing.
