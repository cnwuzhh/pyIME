param(
    [Parameter(Mandatory = $true)]
    [string]$DataDirectory,
    [string]$BoostRoot = $env:BOOST_ROOT
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $BoostRoot) {
    $BoostRoot = Join-Path $root '.tools\boost_1_84_0'
}
$profile = Join-Path $PSScriptRoot '..\config\pyime'
$encoding = New-Object System.Text.UTF8Encoding($false)

foreach ($name in @('default', 'weasel')) {
    $source = Join-Path $profile "pyime.$name.yaml"
    $base = Join-Path $DataDirectory "$name.yaml"
    Copy-Item -LiteralPath $source -Destination (Join-Path $DataDirectory "pyime.$name.yaml") -Force
    $text = [System.IO.File]::ReadAllText($base)
    if ($text -match '(?m)^__patch:') {
        if ($text -notmatch "(?m)^  - `"?pyime\.$name`:/patch`"?\r?$" -or
            $text -notmatch "(?m)^  - `"?$name\.custom:/patch\?`"?\r?$") {
            throw "Unrecognized existing root patch in $base; refusing to replace upstream or user settings."
        }
        continue
    }
    $patch = "`n__patch:`n  - pyime.$name`:/patch`n  - $name.custom:/patch?`n"
    [System.IO.File]::WriteAllText($base, $text.TrimEnd("`r", "`n") + $patch, $encoding)
}
foreach ($schema in @('luna_pinyin_simp', 'luna_pinyin')) {
    if (-not (Test-Path -LiteralPath (Join-Path $DataDirectory "$schema.schema.yaml"))) {
        throw "The required Pinyin schema was not included in the prepared data: $schema"
    }
}
$weasel = Join-Path $root 'vendor\weasel'
$tools = Join-Path $root '.build\profile-tools'
New-Item -ItemType Directory -Path $tools -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $weasel 'output\rime.dll') -Destination (Join-Path $tools 'rime.dll') -Force
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products '*' -version '[17.0,18.0)' -requires `
    Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $vs) {
    throw 'Visual Studio 2022 C++ Build Tools were not found for profile preparation.'
}
$compile = 'call "{0}\VC\Auxiliary\Build\vcvarsall.bat" x64 10.0.19041.0 && cd /d "{1}" && cl /nologo /std:c++17 /utf-8 /EHsc /MT /O2 /DRIME_IMPORTS /DRIME_BUILD_SHARED_LIBS /DBOOST_DLL_USE_STD_FS /DGLOG_EXPORT= /DGLOG_NO_EXPORT= /DGLOG_NO_ABBREVIATED_SEVERITIES "/DGLOG_DEPRECATED=__declspec(deprecated)" /I"{2}\librime\src" /I"{2}\librime\include" /I"{2}\librime\build_x64\src" /I"{3}" "{4}" /Fe:ApplyProfile.exe /link /LIBPATH:"{2}\lib64" rime.lib' -f `
    $vs, $tools, $weasel, $BoostRoot, (Join-Path $root 'tools\ApplyProfile.cpp')
& $env:ComSpec /d /c $compile
if ($LASTEXITCODE -ne 0) {
    throw "Profile preparation tool compilation failed with exit code $LASTEXITCODE."
}
Push-Location -LiteralPath $tools
try {
    & (Join-Path $tools 'ApplyProfile.exe') (Resolve-Path -LiteralPath $DataDirectory).Path (Resolve-Path -LiteralPath $profile).Path
    if ($LASTEXITCODE -ne 0) {
        throw "Profile preparation failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}
Copy-Item -LiteralPath (Join-Path $root 'README.md') -Destination (Join-Path $weasel 'output\README.txt') -Force
Write-Host 'Simplified-first and traditional Pinyin defaults, Shift switching and candidate style applied.'
