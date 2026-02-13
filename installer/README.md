# ATLAS Backend Installer

Installer builds use WiX Toolset to build a Windows MSI with install/repair/uninstall support.

## Requirements
- Flutter SDK (bundled in this repo under `flutter/`)
- WiX Toolset (`wix` on PATH) for MSI output

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
- `-SkipMsi` to skip MSI generation (only stage files into `dist\ATLAS`)
- `-BunVersion` to override bundled Bun version (default: `1.3.5`)

## Output
- `dist\ATLAS-Backend-<version>.msi`

## Notes
- The setup icon uses `atlas_gui_flutter\windows\runner\resources\app_icon.ico`.
- Backend files are staged next to the GUI so `getBackendRoot()` resolves correctly.
- Bun is bundled under `tools\bun\bun.exe` so the backend runs without a separate Bun install.
- The MSI will automatically uninstall legacy Inno Setup (EXE) installs if detected.
