$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Set-Location $Root

$artifactDir = Join-Path $Root "build\release-artifacts\windows"
$stageDir = Join-Path $artifactDir "LocalDrop"
New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null

$flutterArgs = @()
if ($env:LOCALDROP_BUILD_NAME) {
    $flutterArgs += "--build-name=$($env:LOCALDROP_BUILD_NAME)"
}
if ($env:LOCALDROP_BUILD_NUMBER) {
    $flutterArgs += "--build-number=$($env:LOCALDROP_BUILD_NUMBER)"
}

flutter build windows --release @flutterArgs

$releaseDir = Join-Path $Root "build\windows\x64\runner\Release"
if (-not (Test-Path $releaseDir)) {
    throw "Windows release output was not found at $releaseDir"
}

if (Test-Path $stageDir) {
    Remove-Item -Recurse -Force $stageDir
}
New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
Copy-Item (Join-Path $releaseDir "*") $stageDir -Recurse -Force

if ($env:LOCALDROP_WINDOWS_SIGN_COMMAND) {
    Invoke-Expression $env:LOCALDROP_WINDOWS_SIGN_COMMAND
}

$zipPath = Join-Path $artifactDir "LocalDrop-windows-release.zip"
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}
Compress-Archive -Path (Join-Path $stageDir "*") -DestinationPath $zipPath

Write-Host "Windows artifacts are ready in $artifactDir"
