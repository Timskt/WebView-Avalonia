[CmdletBinding()]
param(
    [ValidateSet('106', '134', 'both')]
    [string]$Line = 'both',
    [ValidateSet('auto', 'win-x64', 'win-arm64')]
    [string]$Rid = 'auto',
    [string]$Cache = '',
    [string]$Output = '',
    [switch]$SkipNative,
    [switch]$NoDemo,
    [switch]$AllowLowDisk,
    [switch]$PreflightOnly
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not (Get-Command bash -ErrorAction SilentlyContinue)) {
    throw 'bash.exe was not found. Install Git for Windows with Git Bash, then run this script again.'
}

Push-Location $repo
try {
    $arguments = @('--line', $Line, '--rid', $Rid)
    if ($Cache) { $arguments += @('--cache', $Cache) }
    if ($Output) { $arguments += @('--output', $Output) }
    if ($SkipNative) { $arguments += '--skip-native' }
    if ($NoDemo) { $arguments += '--no-demo' }
    if ($AllowLowDisk) { $arguments += '--allow-low-disk' }
    if ($PreflightOnly) { $arguments += '--preflight-only' }
    & bash (Join-Path 'scripts' 'build-physical.sh') @arguments
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
    Pop-Location
}
