; Per-user installer for the Windows build; see .github/workflows/release.yml.
;   iscc /DAppVersion=0.2.0 /DSourceDir=<staged dir> /DOutputDir=<dir> /DOutputName=<name> look-studio.iss

#define AppName "Look Studio"
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "dist"
#endif
#ifndef OutputName
  #define OutputName "look-studio-setup"
#endif

[Setup]
AppId={{285AE177-5D68-4A4F-8D36-76C6606037AD}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Look Studio contributors
AppPublisherURL=https://github.com/WALKERKILLER/Look-Tongji-Notes/tree/app
AppSupportURL=https://github.com/WALKERKILLER/Look-Tongji-Notes/issues
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\look_studio.exe
UninstallDisplayName={#AppName}
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
; lookd.exe runs while the app is open; let Restart Manager close both.
CloseApplications=force

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\look_studio.exe"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\look_studio.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\look_studio.exe"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM lookd.exe"; Flags: runhidden; RunOnceId: "StopLookd"
