; Inno Setup Installer Script for Perfect Solution Shop Management
; Designed for Windows x64

#define MyAppName "Perfect Solution Shop Management"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Perfect Solution"
#define MyAppExeName "shop_management_flutter.exe"
#define BuildDir "..\..\build\windows\runner\Release"

[Setup]
AppId={{6B90C264-49B0-4EE3-AA35-694EEEE69E11}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\PerfectSolution\ShopManagement
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir=..\..\build\windows\installer
OutputBaseFilename=ShopManagement_Installer_x64
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
SetupIconFile=..\runner\resources\app_icon.ico

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Copy main release build files and bundled runtime DLLs
Source: "{#BuildDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion ignoremissing
Source: "{#BuildDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
