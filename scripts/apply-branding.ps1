param(
    [switch]$ListFiles,
    [string]$BuildInfo = $env:STELLAR_BUILD_INFO
)

$ErrorActionPreference = 'Stop'
$files = @(
    'build.bat',
    'weasel.props.template',
    'include\WeaselUtility.h',
    'WeaselTSF\Globals.h',
    'WeaselTSF\LanguageBar.cpp',
    'WeaselTSF\DisplayAttributeInfo.cpp',
    'WeaselTSF\WeaselTSF.rc',
    'WeaselSetup\WeaselSetup.cpp',
    'WeaselSetup\WeaselSetup.rc',
    'WeaselServer\WeaselServer.rc',
    'WeaselServer\WeaselServerApp.cpp',
    'WeaselServer\WeaselServerApp.h',
    'WeaselDeployer\WeaselDeployer.rc',
    'WeaselDeployer\UIStyleSettingsDialog.cpp',
    'output\install.nsi'
)
if ($ListFiles) {
    return $files
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$brand = Get-Content -LiteralPath (Join-Path $root 'config\branding.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $BuildInfo) {
    throw 'Build metadata is required. Invoke branding through scripts\build.ps1.'
}
$build = Get-Content -LiteralPath $BuildInfo -Raw -Encoding UTF8 | ConvertFrom-Json
$weasel = Join-Path $root 'vendor\weasel'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$oldName = -join ([char]0x5C0F, [char]0x72FC, [char]0x6BEB)

function Replace-Required([string]$Text, [string]$Old, [string]$New) {
    if (-not $Text.Contains($Old)) {
        throw "Upstream branding anchor not found: $Old"
    }
    return $Text.Replace($Old, $New)
}

foreach ($relative in $files) {
    $path = Join-Path $weasel $relative
    $reader = New-Object System.IO.StreamReader($path, $utf8, $true)
    try {
        $text = $reader.ReadToEnd()
        $encoding = $reader.CurrentEncoding
    } finally {
        $reader.Dispose()
    }
    if ($relative -eq 'build.bat') {
        $text = Replace-Required $text 'set PRODUCT_VERSION=%WEASEL_VERSION%.%WEASEL_BUILD%' `
            'if not defined PRODUCT_VERSION set PRODUCT_VERSION=%WEASEL_VERSION%.%WEASEL_BUILD%'
        $text = Replace-Required $text '  FILE_VERSION' "  FILE_VERSION^`r`n  WEASEL_BUILD"
    } elseif ($relative -eq 'weasel.props.template') {
        $text = Replace-Required $text '<FILE_VERSION>$FILE_VERSION</FILE_VERSION>' `
            "<FILE_VERSION>`$FILE_VERSION</FILE_VERSION>`r`n    <WEASEL_BUILD>`$WEASEL_BUILD</WEASEL_BUILD>"
        $text = Replace-Required $text 'FILE_VERSION=$(FILE_VERSION);' `
            'FILE_VERSION=$(FILE_VERSION);WEASEL_BUILD=$(WEASEL_BUILD);'
    } elseif ($relative -eq 'include\WeaselUtility.h') {
        $text = Replace-Required $text ('return L"' + $oldName + '";') ('return L"' + $brand.name + '";')
        $text = Replace-Required $text 'return L"Weasel";' ('return L"' + $brand.englishName + '";')
    } elseif ($relative -eq 'WeaselTSF\Globals.h') {
        $text = Replace-Required $text '#define TEXTSERVICE_DESC_A WEASEL_CODE_NAME' `
            ('#define TEXTSERVICE_DESC_A "' + $brand.englishName + '"')
    } elseif ($relative -eq 'WeaselTSF\LanguageBar.cpp') {
        $text = Replace-Required $text 'L"WeaselTSF Button"' ('L"' + $brand.englishName + '"')
    } elseif ($relative -eq 'WeaselTSF\DisplayAttributeInfo.cpp') {
        $text = Replace-Required $text 'L"Weasel Display Attribute Input"' `
            ('L"' + $brand.englishName + ' Display Attribute Input"')
    } elseif ($relative -eq 'WeaselSetup\WeaselSetup.cpp') {
        $text = Replace-Required $text 'L"WeaselSetup"' ('L"' + $brand.englishName + ' Setup"')
        $text = [regex]::Replace($text, '(?m)^\s*L"/.*$', {
            param($match)
            [regex]::Replace($match.Value, '\bWeasel\b', $brand.englishName)
        })
    } elseif ($relative -eq 'WeaselServer\WeaselServerApp.cpp') {
        $text = Replace-Required $text '  win_sparkle_init();' `
            '  // Project updates are published manually; do not start the upstream updater.'
        $text = Replace-Required $text '  win_sparkle_cleanup();' ''
        $text = Replace-Required $text 'std::bind(open, L"https://rime.im/")' `
            ('std::bind(open, L"' + $brand.projectUrl + '")')
    } elseif ($relative -eq 'WeaselServer\WeaselServerApp.h') {
        $pattern = '(?s)  static bool check_update\(\) \{.*?\r?\n  \}\r?\n'
        if ([regex]::Matches($text, $pattern).Count -ne 1) {
            throw 'The upstream updater function could not be located uniquely.'
        }
        $replacement = "  static bool check_update() {`n    return open(L`"$($brand.projectUrl)/releases`");`n  }`n"
        $text = [regex]::Replace($text, $pattern, $replacement)
    } elseif ($relative -eq 'output\install.nsi') {
        if ($brand.installDirectory -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') {
            throw 'The default installation directory must be a single folder name.'
        }
        $text = Replace-Required $text '$PROGRAMFILES64\Rime' ('$PROGRAMFILES64\' + $brand.installDirectory)
        $text = Replace-Required $text '$PROGRAMFILES\Rime' ('$PROGRAMFILES\' + $brand.installDirectory)
        $text = Replace-Required $text ('Name "' + $oldName + ' ${WEASEL_VERSION}"') `
            ('Name "' + $brand.name + ' ${PRODUCT_VERSION}"')
        $text = Replace-Required $text 'OutFile "archives\weasel-${PRODUCT_VERSION}-installer.exe"' `
            ('OutFile "archives\' + $build.installerFile + '"')
        $text = Replace-Required $text 'VIProductVersion "${WEASEL_VERSION}.${WEASEL_BUILD}"' `
            ('VIProductVersion "' + $build.windowsVersion + '"')
        $text = Replace-Required $text '"DisplayVersion" "${WEASEL_VERSION}.${WEASEL_BUILD}"' `
            '"DisplayVersion" "${PRODUCT_VERSION}"'
        $text = Replace-Required $text '"FileVersion" "${WEASEL_VERSION}"' `
            '"FileVersion" "${PRODUCT_VERSION}"'
        $text = Replace-Required $text 'VIAddVersionKey /LANG=2052 "Comments"' `
            ('VIAddVersionKey /LANG=2052 "ProductVersion" "' + $build.productVersion + '"' + "`r`n" +
             'VIAddVersionKey /LANG=2052 "Comments"')
        $text = Replace-Required $text '  File "README.txt"' @'
  File "README.txt"
  File "japanese-LICENSE.txt"
  File "japanese-README.txt"
  File "japanese-NOTICES.txt"
  File "japanese-EDRDG-LICENCE.html"
  File "japanese-CC-BY-SA-4.0.txt"
'@
        $text = [regex]::Replace($text, '(?m)^LangString .*$', {
            param($match)
            $match.Value.Replace('Weasel', $brand.englishName).Replace($oldName, $brand.name)
        })
        $text = [regex]::Replace($text, '(?m)^(VIAddVersionKey /LANG=2052 "(?:ProductName|FileDescription)" )".*"\r?$', `
            ('$1"' + $brand.name + '"'))
        $text = [regex]::Replace($text, '(?m)^(VIAddVersionKey /LANG=2052 "CompanyName" )".*"\r?$', `
            ('$1"' + $brand.publisher + '"'))
        $text = [regex]::Replace($text, '(?m)^(\s*WriteRegStr HKLM "\$\{REG_UNINST_KEY\}" "Publisher" )".*"\r?$', `
            ('$1"' + $brand.publisher + '"'))
        $text = Replace-Required $text '"URLInfoAbout" "https://rime.im/"' `
            ('"URLInfoAbout" "' + $brand.projectUrl + '"')
        $pattern = '(?s)  ; option CheckForUpdates.*?\r?\n  end:'
        if ([regex]::Matches($text, $pattern).Count -ne 1) {
            throw 'The upstream automatic-update installer option could not be located uniquely.'
        }
        $text = [regex]::Replace($text, $pattern, `
            '  WriteRegStr HKCU "Software\Rime\Weasel\Updates" "CheckForUpdates" "0"')
        $text = $text.Replace($oldName, $brand.name)
    } elseif ($relative.EndsWith('.rc')) {
        $text = Replace-Required $text 'VERSION_MAJOR,VERSION_MINOR,VERSION_PATCH,0' `
            'VERSION_MAJOR,VERSION_MINOR,VERSION_PATCH,WEASEL_BUILD'
        $text = Replace-Required $text 'VALUE "FileVersion", FILE_VERSION' `
            'VALUE "FileVersion", STRZ(PRODUCT_VERSION)'
        $text = $text.Replace($oldName, $brand.name)
        $text = $text.Replace('"WeaselSetup Module"', ('"' + $brand.englishName + ' Setup"'))
        $text = [regex]::Replace($text, '(?m)^\s*(?:CAPTION|IDS_STR_\w+|IDR_MAINFRAME|VALUE "(?:ProductName|FileDescription)").*$', {
            param($match)
            [regex]::Replace($match.Value, '\bWeasel\b(?!Setup\.exe)', $brand.englishName).Replace('"WeaselSetup"', ('"' + $brand.englishName + ' Setup"'))
        })
        $text = [regex]::Replace($text, '(?m)^(\s*VALUE "CompanyName", )".*"\r?$', `
            ('$1"' + $brand.publisher + '"'))
        $text = $text.Replace('CAPTION "Setup Options"', ('CAPTION "' + $brand.englishName + ' Setup Options"'))
    } elseif ($relative -eq 'WeaselDeployer\UIStyleSettingsDialog.cpp') {
        $text = Replace-Required $text ($oldName + 'pei se\u2038') ($brand.name + 'pei se\u2038')
    }
    foreach ($suffix in @(
        (-join ([char]0x8F93, [char]0x5165, [char]0x6CD5)),
        (-join ([char]0x8F38, [char]0x5165, [char]0x6CD5))
    )) {
        $text = $text.Replace($brand.name + $suffix, $brand.name)
    }
    [System.IO.File]::WriteAllText($path, $text, $encoding)
}
Write-Host "Applied branding: $($brand.englishName)"
