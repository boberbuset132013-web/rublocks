#define AppName "RUblocks"
#define AppVersion "0.2.0"
#define AppPublisher "RUblocks"

[Setup]
AppId={{9E1E5B77-ED4A-4C5E-B85B-DA27F70C1A31}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={localappdata}\Programs\RUblocks
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64
OutputDir=..\artifacts
OutputBaseFilename=RUblocks-Setup
SetupIconFile=..\assets\rublocks_icon.ico
UninstallDisplayIcon={app}\RUblocks.exe
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
SetupLogging=yes

[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Дополнительно:"; Flags: checkedonce

[Files]
Source: "..\installer-input\RUblocks.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "README_RU.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\RUblocks"; Filename: "{app}\RUblocks.exe"; WorkingDir: "{app}"; IconFilename: "{app}\RUblocks.exe"
Name: "{autodesktop}\RUblocks"; Filename: "{app}\RUblocks.exe"; WorkingDir: "{app}"; Tasks: desktopicon; IconFilename: "{app}\RUblocks.exe"

[Run]
Filename: "{app}\RUblocks.exe"; Description: "Запустить RUblocks"; Flags: postinstall nowait skipifsilent
