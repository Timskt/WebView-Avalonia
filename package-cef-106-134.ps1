[CmdletBinding()]
param(
    [ValidateSet('106', '134', 'both')]
    [string]$Line = '134',
    [ValidateSet('auto', 'win-x64', 'win-arm64')]
    [string]$Rid = 'win-x64',
    [string]$Output = '',
    [string]$Cache = '',
    [string]$Proxy = '',
    [switch]$PreflightOnly,
    [switch]$AllowLowDisk
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Output) { $Output = Join-Path $scriptRoot 'dist' }
if (-not $Cache) { $Cache = Join-Path $scriptRoot '.cef-cache' }
$Output = [System.IO.Path]::GetFullPath($Output)
$Cache = [System.IO.Path]::GetFullPath($Cache)
New-Item -ItemType Directory -Force -Path $Output, $Cache | Out-Null

$longPathsEnabled = (Get-ItemProperty `
    -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' `
    -Name LongPathsEnabled `
    -ErrorAction SilentlyContinue).LongPathsEnabled -eq 1
if (-not $longPathsEnabled -and $Cache -match '^[A-Za-z]:\\' -and $Cache.Length -gt 3) {
    $substMappings = @{}
    foreach ($substLine in @(& subst.exe)) {
        if ($substLine -match '^([A-Za-z]):\\: => (.+)$') {
            $substMappings[$Matches[1].ToUpperInvariant()] = `
                [System.IO.Path]::GetFullPath($Matches[2]).TrimEnd('\')
        }
    }

    $physicalCache = $Cache.TrimEnd('\')
    $cacheDrive = $substMappings.GetEnumerator() |
        Where-Object { $_.Value -eq $physicalCache } |
        Select-Object -ExpandProperty Key -First 1
    if (-not $cacheDrive) {
        foreach ($candidate in @('X','W','V','U','T','S','R','Q','P')) {
            if ($substMappings.ContainsKey($candidate) -or (Get-PSDrive $candidate -ErrorAction SilentlyContinue)) {
                continue
            }
            & subst.exe "$candidate`:" $physicalCache
            if ($LASTEXITCODE -eq 0) {
                $cacheDrive = $candidate
                break
            }
        }
    }
    if (-not $cacheDrive) {
        throw 'Windows long paths are disabled and no free drive letter was available for the short build-cache mapping.'
    }
    $Cache = "$cacheDrive`:\"
    Write-Host "[INFO] Long paths are disabled. Build cache mapped to $Cache ($physicalCache)" -ForegroundColor Yellow
}
$buildScript = Join-Path $scriptRoot 'scripts\build-physical.ps1'
if (-not (Test-Path -LiteralPath $buildScript)) { throw "Build script not found: $buildScript" }

$toolPaths = @(
    'C:\Program Files\Git\bin',
    'C:\Program Files\Git\cmd',
    'C:\Program Files\Git\usr\bin',
    'C:\Program Files\CMake\bin',
    'C:\Program Files\7-Zip',
    'C:\depot_tools'
)
if ($env:DEPOT_TOOLS_DIR -and (Test-Path -LiteralPath $env:DEPOT_TOOLS_DIR)) {
    $toolPaths += $env:DEPOT_TOOLS_DIR
}
$gclientCommand = Get-Command gclient -ErrorAction SilentlyContinue
if ($gclientCommand) {
    $toolPaths += Split-Path -Parent $gclientCommand.Source
}

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path -LiteralPath $vswhere) {
    $msbuildPath = & $vswhere -latest -products * -version '[17.0,18.0)' -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
    if ($msbuildPath) { $toolPaths += Split-Path -Parent $msbuildPath }

    $visualStudioPath = & $vswhere -latest -products * -version '[17.0,18.0)' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1
    if ($visualStudioPath) {
        $toolPaths += Join-Path $visualStudioPath 'Common7\Tools'
        $toolPaths += Join-Path $visualStudioPath 'MSBuild\Current\Bin'
        $env:vs2022_install = $visualStudioPath
    }
}
$ninja = Get-ChildItem -LiteralPath "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter ninja.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if ($ninja) { $toolPaths += $ninja.DirectoryName }
$env:Path = (($toolPaths + $env:Path.Split(';')) | Where-Object { $_ } | Select-Object -Unique) -join ';'

