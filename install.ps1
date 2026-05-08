<#
.SYNOPSIS
    EdgeFirst Profiler CLI installer for Windows.
.DESCRIPTION
    Detects platform, downloads the matching release asset from
    GitHub, verifies SHA-256, and installs to a per-user or
    system-wide directory depending on whether the script runs
    elevated.
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

    if ($fails.Count -eq 0) {
        Write-Host 'install.ps1 self-test: PASS'
        return 0
    }
    foreach ($f in $fails) { Write-Error "FAIL $f" }
    Write-Host 'install.ps1 self-test: FAIL' -ForegroundColor Red
    return 1
}

# ---------- Entry point -----------------------------------------------------

if ($SelfTest) {
    exit (Invoke-SelfTest)
}

Write-Error 'install.ps1: main body not yet implemented (added in Task 8)'
exit 1
