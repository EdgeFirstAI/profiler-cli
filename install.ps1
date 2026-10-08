<#
.SYNOPSIS
    EdgeFirst Profiler CLI installer for Windows.
.DESCRIPTION
    Detects platform, downloads the matching release asset from
    GitHub, verifies SHA-256, and installs to a per-user or
    system-wide directory depending on whether the script runs
    elevated. On Windows the archive also carries ONNX Runtime
    (CPU and DirectML), DirectML and ANGLE, which are installed
    beside the executable. CUDA is not installed: see the
    "CUDA on Windows" section of the README.
.PARAMETER Version
    Specific version to install. Defaults to latest release.
.PARAMETER Prefix
    Override the install directory.
.PARAMETER NoVerifyChecksum
    Skip SHA-256 verification (NOT recommended).
.PARAMETER SelfTest
    Run internal sanity checks and exit.
.NOTES
    Copyright (c) 2026 Au-Zone Technologies Inc.
    Licensed under the EdgeFirst Profiler CLI End User License (LICENSE).
#>

[CmdletBinding()]
param(
    [string]$Version,
    [string]$Prefix,
    [switch]$NoVerifyChecksum,
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:Repo = 'EdgeFirstAI/profiler-cli'

# ---------- Pure helpers ----------------------------------------------------

function Get-DetectedOS {
    if ($IsWindows -or $env:OS -eq 'Windows_NT') { return 'windows' }
    if ($IsLinux)   { return 'linux' }
    if ($IsMacOS)   { return 'macos' }
    return 'unknown'
}

function Get-DetectedArch {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLower()
    switch ($arch) {
        'x64'   { 'x86_64' }
        'arm64' { 'aarch64' }
        default { 'unknown' }
    }
}

function Get-AssetExtensionForOS {
    param([string]$OS)
    switch ($OS) {
        'linux'   { 'tar.gz' }
        'macos'   { 'tar.gz' }
        'windows' { 'zip' }
        default   { 'unknown' }
    }
}

function Get-AssetName {
    param(
        [string]$Version,
        [string]$OS,
        [string]$Arch
    )
    $ext = Get-AssetExtensionForOS -OS $OS
    return ("edgefirst-profiler-{0}-{1}-{2}.{3}" -f $Version, $OS, $Arch, $ext)
}

function Test-IsElevated {
    if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        $current = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($current)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    return $false
}

function Get-DefaultPrefix {
    if (Test-IsElevated) {
        return Join-Path $env:ProgramFiles 'edgefirst-profiler'
    }
    return Join-Path $env:LOCALAPPDATA 'Programs\edgefirst-profiler'
}

$Script:ShippedPlatforms = @('linux-x86_64', 'linux-aarch64', 'macos-aarch64', 'windows-x86_64')

function Test-PlatformBinariesAvailable {
    # Returns $true if release archives exist for the given platform, so
    # the installer gives a friendly error rather than attempt a 404
    # download.
    param([string]$OS, [string]$Arch)
    return ("$OS-$Arch" -in $Script:ShippedPlatforms)
}

# ---------- Self-test -------------------------------------------------------

function Invoke-SelfTest {
    $fails = @()

    $expected = 'edgefirst-profiler-0.2.0-windows-x86_64.zip'
    $actual = Get-AssetName -Version '0.2.0' -OS 'windows' -Arch 'x86_64'
    if ($actual -ne $expected) { $fails += "Get-AssetName windows x86_64: got '$actual'" }

    $expected = 'edgefirst-profiler-0.2.0-linux-aarch64.tar.gz'
    $actual = Get-AssetName -Version '0.2.0' -OS 'linux' -Arch 'aarch64'
    if ($actual -ne $expected) { $fails += "Get-AssetName linux aarch64: got '$actual'" }

    $expected = 'edgefirst-profiler-0.2.0-macos-aarch64.tar.gz'
    $actual = Get-AssetName -Version '0.2.0' -OS 'macos' -Arch 'aarch64'
    if ($actual -ne $expected) { $fails += "Get-AssetName macos aarch64: got '$actual'" }

    if ((Get-AssetExtensionForOS -OS 'windows') -ne 'zip')      { $fails += 'Get-AssetExtensionForOS windows' }
    if ((Get-AssetExtensionForOS -OS 'linux')   -ne 'tar.gz')   { $fails += 'Get-AssetExtensionForOS linux' }
    if ((Get-AssetExtensionForOS -OS 'freebsd') -ne 'unknown')  { $fails += 'Get-AssetExtensionForOS freebsd' }

    $os = Get-DetectedOS
    if ($os -notin @('windows', 'linux', 'macos', 'unknown')) {
        $fails += "Get-DetectedOS returned unexpected value: $os"
    }

    $arch = Get-DetectedArch
    if ($arch -notin @('x86_64', 'aarch64', 'unknown')) {
        $fails += "Get-DetectedArch returned unexpected value: $arch"
    }

    foreach ($shipped in @(@('windows', 'x86_64'), @('linux', 'x86_64'), @('linux', 'aarch64'), @('macos', 'aarch64'))) {
        if ((Test-PlatformBinariesAvailable -OS $shipped[0] -Arch $shipped[1]) -ne $true) { $fails += "Test-PlatformBinariesAvailable should return `$true for $($shipped -join '-')" }
    }
    foreach ($missing in @(@('windows', 'aarch64'), @('macos', 'x86_64'))) {
        if ((Test-PlatformBinariesAvailable -OS $missing[0] -Arch $missing[1]) -ne $false) { $fails += "Test-PlatformBinariesAvailable should return `$false for $($missing -join '-')" }
    }

    if ($fails.Count -eq 0) {
        Write-Host 'install.ps1 self-test: PASS'
        return 0
    }
    foreach ($f in $fails) { Write-Error "FAIL $f" }
    Write-Host 'install.ps1 self-test: FAIL' -ForegroundColor Red
    return 1
}

# ---------- Entry point -----------------------------------------------------

function Resolve-LatestVersion {
    $api = "https://api.github.com/repos/$Script:Repo/releases/latest"
    try {
        $resp = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'edgefirst-profiler-cli-install' }
    } catch {
        throw "Could not resolve latest release tag from $api : $_"
    }
    if (-not $resp.tag_name) { throw "Latest release has no tag_name" }
    return ($resp.tag_name -replace '^v', '')
}