$pythonCandidates = @()
if ($env:DEPOT_TOOLS_DIR) {
    $pythonCandidates += Join-Path $env:DEPOT_TOOLS_DIR 'python3.bat'
    $pythonCandidates += Join-Path $env:DEPOT_TOOLS_DIR 'python.bat'
}
$pythonCandidates += @(
    'C:\depot_tools\python3.bat',
    'C:\depot_tools\python.bat',
    (Get-Command python3.bat -ErrorAction SilentlyContinue).Source,
    (Get-Command python3 -ErrorAction SilentlyContinue).Source,
    (Get-Command python.bat -ErrorAction SilentlyContinue).Source,
    (Get-Command python -ErrorAction SilentlyContinue).Source
)
$python3Path = $pythonCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $python3Path) { throw 'Python 3 was not found.' }
$python3Path = [System.IO.Path]::GetFullPath($python3Path)
if ($python3Path -notmatch '^([A-Za-z]):\\(.*)$') {
    throw "Python path cannot be converted for Git Bash: $python3Path"
}
$env:PYTHON_BIN = ('/{0}/{1}' -f $Matches[1].ToLowerInvariant(), ($Matches[2] -replace '\\', '/'))
if (-not $Proxy -and $env:CEF_PROXY) { $Proxy = $env:CEF_PROXY }
if ($Proxy) {
    if ($Proxy -notmatch '^[a-z]+://') { $Proxy = "http://$Proxy" }
    $env:HTTP_PROXY = $Proxy
    $env:HTTPS_PROXY = $Proxy
}
$env:NO_PROXY = 'localhost,127.0.0.1'
$env:GIT_HTTP_VERSION = 'HTTP/1.1'

Write-Host '=== Checking build environment ===' -ForegroundColor Cyan
$missing = @()
foreach ($name in @('git','bash','python','dotnet','cmake','ninja','msbuild','7z')) {
    $command = Get-Command $name -ErrorAction SilentlyContinue
    if ($command) { Write-Host "[OK] $name -> $($command.Source)" -ForegroundColor Green }
    else { Write-Host "[MISSING] $name" -ForegroundColor Red; $missing += $name }
}
$sdkRoot = 'C:\Program Files (x86)\Windows Kits\10\Include'
$sdk = Get-ChildItem -LiteralPath $sdkRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
if ($sdk) { Write-Host "[OK] Windows SDK -> $($sdk.FullName)" -ForegroundColor Green }
else { Write-Host '[MISSING] Windows SDK headers' -ForegroundColor Red; $missing += 'Windows SDK' }
if ($missing.Count -gt 0) { throw "Environment is incomplete: $($missing -join ', ')" }

if (-not $PreflightOnly -and $Line -in @('134', 'both')) {
    $chromiumOut = Join-Path $Cache '134\win-x64\source\chromium\src\out'
    $releaseArgs = Get-ChildItem -LiteralPath $chromiumOut -Recurse -Filter args.gn -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match 'Release' } |
        Select-Object -First 1
    $releaseTarget = Join-Path $chromiumOut 'Release_GN_x64\cefsimple.exe'

    if (-not $releaseArgs) {
        if (Test-Path -LiteralPath $chromiumOut) {
            $expectedOut = [System.IO.Path]::GetFullPath((Join-Path $Cache '134\win-x64\source\chromium\src\out'))
            $resolvedOut = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $chromiumOut).Path)
            $cacheRoot = [System.IO.Path]::GetFullPath($Cache).TrimEnd('\') + '\'
            if ($resolvedOut -ne $expectedOut -or -not $resolvedOut.StartsWith($cacheRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to remove unexpected build directory: $resolvedOut"
            }
            Remove-Item -LiteralPath $resolvedOut -Recurse -Force
            Write-Host "[INFO] Removed incomplete native output: $resolvedOut" -ForegroundColor Yellow
        }
        Write-Host '[INFO] Release args.gn is missing. Enabled --force-build.' -ForegroundColor Yellow
    }
    if (-not (Test-Path -LiteralPath $releaseTarget)) {
        $existingArguments = @($env:GN_ARGUMENTS -split '\s+' | Where-Object { $_ })
        if ('--force-build' -notin $existingArguments) {
            $env:GN_ARGUMENTS = (@($existingArguments) + '--force-build') -join ' '
        }
        Write-Host '[INFO] Release cefsimple.exe is missing. Enabled resumable --force-build.' -ForegroundColor Yellow
    }
}

$innerArguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$buildScript,'-Line',$Line,'-Rid',$Rid,'-Output',$Output,'-Cache',$Cache)
if ($PreflightOnly) { $innerArguments += '-PreflightOnly' }
if ($AllowLowDisk) { $innerArguments += '-AllowLowDisk' }
& powershell.exe @innerArguments
if ($LASTEXITCODE -ne 0) { throw "Build failed with exit code $LASTEXITCODE" }
Write-Host "Build completed: $Output" -ForegroundColor Green
