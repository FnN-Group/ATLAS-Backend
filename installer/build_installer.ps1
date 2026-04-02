[CmdletBinding()]
param(
  [string]$Version = "",
  [string]$BunVersion = "1.3.5",
  [switch]$SkipFlutterBuild,
  [switch]$SkipFlutterClean,
  [switch]$SkipInnoCompile
)

$ErrorActionPreference = "Stop"

function Write-Step {
  param([string]$Message)
  Write-Host "[ATLAS Backend Installer] $Message" -ForegroundColor Cyan
}

function Stop-AtlasBackendProcesses {
  $names = @(
    "ATLAS Backend",
    "ATLAS",
    "atlas_gui_flutter"
  )

  foreach ($name in $names) {
    try {
      $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
      foreach ($proc in @($procs)) {
        Write-Step "Stopping running process: $($proc.ProcessName) (pid $($proc.Id))"
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
      }
    } catch {
      # Ignore best-effort process cleanup failures.
    }
  }
}

function Remove-DirWithRetry {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [int]$Attempts = 6
  )

  if (-not (Test-Path $Path)) {
    return
  }

  for ($i = 1; $i -le $Attempts; $i++) {
    try {
      Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
      return
    } catch {
      if ($i -eq $Attempts) {
        Write-Step "Warning: failed to remove '$Path' after $Attempts attempts: $($_.Exception.Message)"
        return
      }
      Start-Sleep -Milliseconds (200 * $i)
    }
  }
}

function Remove-FileWithRetry {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [int]$Attempts = 6
  )

  if (-not (Test-Path $Path)) {
    return
  }

  for ($i = 1; $i -le $Attempts; $i++) {
    try {
      Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
      return
    } catch {
      if ($i -eq $Attempts) {
        Write-Step "Warning: failed to remove file '$Path' after $Attempts attempts: $($_.Exception.Message)"
        return
      }
      Start-Sleep -Milliseconds (200 * $i)
    }
  }
}

