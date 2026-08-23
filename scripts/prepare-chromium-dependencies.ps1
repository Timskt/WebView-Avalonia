[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ChromiumSource,
    [int]$MaxAttempts = 10,
    [int]$DelaySeconds = 20
)

$ErrorActionPreference = 'Continue'
$ChromiumSource = [System.IO.Path]::GetFullPath($ChromiumSource)
if (-not (Test-Path -LiteralPath (Join-Path $ChromiumSource '.git'))) {
    exit 0
}

function Test-GitRevisionComplete {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository,
        [Parameter(Mandatory = $true)]
        [string]$Revision
    )

    & git -c 'safe.directory=*' -C $Repository cat-file -e "$Revision`^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    $missingObjects = @(
        & git -c 'safe.directory=*' -C $Repository `
            rev-list --objects --missing=print "$Revision`^{tree}" 2>$null |
            Where-Object { $_.StartsWith('?') }
    )
    return $LASTEXITCODE -eq 0 -and $missingObjects.Count -eq 0
}

$repositories = @(
    @{
        Relative = 'third_party/dawn'
        Url = 'https://dawn.googlesource.com/dawn.git'
        ResolveRevisionRef = $true
    },
    @{
        Relative = 'third_party/depot_tools'
        Url = 'https://chromium.googlesource.com/chromium/tools/depot_tools.git'
        LocalSource = 'C:\depot_tools'
    },
    @{
        Relative = 'third_party/devtools-frontend/src'
        Url = 'https://chromium.googlesource.com/devtools/devtools-frontend.git'
        FetchUrl = 'https://github.com/ChromeDevTools/devtools-frontend.git'
    },
    @{
        Relative = 'third_party/libFuzzer/src'
        Url = 'https://chromium.googlesource.com/external/github.com/llvm/llvm-project/compiler-rt/lib/fuzzer.git'
    },
    @{
        Relative = 'third_party/libphonenumber/dist'
        Url = 'https://chromium.googlesource.com/external/libphonenumber.git'
        FetchUrl = 'https://github.com/google/libphonenumber.git'
    },
    @{
        Relative = 'third_party/perfetto'
        Url = 'https://android.googlesource.com/platform/external/perfetto.git'
        ResolveRevisionRef = $true
    },
    @{
        Relative = 'third_party/vulkan_memory_allocator'
        ArchiveUrl = 'https://chromium.googlesource.com/external/github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator/+archive/56300b29fbfcc693ee6609ddad3fdd5b7a449a21.tar.gz'
        Marker = 'include/vk_mem_alloc.h'
    }
)

