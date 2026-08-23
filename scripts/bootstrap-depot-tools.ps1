[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DepotTools
)

$ErrorActionPreference = 'Stop'
$bootstrap = Join-Path $DepotTools 'bootstrap\win_tools.bat'
if (-not (Test-Path -LiteralPath $bootstrap)) {
    throw "Missing depot_tools bootstrap script: $bootstrap"
}

& $bootstrap
if ($LASTEXITCODE -ne 0) {
    throw "depot_tools Windows bootstrap failed with exit code $LASTEXITCODE"
}

foreach ($wrapper in @('git.bat', 'python3.bat')) {
    $wrapperPath = Join-Path $DepotTools $wrapper
    if (-not (Test-Path -LiteralPath $wrapperPath)) {
        throw "depot_tools bootstrap did not generate: $wrapperPath"
    }
}
