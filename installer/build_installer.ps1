[CmdletBinding()]
param(
  [string]$Version = "",
  [string]$BunVersion = "1.3.5",
  [switch]$SkipFlutterBuild,
  [switch]$SkipMsi
)

$ErrorActionPreference = "Stop"

function Write-Step {
  param([string]$Message)
  Write-Host "[ATLAS Backend Installer] $Message" -ForegroundColor Cyan
}

$root = Resolve-Path (Join-Path $PSScriptRoot "..")

# Prefer flutter from PATH; fallback to repo-bundled SDK.
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if ($flutterCmd) {
  $flutter = $flutterCmd.Source
} else {
  $flutter = Join-Path $root "flutter\bin\flutter.bat"
}

$guiDir = Join-Path $root "atlas_gui_flutter"
$distDir = Join-Path $root "dist"
$buildRoot = Join-Path $distDir "ATLAS"
$wxsFile = Join-Path $PSScriptRoot "ATLAS.wxs"
$licenseFile = Join-Path $PSScriptRoot "LICENSE.rtf"
$iconPath = Join-Path $root "atlas_gui_flutter\windows\runner\resources\app_icon.ico"

if (-not (Test-Path $wxsFile)) {
  throw "Missing WiX source file: $wxsFile"
}

if (-not (Test-Path $licenseFile)) {
  throw "Missing license file: $licenseFile"
}

if (-not (Test-Path $distDir)) {
  New-Item -ItemType Directory -Path $distDir | Out-Null
}

if ([string]::IsNullOrWhiteSpace($Version)) {
  $packageJson = Join-Path $root "package.json"
  if (Test-Path $packageJson) {
    $json = Get-Content $packageJson -Raw | ConvertFrom-Json
    if ($json.version) {
      $Version = [string]$json.version
    }
  }
}

if ([string]::IsNullOrWhiteSpace($Version)) {
  $Version = "1.0.0"
}

Write-Step "Resolved version: $Version"

if (-not $SkipFlutterBuild) {
  if (-not (Test-Path $flutter)) {
    throw "Flutter not found at $flutter"
  }
  Write-Step "Running flutter build windows --release"
  Push-Location $guiDir
  & $flutter build windows --release
  Pop-Location
} else {
  Write-Step "Skipping Flutter build (using existing Release output)"
}

