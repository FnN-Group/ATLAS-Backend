#define MyAppName "ATLAS Backend"
#define MyAppPublisher "cipherfps"
#define MyAppURL "https://github.com/cipherfps/ATLAS-Backend"

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

#ifndef SourceDir
  #error SourceDir define is required.
#endif

#ifndef ExecutableName
  #define ExecutableName "ATLAS Backend.exe"
#endif

#ifndef OutputDir
  #error OutputDir define is required.
#endif

#ifndef OutputBaseFilename
  #define OutputBaseFilename "ATLAS Backend Setup"
#endif

#ifndef SetupIconFile
  #define SetupIconFile ""
#endif

#ifndef VcRedistPath
  #define VcRedistPath ""
#endif

[Setup]
AppId={{8C7FECAB-4CE9-43A5-9BB4-3BCE5AF7FB7F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
UninstallDisplayName={#MyAppName}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\ATLAS Backend
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
UsePreviousTasks=no
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#ExecutableName}
CloseApplications=yes
CloseApplicationsFilter={#ExecutableName},ATLAS.exe,atlas_gui_flutter.exe
RestartApplications=no
DisableReadyMemo=yes
#if SetupIconFile != ""
SetupIconFile={#SetupIconFile}
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
SelectTasksDesc=Which ATLAS Backend setup options should be performed?
SelectTasksLabel2=Select the options you would like Setup to perform while installing ATLAS Backend, then click Next.
ReadyLabel1=Setup is now ready to install ATLAS Backend on your computer.
ReadyLabel2a=Click Install to continue with the installation, or click Back if you want to review any ATLAS Backend setup options.
ReadyLabel2b=Click Install to continue with the installation.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "Additional options:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
#if VcRedistPath != ""
Source: "{#VcRedistPath}"; DestDir: "{tmp}"; DestName: "vc_redist.x64.exe"; Flags: deleteafterinstall
#endif

[InstallDelete]
Type: files; Name: "{app}\ATLAS.exe"
Type: files; Name: "{app}\atlas_gui_flutter.exe"

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#ExecutableName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#ExecutableName}"; Tasks: desktopicon

[Run]
#if VcRedistPath != ""
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing Microsoft Visual C++ Runtime..."; Check: NeedsVCRedist; Flags: runhidden waituntilterminated
#endif
Filename: "{app}\{#ExecutableName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
function InstallerMigrationRoot: string;
begin
  Result := ExpandConstant('{localappdata}\ATLAS\installer-migration');
end;

function LegacyMsiResetMarkerPath(const MigrationRoot: string): string;
begin
  Result := AddBackslash(MigrationRoot) + '.legacy-msi-reset';
end;

function CurrentAtlasDataRoot: string;
begin
  Result := ExpandConstant('{userappdata}\ATLAS');
end;

procedure CopyDirectoryRecursive(const SourceDir: string; const DestDir: string);
var
  FindRec: TFindRec;
  SourcePath: string;
  DestPath: string;
begin
  if not DirExists(SourceDir) then
    Exit;

  if not DirExists(DestDir) then
    ForceDirectories(DestDir);

  if not FindFirst(AddBackslash(SourceDir) + '*', FindRec) then
    Exit;

  try
    repeat
      if (FindRec.Name = '.') or (FindRec.Name = '..') then
        Continue;

      SourcePath := AddBackslash(SourceDir) + FindRec.Name;
      DestPath := AddBackslash(DestDir) + FindRec.Name;

      if (FindRec.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then begin
        CopyDirectoryRecursive(SourcePath, DestPath);
      end else begin
        ForceDirectories(ExtractFileDir(DestPath));
        CopyFile(SourcePath, DestPath, False);
      end;
    until not FindNext(FindRec);
  finally
    FindClose(FindRec);
  end;
end;

procedure CopyRelativeFileToInstallerMigrationFromRoot(
  const SourceRoot: string;
  const MigrationRoot: string;
  const RelativePath: string
);
var
  SourcePath: string;
  DestPath: string;
begin
  SourcePath := AddBackslash(SourceRoot) + RelativePath;
  if not FileExists(SourcePath) then
    Exit;

  DestPath := AddBackslash(MigrationRoot) + RelativePath;
  ForceDirectories(ExtractFileDir(DestPath));
  CopyFile(SourcePath, DestPath, False);
end;

procedure CopyRelativeDirToInstallerMigrationFromRoot(
  const SourceRoot: string;
  const MigrationRoot: string;
  const RelativePath: string
);
var
  SourcePath: string;
  DestPath: string;
begin
  SourcePath := AddBackslash(SourceRoot) + RelativePath;
  if not DirExists(SourcePath) then
    Exit;

  DestPath := AddBackslash(MigrationRoot) + RelativePath;
  CopyDirectoryRecursive(SourcePath, DestPath);
end;

procedure CopyCustomItemImagesToInstallerMigrationFromRoot(
  const SourceRoot: string;
  const MigrationRoot: string
);
var
  ItemsDir: string;
  FindRec: TFindRec;
  SourcePath: string;
  DestPath: string;
begin
  ItemsDir := AddBackslash(SourceRoot) + 'public\items';
  if not DirExists(ItemsDir) then
    Exit;

  if not FindFirst(AddBackslash(ItemsDir) + 'custom_*', FindRec) then
    Exit;

  try
    repeat
      if (FindRec.Name = '.') or (FindRec.Name = '..') then
        Continue;
      if (FindRec.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
        Continue;

      SourcePath := AddBackslash(ItemsDir) + FindRec.Name;
      DestPath := AddBackslash(MigrationRoot) + 'public\items\' + FindRec.Name;
      ForceDirectories(ExtractFileDir(DestPath));
      CopyFile(SourcePath, DestPath, False);
    until not FindNext(FindRec);
  finally
    FindClose(FindRec);
  end;
end;

procedure StageMutableDataRootForInstallerMigration(
  const SourceRoot: string;
  const MigrationRoot: string
);
begin
  if not DirExists(SourceRoot) then
    Exit;

  CopyRelativeFileToInstallerMigrationFromRoot(SourceRoot, MigrationRoot, 'gui.ini');
  CopyRelativeFileToInstallerMigrationFromRoot(SourceRoot, MigrationRoot, 'profiles-ui-state.json');
  CopyRelativeFileToInstallerMigrationFromRoot(SourceRoot, MigrationRoot, 'static\athenaprofiles\profiles-ui-state.json');
  CopyRelativeFileToInstallerMigrationFromRoot(SourceRoot, MigrationRoot, 'responses\curves.json');
  CopyRelativeFileToInstallerMigrationFromRoot(SourceRoot, MigrationRoot, 'responses\curvetables-state.json');
  CopyRelativeFileToInstallerMigrationFromRoot(SourceRoot, MigrationRoot, 'responses\datatables.json');
  CopyRelativeFileToInstallerMigrationFromRoot(SourceRoot, MigrationRoot, 'responses\datatables-ui.json');
  CopyRelativeFileToInstallerMigrationFromRoot(SourceRoot, MigrationRoot, 'responses\user-toggle-states.json');
  CopyRelativeFileToInstallerMigrationFromRoot(SourceRoot, MigrationRoot, 'responses\epic-settings.json');
  CopyRelativeFileToInstallerMigrationFromRoot(SourceRoot, MigrationRoot, 'responses\modifications-backup.json');
  CopyRelativeFileToInstallerMigrationFromRoot(SourceRoot, MigrationRoot, 'responses\straight-bloom-state.json');
  CopyRelativeFileToInstallerMigrationFromRoot(SourceRoot, MigrationRoot, 'static\hotfixes\DefaultGame Data\StraightBloom.ini');
  CopyRelativeFileToInstallerMigrationFromRoot(SourceRoot, MigrationRoot, 'static\hotfixes\DefaultGame Data\Fixes.ini');
  CopyRelativeFileToInstallerMigrationFromRoot(SourceRoot, MigrationRoot, 'static\hotfixes\DefaultGame Data\CurveTables.ini');
  CopyRelativeFileToInstallerMigrationFromRoot(SourceRoot, MigrationRoot, 'static\hotfixes\DefaultGame Data\DataTables.ini');
  CopyRelativeFileToInstallerMigrationFromRoot(SourceRoot, MigrationRoot, 'responses\user-curvetables.ini');
  CopyRelativeFileToInstallerMigrationFromRoot(SourceRoot, MigrationRoot, 'responses\user-datatables.ini');
  CopyRelativeFileToInstallerMigrationFromRoot(SourceRoot, MigrationRoot, 'src\config\config.ini');
  CopyRelativeFileToInstallerMigrationFromRoot(SourceRoot, MigrationRoot, 'static\hotfixes\DefaultEngine.ini');
  CopyRelativeFileToInstallerMigrationFromRoot(SourceRoot, MigrationRoot, 'static\hotfixes\DefaultGame.ini');
  CopyRelativeFileToInstallerMigrationFromRoot(SourceRoot, MigrationRoot, 'static\athenaprofiles\custom-presets.json');
  CopyRelativeDirToInstallerMigrationFromRoot(SourceRoot, MigrationRoot, 'static\athenaprofiles\Profile Presets');
  CopyRelativeDirToInstallerMigrationFromRoot(SourceRoot, MigrationRoot, 'static\ClientSettings');
  CopyRelativeDirToInstallerMigrationFromRoot(SourceRoot, MigrationRoot, 'static\profiles');
  CopyRelativeDirToInstallerMigrationFromRoot(SourceRoot, MigrationRoot, 'exports');
  CopyRelativeDirToInstallerMigrationFromRoot(SourceRoot, MigrationRoot, 'public\items\custom-groups');
  CopyCustomItemImagesToInstallerMigrationFromRoot(SourceRoot, MigrationRoot);
end;

procedure StageMutableDataForInstallerMigration;
var
  MigrationRoot: string;
begin
  if not DirExists(ExpandConstant('{app}')) and not DirExists(CurrentAtlasDataRoot) then
    Exit;

  MigrationRoot := InstallerMigrationRoot;
  if DirExists(MigrationRoot) then
    DelTree(MigrationRoot, True, True, True);
  ForceDirectories(MigrationRoot);

  { Legacy install-root data first. }
  StageMutableDataRootForInstallerMigration(ExpandConstant('{app}'), MigrationRoot);
  { Current AppData-root data wins if both layouts exist. }
  StageMutableDataRootForInstallerMigration(CurrentAtlasDataRoot, MigrationRoot);
end;

procedure StageLegacyMsiResetForInstallerMigration;
var
  MigrationRoot: string;
begin
  MigrationRoot := InstallerMigrationRoot;
  if DirExists(MigrationRoot) then
    DelTree(MigrationRoot, True, True, True);
  ForceDirectories(MigrationRoot);
  SaveStringToFile(LegacyMsiResetMarkerPath(MigrationRoot), 'reset', False);
end;

function IsVCRedistInstalled: Boolean;
var
  Installed: Cardinal;
begin
  Result :=
    RegQueryDWordValue(
      HKLM64,
      'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
      'Installed',
      Installed
    ) and (Installed = 1);

  if not Result then
    Result :=
      RegQueryDWordValue(
        HKLM,
        'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
        'Installed',
        Installed
      ) and (Installed = 1);
end;

function NeedsVCRedist: Boolean;
begin
  Result := not IsVCRedistInstalled;
end;

procedure _TaskKillImage(const ImageName: string);
var
  ResultCode: Integer;
begin
  if ImageName = '' then
    Exit;

  Exec(
    ExpandConstant('{sys}\taskkill.exe'),
    '/IM "' + ImageName + '"',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  );
  Exec(
    ExpandConstant('{sys}\taskkill.exe'),
    '/F /T /IM "' + ImageName + '"',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  );
end;

procedure _StopBundledBunInRoot(const RootDir: string);
var
  BunPath: string;
  EscapedBunPath: string;
  Parameters: string;
  ResultCode: Integer;
begin
  if RootDir = '' then
    Exit;

  BunPath := AddBackslash(RootDir) + 'tools\bun\bun.exe';
  if not FileExists(BunPath) then
    Exit;

  EscapedBunPath := BunPath;
  StringChangeEx(EscapedBunPath, '''', '''''', True);
  Parameters :=
    '-NoProfile -ExecutionPolicy Bypass -Command ' +
    '"$target = ''' + EscapedBunPath + '''; ' +
    'Get-Process bun -ErrorAction SilentlyContinue | ' +
    'Where-Object { $_.Path -eq $target } | ' +
    'Stop-Process -Force"';

  Exec(
    ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    Parameters,
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  );
end;

procedure ForceCloseRunningAtlasBackendInstances;
begin
  _TaskKillImage('{#ExecutableName}');
  if CompareText('{#ExecutableName}', 'ATLAS.exe') <> 0 then
    _TaskKillImage('ATLAS.exe');
  if CompareText('{#ExecutableName}', 'atlas_gui_flutter.exe') <> 0 then
    _TaskKillImage('atlas_gui_flutter.exe');
  _StopBundledBunInRoot(ExpandConstant('{app}'));
end;

function TryExtractMsiProductCode(const UninstallString: string; var ProductCode: string): Boolean;
var
  StartPos: Integer;
  EndPos: Integer;
begin
  Result := False;
  ProductCode := '';
  StartPos := Pos('{', UninstallString);
  EndPos := Pos('}', UninstallString);
  if (StartPos <= 0) or (EndPos <= StartPos) then
    Exit;

  ProductCode := Copy(UninstallString, StartPos, EndPos - StartPos + 1);
  Result := ProductCode <> '';
end;

function FindExistingAtlasBackendMsiProductCodeInRoot(const RootKey: Integer; const BaseKey: string; var ProductCode: string): Boolean;
var
  SubKeys: TArrayOfString;
  I: Integer;
  KeyName: string;
  DisplayName: string;
  UninstallString: string;
begin
  Result := False;
  if not RegGetSubkeyNames(RootKey, BaseKey, SubKeys) then
    Exit;

  for I := 0 to GetArrayLength(SubKeys) - 1 do begin
    KeyName := BaseKey + '\' + SubKeys[I];
    DisplayName := '';
    if not RegQueryStringValue(RootKey, KeyName, 'DisplayName', DisplayName) then
      Continue;
    if Pos('atlas backend', Lowercase(Trim(DisplayName))) = 0 then
      Continue;

    UninstallString := '';
    if not RegQueryStringValue(RootKey, KeyName, 'UninstallString', UninstallString) then
      Continue;
    if Pos('msiexec', Lowercase(UninstallString)) = 0 then
      Continue;

    if TryExtractMsiProductCode(UninstallString, ProductCode) then begin
      Result := True;
      Exit;
    end;
  end;
end;

function FindExistingAtlasBackendMsiProductCode(var ProductCode: string): Boolean;
begin
  Result :=
    FindExistingAtlasBackendMsiProductCodeInRoot(
      HKCU,
      'Software\Microsoft\Windows\CurrentVersion\Uninstall',
      ProductCode
    ) or
    FindExistingAtlasBackendMsiProductCodeInRoot(
      HKLM,
      'Software\Microsoft\Windows\CurrentVersion\Uninstall',
      ProductCode
    ) or
    FindExistingAtlasBackendMsiProductCodeInRoot(
      HKLM64,
      'Software\Microsoft\Windows\CurrentVersion\Uninstall',
      ProductCode
    ) or
    FindExistingAtlasBackendMsiProductCodeInRoot(
      HKLM32,
      'Software\Microsoft\Windows\CurrentVersion\Uninstall',
      ProductCode
    );
end;

function UninstallExistingMsi(var NeedsRestart: Boolean): string;
var
  ProductCode: string;
  ResultCode: Integer;
begin
  Result := '';
  ProductCode := '';
  if not FindExistingAtlasBackendMsiProductCode(ProductCode) then
    Exit;

  ForceCloseRunningAtlasBackendInstances;

  if not Exec(
    ExpandConstant('{sys}\msiexec.exe'),
    '/x ' + ProductCode + ' /qn /norestart',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  ) then begin
    Result :=
      'Setup could not remove the previous MSI-based ATLAS Backend installation.'#13#10#13#10 +
      'Please uninstall ATLAS Backend from Apps & Features and run this setup again.';
    Exit;
  end;

  if (ResultCode = 3010) then begin
    NeedsRestart := True;
    Exit;
  end;

  if (ResultCode <> 0) and (ResultCode <> 1605) and (ResultCode <> 1614) then
    Result :=
      'Setup could not remove the previous MSI-based ATLAS Backend installation (exit code ' +
      IntToStr(ResultCode) + ').'#13#10#13#10 +
      'Please uninstall ATLAS Backend from Apps & Features and run this setup again.';
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  LegacyMsiProductCode: string;
  HasLegacyMsi: Boolean;
begin
  ForceCloseRunningAtlasBackendInstances;
  LegacyMsiProductCode := '';
  HasLegacyMsi := FindExistingAtlasBackendMsiProductCode(LegacyMsiProductCode);
  if HasLegacyMsi then
    StageLegacyMsiResetForInstallerMigration
  else
    StageMutableDataForInstallerMigration;
  Result := UninstallExistingMsi(NeedsRestart);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then begin
    ForceCloseRunningAtlasBackendInstances;
  end;
end;