function Find-Iscc {
  $isccCommand = Get-Command iscc -ErrorAction SilentlyContinue
  if ($isccCommand) {
    return $isccCommand.Source
  }

  $candidates = @(
    (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"),
    (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 5\ISCC.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
    (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 5\ISCC.exe"),
    (Join-Path $env:ProgramFiles "Inno Setup 5\ISCC.exe")
  ) | Where-Object { $_ -and (Test-Path $_ -PathType Leaf) }

  return @($candidates) | Select-Object -First 1
}

function Get-VcRedistPath {
  param([string]$ScriptDir)

  $repoCopy = Join-Path $ScriptDir "vc_redist.x64.exe"
  if (Test-Path $repoCopy -PathType Leaf) {
    $resolvedRepoCopy = Resolve-Path $repoCopy
    Write-Step "Using repository VC++ redistributable: $resolvedRepoCopy"
    return [string]$resolvedRepoCopy
  }

  $cacheDir = Join-Path $env:TEMP "ATLAS-Backend"
  if (-not (Test-Path $cacheDir)) {
    New-Item -ItemType Directory -Path $cacheDir | Out-Null
  }

  $cacheCopy = Join-Path $cacheDir "vc_redist.x64.exe"
  if (-not (Test-Path $cacheCopy -PathType Leaf)) {
    $url = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
    Write-Step "Downloading VC++ redistributable from $url"
    try {
      Invoke-WebRequest -Uri $url -OutFile $cacheCopy
    } catch {
      throw @"
Failed to download vc_redist.x64.exe from:
  $url

Either restore internet access and rerun the build, or place a local copy at:
  $repoCopy
"@
    }
  } else {
    Write-Step "Using cached VC++ redistributable: $cacheCopy"
  }

  if (-not (Test-Path $cacheCopy -PathType Leaf)) {
    throw "VC++ redistributable not found at $cacheCopy"
  }

  $size = (Get-Item -LiteralPath $cacheCopy).Length
  if ($size -lt 1048576) {
    throw "VC++ redistributable at $cacheCopy looks invalid (size: $size bytes)"
  }

  $resolvedCacheCopy = Resolve-Path $cacheCopy
  return [string]$resolvedCacheCopy
}

function Get-PackageVersion {
  param([string]$PackageJsonPath)

  if (-not (Test-Path $PackageJsonPath -PathType Leaf)) {
    throw "package.json not found at $PackageJsonPath"
  }

  $json = Get-Content $PackageJsonPath -Raw | ConvertFrom-Json
  if (-not $json.version) {
    throw "Could not find version in $PackageJsonPath"
  }

  return [string]$json.version
}

function Get-StageExecutableName {
  param([string]$StageDir)

  $exe = Get-ChildItem -Path $StageDir -Filter *.exe -File |
    Where-Object { $_.Name -notmatch '^unins[0-9]*\.exe$' } |
    Sort-Object Length -Descending |
    Select-Object -First 1

  if (-not $exe) {
    throw "No executable found in $StageDir"
  }

  return $exe.Name
}

$root = Resolve-Path (Join-Path $PSScriptRoot "..")

$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if ($flutterCmd) {
  $flutter = $flutterCmd.Source
} else {
  $flutter = Join-Path $root "flutter\bin\flutter.bat"
}

$guiDir = Join-Path $root "atlas_gui_flutter"
$distDir = Join-Path $root "dist"
$stageDir = Join-Path $distDir "ATLAS-Backend"
$packageJson = Join-Path $root "package.json"
$installerScript = Join-Path $PSScriptRoot "ATLAS-Backend.iss"
$iconPath = Join-Path $root "atlas_gui_flutter\windows\runner\resources\app_icon.ico"
$releaseDir = Join-Path $guiDir "build\windows\x64\runner\Release"
$desiredExecutableName = "ATLAS Backend.exe"

if (-not (Test-Path $installerScript -PathType Leaf)) {
  throw "Installer script not found: $installerScript"
}

if (-not (Test-Path $distDir)) {
  New-Item -ItemType Directory -Path $distDir | Out-Null
}

if ([string]::IsNullOrWhiteSpace($Version)) {
  $Version = Get-PackageVersion -PackageJsonPath $packageJson
}

if ([string]::IsNullOrWhiteSpace($Version)) {
  $Version = "1.0.0"
}

Write-Step "Resolved version: $Version"

if (-not $SkipFlutterBuild) {
  if (-not (Test-Path $flutter -PathType Leaf)) {
    throw "Flutter not found at $flutter"
  }

  if (-not $SkipFlutterClean) {
    Write-Step "Running flutter clean"
    Stop-AtlasBackendProcesses
    Remove-FileWithRetry -Path (Join-Path $releaseDir "ATLAS.exe")
    Remove-FileWithRetry -Path (Join-Path $releaseDir "ATLAS Backend.exe")
    Remove-FileWithRetry -Path (Join-Path $releaseDir "atlas_gui_flutter.exe")

    Push-Location $guiDir
    try {
      try {
        & $flutter clean
      } catch {
        Write-Step "flutter clean failed (likely locked files). Retrying after process cleanup..."
        Stop-AtlasBackendProcesses
        Start-Sleep -Milliseconds 350
        try {
          & $flutter clean
        } catch {
          Write-Step "Warning: flutter clean still failed. Continuing with best-effort manual cleanup."
        }
      }
    } finally {
      Pop-Location
    }

    Remove-DirWithRetry -Path (Join-Path $guiDir "build")
    Remove-DirWithRetry -Path (Join-Path $guiDir ".dart_tool")
  }

  Write-Step "Running flutter build windows --release"
  Push-Location $guiDir
  try {
    & $flutter build windows --release
  } finally {
    Pop-Location
  }
} else {
  Write-Step "Skipping Flutter build (using existing Release output)"
}

if (-not (Test-Path $releaseDir)) {
  throw "Release build not found: $releaseDir"
}

Remove-DirWithRetry -Path $stageDir
New-Item -ItemType Directory -Path $stageDir | Out-Null

Copy-Item -Path (Join-Path $releaseDir "*") -Destination $stageDir -Recurse -Force

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
    Copy-Item -Path $srcPath -Destination (Join-Path $stageDir $item) -Recurse -Force
  }
}

$stagedConfigIni = Join-Path $stageDir "src\config\config.ini"
if (Test-Path $stagedConfigIni -PathType Leaf) {
  Remove-Item -LiteralPath $stagedConfigIni -Force
}

$stagedStaticDir = Join-Path $stageDir "static"
$stagedProfilesDir = Join-Path $stagedStaticDir "profiles"
$stagedClientSettingsDir = Join-Path $stagedStaticDir "ClientSettings"
$stagedHotfixesDir = Join-Path $stagedStaticDir "hotfixes"

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

if (Test-Path $stagedClientSettingsDir) {
  Get-ChildItem -LiteralPath $stagedClientSettingsDir -Force | ForEach-Object {
    if ($_.PSIsContainer -and $_.Name.ToLowerInvariant() -eq "config") {
      return
    }
    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
  }
}

if (Test-Path $stagedHotfixesDir) {
  Get-ChildItem -LiteralPath $stagedHotfixesDir -Recurse -File -Filter "*.bak" -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue
}

$bunDir = Join-Path $stageDir "tools\bun"
$bunExe = Join-Path $bunDir "bun.exe"
if (-not (Test-Path $bunExe -PathType Leaf)) {
  New-Item -ItemType Directory -Path $bunDir -Force | Out-Null
  $bunZip = Join-Path $distDir ("bun-{0}-windows-x64.zip" -f $BunVersion)
  if (-not (Test-Path $bunZip -PathType Leaf)) {
    $bunUrl = "https://github.com/oven-sh/bun/releases/download/bun-v$BunVersion/bun-windows-x64.zip"
    Write-Step "Downloading Bun $BunVersion"
    Invoke-WebRequest -Uri $bunUrl -OutFile $bunZip
  }

  $bunTemp = Join-Path $distDir "bun_tmp"
  Remove-DirWithRetry -Path $bunTemp
  Expand-Archive -Path $bunZip -DestinationPath $bunTemp
  $bunExtracted = Get-ChildItem -Path $bunTemp -Filter "bun.exe" -Recurse | Select-Object -First 1
  if (-not $bunExtracted) {
    throw "bun.exe not found in downloaded archive."
  }
  Copy-Item -Path $bunExtracted.FullName -Destination $bunExe -Force
  Remove-DirWithRetry -Path $bunTemp
}

$executableName = Get-StageExecutableName -StageDir $stageDir
$desiredExecutablePath = Join-Path $stageDir $desiredExecutableName
$flutterOutputExecutablePath = Join-Path $stageDir "ATLAS.exe"

if (Test-Path $flutterOutputExecutablePath -PathType Leaf) {
  if (Test-Path $desiredExecutablePath -PathType Leaf) {
    Remove-Item -LiteralPath $desiredExecutablePath -Force
  }
  Rename-Item -LiteralPath $flutterOutputExecutablePath -NewName $desiredExecutableName
  $executableName = $desiredExecutableName
  Write-Step "Renamed Flutter output executable to: $executableName"
} elseif ($executableName -ne $desiredExecutableName) {
  $sourceExecutablePath = Join-Path $stageDir $executableName
  if (Test-Path $desiredExecutablePath -PathType Leaf) {
    Remove-Item -LiteralPath $desiredExecutablePath -Force
  }
  Rename-Item -LiteralPath $sourceExecutablePath -NewName $desiredExecutableName
  $executableName = $desiredExecutableName
  Write-Step "Renamed staged executable to: $executableName"
} else {
  Write-Step "Using executable: $executableName"
}

Get-ChildItem -Path $stageDir -Filter *.exe -File |
  Where-Object {
    $_.Name -ne $desiredExecutableName -and
    $_.Name -notmatch '^unins[0-9]*\.exe$'
  } |
  ForEach-Object {
    Write-Step "Removing extra executable from staged output: $($_.Name)"
    Remove-Item -LiteralPath $_.FullName -Force
  }

Write-Step "Staged build output at $stageDir"

if ($SkipInnoCompile) {
  Write-Step "Skipping Inno Setup compilation"
  exit 0
}

$vcRedistPath = Get-VcRedistPath -ScriptDir $PSScriptRoot
$isccPath = Find-Iscc
if (-not $isccPath) {
  throw @"
Inno Setup compiler (ISCC.exe) was not found.
Install Inno Setup 6 from https://jrsoftware.org/isinfo.php and rerun:
  .\installer\build_installer.ps1
"@
}

$outputBaseFilename = "ATLAS Backend Setup-$Version"
Write-Step "Compiling installer with ISCC: $isccPath"

$isccArgs = @(
  "/DMyAppVersion=$Version",
  "/DSourceDir=$stageDir",
  "/DExecutableName=$desiredExecutableName",
  "/DOutputDir=$distDir",
  "/DOutputBaseFilename=$outputBaseFilename",
  "/DVcRedistPath=$vcRedistPath"
)

if (Test-Path $iconPath -PathType Leaf) {
  $isccArgs += "/DSetupIconFile=$iconPath"
}

$isccArgs += $installerScript

& $isccPath @isccArgs
if ($LASTEXITCODE -ne 0) {
  throw "ISCC failed with exit code $LASTEXITCODE"
}

$installerPath = Join-Path $distDir "$outputBaseFilename.exe"
if (Test-Path $installerPath -PathType Leaf) {
  Write-Step "Installer created: $installerPath"
} else {
  Write-Step "Installer compilation finished. Check output directory: $distDir"
}
