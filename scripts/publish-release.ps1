param([string]$BuildManifest)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $BuildManifest) {
    $BuildManifest = Join-Path $root 'output\latest-build.json'
}
$info = Get-Content -LiteralPath $BuildManifest -Raw -Encoding UTF8 | ConvertFrom-Json
$brand = Get-Content -LiteralPath (Join-Path $root 'config\branding.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($info.sourceDirty -isnot [bool] -or $info.sourceDirty -or
    $info.tagged -isnot [bool] -or -not $info.tagged -or
    [IO.Path]::GetFileName($info.installerFile) -ne $info.installerFile) {
    throw 'Only clean, tagged builds with safe artifact names can be published.'
}
$installer = Join-Path $root ('output\' + $info.installerFile)
$manifest = $installer + '.build.json'
$sidecar = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($key in @('sourceCommit', 'tag', 'installerFile', 'installerSha256', 'productVersion', 'sourceDirty', 'tagged')) {
    if ($sidecar.$key -ne $info.$key) { throw "The installer sidecar does not match the selected build: $key." }
}
$receipt = Get-Content -LiteralPath ($installer + '.validation.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($receipt.passed -isnot [bool] -or -not $receipt.passed -or $receipt.sourceCommit -ne $info.sourceCommit -or
    $receipt.tag -ne $info.tag -or $receipt.installerSha256 -ne $info.installerSha256 -or
    $receipt.productVersion -ne $info.productVersion -or
    (Get-Item -LiteralPath $installer).Length -ne $info.installerBytes -or
    (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash -ne $info.installerSha256) {
    throw 'This exact installer does not have a matching successful validation receipt.'
}
$tagRef = 'refs/tags/' + $info.tag
$refs = git -C $root ls-remote origin $tagRef ($tagRef + '^{}')
if ($LASTEXITCODE -ne 0) { throw 'Cannot verify the remote build tag.' }
$peeled = @($refs | Where-Object { ($_ -split '\s+', 2)[1] -eq ($tagRef + '^{}') })
$base = @($refs | Where-Object { ($_ -split '\s+', 2)[1] -eq $tagRef })
$localTag = git -C $root rev-parse $tagRef
if ($peeled.Count -ne 1 -or ($peeled[0] -split '\s+')[0] -ne $info.sourceCommit) {
    throw 'The remote tag does not point to the validated build source.'
}
if ($LASTEXITCODE -ne 0 -or $base.Count -ne 1 -or ($base[0] -split '\s+')[0] -ne "$localTag".Trim()) {
    throw 'The remote and local annotated tag objects differ.'
}
$annotation = git -C $root for-each-ref --format='%(contents)' $tagRef
if ($LASTEXITCODE -ne 0 -or -not ($annotation -join "`n").Contains($info.installerSha256)) {
    throw 'The tag annotation does not match the local installer checksum.'
}
$uri = [uri]$brand.projectUrl
$repo = $uri.AbsolutePath.Trim('/')
if ($uri.Host -ne 'github.com' -or $repo -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
    throw 'The configured GitHub release repository is invalid.'
}
$origin = git -C $root remote get-url origin
if ($LASTEXITCODE -ne 0 -or
    ($origin -ne "git@github.com:$repo.git" -and $origin -ne "https://github.com/$repo.git" -and
     $origin -ne "https://github.com/$repo")) {
    throw 'The release repository does not match origin.'
}
$gh = & (Join-Path $PSScriptRoot 'resolve-gh.ps1') -CheckAuth
function Invoke-Gh([string[]]$Arguments) {
    $result = & $gh @Arguments
    if ($LASTEXITCODE -ne 0) { throw "GitHub command failed: $($Arguments[0]) (exit $LASTEXITCODE)." }
    return $result
}
function Get-Release {
    $parts = $repo.Split('/')
    $query = 'query($owner:String!,$name:String!,$tag:String!){repository(owner:$owner,name:$name){release(tagName:$tag){databaseId isDraft isPrerelease url}}}'
    $response = (Invoke-Gh @('api','graphql','-f',"query=$query",'-f',"owner=$($parts[0])",'-f',"name=$($parts[1])",'-f',"tag=$($info.tag)")) -join "`n" | ConvertFrom-Json
    if (-not $response.data.repository) { throw 'The release repository is not accessible.' }
    return $response.data.repository.release
}
$permission = Invoke-Gh @('api',"repos/$repo",'--jq','.permissions.push')
if ("$permission".Trim() -ne 'true') { throw 'The authenticated account does not have repository write access.' }
$source = & (Join-Path $PSScriptRoot 'export-release-source.ps1') -BuildManifest $BuildManifest
$files = @($installer, $manifest, $source)
$assets = foreach ($file in $files) {
    [pscustomobject]@{
        path = $file
        name = [IO.Path]::GetFileName($file)
        bytes = (Get-Item -LiteralPath $file).Length
        sha256 = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    }
}
$work = Join-Path $root ('.build\release-upload-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $notes = Join-Path $work 'release-notes.md'
    $hashes = ($assets | ForEach-Object { "- $($_.name): ``$($_.sha256.ToLowerInvariant())``" }) -join "`n"
    $body = "## Stellar River IME $($info.productVersion)`n`nBuild: $($info.buildNumber)`nSource: $($info.sourceCommit)`n`nIncludes simplified/traditional Pinyin, Japanese romaji, Shift English, Alt+grave scheme cycling and comma/period candidate navigation.`n`nJapanese conversion is dictionary-based, not the Mozc engine. First Japanese deployment compiles the dictionary. Existing user scheme selections are preserved. Real-application compatibility has not been comprehensively certified.`n`nThe source ZIP includes pinned Git submodules and license notices; Git metadata, caches and private user dictionaries are excluded.`n`n## SHA-256`n$hashes`n"
    [IO.File]::WriteAllText($notes, $body, (New-Object Text.UTF8Encoding($false)))
    $release = Get-Release
    if ($release -and -not $release.isDraft -and $release.isPrerelease) {
        throw 'A published prerelease already uses this tag; its publication type will not be changed automatically.'
    }
    if (-not $release) {
        Invoke-Gh @('release','create',$info.tag,'--repo',$repo,'--verify-tag','--draft','--title',"$($brand.englishName) $($info.productVersion)",'--notes-file',$notes) | Out-Null
        $release = Get-Release
        if (-not $release) { throw 'The newly created draft release cannot be read.' }
    }
    foreach ($asset in $assets) {
        $details = (Invoke-Gh @('api',"repos/$repo/releases/$($release.databaseId)")) -join "`n" | ConvertFrom-Json
        $matches = @($details.assets | Where-Object { $_.name -eq $asset.name })
        if ($matches.Count -gt 1) { throw "Duplicate release assets: $($asset.name)" }
        if ($matches.Count -eq 0) {
            if (-not $release.isDraft) {
                throw "A published release is missing $($asset.name); it will not be modified automatically."
            }
            Invoke-Gh @('release','upload',$info.tag,$asset.path,'--repo',$repo) | Out-Null
            $details = (Invoke-Gh @('api',"repos/$repo/releases/$($release.databaseId)")) -join "`n" | ConvertFrom-Json
            $matches = @($details.assets | Where-Object { $_.name -eq $asset.name })
        }
        if ($matches.Count -ne 1 -or $matches[0].state -ne 'uploaded' -or $matches[0].size -ne $asset.bytes) {
            throw "Release asset is missing, incomplete or conflicting: $($asset.name)"
        }
        $remote = $matches[0]
        if ($remote.digest) {
            if ($remote.digest -ne ('sha256:' + $asset.sha256.ToLowerInvariant())) {
                throw "Existing release asset checksum differs; refusing to overwrite $($asset.name)."
            }
        } else {
            Write-Host "Asset digest unavailable; downloading to verify $($asset.name)."
            Invoke-Gh @('release','download',$info.tag,'--repo',$repo,'--pattern',$asset.name,'--dir',$work) | Out-Null
            if ((Get-FileHash -LiteralPath (Join-Path $work $asset.name) -Algorithm SHA256).Hash -ne $asset.sha256) {
                throw "Downloaded release asset checksum differs: $($asset.name)"
            }
        }
        Write-Host "RELEASE_ASSET_VERIFIED=$($asset.name)"
    }
    if ($release.isDraft) {
        Invoke-Gh @('release','edit',$info.tag,'--repo',$repo,'--draft=false','--prerelease=false','--latest=true','--notes-file',$notes) | Out-Null
    }
    $release = Get-Release
    if (-not $release -or $release.isDraft -or $release.isPrerelease) {
        throw 'The uploaded release did not reach the requested publication state.'
    }
    $report = [pscustomobject]@{
        productVersion = $info.productVersion
        tag = $info.tag
        sourceCommit = $info.sourceCommit
        releaseType = 'stable'
        releaseUrl = $release.url
        verifiedAt = (Get-Date).ToString('o')
        assets = @($assets | Select-Object name,bytes,sha256)
    } | ConvertTo-Json -Depth 5
    foreach ($path in @(($installer + '.release.json'), (Join-Path $root 'output\latest-release.json'))) {
        [IO.File]::WriteAllText($path, $report, (New-Object Text.UTF8Encoding($false)))
    }
    Write-Host "RELEASE_PUBLISHED=$($release.url) (stable)"
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force
}
