[CmdletBinding()]
param(
  [string]$Version = "",
  [string]$BunVersion = "1.3.5",
  [switch]$SkipFlutterBuild,
  [switch]$SkipInnoCompile
)

$ErrorActionPreference = "Stop"

function Write-Step {
  param([string]$Message)
  Write-Host "[ATLAS Backend Installer] $Message" -ForegroundColor Cyan
}

function Find-Iscc {
  $isccCommand = Get-Command iscc -ErrorAction SilentlyContinue
  if ($isccCommand) {
    return $isccCommand.Source
  }

  $candidates = @(
    (Join-Path $env:LOCALAPPDATA "Programs\Inno\ISCC.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
    (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 5\ISCC.exe"),
    (Join-Path $env:ProgramFiles "Inno Setup 5\ISCC.exe")
  ) | Where-Object { $_ -and (Test-Path $_) }

  if ($candidates.Count -gt 0) {
    return @($candidates)[0]
  }

  return $null
}

function Get-StagedExecutableName {
  param([string]$SourceDir)
  $exe = Get-ChildItem -Path $SourceDir -Filter *.exe -File |
    Where-Object { $_.Name -notmatch '^unins[0-9]*\.exe$' } |
    Sort-Object Length -Descending |
    Select-Object -First 1

  if (-not $exe) {
    throw "No executable found in $SourceDir"
  }

  return $exe.Name
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
$issFile = Join-Path $PSScriptRoot "ATLAS-Backend.iss"
$iconPath = Join-Path $root "atlas_gui_flutter\windows\runner\resources\app_icon.ico"

if (-not (Test-Path $issFile)) {
  throw "Missing Inno Setup script: $issFile"
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

if ($SkipInnoCompile) {
  Write-Step "Skipping Inno compilation"
  exit 0
}

$isccPath = Find-Iscc
if (-not $isccPath) {
  throw @"
Inno Setup compiler (ISCC.exe) was not found.
Install Inno Setup 6 from https://jrsoftware.org/isinfo.php and rerun:
  .\installer\build_installer.ps1
"@
}

$executableName = Get-StagedExecutableName -SourceDir $buildRoot
$outputBaseFilename = "ATLAS-Backend-Setup-$Version"
Write-Step "Compiling Inno Setup installer: $outputBaseFilename.exe"

$isccArgs = @(
  "/DMyAppVersion=$Version",
  "/DSourceDir=$buildRoot",
  "/DExecutableName=$executableName",
  "/DOutputDir=$distDir",
  "/DOutputBaseFilename=$outputBaseFilename"
)

if (Test-Path $iconPath) {
  $isccArgs += "/DSetupIconFile=$iconPath"
}

$isccArgs += $issFile

& $isccPath @isccArgs
if ($LASTEXITCODE -ne 0) {
  throw "ISCC failed with exit code $LASTEXITCODE"
}

$setupExe = Join-Path $distDir "$outputBaseFilename.exe"
if (Test-Path $setupExe) {
  Write-Step "EXE installer created: $setupExe"
}
