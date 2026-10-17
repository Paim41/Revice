[Setup]
AppId=ReviceAgent
AppName=Revice Agent
AppVersion=0.2.0
DefaultDirName={localappdata}\Programs\ReviceAgent
DefaultGroupName=Revice Agent
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\installer-output
OutputBaseFilename=Revice-Agent-Setup
Compression=lzma2
SolidCompression=yes
UninstallDisplayIcon={app}\Revice.Agent.exe
CloseApplications=yes

[Files]
Source: "..\publish\Revice.Agent.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Device Agent"; Filename: "{app}\Revice.Agent.exe"
Name: "{group}\Uninstall"; Filename: "{uninstallexe}"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "ReviceAgent"; Flags: uninsdeletevalue

[Run]
Filename: "{app}\Revice.Agent.exe"; Description: "Open Device Agent"; Flags: nowait postinstall skipifsilent
