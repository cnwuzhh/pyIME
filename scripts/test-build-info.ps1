$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$create = Join-Path $PSScriptRoot 'new-build-info.ps1'
$first = & $create -Root $root -Timestamp ([datetime]'2026-11-04T08:35:33')
$second = & $create -Root $root -Timestamp ([datetime]'2026-11-04T08:35:34')
$nextDay = & $create -Root $root -Timestamp ([datetime]'2026-11-05T00:00:00')
if ($first.buildNumber -ne '20261104.083533' -or
    $first.productVersion -ne "$($first.baseVersion)+20261104.083533" -or
    $first.tag -ne 'build-20261104-083533' -or
    -not $first.installerFile.Contains($first.productVersion)) {
    throw 'The date/time build number, product version, filename or tag is incorrect.'
}
if ($first.installerFile -eq $second.installerFile -or $first.tag -eq $second.tag -or
    $first.windowsBuildNumber -ne $second.windowsBuildNumber) {
    throw 'Two builds on the same day do not have unique names and legal numeric versions.'
}
if ($nextDay.windowsBuildNumber -ne $first.windowsBuildNumber + 1) {
    throw 'The Windows numeric build component did not advance with the date.'
}
$maximumDate = ([datetime]'2000-01-01').AddDays(65535)
$maximum = & $create -Root $root -Timestamp $maximumDate
if ($maximum.windowsBuildNumber -ne 65535) {
    throw 'The highest legal Windows build component was not accepted.'
}
$parts = $first.windowsVersion.Split('.')
if ($parts.Count -ne 4) {
    throw 'The Windows numeric version must have four components.'
}
foreach ($part in $parts) {
    if ([long]$part -lt 0 -or [long]$part -gt 65535) {
        throw 'A Windows numeric version component is outside the allowed range.'
    }
}
foreach ($invalid in @([datetime]'1999-12-31', $maximumDate.AddDays(1))) {
    try {
        $null = & $create -Root $root -Timestamp $invalid
        throw 'An unrepresentable build date was accepted.'
    } catch {
        if ($_.Exception.Message -notlike '*build date cannot be represented*') {
            throw
        }
    }
}
git -C $root check-ref-format ("refs/tags/" + $first.tag)
if ($LASTEXITCODE -ne 0) {
    throw 'The generated build tag is not a valid Git ref.'
}
$fixture = Join-Path $root ('.build\tag-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
try {
    git -C $fixture init --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Test repository initialization failed.' }
    Copy-Item -LiteralPath (Join-Path $root 'config\branding.json') -Destination (Join-Path $fixture 'branding.json')
    git -C $fixture add -- branding.json
    if ($LASTEXITCODE -ne 0) { throw 'Test source staging failed.' }
    git -C $fixture -c user.name='Stellar River Tests' -c user.email='tests@example.invalid' `
        -c commit.gpgsign=false commit --quiet -m 'Test annotated build source' `
        -m 'Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
    if ($LASTEXITCODE -ne 0) { throw 'Test source commit failed.' }
    $head = git -C $fixture rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Test commit lookup failed.' }
    git -C $fixture -c tag.gpgsign=false tag -a $first.tag $head -m 'Dated build tag test'
    if ($LASTEXITCODE -ne 0) { throw 'Test annotated tag creation failed.' }
    $tagRef = "refs/tags/$($first.tag)"
    $refs = git ls-remote $fixture $tagRef ($tagRef + '^{}')
    if ($LASTEXITCODE -ne 0) { throw 'Test tag lookup failed.' }
    $peeled = @($refs | Where-Object { ($_ -split '\s+', 2)[1] -eq ($tagRef + '^{}') })
    if ($peeled.Count -ne 1 -or ($peeled[0] -split '\s+')[0] -ne $head) {
        throw 'The annotated tag did not resolve to its exact source commit.'
    }
} finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force
}
Write-Host 'BUILD_INFO_PASS=date, unique same-day builds, numeric version limits and valid Git tag'
