; Intent for Windows 安装器(Inno Setup 6)
; 由 CI 在 repack 完成后编译:
;   iscc /DAppVersion=<版本> /DSourceDir=<repo>\.work\Intent-win scripts\installer.iss
; 本地编译同理(需先跑 repack.ps1 产出 .work\Intent-win)。

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\.work\Intent-win"
#endif

[Setup]
; AppId 固定,新版本安装器可直接覆盖升级旧安装
AppId={{DDE1540E-9707-4C2F-B694-E68FC8E3F057}
AppName=Intent by Augment
AppVersion={#AppVersion}
AppPublisher=intent-windows-repack (unofficial)
; 免管理员:装到当前用户目录
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\Intent
DefaultGroupName=Intent
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; 升级时自动请求关闭正在运行的应用
CloseApplications=yes
OutputDir=..\dist
OutputBaseFilename=Intent-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
UninstallDisplayIcon={app}\IntentbyAugment.exe
#define IconPath SourceDir + "\..\icon.ico"
#if FileExists(IconPath)
SetupIconFile={#IconPath}
#endif

[Tasks]
Name: desktopicon; Description: "创建桌面快捷方式(&D)"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{autoprograms}\Intent"; Filename: "{app}\IntentbyAugment.exe"
Name: "{autodesktop}\Intent"; Filename: "{app}\IntentbyAugment.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\IntentbyAugment.exe"; Description: "启动 Intent"; Flags: nowait postinstall skipifsilent

; 卸载时保留 %APPDATA%\intent 用户数据(登录/设置/会话),只删应用本体
