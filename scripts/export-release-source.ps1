param(
    [string]$BuildManifest
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $BuildManifest) {
    $BuildManifest = Join-Path $root 'output\latest-build.json'
}
$info = Get-Content -LiteralPath $BuildManifest -Raw -Encoding UTF8 | ConvertFrom-Json
if ($info.sourceDirty -isnot [bool] -or $info.sourceDirty -or
    $info.tagged -isnot [bool] -or -not $info.tagged -or
    $info.sourceCommit -notmatch '^[0-9a-f]{40}$') {
    throw 'Release sources require a clean, tagged build manifest.'
}
$tagCommit = git -C $root rev-parse ($info.tag + '^{commit}')
if ($LASTEXITCODE -ne 0 -or "$tagCommit".Trim() -ne $info.sourceCommit) {
    throw 'The build tag does not identify the source commit in the manifest.'
}
$name = $info.installerFile -replace '-setup\.exe$', '-source.zip'
if ($name -eq $info.installerFile -or [IO.Path]::GetFileName($name) -ne $name) {
    throw 'The source archive name cannot be derived safely from the installer.'
}
$archive = Join-Path $root ('output\' + $name)
$record = $archive + '.source.json'
if (Test-Path -LiteralPath $archive) {
    $saved = Get-Content -LiteralPath $record -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($saved.sourceCommit -ne $info.sourceCommit -or $saved.tag -ne $info.tag -or
        $saved.archiveSha256 -ne (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash) {
        throw 'An existing source archive conflicts with this build; it will not be overwritten.'
    }
    return $archive
}

$work = Join-Path $root ('.build\source-export-' + [guid]::NewGuid().ToString('N'))
$tree = Join-Path $work 'StellarRiver-source'
New-Item -ItemType Directory -Path $tree -Force | Out-Null
$modules = New-Object 'System.Collections.Generic.List[object]'
function Export-Commit([string]$Repository, [string]$Commit, [string]$Destination, [string]$Relative) {
    $zip = Join-Path $work ([guid]::NewGuid().ToString('N') + '.zip')
    git -C $Repository archive --format=zip "--output=$zip" $Commit
    if ($LASTEXITCODE -ne 0) {
        throw "Cannot export pinned source $Relative at $Commit. Initialize or fetch its submodule commit."
    }
    Expand-Archive -LiteralPath $zip -DestinationPath $Destination -Force
    Remove-Item -LiteralPath $zip
    $entries = git -C $Repository ls-tree -rz $Commit
    if ($LASTEXITCODE -ne 0) { throw "Cannot enumerate source dependencies in $Relative." }
    foreach ($entry in (("$entries") -split [char]0)) {
        if ($entry -notmatch '^160000 commit ([0-9a-f]{40})\t(.+)$') { continue }
        $revision = $Matches[1]
        $path = $Matches[2]
        $windowsPath = $path -replace '/', '\'
        $fullRelative = if ($Relative) { "$Relative/$path" } else { $path }
        $modules.Add([pscustomobject]@{ path = $fullRelative; commit = $revision })
        Export-Commit (Join-Path $Repository $windowsPath) $revision `
            (Join-Path $Destination $windowsPath) $fullRelative
    }
}
try {
    Export-Commit $root $info.sourceCommit $tree ''
    $brand = Get-Content -LiteralPath (Join-Path $root 'config\branding.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $source = [pscustomobject]@{
        repository = $brand.projectUrl
        tag = $info.tag
        sourceCommit = $info.sourceCommit
        submodules = $modules.ToArray()
    }
    [IO.File]::WriteAllText((Join-Path $tree 'SOURCE-INFO.json'),
        ($source | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
    $instructions = "Source snapshot: $($info.sourceCommit)`nTag: $($info.tag)`n`nGit metadata is deliberately excluded. For the normal Git-based build/tag workflow, clone the exact tag with all submodules:`n`ngit clone --branch $($info.tag) --recurse-submodules $($brand.projectUrl).git StellarRiver`n`nThis archive contains the tagged repository and each pinned Git submodule, not untracked caches, Git credentials or private user dictionaries.`n"
    [IO.File]::WriteAllText((Join-Path $tree 'SOURCE-INFO.txt'), $instructions, (New-Object Text.UTF8Encoding($false)))
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::Open($archive, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in [IO.Directory]::EnumerateFiles($tree, '*', [IO.SearchOption]::AllDirectories)) {
            $entry = 'StellarRiver-source/' + ($file.Substring($tree.Length + 1) -replace '\\', '/')
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file, $entry,
                [IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    } finally {
        $zip.Dispose()
    }
    $saved = [pscustomobject]@{
        tag = $info.tag
        sourceCommit = $info.sourceCommit
        archiveSha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
        archiveBytes = (Get-Item -LiteralPath $archive).Length
    }
    [IO.File]::WriteAllText($record, ($saved | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    return $archive
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force
}