foreach ($repository in $repositories) {
    $relative = $repository.Relative
    $gitlink = & git -c 'safe.directory=*' -C $ChromiumSource ls-files -s -- $relative
    if ($LASTEXITCODE -ne 0 -or -not $gitlink) {
        throw "Unable to resolve Chromium gitlink: $relative"
    }
    $revision = ($gitlink -split '\s+')[1]
    $target = [System.IO.Path]::GetFullPath(
        (Join-Path $ChromiumSource ($relative -replace '/', '\'))
    )
    $thirdPartyRoot = [System.IO.Path]::GetFullPath(
        (Join-Path $ChromiumSource 'third_party')
    ).TrimEnd('\') + '\'
    if (-not $target.StartsWith($thirdPartyRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify unexpected dependency path: $target"
    }

    if ($repository.ArchiveUrl) {
        $markerPath = Join-Path $target $repository.Marker
        if (-not (Test-Path -LiteralPath $markerPath)) {
            if (Test-Path -LiteralPath $target) {
                Remove-Item -LiteralPath $target -Recurse -Force
            }
            New-Item -ItemType Directory -Force -Path $target | Out-Null
            $archivePath = Join-Path ([System.IO.Path]::GetTempPath()) ("cef-dependency-" + [guid]::NewGuid().ToString('N') + '.tar.gz')
            try {
                $curl = Get-Command curl.exe -ErrorAction Stop
                & $curl.Source -L --fail --retry 5 --retry-delay 5 --connect-timeout 30 --max-time 1800 `
                    $repository.ArchiveUrl -o $archivePath
                if ($LASTEXITCODE -ne 0) { throw "Archive download failed: $relative" }
                $systemTar = Join-Path $env:SystemRoot 'System32\tar.exe'
                if (-not (Test-Path -LiteralPath $systemTar)) {
                    throw "Windows tar.exe was not found: $systemTar"
                }
                & $systemTar -xzf $archivePath -C $target
                if ($LASTEXITCODE -ne 0) { throw "Archive extraction failed: $relative" }
            } finally {
                Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue
            }
        }
        if (-not (Test-Path -LiteralPath $markerPath)) {
            throw "Archive dependency is incomplete: $relative"
        }
        continue
    }

    $hasRevision = $false
    if (Test-Path -LiteralPath (Join-Path $target '.git')) {
        $hasRevision = Test-GitRevisionComplete -Repository $target -Revision $revision
    }

    if (-not $hasRevision) {
        if (Test-Path -LiteralPath $target) {
            Remove-Item -LiteralPath $target -Recurse -Force
        }
        $localSource = $repository.LocalSource
        $localHasRevision = $false
        if ($localSource -and (Test-Path -LiteralPath (Join-Path $localSource '.git'))) {
            $localHasRevision = Test-GitRevisionComplete -Repository $localSource -Revision $revision
        }
        if ($localHasRevision) {
            & git -c 'safe.directory=*' clone --no-local --no-checkout $localSource $target
            if ($LASTEXITCODE -ne 0) { throw "Local git clone failed: $relative" }
            $hasRevision = $true
        } else {
            New-Item -ItemType Directory -Force -Path $target | Out-Null
            & git -c 'safe.directory=*' -C $target init
            if ($LASTEXITCODE -ne 0) { throw "git init failed: $relative" }
            $fetchUrl = if ($repository.FetchUrl) { $repository.FetchUrl } else { $repository.Url }
            & git -c 'safe.directory=*' -C $target remote add origin $fetchUrl
            if ($LASTEXITCODE -ne 0) { throw "git remote add failed: $relative" }
        }

        if (-not $hasRevision) {
            $fetchTarget = $revision
            if ($repository.ResolveRevisionRef) {
                $fetchUrl = if ($repository.FetchUrl) { $repository.FetchUrl } else { $repository.Url }
                $matchingRef = @(
                    & git -c 'safe.directory=*' ls-remote --refs $fetchUrl 2>$null |
                        Where-Object { $_ -match "^$([regex]::Escape($revision))`trefs/heads/" } |
                        ForEach-Object { ($_ -split "`t", 2)[1] } |
                        Sort-Object Length |
                        Select-Object -First 1
                )
                if ($matchingRef.Count -gt 0) {
                    $fetchTarget = $matchingRef[0]
                }
            }
            for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
                Write-Host "Fetching $relative ($attempt/$MaxAttempts)..." -ForegroundColor Cyan
                & git -c 'safe.directory=*' -C $target `
                    -c http.version=HTTP/1.1 `
                    -c http.maxRequests=1 `
                    fetch --depth=1 origin $fetchTarget
                if ($LASTEXITCODE -eq 0) {
                    $hasRevision = $true
                    break
                }
                if ($attempt -lt $MaxAttempts) {
                    Start-Sleep -Seconds $DelaySeconds
                }
            }
        }
        if (-not $hasRevision) {
            throw "Unable to fetch $relative at $revision"
        }
    }

    & git -c 'safe.directory=*' -C $target remote set-url origin $repository.Url
    if ($LASTEXITCODE -ne 0) { throw "git remote set-url failed: $relative" }
    & git -c 'safe.directory=*' -C $target checkout --force $revision
    if ($LASTEXITCODE -ne 0) { throw "git checkout failed: $relative" }
}
