# ATLAS Backend Installer

Installer builds use Inno Setup EXE (ATLAS Link-style flow).

## Requirements
- Flutter SDK (bundled in this repo under `flutter/`)
- Inno Setup 6 (`ISCC.exe`) for EXE output

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
- `-SkipInnoCompile` to skip EXE installer generation
- `-BunVersion` to override bundled Bun version (default: `1.3.5`)

## Output
- `dist\ATLAS-Backend-Setup-<version>.exe`

## Notes
- The setup icon uses `atlas_gui_flutter\windows\runner\resources\app_icon.ico`.
- Backend files are staged next to the GUI so `getBackendRoot()` resolves correctly.
- Bun is bundled under `tools\bun\bun.exe` so the backend runs without a separate Bun install.
