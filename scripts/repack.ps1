<#
.SYNOPSIS
  将 Intent by Augment 的 macOS (.dmg) 包重打包为可在 Windows 运行的版本。

.DESCRIPTION
  自动完成以下步骤(全部从 dmg 动态探测版本,不写死):
    1. 解开 dmg,提取 app.asar / app.asar.unpacked,读取 Electron 版本与原生模块 ABI
    2. 下载对应版本的 Windows 版 Electron 运行时
    3. 将 app.asar 解为 app 目录(绕开 asar 索引限制),合并 unpacked
    4. 用 Windows 预编译替换 sharp / @parcel/watcher / better-sqlite3
    5. 本机/CI 编译 node-pty(关闭 Spectre 缓解)并装入
    6. 组装为 Intent-win,打包为 zip

  设计为既可本地运行,也可在 GitHub Actions 的 windows-latest runner 上运行
  (runner 自带 7-Zip / Node / Python / VS C++ 工具链)。

.PARAMETER DmgPath
  Intent 的 .dmg 文件路径。与 -DmgUrl 二选一。

.PARAMETER DmgUrl
  Intent 的 .dmg 下载地址(CI 场景)。与 -DmgPath 二选一。

.PARAMETER OutDir
  成品输出目录,默认 <repo>/dist。

.EXAMPLE
  pwsh scripts/repack.ps1 -DmgPath "D:\Downloads\Intent-latest-arm64.dmg"
#>
[CmdletBinding()]
param(
  [string]$DmgPath,
  [string]$DmgUrl,
  [string]$OutDir   = (Join-Path $PSScriptRoot "..\dist"),
  [string]$WorkDir  = (Join-Path $PSScriptRoot "..\.work"),
  [string]$ElectronMirror = "https://npmmirror.com/mirrors/electron/"
)

$ErrorActionPreference = 'Stop'
function Log  ($m) { Write-Host "[repack] $m" -ForegroundColor Cyan }
function Warn ($m) { Write-Host "[repack] WARN: $m" -ForegroundColor Yellow }
function Die  ($m) { Write-Host "[repack] ERROR: $m" -ForegroundColor Red; exit 1 }

# 某些加固环境会设置该变量,导致 winpty 构建脚本 (cd shared && GetCommitHash.bat) 找不到同目录 bat。
# 清除它只影响本进程及其子进程,不改系统设置。
$env:NoDefaultCurrentDirectoryInExePath = $null

