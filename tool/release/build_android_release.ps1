$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Set-Location $Root

$artifactDir = Join-Path $Root "build\release-artifacts\android"
New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null

$flutterArgs = @()
if ($env:LOCALDROP_BUILD_NAME) {
    $flutterArgs += "--build-name=$($env:LOCALDROP_BUILD_NAME)"
}
if ($env:LOCALDROP_BUILD_NUMBER) {
    $flutterArgs += "--build-number=$($env:LOCALDROP_BUILD_NUMBER)"
}

flutter build apk --release @flutterArgs
flutter build appbundle --release @flutterArgs

$apkSource = Join-Path $Root "build\app\outputs\flutter-apk\app-release.apk"
$aabSource = Join-Path $Root "build\app\outputs\bundle\release\app-release.aab"

if (Test-Path $apkSource) {
    Copy-Item $apkSource (Join-Path $artifactDir "LocalDrop-release.apk") -Force
}
if (Test-Path $aabSource) {
    Copy-Item $aabSource (Join-Path $artifactDir "LocalDrop-release.aab") -Force
}

Write-Host "Android artifacts are ready in $artifactDir"
