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
& (Join-Path $PSScriptRoot 'build-physical.ps1') @PSBoundParameters
exit $LASTEXITCODE
