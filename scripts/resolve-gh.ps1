param([switch]$CheckAuth)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$command = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue
$gh = if ($command) { $command.Source } else { Join-Path $root '.tools\gh\bin\gh.exe' }
if (-not (Test-Path -LiteralPath $gh)) {
    throw 'GitHub CLI is missing. Install it and run gh auth login before publishing.'
}
if ($CheckAuth) {
    & $gh api --hostname github.com user --silent
    if ($LASTEXITCODE -ne 0) {
        throw 'GitHub authentication is unavailable. Complete gh auth login --web; never store a token in this project.'
    }
}
return $gh
