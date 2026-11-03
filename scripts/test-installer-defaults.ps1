# Called during the build, before branded installer source is restored upstream.
param(
    [Parameter(Mandatory = $true)]
    [string]$Script
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$brand = Get-Content -LiteralPath (Join-Path $root 'config\branding.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$makensis = Join-Path ${env:ProgramFiles(x86)} 'NSIS\Bin\makensis.exe'
$output = Join-Path $root '.build\installer-defaults-preprocessed.nsi'
Push-Location -LiteralPath (Split-Path -Parent $Script)
try {
    & $makensis /PPO $Script | Out-File -LiteralPath $output -Encoding UTF8
    if ($LASTEXITCODE -ne 0) {
        throw "Installer preprocessing failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}
$text = Get-Content -LiteralPath $output -Raw -Encoding UTF8
$folder = [regex]::Escape($brand.installDirectory)
$paths = [regex]::Matches($text, ('(?m)^\s*StrCpy \$INSTDIR "\$PROGRAMFILES(64)?\\' + $folder + '"\s*$'))
if ($paths.Count -ne 5) {
    throw "Not all fresh-install architecture branches use the default directory $($brand.installDirectory)."
}
if (-not $text.Contains('InstallDirRegKey HKLM "Software\Rime\Weasel" "InstallDir"') -or
    -not $text.Contains('ReadRegStr $R0 HKLM "Software\Rime\Weasel" "InstallDir"') -or
    -not $text.Contains('StrCmp $R0 "" 0 skip')) {
    throw 'Existing installation directory reuse was not preserved.'
}
Write-Host "INSTALLER_DEFAULTS_PASS=$($brand.installDirectory), all architecture branches and existing directory reuse"
