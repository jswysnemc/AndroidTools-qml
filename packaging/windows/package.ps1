# 把 Release 可执行文件、Qt 运行库、FluentUI、FFmpeg 和 adb 组装成 zip 与 NSIS 安装包。
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDir,
    [Parameter(Mandatory = $true)]
    [string]$BuildDir,
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [Parameter(Mandatory = $true)]
    [string]$OutputDir
)

$ErrorActionPreference = 'Stop'
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $true
}

function Assert-PackageContents {
    param([string]$Root)
    $required = @(
        'AndroidTools.exe',
        'Qt6Core.dll',
        'Qt6Gui.dll',
        'Qt6Qml.dll',
        'Qt6Quick.dll',
        'qml\FluentUI\fluentuiplugin.dll',
        'qml\FluentUI\qmldir',
        'avcodec-58.dll',
        'avformat-58.dll',
        'avutil-56.dll',
        'swscale-5.dll',
        'tools\adb.exe',
        'tools\AdbWinApi.dll',
        'tools\AdbWinUsbApi.dll'
    )
    foreach ($relative in $required) {
        $path = Join-Path $Root $relative
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Package is missing $relative"
        }
    }
}

function Get-AndroidToolsExecutable {
    param([string]$Root)
    $candidates = @(
        (Join-Path $Root 'Release\AndroidTools.exe'),
        (Join-Path $Root 'AndroidTools.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw "AndroidTools.exe was not found under $Root"
}

function Copy-FluentUiPlugin {
    param(
        [string]$Root,
        [string]$Destination
    )
    $qmlDir = Get-ChildItem -Path (Join-Path $Root 'qml') -Recurse -Filter 'qmldir' -ErrorAction SilentlyContinue |
        Where-Object { $_.Directory.Name -eq 'FluentUI' } |
        Select-Object -First 1
    if (-not $qmlDir) {
        throw "FluentUI qmldir was not found under $Root\qml"
    }

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Copy-Item -Path (Join-Path $qmlDir.Directory.FullName '*') -Destination $Destination -Recurse -Force

    $plugin = Join-Path $Destination 'fluentuiplugin.dll'
    if (Test-Path -LiteralPath $plugin) {
        return
    }

    $builtPlugin = Get-ChildItem -Path $Root -Recurse -Filter 'fluentuiplugin.dll' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\Debug\\' } |
        Select-Object -First 1
    if (-not $builtPlugin) {
        throw 'fluentuiplugin.dll was not found in the build tree'
    }
    Copy-Item -LiteralPath $builtPlugin.FullName -Destination $plugin -Force
}

function Copy-FfmpegRuntime {
    param(
        [string]$Repository,
        [string]$Destination
    )
    $binDir = Join-Path $Repository 'src\cpp\imagePageTool\scrcpy\core\src\third_party\ffmpeg\bin\x64'
    if (-not (Test-Path -LiteralPath $binDir)) {
        throw "FFmpeg runtime directory is missing: $binDir"
    }
    Copy-Item -Path (Join-Path $binDir '*.dll') -Destination $Destination -Force
}

function Install-PlatformTools {
    param(
        [string]$Repository,
        [string]$Destination
    )
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $required = @('adb.exe', 'AdbWinApi.dll', 'AdbWinUsbApi.dll')
    $downloaded = $false
    try {
        $zip = Join-Path $env:TEMP 'platform-tools-windows.zip'
        $extract = Join-Path $env:TEMP 'platform-tools-extract'
        Invoke-WebRequest -Uri 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip' -OutFile $zip
        if (Test-Path -LiteralPath $extract) {
            Remove-Item -LiteralPath $extract -Recurse -Force
        }
        Expand-Archive -LiteralPath $zip -DestinationPath $extract
        $src = Join-Path $extract 'platform-tools'
        foreach ($name in @('adb.exe', 'fastboot.exe', 'AdbWinApi.dll', 'AdbWinUsbApi.dll')) {
            $file = Join-Path $src $name
            if (-not (Test-Path -LiteralPath $file)) {
                throw "platform-tools archive is missing $name"
            }
            Copy-Item -LiteralPath $file -Destination (Join-Path $Destination $name) -Force
        }
        $downloaded = $true
    } catch {
        Write-Output "Platform-tools download failed, using the bundled adb: $($_.Exception.Message)"
    }

    if ($downloaded) {
        return
    }

    $bundled = Join-Path $Repository 'src\cpp\imagePageTool\scrcpy\core\src\third_party\adb\win'
    foreach ($name in $required) {
        $file = Join-Path $bundled $name
        if (-not (Test-Path -LiteralPath $file)) {
            throw "Bundled adb file is missing: $file"
        }
        Copy-Item -LiteralPath $file -Destination (Join-Path $Destination $name) -Force
    }
}

function New-PackageReadme {
    param(
        [string]$Destination,
        [string]$PackageVersion
    )
    $text = @"
AndroidTools $PackageVersion for Windows x64

Run AndroidTools.exe from this folder, or use the NSIS installer.
Qt libraries are deployed with windeployqt. The FluentUI module is in qml\FluentUI.
FFmpeg libraries required by screen mirroring sit next to AndroidTools.exe.
adb.exe and fastboot.exe are in tools\. The application adds that directory to PATH when it starts.
"@
    Set-Content -LiteralPath (Join-Path $Destination 'README.txt') -Value $text -Encoding utf8
}

function Invoke-Nsis {
    param(
        [string]$Repository,
        [string]$Stage,
        [string]$PackageVersion,
        [string]$Destination
    )
    $makensis = Get-Command makensis -ErrorAction SilentlyContinue
    if (-not $makensis) {
        $fallback = 'C:\Program Files (x86)\NSIS\makensis.exe'
        if (Test-Path -LiteralPath $fallback) {
            $makensis = $fallback
        }
    } else {
        $makensis = $makensis.Source
    }
    if (-not $makensis) {
        throw 'makensis was not found'
    }

    $stageNsis = ((Resolve-Path -LiteralPath $Stage).Path) -replace '\\', '/'
    $outNsis = ((Resolve-Path -LiteralPath $Destination).Path) -replace '\\', '/'
    $license = ((Resolve-Path -LiteralPath (Join-Path $Repository 'LICENSE')).Path) -replace '\\', '/'
    $script = Join-Path $Repository 'packaging\windows\android-tools.nsi'
    & $makensis "/DAPP_VERSION=$PackageVersion" "/DSTAGE_DIR=$stageNsis" "/DOUT_DIR=$outNsis" "/DLICENSE_FILE=$license" $script
    if ($LASTEXITCODE -ne 0) {
        throw "makensis exited with $LASTEXITCODE"
    }
}

$executable = Get-AndroidToolsExecutable -Root $BuildDir
$stage = Join-Path $OutputDir 'stage'
if (Test-Path -LiteralPath $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stage | Out-Null
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

Copy-Item -LiteralPath $executable -Destination (Join-Path $stage 'AndroidTools.exe') -Force
Copy-FluentUiPlugin -Root $BuildDir -Destination (Join-Path $stage 'qml\FluentUI')

$env:QML_IMPORT_PATH = Join-Path $stage 'qml'
$windeployqt = (Get-Command windeployqt).Source
& $windeployqt --release --compiler-runtime --qmldir (Join-Path $SourceDir 'src\qml2') (Join-Path $stage 'AndroidTools.exe')
if ($LASTEXITCODE -ne 0) {
    throw "windeployqt exited with $LASTEXITCODE"
}

Copy-FfmpegRuntime -Repository $SourceDir -Destination $stage
Install-PlatformTools -Repository $SourceDir -Destination (Join-Path $stage 'tools')
Copy-Item -LiteralPath (Join-Path $SourceDir 'LICENSE') -Destination (Join-Path $stage 'LICENSE') -Force
New-PackageReadme -Destination $stage -PackageVersion $Version
Assert-PackageContents -Root $stage

$versionedZip = Join-Path $OutputDir "AndroidTools-$Version-windows-x64.zip"
$stableZip = Join-Path $OutputDir 'AndroidTools-windows-x64.zip'
if (Test-Path -LiteralPath $versionedZip) {
    Remove-Item -LiteralPath $versionedZip -Force
}
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $versionedZip
Copy-Item -LiteralPath $versionedZip -Destination $stableZip -Force

Invoke-Nsis -Repository $SourceDir -Stage $stage -PackageVersion $Version -Destination $OutputDir
$versionedSetup = Join-Path $OutputDir "AndroidTools-$Version-windows-x64-setup.exe"
$stableSetup = Join-Path $OutputDir 'AndroidTools-windows-x64-setup.exe'
Copy-Item -LiteralPath $versionedSetup -Destination $stableSetup -Force

Get-ChildItem -LiteralPath $OutputDir -File | Select-Object Name, Length | Format-Table -AutoSize
