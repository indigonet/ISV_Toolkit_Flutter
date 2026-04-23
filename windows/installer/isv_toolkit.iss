; Script generador por Antigravity para ISV Toolkit
#define MyAppName "ISV Toolkit"
#define MyAppVersion "1.0.1"
#define MyAppPublisher "iOnetech"
#define MyAppExeName "isv_toolkit.exe"
#define BuildPath "..\..\build\windows\x64\runner\Release"

[Setup]
; AppId único para identificar la app en el sistema
AppId={{D2B5D8CD-9E6D-4E9A-B556-9B5A89E6E5A8}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
; Carpeta de salida del instalador
OutputDir=..\..\build\installer
OutputBaseFilename=ISV_Toolkit_Setup
; Icono oficial
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Ejecutable principal (Ignorar versión para asegurar sobrescritura en updates)
Source: "{#BuildPath}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
; Librerías DLL dinámicas
Source: "{#BuildPath}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
; Carpeta de datos y recursos (Obligatorio para que Flutter funcione)
Source: "{#BuildPath}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
; Herramientas SDK y Firmas (Bundled)
Source: "..\..\resources\bin\*"; DestDir: "{app}\bin"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\resources\jks\*"; DestDir: "{app}\jks"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
