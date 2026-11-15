; Aeris Monitor — Windows desktop installer (Inno Setup 6)
; Build: ISCC.exe deploy\installer\windesktop.iss

#define AppName       "Aeris Monitor"
#ifndef AppVersion
  #define AppVersion  "1.2.1"
#endif
#define AppPublisher  "Aeris Monitor"
#define AppExe        "aeris.exe"
#define AppRoot       "..\..\mobile_app"
#define BuildDir      AppRoot + "\build\windows\x64\runner\Release"
#define AppIcon       AppRoot + "\windows\runner\resources\app_icon.ico"

[Setup]
AppId={{7B4F1F52-3C8A-4E6B-9D2A-5E0C9A7B3F01}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\Aeris Monitor
DefaultGroupName=Aeris Monitor
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=output
OutputBaseFilename=aeris_setup_{#AppVersion}
SetupIconFile={#AppIcon}
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
RestartApplications=no
CloseApplications=yes

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, "&", "&&")}}"; Flags: nowait postinstall skipifsilent