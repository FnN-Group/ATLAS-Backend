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
  #define ExecutableName "ATLAS.exe"
#endif

#ifndef OutputDir
  #error OutputDir define is required.
#endif

#ifndef OutputBaseFilename
  #define OutputBaseFilename "ATLAS-Backend-Setup"
#endif

#ifndef SetupIconFile
  #define SetupIconFile ""
#endif

[Setup]
AppId={{8C7FECAB-4CE9-43A5-9BB4-3BCE5AF7FB7F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
VersionInfoDescription={#MyAppName}
UninstallDisplayName={#MyAppName}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={localappdata}\ATLAS Backend
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#ExecutableName}
#if SetupIconFile != ""
SetupIconFile={#SetupIconFile}
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Install the full app payload, but do not overwrite mutable runtime files on update.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "responses\curves.json,responses\datatables-ui.json,responses\modifications-backup.json,src\config\config.ini,static\hotfixes\DefaultGame.ini"
; First install gets defaults; upgrades preserve user-edited files.
Source: "{#SourceDir}\responses\curves.json"; DestDir: "{app}\responses"; Flags: ignoreversion onlyifdoesntexist
Source: "{#SourceDir}\responses\datatables-ui.json"; DestDir: "{app}\responses"; Flags: ignoreversion onlyifdoesntexist
Source: "{#SourceDir}\responses\modifications-backup.json"; DestDir: "{app}\responses"; Flags: ignoreversion onlyifdoesntexist
Source: "{#SourceDir}\src\config\config.ini"; DestDir: "{app}\src\config"; Flags: ignoreversion onlyifdoesntexist
Source: "{#SourceDir}\static\hotfixes\DefaultGame.ini"; DestDir: "{app}\static\hotfixes"; Flags: ignoreversion onlyifdoesntexist
#if SetupIconFile != ""
Source: "{#SetupIconFile}"; DestDir: "{app}"; DestName: "ATLAS-Backend.ico"; Flags: ignoreversion
#endif

[InstallDelete]
; Remove stale shortcuts so upgrades recreate links with the latest icon metadata.
Type: files; Name: "{autoprograms}\{#MyAppName}.lnk"
Type: files; Name: "{autodesktop}\{#MyAppName}.lnk"
Type: files; Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\{#MyAppName}.lnk"

[Icons]
#if SetupIconFile != ""
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#ExecutableName}"; IconFilename: "{app}\ATLAS-Backend.ico"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#ExecutableName}"; IconFilename: "{app}\ATLAS-Backend.ico"; Tasks: desktopicon
#else
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#ExecutableName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#ExecutableName}"; Tasks: desktopicon
#endif

[Run]
Filename: "{app}\{#ExecutableName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
Filename: "{sys}\ie4uinit.exe"; Parameters: "-ClearIconCache"; Flags: runhidden skipifsilent; Check: FileExists(ExpandConstant('{sys}\ie4uinit.exe'))
Filename: "{sys}\ie4uinit.exe"; Parameters: "-show"; Flags: runhidden skipifsilent; Check: FileExists(ExpandConstant('{sys}\ie4uinit.exe'))

[Code]
const
  UninstallRegPath =
    'Software\Microsoft\Windows\CurrentVersion\Uninstall\{#SetupSetting("AppId")}_is1';

function TryGetExistingInstall(var UninstallCmd: string;
  var InstalledVersion: string): Boolean;
begin
  UninstallCmd := '';
  InstalledVersion := '';

  Result := RegQueryStringValue(HKCU, UninstallRegPath, 'UninstallString',
    UninstallCmd);
  if Result then begin
    RegQueryStringValue(HKCU, UninstallRegPath, 'DisplayVersion',
      InstalledVersion);
    Exit;
  end;

  Result := RegQueryStringValue(HKLM, UninstallRegPath, 'UninstallString',
    UninstallCmd);
  if Result then begin
    RegQueryStringValue(HKLM, UninstallRegPath, 'DisplayVersion',
      InstalledVersion);
  end;
end;

function ParseCommand(const CommandLine: string; var FileName: string;
  var Params: string): Boolean;
var
  S: string;
  QuotePos: Integer;
  SpacePos: Integer;
begin
  Result := False;
  FileName := '';
  Params := '';
  S := Trim(CommandLine);
  if S = '' then
    Exit;

  if S[1] = '"' then begin
    Delete(S, 1, 1);
    QuotePos := Pos('"', S);
    if QuotePos = 0 then
      Exit;
    FileName := Copy(S, 1, QuotePos - 1);
    Params := Trim(Copy(S, QuotePos + 1, MaxInt));
  end else begin
    SpacePos := Pos(' ', S);
    if SpacePos > 0 then begin
      FileName := Copy(S, 1, SpacePos - 1);
      Params := Trim(Copy(S, SpacePos + 1, MaxInt));
    end else
      FileName := S;
  end;

  Result := FileName <> '';
end;

function RunExistingUninstaller(const UninstallCmd: string): Boolean;
var
  UninstallerExe: string;
  UninstallParams: string;
  ResultCode: Integer;
begin
  Result := False;
  if not ParseCommand(UninstallCmd, UninstallerExe, UninstallParams) then begin
    MsgBox('Unable to parse the existing uninstall command.', mbError, MB_OK);
    Exit;
  end;

  if not Exec(UninstallerExe, UninstallParams, '', SW_SHOWNORMAL,
    ewWaitUntilTerminated, ResultCode) then begin
    MsgBox('Failed to launch the existing uninstaller.', mbError, MB_OK);
    Exit;
  end;

  if ResultCode <> 0 then begin
    MsgBox('The uninstall process did not complete successfully (exit code ' +
      IntToStr(ResultCode) + ').', mbError, MB_OK);
    Exit;
  end;

  Result := True;
end;

function IsSilentInstall: Boolean;
begin
  Result := WizardSilent;
end;

function InitializeSetup(): Boolean;
var
  UninstallCmd: string;
  InstalledVersion: string;
  Choice: Integer;
begin
  Result := True;

  if IsSilentInstall then
    Exit;

  if not TryGetExistingInstall(UninstallCmd, InstalledVersion) then
    Exit;

  if InstalledVersion <> '{#MyAppVersion}' then
    Exit;

  Choice := MsgBox(
    '{#MyAppName} {#MyAppVersion} is already installed.'#13#10#13#10 +
    'Yes = Repair (reinstall this version)'#13#10 +
    'No = Uninstall'#13#10 +
    'Cancel = Exit setup',
    mbConfirmation,
    MB_YESNOCANCEL
  );

  if Choice = IDYES then begin
    Log('Maintenance mode selected: Repair');
    Exit;
  end;

  if Choice = IDNO then begin
    Log('Maintenance mode selected: Uninstall');
    if RunExistingUninstaller(UninstallCmd) then
      MsgBox('{#MyAppName} was uninstalled. Run setup again to reinstall.',
        mbInformation, MB_OK);
    Result := False;
    Exit;
  end;

  Log('Maintenance mode selected: Cancel');
  Result := False;
end;
