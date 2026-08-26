[CmdletBinding()]
param(
    [string]$OutputDirectory = "",
    [switch]$CreateZip
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
$project = Join-Path $repoRoot "samples\Cef134NugetMediaDeviceDemo\Cef134NugetMediaDeviceDemo.csproj"
$nugetConfig = Join-Path $repoRoot "samples\Cef134NugetMediaDeviceDemo\NuGet.config"
$feed = Join-Path $repoRoot "dist\cef-134\win-x64\nuget"

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot "dist\cef-134\win-x64\media-device-demo-nuget.11"
}

$requiredPackages = @(
    "WebViewControl-Avalonia.3.134.178-codecs.11.nupkg",
    "CefGlue.Common.134.6998.178-9n1m.11.nupkg",
    "CefGlue.Avalonia.134.6998.178-9n1m.11.nupkg",
    "chromiumembeddedframework.runtime.win-x64.134.3.9-codecs.1.nupkg"
)

foreach ($package in $requiredPackages) {
    $packagePath = Join-Path $feed $package
    if (-not (Test-Path -LiteralPath $packagePath)) {
        throw "Required local NuGet package not found: $packagePath"
    }
}

dotnet restore $project --configfile $nugetConfig --force-evaluate
if ($LASTEXITCODE -ne 0) { throw "Demo restore failed with exit code $LASTEXITCODE" }

dotnet publish $project -c Release -r win-x64 --self-contained true --no-restore -o $OutputDirectory
if ($LASTEXITCODE -ne 0) { throw "Demo publish failed with exit code $LASTEXITCODE" }

Write-Host "Demo: $OutputDirectory"

if ($CreateZip) {
    $releaseDirectory = Join-Path $repoRoot "dist\github-release"
    New-Item -ItemType Directory -Path $releaseDirectory -Force | Out-Null
    $zipPath = Join-Path $releaseDirectory "cef-134-codecs.11-media-device-demo-win-x64.zip"
    if (Test-Path -LiteralPath $zipPath) {
        throw "Archive already exists. Remove or rename it before retrying: $zipPath"
    }

    $sevenZip = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($sevenZip) {
        & $sevenZip.Source a -tzip $zipPath (Join-Path $OutputDirectory "*") -mx=5
        if ($LASTEXITCODE -ne 0) { throw "7-Zip failed with exit code $LASTEXITCODE" }
    } else {
        Compress-Archive -Path (Join-Path $OutputDirectory "*") -DestinationPath $zipPath -CompressionLevel Optimal
    }

    $hash = Get-FileHash -Algorithm SHA256 $zipPath
    Write-Host "Archive: $zipPath"
    Write-Host "SHA256: $($hash.Hash)"
}
