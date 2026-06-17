; =========================================================
; ISV Toolkit - Instalador Inno Setup
; =========================================================

#define MyAppName "ISV Toolkit"
#define MyAppVersion "1.0.4"
#define MyAppPublisher "iOnetech"
#define MyAppExeName "isv_toolkit.exe"
#define BuildPath "..\..\build\windows\x64\runner\Release"

[Setup]

AppId={{D2B5D8CD-9E6D-4E9A-B556-9B5A89E6E5A8}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}

; Instalar correctamente como x64
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; Carpeta de instalación
DefaultDirName={autopf}\{#MyAppName}

DisableProgramGroupPage=yes

; Salida instalador
OutputDir=..\..\build\installer
OutputBaseFilename=ISV_Toolkit_1.0.4_Setup

; Icono
SetupIconFile=..\..\windows\runner\resources\app_icon.ico

Compression=lzma
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]

; =========================================================
; COPIAR TODO EL BUILD FLUTTER
; =========================================================
Source: "{#BuildPath}\*"; \
    DestDir: "{app}"; \
    Flags: ignoreversion recursesubdirs createallsubdirs

; =========================================================
; RECURSOS ADICIONALES
; =========================================================
Source: "..\..\resources\bin\*"; \
    DestDir: "{app}\bin"; \
    Flags: ignoreversion recursesubdirs createallsubdirs

Source: "..\..\resources\jks\*"; \
    DestDir: "{app}\jks"; \
    Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]

Name: "{autoprograms}\{#MyAppName}"; \
    Filename: "{app}\{#MyAppExeName}"

Name: "{autodesktop}\{#MyAppName}"; \
    Filename: "{app}\{#MyAppExeName}"; \
    Tasks: desktopicon

[Run]

Filename: "{app}\{#MyAppExeName}"; \
    Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; \
    Flags: nowait postinstall skipifsilent