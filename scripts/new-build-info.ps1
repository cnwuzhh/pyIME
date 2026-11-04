param(
    [Parameter(Mandatory = $true)]
    [string]$Root,
    [datetime]$Timestamp = (Get-Date)
)

$ErrorActionPreference = 'Stop'
$brand = Get-Content -LiteralPath (Join-Path $Root 'config\branding.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($brand.baseVersion -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') {
    throw 'The base version must contain three numeric components.'
}
foreach ($part in $brand.baseVersion.Split('.')) {
    if ([long]$part -gt 65535) {
        throw 'A Windows numeric version component exceeds 65535.'
    }
}
$windowsBuild = [int]($Timestamp.Date - [datetime]'2000-01-01').TotalDays
if ($windowsBuild -lt 0 -or $windowsBuild -gt 65535) {
    throw 'The build date cannot be represented in the Windows numeric version.'
}
$commit = git -C $Root rev-parse HEAD
if ($LASTEXITCODE -ne 0) {
    throw 'The build source commit could not be determined.'
}
$state = git -C $Root status --porcelain --untracked-files=normal
if ($LASTEXITCODE -ne 0) {
    throw 'The build source status could not be determined.'
}
$number = $Timestamp.ToString('yyyyMMdd.HHmmss')
$version = "$($brand.baseVersion)+$number"
[pscustomobject]@{
    baseVersion = $brand.baseVersion
    buildNumber = $number
    productVersion = $version
    windowsBuildNumber = $windowsBuild
    windowsVersion = "$($brand.baseVersion).$windowsBuild"
    installerFile = "$($brand.name)-$version-setup.exe"
    tag = 'build-' + $Timestamp.ToString('yyyyMMdd-HHmmss')
    sourceCommit = "$commit".Trim()
    sourceDirty = -not [string]::IsNullOrWhiteSpace(($state -join "`n"))
    createdAt = ([datetimeoffset]$Timestamp).ToString('o')
    installerSha256 = $null
    installerBytes = $null
    tagged = $false
}
