param(
    [Parameter(Mandatory = $true)]
    [string]$Installer,
    [Parameter(Mandatory = $true)]
    [string]$PackageDirectory
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$brand = Get-Content -LiteralPath (Join-Path $root 'config\branding.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$build = Get-Content -LiteralPath ($Installer + '.build.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$oldName = -join ([char]0x5C0F, [char]0x72FC, [char]0x6BEB)
if (-not ('StellarRiverBrandResources' -as [type])) {
    Add-Type -Path (Join-Path $root 'test\BrandResources.cs')
}
if ((Split-Path -Leaf $Installer) -ne $build.installerFile -or
    $build.buildNumber -notmatch '^\d{8}\.\d{6}$' -or
    $build.productVersion -ne "$($brand.baseVersion)+$($build.buildNumber)") {
    throw 'The installer does not use the configured product filename.'
}
if ((Get-FileHash -LiteralPath $Installer -Algorithm SHA256).Hash -ne $build.installerSha256) {
    throw 'The installer hash does not match its dated build metadata.'
}
foreach ($field in @('FileVersion', 'ProductVersion')) {
    foreach ($value in [StellarRiverBrandResources]::VersionValues($Installer, $field)) {
        if ($value -ne $build.productVersion) {
            throw "Installer $field does not contain its exact dated build version: $value"
        }
    }
}
$fixed = [Diagnostics.FileVersionInfo]::GetVersionInfo($Installer)
$numeric = '{0}.{1}.{2}.{3}' -f $fixed.FileMajorPart,$fixed.FileMinorPart,$fixed.FileBuildPart,$fixed.FilePrivatePart
if ($numeric -ne $build.windowsVersion) {
    throw "Installer numeric version is not Windows-compatible: $numeric"
}
$products = [StellarRiverBrandResources]::VersionValues($Installer, 'ProductName')
foreach ($name in $products) {
    if ($name -ne $brand.name) {
        throw "The installer product name was not rebranded: $name"
    }
}
foreach ($publisher in [StellarRiverBrandResources]::VersionValues($Installer, 'CompanyName')) {
    if ($publisher -ne $brand.publisher) {
        throw "Incorrect installer publisher: $publisher"
    }
}
$programs = Get-ChildItem -LiteralPath $PackageDirectory -File | Where-Object {
    $_.Name -match '^(weasel(?:x64)?(?:_\d+)?\.dll|Weasel(?:Server|Deployer|Setup)(?:_\d+)?\.exe)$'
}
if (@($programs).Count -ne 7) {
    throw "Expected seven packaged TSF, server, deployer and setup binaries, got $(@($programs).Count)."
}
foreach ($program in $programs) {
    foreach ($field in @('FileVersion', 'ProductVersion')) {
        foreach ($value in [StellarRiverBrandResources]::VersionValues($program.FullName, $field)) {
            if ($value -ne $build.productVersion) {
                throw "$field lacks the exact dated build version in $($program.Name): $value"
            }
        }
    }
    $fixed = [Diagnostics.FileVersionInfo]::GetVersionInfo($program.FullName)
    $numeric = '{0}.{1}.{2}.{3}' -f $fixed.FileMajorPart,$fixed.FileMinorPart,$fixed.FileBuildPart,$fixed.FilePrivatePart
    if ($numeric -ne $build.windowsVersion) {
        throw "Incorrect numeric build version in $($program.Name): $numeric"
    }
    foreach ($name in [StellarRiverBrandResources]::VersionValues($program.FullName, 'ProductName')) {
        if ($name -ne $brand.name -and $name -ne $brand.englishName) {
            throw "Old product name in $($program.Name): $name"
        }
    }
    foreach ($description in [StellarRiverBrandResources]::VersionValues($program.FullName, 'FileDescription')) {
        if (-not $description.Contains($brand.name) -and -not $description.Contains($brand.englishName)) {
            throw "Old file description in $($program.Name): $description"
        }
    }
    foreach ($copyright in [StellarRiverBrandResources]::VersionValues($program.FullName, 'LegalCopyright')) {
        if (-not $copyright) {
            throw "Missing copyright attribution in $($program.Name)."
        }
    }
    foreach ($type in @(5, 6, 16)) {
        $text = [StellarRiverBrandResources]::ReadUiResources($program.FullName, $type)
        if ($text.Contains($oldName) -or $text.Contains('Xinghe')) {
            throw "Old localized branding resource in $($program.Name)."
        }
        if ($type -eq 16 -and -not $text.Contains($brand.englishName)) {
            throw "The English version resource was not updated in $($program.Name)."
        }
    }
    Write-Host "BRAND_PASS=$($program.Name) (all version languages, dialogs and string tables)"
}
$license = Join-Path $PackageDirectory 'LICENSE.txt'
$upstream = Join-Path $root 'vendor\weasel\LICENSE.txt'
if ((Get-FileHash -LiteralPath $license -Algorithm SHA256).Hash -ne
    (Get-FileHash -LiteralPath $upstream -Algorithm SHA256).Hash) {
    throw 'The upstream license was not preserved in the installer.'
}
Write-Host 'BRAND_PASS=installer filename, product name, publisher and preserved upstream license'
