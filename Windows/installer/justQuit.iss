#define MyAppName "justQuit"
#define MyAppVersion "1.2.18"
#define MyAppPublisher "Agraja"
#define MyAppExeName "justQuit.exe"

#ifndef Architecture
  #define Architecture "x64"
#endif

#ifndef SourceDir
  #define SourceDir "..\publish\win-x64"
#endif

#if Architecture == "arm64"
  #define MyInstallerSuffix "ARM64"
  #define MyArchitecturesAllowed "arm64"
  #define MyArchitecturesInstallMode "arm64"
#else
  #define MyInstallerSuffix "x64"
  #define MyArchitecturesAllowed "x64compatible"
  #define MyArchitecturesInstallMode "x64compatible"
#endif

[Setup]
AppId={{8E6350A8-F63E-4DB7-B9CF-2B1ED7EA0D2A}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
WizardStyle=modern
Compression=lzma
SolidCompression=yes
OutputDir=output
OutputBaseFilename=justQuit-Setup-{#MyInstallerSuffix}
ArchitecturesAllowed={#MyArchitecturesAllowed}
ArchitecturesInstallIn64BitMode={#MyArchitecturesInstallMode}
PrivilegesRequired=lowest
CloseApplications=yes
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked
Name: "startup"; Description: "Launch justQuit when Windows starts"; GroupDescription: "Startup options:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#MyAppName}"; ValueData: """{app}\{#MyAppExeName}"""; Flags: uninsdeletevalue; Tasks: startup
