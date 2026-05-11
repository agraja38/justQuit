param(
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerScript = Join-Path $projectRoot "installer\justQuit.iss"
$runtimes = @("win-x64", "win-arm64")

foreach ($runtime in $runtimes) {
    $publishDir = Join-Path $projectRoot "publish\$runtime"

    Write-Host "Publishing justQuit for $runtime..."
    dotnet publish (Join-Path $projectRoot "justQuit.Windows.csproj") `
        -c $Configuration `
        -r $runtime `
        --self-contained $true `
        -p:PublishSingleFile=true `
        -o $publishDir
}

$innoCompiler = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $innoCompiler)) {
    $innoCompiler = "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
}

if (-not (Test-Path $innoCompiler)) {
    $innoCompiler = Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"
}

if (-not (Test-Path $innoCompiler)) {
    throw "Inno Setup 6 was not found. Install it, then rerun this script."
}

foreach ($runtime in $runtimes) {
    $architecture = if ($runtime -eq "win-arm64") { "arm64" } else { "x64" }
    $publishDir = Join-Path $projectRoot "publish\$runtime"

    Write-Host "Building installer for $architecture..."
    & $innoCompiler `
        "/DArchitecture=$architecture" `
        "/DSourceDir=$publishDir" `
        $installerScript
}

Write-Host ""
Write-Host "Installers created in:"
Write-Host (Join-Path $projectRoot "installer\output")