$WorkDir = [System.IO.Path]::GetFullPath($WorkDir)
$OutDir  = [System.IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force $WorkDir | Out-Null
New-Item -ItemType Directory -Force $OutDir  | Out-Null

# ---------------------------------------------------------------------------
# 工具:确保有一个支持 dmg/APFS 的完整版 7-Zip,返回 7z.exe 路径
# ---------------------------------------------------------------------------
function Ensure-SevenZip {
  foreach ($c in @("C:\Program Files\7-Zip\7z.exe", "C:\Program Files (x86)\7-Zip\7z.exe")) {
    if (Test-Path $c) { return $c }
  }
  $onPath = Get-Command 7z.exe -ErrorAction SilentlyContinue
  if ($onPath) { return $onPath.Source }

  Log "未找到系统 7-Zip,自动下载完整版命令行..."
  $tool = Join-Path $WorkDir "7ztool"
  New-Item -ItemType Directory -Force $tool | Out-Null
  # 先用 npm 的 7zip-bin 拿到精简版 7za(它能解 7-Zip 自解压安装器)
  npm install --prefix $tool 7zip-bin 2>&1 | Out-Null
  $7za = Join-Path $tool "node_modules\7zip-bin\win\x64\7za.exe"
  if (-not (Test-Path $7za)) { Die "无法获取 7za" }
  $inst = Join-Path $tool "7z-inst.exe"
  Invoke-WebRequest -Uri "https://www.7-zip.org/a/7z2409-x64.exe" -OutFile $inst -UseBasicParsing
  & $7za x $inst "-o$tool\full" 7z.exe 7z.dll -y | Out-Null
  $full = Join-Path $tool "full\7z.exe"
  if (-not (Test-Path $full)) { Die "无法从安装器提取完整版 7z.exe" }
  return $full
}

# ---------------------------------------------------------------------------
# 工具:读取 json 文件的某个字段
# ---------------------------------------------------------------------------
function Get-JsonValue($file, $prop) {
  if (-not (Test-Path $file)) { return $null }
  return (Get-Content $file -Raw | ConvertFrom-Json).$prop
}

# ---------------------------------------------------------------------------
# 0. 准备 dmg
# ---------------------------------------------------------------------------
if ($DmgUrl) {
  $DmgPath = Join-Path $WorkDir "Intent.dmg"
  Log "下载 dmg: $DmgUrl"
  Invoke-WebRequest -Uri $DmgUrl -OutFile $DmgPath -UseBasicParsing
}
if (-not $DmgPath -or -not (Test-Path $DmgPath)) { Die "请通过 -DmgPath 或 -DmgUrl 提供 dmg" }
Log "dmg: $DmgPath ($([math]::Round((Get-Item $DmgPath).Length/1MB,1)) MB)"

$7z = Ensure-SevenZip
Log "7-Zip: $7z"

# ---------------------------------------------------------------------------
# 1. 解 dmg,提取 Resources(app.asar + app.asar.unpacked)
# ---------------------------------------------------------------------------
$extracted = Join-Path $WorkDir "extracted"
if (Test-Path $extracted) { Remove-Item $extracted -Recurse -Force }
Log "解开 dmg 中的 app.asar / app.asar.unpacked ..."
& $7z x $DmgPath "-o$extracted" "*\Contents\Resources\app.asar*" -r -y | Out-Null

# 定位 .app/Contents/Resources(应用名未写死)
$resDir = Get-ChildItem $extracted -Recurse -Directory -Filter "Resources" |
          Where-Object { Test-Path (Join-Path $_.FullName "app.asar") } |
          Select-Object -First 1
if (-not $resDir) { Die "dmg 中未找到 app.asar" }
$resDir = $resDir.FullName
$appName = (Get-Item (Join-Path $resDir "..\..")).Name   # e.g. "Intent by Augment.app"
Log "应用: $appName"

# 探测 Electron 版本(从 Electron Framework Info.plist)
$plist = Join-Path $WorkDir "ElectronInfo.plist"
$plistInDmg = "$appName\Contents\Frameworks\Electron Framework.framework\Versions\A\Resources\Info.plist"
& $7z e $DmgPath "-o$WorkDir" $plistInDmg -y | Out-Null
$tmpPlist = Join-Path $WorkDir "Info.plist"
$electronVersion = $null
if (Test-Path $tmpPlist) {
  $c = Get-Content $tmpPlist -Raw
  if ($c -match "<key>CFBundleVersion</key>\s*<string>([^<]+)</string>") { $electronVersion = $matches[1] }
}
if (-not $electronVersion) { Die "无法探测 Electron 版本" }
Log "Electron 版本: $electronVersion"

# 探测原生模块 ABI(从 node-pty 的 bin/darwin-*-<abi> 目录名)
$abi = $null
$nptyBin = Join-Path $resDir "app.asar.unpacked\node_modules\node-pty\bin"
if (Test-Path $nptyBin) {
  $d = Get-ChildItem $nptyBin -Directory | Select-Object -First 1
  if ($d -and $d.Name -match "-(\d+)$") { $abi = $matches[1] }
}
if (-not $abi) { Warn "无法从 node-pty 探测 ABI,将依赖 electron-rebuild 自动推断" }
else { Log "原生模块 ABI: $abi" }

# ---------------------------------------------------------------------------
# 2. 下载 Windows 版 Electron 运行时
# ---------------------------------------------------------------------------
$electronZip = Join-Path $WorkDir "electron-win.zip"
$url = "$($ElectronMirror.TrimEnd('/'))/v$electronVersion/electron-v$electronVersion-win32-x64.zip"
Log "下载 Electron 运行时: $url"
Invoke-WebRequest -Uri $url -OutFile $electronZip -UseBasicParsing

$dest = Join-Path $WorkDir "Intent-win"
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
& $7z x $electronZip "-o$dest" -y | Out-Null
if (-not (Test-Path (Join-Path $dest "electron.exe"))) { Die "Electron 运行时解压失败" }

# ---------------------------------------------------------------------------
# 3. app.asar -> app 目录(绕开 asar 索引),合并 unpacked
# ---------------------------------------------------------------------------
Log "将 app.asar 解为 app 目录 ..."
npm install --prefix $WorkDir "@electron/asar" 2>&1 | Out-Null
$asar = Join-Path $WorkDir "node_modules\.bin\asar.cmd"
$appDir = Join-Path $dest "resources\app"
if (Test-Path $appDir) { Remove-Item $appDir -Recurse -Force }
& $asar extract (Join-Path $resDir "app.asar") $appDir

# 合并 app.asar.unpacked 的真实二进制
$unpacked = Join-Path $resDir "app.asar.unpacked"
if (Test-Path $unpacked) {
  $cut = $unpacked.Length + 1
  Get-ChildItem $unpacked -Recurse -File | ForEach-Object {
    $target = Join-Path $appDir $_.FullName.Substring($cut)
    $tdir = Split-Path $target -Parent
    if (-not (Test-Path $tdir)) { New-Item -ItemType Directory -Force $tdir | Out-Null }
    Copy-Item $_.FullName $target -Force
  }
}
$nm = Join-Path $appDir "node_modules"

# ---------------------------------------------------------------------------
# 4. 替换平台预编译原生模块:sharp / @parcel/watcher / better-sqlite3
# ---------------------------------------------------------------------------
$dl = Join-Path $WorkDir "dl"
New-Item -ItemType Directory -Force $dl | Out-Null

function Add-NpmTarball($pkgSpec, $destPkgDir) {
  # 用 npm pack 下载(不做 os/cpu 平台校验),解开 package/ 放到目标目录
  Log "获取 $pkgSpec"
  npm pack $pkgSpec --pack-destination $dl 2>&1 | Out-Null
  $tgz = Get-ChildItem $dl -Filter *.tgz | Sort-Object LastWriteTime | Select-Object -Last 1
  $tmp = Join-Path $WorkDir ("pkg_" + [System.IO.Path]::GetFileNameWithoutExtension($tgz.Name))
  if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
  New-Item -ItemType Directory -Force $tmp | Out-Null
  tar -xzf $tgz.FullName -C $tmp
  if (Test-Path $destPkgDir) { Remove-Item $destPkgDir -Recurse -Force }
  New-Item -ItemType Directory -Force (Split-Path $destPkgDir -Parent) | Out-Null
  Move-Item (Join-Path $tmp "package") $destPkgDir
}

# sharp: win32-x64 binding 包(自带 libvips dll),版本对齐 darwin 分包
$sharpVer = Get-JsonValue (Join-Path $nm "@img\sharp-darwin-arm64\package.json") "version"
if ($sharpVer) {
  Add-NpmTarball "@img/sharp-win32-x64@$sharpVer" (Join-Path $nm "@img\sharp-win32-x64")
} else { Warn "未发现 sharp,跳过" }

# @parcel/watcher: win32-x64 分包,嵌套在 watcher/node_modules/@parcel 下
$watcherVer = Get-JsonValue (Join-Path $nm "@parcel\watcher\package.json") "version"
if ($watcherVer) {
  Add-NpmTarball "@parcel/watcher-win32-x64@$watcherVer" `
    (Join-Path $nm "@parcel\watcher\node_modules\@parcel\watcher-win32-x64")
} else { Warn "未发现 @parcel/watcher,跳过" }

# better-sqlite3: 替换已存在的 .node(从 GitHub release 拉对应 electron ABI 预编译)
$bsVer = Get-JsonValue (Join-Path $nm "better-sqlite3\package.json") "version"
if ($bsVer -and $abi) {
  $bsTar = Join-Path $dl "better-sqlite3-win.tar.gz"
  $bsUrl = "https://github.com/WiseLibs/better-sqlite3/releases/download/v$bsVer/better-sqlite3-v$bsVer-electron-v$abi-win32-x64.tar.gz"
  Log "获取 better-sqlite3 预编译: $bsUrl"
  Invoke-WebRequest -Uri $bsUrl -OutFile $bsTar -UseBasicParsing
  $bsTmp = Join-Path $WorkDir "bs"
  if (Test-Path $bsTmp) { Remove-Item $bsTmp -Recurse -Force }
  New-Item -ItemType Directory -Force $bsTmp | Out-Null
  tar -xzf $bsTar -C $bsTmp
  Copy-Item (Join-Path $bsTmp "build\Release\better_sqlite3.node") `
            (Join-Path $nm "better-sqlite3\build\Release\better_sqlite3.node") -Force
} else { Warn "未发现 better-sqlite3 或 ABI,跳过" }

# ---------------------------------------------------------------------------
# 5. 编译 node-pty(关闭 Spectre)并装入
# ---------------------------------------------------------------------------
$nptyVer = Get-JsonValue (Join-Path $nm "node-pty\package.json") "version"
if ($nptyVer) {
  Log "编译 node-pty@$nptyVer for Electron $electronVersion ..."
  $nb = Join-Path $WorkDir "nptybuild"
  if (Test-Path $nb) { Remove-Item $nb -Recurse -Force }
  New-Item -ItemType Directory -Force $nb | Out-Null
  npm install --prefix $nb "node-pty@$nptyVer" "@electron/rebuild" --ignore-scripts 2>&1 | Out-Null

  # 关闭 Spectre 缓解(node-pty 默认要求 Spectre 库;本地终端模块无此威胁模型)
  $gyp = Join-Path $nb "node_modules\node-pty\binding.gyp"
  (Get-Content $gyp -Raw).Replace("'SpectreMitigation': 'Spectre'", "'SpectreMitigation': 'false'") |
    Set-Content $gyp -NoNewline

  # 修复 node-pty 已知缺陷(详见 README"已知问题与修复"):
  #   1) conpty.cc 退出竞态:应用关闭时主线程 napi env 正在拆除,BlockingCall 返回
  #      napi_closing,旧代码 assert(status==napi_ok) 触发 C++ 断言弹框 → 改为容忍并清理。
  #   2) assert 内包裹有副作用调用(remove_pty_baton / remove_pipe_handle),一旦定义
  #      NDEBUG 整个 assert 会被编译掉导致资源泄漏 → 把调用拎出来、去掉 assert。
  $srcWin = Join-Path $nb "node_modules\node-pty\src\win"
  $patches = @(
    @{ File = "conpty.cc"; From = 'assert(status == napi_ok);';       To = 'if (status != napi_ok) { delete exit_event; }' },
    @{ File = "conpty.cc"; From = 'assert(remove_pty_baton(id));';    To = 'remove_pty_baton(id);' },
    @{ File = "winpty.cc"; From = 'assert(remove_pipe_handle(pid));'; To = 'remove_pipe_handle(pid);' }
  )
  foreach ($p in $patches) {
    $pf = Join-Path $srcWin $p.File
    if (-not (Test-Path $pf)) { Warn ("patch 跳过,文件不存在: " + $p.File); continue }
    $c = Get-Content $pf -Raw
    if ($c.Contains($p.From)) {
      $c.Replace($p.From, $p.To) | Set-Content $pf -NoNewline
      Log ("patched " + $p.File + ": " + $p.From)
    } else {
      Warn ("patch 未命中(上游可能已变更),跳过: " + $p.File + " <= " + $p.From)
    }
  }

  $env:ELECTRON_MIRROR = $ElectronMirror
  $er = Join-Path $nb "node_modules\.bin\electron-rebuild.cmd"
  & $er --version $electronVersion --only node-pty --module-dir $nb --force
  if ($LASTEXITCODE -ne 0) { Die "node-pty 编译失败" }

  $rel = Join-Path $nb "node_modules\node-pty\build\Release"
  $dstRel = Join-Path $nm "node-pty\build\Release"
  New-Item -ItemType Directory -Force $dstRel | Out-Null
  foreach ($f in @("conpty.node","pty.node","conpty_console_list.node","winpty.dll","winpty-agent.exe")) {
    $src = Join-Path $rel $f
    if (Test-Path $src) { Copy-Item $src (Join-Path $dstRel $f) -Force }
  }
  Log "node-pty 装入完成"
} else { Warn "未发现 node-pty,跳过" }

# ---------------------------------------------------------------------------
# 6. 删除原 app.asar / unpacked(改用 app 目录),打包成品
# ---------------------------------------------------------------------------
foreach ($p in @("app.asar","app.asar.unpacked")) {
  $t = Join-Path $dest "resources\$p"
  if (Test-Path $t) {
    if ([System.IO.Directory]::Exists($t)) { [System.IO.Directory]::Delete($t, $true) }
    else { [System.IO.File]::Delete($t) }
  }
}

# 把 electron.exe 改名为应用名,更像原生应用(可选)
$exeName = ($appName -replace "\.app$","") -replace " ",""
Copy-Item (Join-Path $dest "electron.exe") (Join-Path $dest "$exeName.exe") -Force

$stamp = (Get-Date -Format "yyyyMMdd")
$zip = Join-Path $OutDir "Intent-win32-x64-electron$electronVersion-$stamp.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Log "打包成品: $zip"
& $7z a -tzip $zip "$dest\*" -mx=5 | Out-Null

Log "完成! 成品: $zip"
Log "Electron=$electronVersion ABI=$abi  node-pty=$nptyVer sharp=$sharpVer watcher=$watcherVer better-sqlite3=$bsVer"
