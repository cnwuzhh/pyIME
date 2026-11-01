param(
    [string]$BoostRoot = (Join-Path $PSScriptRoot '..\.tools\boost_1_84_0'),
    [string]$CMakeBin = (Join-Path $PSScriptRoot '..\.tools\cmake-3.31.8-windows-x86_64\bin'),
    [switch]$SkipDependencies
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$weasel = Join-Path $root 'vendor\weasel'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$gitBin = Join-Path $env:ProgramFiles 'Git\bin'
$pythonBin = Join-Path $root '.tools\python\Scripts'
$nsis = Join-Path ${env:ProgramFiles(x86)} 'NSIS\Bin\makensis.exe'

foreach ($path in @(
    $vswhere,
    $nsis,
    (Join-Path $BoostRoot 'boost\version.hpp'),
    (Join-Path $CMakeBin 'cmake.exe'),
    (Join-Path $gitBin 'bash.exe'),
    (Join-Path $weasel 'librime\build.bat'),
    (Join-Path $weasel 'plum\rime-install')
)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing build prerequisite: $path. See README.md for toolchain setup."
    }
}

$vs = & $vswhere -latest -products '*' -version '[17.0,18.0)' -requires `
    Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    Microsoft.VisualStudio.Component.VC.ATLMFC -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $vs) {
    throw 'Visual Studio 2022 C++ Build Tools with ATL/MFC were not found.'
}
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvarsall.bat'
if (-not (Test-Path -LiteralPath $vcvars)) {
    throw "Missing compiler environment setup: $vcvars"
}

$env:BOOST_ROOT = (Resolve-Path -LiteralPath $BoostRoot).Path
$env:SDKVER = '10.0.19041.0'
$env:RELEASE_BUILD = '1'
$env:DEVTOOLS_PATH = "$gitBin;$CMakeBin;$pythonBin;"
$env:PATH = "$gitBin;$CMakeBin;$pythonBin;$env:PATH"
$env:BOOST_COMPILED_LIBS = '--project-config="{0}"' -f (Join-Path $PSScriptRoot 'boost-config.jam')

$localEnv = Join-Path $weasel 'env.bat'
if (-not (Test-Path -LiteralPath $localEnv)) {
    Copy-Item -LiteralPath (Join-Path $weasel 'env.vs2022.bat') -Destination $localEnv
}

$targets = 'boost rime data opencc weasel installer'
if ($SkipDependencies) {
    $targets = 'weasel installer'
}

$logs = Join-Path $root '.build'
New-Item -ItemType Directory -Path $logs -Force | Out-Null
$log = Join-Path $logs ("build-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
Write-Host "Build log: $log"
$command = '(call "{0}" x86_amd64 {1} && cd /d "{2}" && call build.bat {3}) 2>&1' -f `
    $vcvars, $env:SDKVER, $weasel, $targets
& $env:ComSpec /d /c $command | Tee-Object -FilePath $log
if ($LASTEXITCODE -ne 0) {
    throw "Weasel build failed with exit code $LASTEXITCODE. See $log."
}
$installer = Get-Item -LiteralPath (Join-Path $weasel 'output\archives\weasel-0.17.4.0-installer.exe')
if ($installer.Length -eq 0) {
    throw 'The generated installer is empty.'
}
Write-Host "Installer: $($installer.FullName)"
