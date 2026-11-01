param(
    [string]$BoostRoot = (Join-Path $PSScriptRoot '..\.tools\boost_1_84_0'),
    [string]$CMakeBin = (Join-Path $PSScriptRoot '..\.tools\cmake-3.31.8-windows-x86_64\bin'),
    [switch]$SkipDependencies
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$weasel = Join-Path $root 'vendor\weasel'
$brand = Get-Content -LiteralPath (Join-Path $root 'config\branding.json') -Raw -Encoding UTF8 | ConvertFrom-Json
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
$env:PYIME_VCVARSALL = $vcvars -replace '\\', '/'
$env:BOOST_COMPILED_LIBS = '--project-config="{0}"' -f (Join-Path $PSScriptRoot 'boost-config.jam')
if (-not $env:CMAKE_BUILD_PARALLEL_LEVEL) {
    $env:CMAKE_BUILD_PARALLEL_LEVEL = $env:NUMBER_OF_PROCESSORS
}

$localEnv = Join-Path $weasel 'env.bat'
if (-not (Test-Path -LiteralPath $localEnv)) {
    Copy-Item -LiteralPath (Join-Path $weasel 'env.vs2022.bat') -Destination $localEnv
}

$phases = @('boost', 'rime', 'data opencc')
if ($SkipDependencies) {
    $phases = @('data opencc')
}

$logs = Join-Path $root '.build'
New-Item -ItemType Directory -Path $logs -Force | Out-Null
$log = Join-Path $logs ("build-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$sourceFiles = @(
    (Join-Path $weasel 'librime\lib\.placeholder'),
    (Join-Path $weasel 'librime\deps\opencc\CMakeLists.txt'),
    (Join-Path $weasel 'output\data\weasel.yaml')
)
foreach ($relative in (& (Join-Path $PSScriptRoot 'apply-branding.ps1') -ListFiles)) {
    $sourceFiles += Join-Path $weasel $relative
}
$originals = foreach ($path in $sourceFiles) {
    @{
        Path = $path
        Bytes = [System.IO.File]::ReadAllBytes($path)
    }
}
Write-Host "Build log: $log"
$commands = @('call "{0}" x86_amd64 {1}' -f $vcvars, $env:SDKVER)
foreach ($phase in $phases) {
    $commands += 'cd /d "{0}" && call build.bat {1}' -f $weasel, $phase
}
$commands += 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}" -DataDirectory "{1}"' -f `
    (Join-Path $PSScriptRoot 'apply-profile.ps1'), (Join-Path $weasel 'output\data')
$commands += 'cd /d "{0}" && call build.bat weasel installer' -f $weasel
$command = '({0}) 2>&1' -f ($commands -join ' && ')
$started = Get-Date
try {
    & (Join-Path $PSScriptRoot 'apply-branding.ps1')
    & $env:ComSpec /d /c $command | Tee-Object -FilePath $log
    $exitCode = $LASTEXITCODE
    $content = [System.IO.File]::ReadAllText($log)
    [System.IO.File]::WriteAllText($log, $content, (New-Object System.Text.UTF8Encoding($false)))
    if ($exitCode -ne 0) {
        throw "Weasel build failed with exit code $exitCode. See $log."
    }
    $installer = Get-Item -LiteralPath (Join-Path $weasel ('output\archives\' + $brand.installerFile))
    if ($installer.Length -eq 0 -or $installer.LastWriteTime -lt $started) {
        throw 'The build did not generate a new, non-empty installer.'
    }
    $output = Join-Path $root 'output'
    New-Item -ItemType Directory -Path $output -Force | Out-Null
    $destination = Join-Path $output $installer.Name
    Copy-Item -LiteralPath $installer.FullName -Destination $destination -Force
    $sourceHash = (Get-FileHash -LiteralPath $installer.FullName -Algorithm SHA256).Hash
    $outputHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    if ($sourceHash -ne $outputHash) {
        throw "Installer copy verification failed: $destination"
    }
    Write-Host "Installer: $destination"
} finally {
    # Restore tracked upstream files changed during compilation and profile packaging.
    foreach ($original in $originals) {
        $directory = Split-Path -Parent $original.Path
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        [System.IO.File]::WriteAllBytes($original.Path, $original.Bytes)
    }
}
