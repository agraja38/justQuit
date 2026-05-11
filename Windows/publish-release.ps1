param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [string]$Branch = "main"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$git = (Get-Command git -ErrorAction Stop).Source
$gh = (Get-Command gh -ErrorAction Stop).Source
$tag = "windows-v$Version"
$releaseTitle = "justQuit Windows $Version"
$assetDir = Join-Path $projectRoot "installer\output"
$x64Installer = Join-Path $assetDir "justQuit-Setup-x64.exe"
$arm64Installer = Join-Path $assetDir "justQuit-Setup-ARM64.exe"

Write-Host "Building installers..."
& powershell -ExecutionPolicy Bypass -File (Join-Path $projectRoot "build-installer.ps1")

if (-not (Test-Path $x64Installer) -or -not (Test-Path $arm64Installer)) {
    throw "Expected installer assets were not found in $assetDir."
}

Push-Location $projectRoot
try {
    & $git add .
    & $git commit -m "Release $tag"
    & $git tag $tag
    & $git push origin $Branch
    & $git push origin $tag
    & $gh release create $tag $x64Installer $arm64Installer --title $releaseTitle --generate-notes

    $publicTag = "justquit-windows-v$Version"
    if (& $gh release view $publicTag --repo agraja38/app-update-feeds 2>$null) {
        & $gh release upload $publicTag $x64Installer $arm64Installer --repo agraja38/app-update-feeds --clobber
    } else {
        & $gh release create $publicTag $x64Installer $arm64Installer --repo agraja38/app-update-feeds --title "justQuit Windows v$Version" --notes "Public updater assets for justQuit Windows v$Version."
    }
}
finally {
    Pop-Location
}
