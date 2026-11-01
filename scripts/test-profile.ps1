param(
    [string]$Installer
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $Installer) {
    $brand = Get-Content -LiteralPath (Join-Path $root 'config\branding.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $Installer = Join-Path $root ('output\' + $brand.installerFile)
}
$weasel = Join-Path $root 'vendor\weasel'
$work = Join-Path $root ('.build\profile-test-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $work | Out-Null
$package = Join-Path $work 'package'
& (Join-Path $weasel 'output\7z.exe') x $Installer "-o$package" -aou -bso0 -bsp0
if ($LASTEXITCODE -ne 0) {
    throw "Installer extraction failed with exit code $LASTEXITCODE."
}
& (Join-Path $PSScriptRoot 'test-branding.ps1') -Installer $Installer -PackageDirectory $package

$dlls = Get-ChildItem -LiteralPath $package -Filter 'rime*.dll' | Where-Object {
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    $offset = [BitConverter]::ToInt32($bytes, 0x3C)
    [BitConverter]::ToUInt16($bytes, $offset + 4) -eq 0x8664
}
if (@($dlls).Count -ne 1) {
    throw 'Expected exactly one x64 Rime DLL in the installer.'
}
Copy-Item -LiteralPath $dlls.FullName -Destination (Join-Path $work 'rime.dll')
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products '*' -version '[17.0,18.0)' -requires `
    Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $vs) {
    throw 'Visual Studio 2022 C++ Build Tools were not found.'
}
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvarsall.bat'
$boost = Join-Path $root '.tools\boost_1_84_0'
$compile = 'call "{0}" x64 10.0.19041.0 && cd /d "{1}" && cl /nologo /std:c++17 /utf-8 /EHsc /MT /O2 /DUNICODE /D_UNICODE /I"{2}\include" /I"{3}" "{4}" /Fe:ImeProfileTest.exe /link /LTCG /LIBPATH:"{2}\lib64" /LIBPATH:"{2}\msbuild\Release\x64" /LIBPATH:"{3}\stage\lib" RimeWithWeasel.lib WeaselUI.lib WeaselIPC.lib rime.lib d2d1.lib dwrite.lib d3d11.lib dxgi.lib dcomp.lib shcore.lib user32.lib gdi32.lib ole32.lib advapi32.lib shell32.lib imm32.lib usp10.lib comctl32.lib version.lib uxtheme.lib dwmapi.lib windowscodecs.lib' -f `
    $vcvars, $work, $weasel, $boost, (Join-Path $root 'test\ImeProfileTest.cpp')
& $env:ComSpec /d /c $compile
if ($LASTEXITCODE -ne 0) {
    throw "Profile test compilation failed with exit code $LASTEXITCODE."
}

$user = Join-Path $work 'user'
New-Item -ItemType Directory -Path $user | Out-Null
foreach ($name in @('default.custom.yaml', 'weasel.custom.yaml')) {
    [System.IO.File]::WriteAllText((Join-Path $user $name), '')
}
$preview = Join-Path $root 'output\candidate-preview.png'
& (Join-Path $work 'ImeProfileTest.exe') (Join-Path $package 'data') $user 14 $preview
if ($LASTEXITCODE -ne 0) {
    throw "Profile runtime or native preview validation failed with exit code $LASTEXITCODE."
}

$overrideUser = Join-Path $work 'user-overrides'
New-Item -ItemType Directory -Path $overrideUser | Out-Null
[System.IO.File]::WriteAllText((Join-Path $overrideUser 'default.custom.yaml'), '')
[System.IO.File]::WriteAllText((Join-Path $overrideUser 'weasel.custom.yaml'), "patch:`n  style/font_point: 16`n")
& (Join-Path $work 'ImeProfileTest.exe') (Join-Path $package 'data') $overrideUser 16
if ($LASTEXITCODE -ne 0) {
    throw "Existing-user override validation failed with exit code $LASTEXITCODE."
}
Remove-Item -LiteralPath $work -Recurse -Force
Write-Host "Profile tests passed. Native preview: $preview"
