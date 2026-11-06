param([string]$BuildManifest)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $BuildManifest) { $BuildManifest = Join-Path $root 'output\latest-build.json' }
$info = Get-Content -LiteralPath $BuildManifest -Raw -Encoding UTF8 | ConvertFrom-Json
$archive = & (Join-Path $PSScriptRoot 'export-release-source.ps1') -BuildManifest $BuildManifest
$hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
$again = & (Join-Path $PSScriptRoot 'export-release-source.ps1') -BuildManifest $BuildManifest
if ($again -ne $archive -or (Get-FileHash -LiteralPath $again -Algorithm SHA256).Hash -ne $hash) {
    throw 'Re-exporting the same source changed the immutable asset.'
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($archive)
$work = Join-Path $root ('.build\release-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $names = @($zip.Entries | ForEach-Object { $_.FullName })
    foreach ($name in @('README.md', '.gitmodules', '.gitattributes', 'SOURCE-INFO.json')) {
        if ($names -notcontains "StellarRiver-source/$name") { throw "Missing source entry: $name" }
    }
    if (@($names | Where-Object { $_ -match '(^|/)\.(git|tools|build)(/|$)' -or
        $_ -match '^StellarRiver-source/output/.*\.(exe|json)$' }).Count) {
        throw 'Source archive contains Git metadata, caches or build artifacts.'
    }
    $reader = New-Object IO.StreamReader($zip.GetEntry('StellarRiver-source/SOURCE-INFO.json').Open())
    try { $source = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
    if ($source.sourceCommit -ne $info.sourceCommit -or $source.tag -ne $info.tag -or
        @($source.submodules).Count -lt 5) { throw 'Source provenance is incomplete.' }
    foreach ($module in $source.submodules) {
        $parent = $source.submodules | Where-Object { $module.path.StartsWith($_.path + '/') } |
            Sort-Object { $_.path.Length } -Descending | Select-Object -First 1
        $repository = if ($parent) { Join-Path $root ($parent.path -replace '/', '\') } else { $root }
        $commit = if ($parent) { $parent.commit } else { $info.sourceCommit }
        $relative = if ($parent) { $module.path.Substring($parent.path.Length + 1) } else { $module.path }
        $expected = git -C $repository rev-parse ($commit + ':' + $relative)
        if ($LASTEXITCODE -ne 0 -or "$expected".Trim() -ne $module.commit) {
            throw "Incorrect pinned dependency: $($module.path)"
        }
        if (@($names | Where-Object { $_.StartsWith("StellarRiver-source/$($module.path)/") }).Count -eq 0) {
            throw "Missing dependency sources: $($module.path)"
        }
    }
    $entry = $zip.GetEntry('StellarRiver-source/config/branding.json').Open()
    $sample = Join-Path $work 'branding.json'
    $file = [IO.File]::Create($sample)
    try { $entry.CopyTo($file) } finally { $file.Dispose(); $entry.Dispose() }
    $actual = git -C $root hash-object $sample
    if ($LASTEXITCODE -ne 0) { throw 'Cannot hash the archived source blob.' }
    $expected = git -C $root rev-parse ($info.sourceCommit + ':config/branding.json')
    if ($LASTEXITCODE -ne 0 -or "$actual".Trim() -ne "$expected".Trim()) {
        throw 'Archived source bytes differ from the tagged commit.'
    }
    Write-Host "SOURCE_ARCHIVE_PASS=$($source.submodules.Count) pinned submodules; $($names.Count) entries; SHA256=$hash"
    $cases = @(
        @{ key='sourceDirty'; value=$true; message='Only clean' },
        @{ key='tagged'; value=$false; message='Only clean' },
        @{ key='sourceDirty'; value=$null; message='Only clean' },
        @{ key='installerFile'; value='..\private-setup.exe'; message='safe artifact names' },
        @{ key='sourceCommit'; value=('0' * 40); message='sidecar does not match' },
        @{ key='tag'; value='build-invalid'; message='sidecar does not match' },
        @{ key='installerSha256'; value=('A' * 64); message='sidecar does not match' }
    )
    foreach ($case in $cases) {
        $bad = $info | ConvertTo-Json | ConvertFrom-Json
        $bad.($case.key) = $case.value
        $path = Join-Path $work 'invalid-build.json'
        [IO.File]::WriteAllText($path, ($bad | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
        try {
            & (Join-Path $PSScriptRoot 'publish-release.ps1') -BuildManifest $path
            throw "Publisher accepted invalid $($case.key)."
        } catch {
            if ($_.Exception.Message -notmatch $case.message) { throw }
        }
    }
    Write-Host 'RELEASE_GUARD_PASS=dirty, untagged, malformed, unsafe path and mismatched source/tag/hash rejected before GitHub writes'
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
    $stub = Join-Path $work 'gh.exe'
    & $compiler /nologo /target:exe "/out:$stub" /reference:System.Web.Extensions.dll `
        (Join-Path $root 'test\ReleaseCliStub.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Cannot compile the isolated GitHub CLI test stub.' }
    $previousPath = $env:PATH
    $previousState = $env:STELLAR_RELEASE_TEST_STATE
    $env:PATH = "$work;$env:PATH"
    $stateFile = Join-Path $work 'state.json'
    $env:STELLAR_RELEASE_TEST_STATE = $stateFile
    $reports = @(
        (Join-Path $root ('output\' + $info.installerFile + '.release.json')),
        (Join-Path $root 'output\latest-release.json')
    )
    $originalReports = @{}
    foreach ($report in $reports) {
        if (Test-Path -LiteralPath $report) { $originalReports[$report] = [IO.File]::ReadAllBytes($report) }
    }
    function Set-TestState([string]$Failure = '') {
        $state = @{
            exists = $false; draft = $true; assets = @(); writes = @()
            failAuth = $Failure -eq 'auth'; badDigest = $Failure -eq 'digest'
            omitDigest = $Failure -eq 'download'
        }
        [IO.File]::WriteAllText($stateFile, ($state | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    }
    try {
        if ((Get-Command gh -CommandType Application).Source -ne $stub) {
            throw 'The test stub is not first on PATH; refusing to contact the real GitHub API.'
        }
        Write-Host 'SIMULATED_RELEASE_PIPELINE_START=no real GitHub API writes; temporary reports restored afterward'
        Set-TestState
        & (Join-Path $PSScriptRoot 'publish-release.ps1') -BuildManifest $BuildManifest
        $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
        if ($state.draft -or $state.assets.Count -ne 3 -or $state.writes[-1] -ne 'publish') {
            throw 'The simulated stable release did not follow all verified uploads.'
        }
        $writes = $state.writes.Count
        & (Join-Path $PSScriptRoot 'publish-release.ps1') -BuildManifest $BuildManifest
        $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
        if ($state.writes.Count -ne $writes) { throw 'Retry modified an already complete release.' }
        foreach ($failure in @('auth', 'digest')) {
            Set-TestState $failure
            $expected = if ($failure -eq 'auth') { 'authentication is unavailable' } else { 'checksum differs' }
            try {
                & (Join-Path $PSScriptRoot 'publish-release.ps1') -BuildManifest $BuildManifest
                throw "Publisher accepted simulated $failure failure."
            } catch {
                if ($_.Exception.Message -notmatch $expected) { throw }
            }
            $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
            if (-not $state.draft -or $state.writes -contains 'publish') {
                throw 'A failed upload was published.'
            }
            if ($failure -eq 'auth' -and $state.exists) { throw 'Authentication failure created a draft.' }
        }
        $writes = $state.writes.Count
        try {
            & (Join-Path $PSScriptRoot 'publish-release.ps1') -BuildManifest $BuildManifest
            throw 'Conflicting asset was accepted on retry.'
        } catch {
            if ($_.Exception.Message -notmatch 'checksum differs') { throw }
        }
        $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
        if ($state.writes.Count -ne $writes) { throw 'A conflicting retry overwrote an asset.' }
        Set-TestState 'download'
        & (Join-Path $PSScriptRoot 'publish-release.ps1') -BuildManifest $BuildManifest
        $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
        if ($state.draft -or @($state.writes | Where-Object { $_ -like 'download:*' }).Count -ne 3) {
            throw 'Missing server digests did not trigger three verified downloads.'
        }
        Write-Host 'SIMULATED_RELEASE_PASS=stable publication, no-write retry, auth failure, conflicting hashes and download verification'
    } finally {
        $env:PATH = $previousPath
        $env:STELLAR_RELEASE_TEST_STATE = $previousState
        foreach ($report in $reports) {
            if ($originalReports.ContainsKey($report)) {
                [IO.File]::WriteAllBytes($report, $originalReports[$report])
            } elseif (Test-Path -LiteralPath $report) {
                Remove-Item -LiteralPath $report
            }
        }
    }
} finally {
    $zip.Dispose()
    Remove-Item -LiteralPath $work -Recurse -Force
}