if (Test-Path $buildRoot) {
  Remove-Item $buildRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $buildRoot | Out-Null

$releaseDir = Join-Path $guiDir "build\windows\x64\runner\Release"
if (-not (Test-Path $releaseDir)) {
  throw "Release build not found: $releaseDir"
}
Copy-Item -Path (Join-Path $releaseDir "*") -Destination $buildRoot -Recurse -Force

$backendItems = @(
  "package.json",
  "bun.lockb",
  "update-notes.md",
  "update-notes.txt",
  "src",
  "static",
  "public",
  "responses",
  "node_modules"
)

foreach ($item in $backendItems) {
  $srcPath = Join-Path $root $item
  if (Test-Path $srcPath) {
    Copy-Item -Path $srcPath -Destination (Join-Path $buildRoot $item) -Recurse -Force
  }
}

# Never ship local runtime config with installer packages.
$stagedConfigIni = Join-Path $buildRoot "src\config\config.ini"
if (Test-Path $stagedConfigIni) {
  Remove-Item -Path $stagedConfigIni -Force
}

# Remove runtime state from staged output.
$stagedStaticDir = Join-Path $buildRoot "static"
$stagedProfilesDir = Join-Path $stagedStaticDir "profiles"
$stagedClientSettingsDir = Join-Path $stagedStaticDir "ClientSettings"

if (Test-Path $stagedProfilesDir) {
  Get-ChildItem -LiteralPath $stagedProfilesDir -Force | ForEach-Object {
    if ($_.PSIsContainer) {
      Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
      return
    }
    if ($_.Name -match '^profile_.*\.json$') {
      return
    }
    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
  }
}

# Keep only "config" under ClientSettings.
if (Test-Path $stagedClientSettingsDir) {
  Get-ChildItem -LiteralPath $stagedClientSettingsDir -Force | ForEach-Object {
    if ($_.PSIsContainer -and $_.Name.ToLowerInvariant() -eq "config") {
      return
    }
    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
  }
}

# Remove hotfix backups from packaged output.
$stagedHotfixesDir = Join-Path $stagedStaticDir "hotfixes"
if (Test-Path $stagedHotfixesDir) {
  Get-ChildItem -LiteralPath $stagedHotfixesDir -Recurse -File -Filter "*.bak" -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue
}

# Ensure bundled Bun is available.
$bunDir = Join-Path $buildRoot "tools\bun"
$bunExe = Join-Path $bunDir "bun.exe"
if (-not (Test-Path $bunExe)) {
  New-Item -ItemType Directory -Path $bunDir -Force | Out-Null
  $bunZip = Join-Path $distDir ("bun-{0}-windows-x64.zip" -f $BunVersion)
  if (-not (Test-Path $bunZip)) {
    $bunUrl = "https://github.com/oven-sh/bun/releases/download/bun-v$BunVersion/bun-windows-x64.zip"
    Write-Step "Downloading Bun $BunVersion"
    Invoke-WebRequest -Uri $bunUrl -OutFile $bunZip
  }
  $bunTemp = Join-Path $distDir "bun_tmp"
  if (Test-Path $bunTemp) {
    Remove-Item $bunTemp -Recurse -Force
  }
  Expand-Archive -Path $bunZip -DestinationPath $bunTemp
  $bunExtracted = Get-ChildItem -Path $bunTemp -Filter "bun.exe" -Recurse | Select-Object -First 1
  if (-not $bunExtracted) {
    throw "bun.exe not found in downloaded archive."
  }
  Copy-Item -Path $bunExtracted.FullName -Destination $bunExe -Force
  Remove-Item $bunTemp -Recurse -Force
}

Write-Step "Staged build output at $buildRoot"

if ($SkipMsi) {
  Write-Step "Skipping MSI build"
  exit 0
}

$wixExe = $null
$wixCmd = Get-Command "wix" -ErrorAction SilentlyContinue
if ($wixCmd) {
  $wixExe = $wixCmd.Source
}

if (-not $wixExe) {
  $wixFromEnv = $null
  if ($env:WIX) {
    if (Test-Path $env:WIX -PathType Leaf) {
      $wixFromEnv = $env:WIX
    } elseif (Test-Path $env:WIX -PathType Container) {
      $wixFromEnv = Join-Path $env:WIX "wix.exe"
    }
  }

  $candidatePaths = @(
    $wixFromEnv,
    (Join-Path $env:ProgramFiles "WiX Toolset v4\bin\wix.exe"),
    (Join-Path $env:ProgramFiles "WiX Toolset v4.0\bin\wix.exe"),
    (Join-Path $env:ProgramFiles "WiX Toolset v5\bin\wix.exe"),
    (Join-Path $env:ProgramFiles "WiX Toolset v5.0\bin\wix.exe"),
    (Join-Path $env:ProgramFiles "WiX Toolset v6\bin\wix.exe"),
    (Join-Path $env:ProgramFiles "WiX Toolset v6.0\bin\wix.exe"),
    (Join-Path $env:ProgramFiles "WiX Toolset\bin\wix.exe"),
    (Join-Path $env:USERPROFILE ".dotnet\tools\wix.exe")
  )

  foreach ($candidate in $candidatePaths) {
    if ($candidate -and (Test-Path $candidate -PathType Leaf)) {
      $wixExe = $candidate
      break
    }
  }
}

if (-not $wixExe) {
  $wingetRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
  if (Test-Path $wingetRoot) {
    $found = Get-ChildItem -Path $wingetRoot -Filter wix.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
      $wixExe = $found.FullName
    }
  }
}

if (-not $wixExe) {
  throw "WiX Toolset not found. Ensure 'wix' is on PATH or set WIX to the install folder."
}

$msiOut = Join-Path $distDir ("ATLAS-Backend-{0}.msi" -f $Version)
Write-Step "Building MSI: $msiOut"

& $wixExe build $wxsFile `
  -d BuildRoot="$buildRoot" `
  -d ProductVersion="$Version" `
  -d LicenseFile="$licenseFile" `
  -d IconPath="$iconPath" `
  -ext WixToolset.UI.wixext `
  -o "$msiOut"

if ($LASTEXITCODE -ne 0) {
  throw "wix build failed with exit code $LASTEXITCODE"
}

if (Test-Path $msiOut) {
  Write-Step "MSI created: $msiOut"
}