function Get-ReleaseAssetUrl {
    param([string]$Version, [string]$Asset)
    return "https://github.com/$Script:Repo/releases/download/v$Version/$Asset"
}

function Test-Sha256 {
    param([string]$Path, [string]$ExpectedHex)
    $hash = (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLower()
    return ($hash -eq $ExpectedHex.ToLower())
}

function Add-ToUserPath {
    param([string]$Dir)
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($current -and ($current.Split(';') -contains $Dir)) { return }
    $next = if ([string]::IsNullOrEmpty($current)) { $Dir } else { "$current;$Dir" }
    [Environment]::SetEnvironmentVariable('Path', $next, 'User')
}

function Add-ToSystemPath {
    param([string]$Dir)
    $current = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if ($current -and ($current.Split(';') -contains $Dir)) { return }
    $next = if ([string]::IsNullOrEmpty($current)) { $Dir } else { "$current;$Dir" }
    [Environment]::SetEnvironmentVariable('Path', $next, 'Machine')
}

function Invoke-Install {
    if ($SelfTest) { return (Invoke-SelfTest) }

    $os = Get-DetectedOS
    $arch = Get-DetectedArch
    if ($os -eq 'unknown' -or $arch -eq 'unknown') {
        Write-Error "Unsupported platform: os=$os arch=$arch"
        Write-Error "Supported: $($Script:ShippedPlatforms -join ', ')"
        return 1
    }

    if (-not (Test-PlatformBinariesAvailable -OS $os -Arch $arch)) {
        Write-Host ''
        Write-Host "EdgeFirst Profiler CLI does not ship binaries for $os-$arch." -ForegroundColor Yellow
        Write-Host ''
        Write-Host 'Supported platforms:'
        Write-Host '  - Linux x86_64   (glibc 2.17+ / manylinux2014)'
        Write-Host '  - Linux aarch64  (glibc 2.17+ / manylinux2014)'
        Write-Host '  - macOS arm64    (macOS 11+)'
        Write-Host '  - Windows x86_64 (Windows 10 or 11)'
        Write-Host ''
        Write-Host 'Track status at https://github.com/EdgeFirstAI/profiler-cli'
        Write-Host ''
        return 2
    }

    $resolvedVersion = if ([string]::IsNullOrEmpty($Version)) {
        Write-Host "Resolving latest version from github.com/$Script:Repo..."
        Resolve-LatestVersion
    } else { $Version }

    Write-Host "Installing edgefirst-profiler v$resolvedVersion for $os-$arch"

    $resolvedPrefix = if ([string]::IsNullOrEmpty($Prefix)) { Get-DefaultPrefix } else { $Prefix }

    $asset = Get-AssetName -Version $resolvedVersion -OS $os -Arch $arch
    $url = Get-ReleaseAssetUrl -Version $resolvedVersion -Asset $asset
    $tmp = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())) | Select-Object -ExpandProperty FullName
    try {
        $archive = Join-Path $tmp $asset
        Write-Host "Downloading $asset..."
        try {
            Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing -Headers @{ 'User-Agent' = 'edgefirst-profiler-cli-install' }
        } catch {
            Write-Error "Could not download $url"
            Write-Error "If you pinned -Version, confirm it exists at https://github.com/$Script:Repo/releases"
            return 1
        }

        if (-not $NoVerifyChecksum) {
            Write-Host 'Verifying SHA-256...'
            $sumsPath = "$archive.sha256"
            try {
                Invoke-WebRequest -Uri "$url.sha256" -OutFile $sumsPath -UseBasicParsing -Headers @{ 'User-Agent' = 'edgefirst-profiler-cli-install' }
            } catch {
                Write-Error "Could not download checksum file $url.sha256"
                return 1
            }
            $expected = ((Get-Content -Path $sumsPath -TotalCount 1) -split '\s+')[0]
            if (-not (Test-Sha256 -Path $archive -ExpectedHex $expected)) {
                Remove-Item -Force $archive
                Write-Error 'Checksum mismatch'
                return 1
            }
        } else {
            Write-Warning '-NoVerifyChecksum was specified; skipping integrity check.'
        }

        Write-Host 'Extracting...'
        if ($archive.EndsWith('.zip')) {
            Expand-Archive -Path $archive -DestinationPath $tmp -Force
        } else {
            # tar.gz on Windows: tar.exe ships with Windows 10 1803+
            tar.exe -xzf $archive -C $tmp
        }

        if (-not (Test-Path $resolvedPrefix)) {
            try {
                New-Item -ItemType Directory -Path $resolvedPrefix -Force | Out-Null
            } catch {
                Write-Error "Could not create install directory: $resolvedPrefix"
                Write-Error 'Try a writable -Prefix DIR, or re-run from an elevated (Administrator) PowerShell.'
                return 1
            }
        }

        $binName = if ($os -eq 'windows') { 'edgefirst-profiler.exe' } else { 'edgefirst-profiler' }
        $binSrc = Join-Path $tmp $binName
        if (-not (Test-Path $binSrc)) {
            $binSrc = (Get-ChildItem -Path $tmp -Recurse -Filter $binName -File | Select-Object -First 1).FullName
        }
        if (-not $binSrc -or -not (Test-Path $binSrc)) {
            Write-Error "$binName not found in archive"
            return 1
        }

        $dest = Join-Path $resolvedPrefix $binName
        try {
            if ($os -eq 'windows') {
                # The bundled ONNX Runtime, DirectML and ANGLE DLLs (and their
                # license texts) must sit beside the executable.
                Get-ChildItem -Path (Split-Path -Parent $binSrc) -File |
                    Copy-Item -Destination $resolvedPrefix -Force
            } else {
                Copy-Item -Path $binSrc -Destination $dest -Force
            }
        } catch {
            Write-Error "Install directory is not writable: $resolvedPrefix"
            Write-Error 'Try a writable -Prefix DIR, or re-run from an elevated (Administrator) PowerShell.'
            return 1
        }
        Write-Host "Installed to $dest"

        if (Test-IsElevated) { Add-ToSystemPath -Dir $resolvedPrefix } else { Add-ToUserPath -Dir $resolvedPrefix }

        $machinePath = ($env:Path -split ';')
        if ($machinePath -notcontains $resolvedPrefix) {
            Write-Host ''
            Write-Host "Note: $resolvedPrefix was added to your PATH but the current shell will not see it until you open a new terminal."
        }

        if ($os -eq 'windows') {
            # The profiler and ONNX Runtime link the Visual C++ 2015-2022
            # runtime, which a fresh Windows install may not have.
            $missingCrt = @('vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll') |
                Where-Object { -not (Test-Path (Join-Path $env:SystemRoot "System32\$_")) }
            if ($missingCrt) {
                Write-Host ''
                Write-Host "The Microsoft Visual C++ Redistributable is missing ($($missingCrt -join ', '))." -ForegroundColor Yellow
                Write-Host 'Install it, then run edgefirst-profiler --version:'
                Write-Host '  https://aka.ms/vs/17/release/vc_redist.x64.exe'
                return 1
            }
        }

        Write-Host ''
        Write-Host 'Verifying install...'
        $versionOutput = & $dest --version 2>&1
        $versionExit = $LASTEXITCODE
        Write-Host $versionOutput
        if ($versionExit -ne 0) {
            Write-Error 'Post-install --version check failed'
            return 1
        }
        if ($versionOutput -notmatch [regex]::Escape($resolvedVersion)) {
            Write-Error "Version mismatch: --version output does not contain '$resolvedVersion'"
            Write-Error 'This could indicate a corrupt download or a wrong asset.'
            return 1
        }

        if ($os -eq 'windows') {
            Write-Host ''
            Write-Host 'ONNX Runtime is installed for --provider cpu and --provider directml.'
            if (Test-Path (Join-Path $env:SystemRoot 'System32\nvcuda.dll')) {
                Write-Host 'An NVIDIA driver is present. --provider cuda needs the CUDA 12 and cuDNN 9'
                Write-Host 'runtime and the CUDA build of ONNX Runtime, which this installer does not install:'
                Write-Host '  https://github.com/EdgeFirstAI/profiler-cli#cuda-on-windows'
            }
        }
        return 0
    } finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
}

exit (Invoke-Install)
