Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$script:FixVersion = "1.0.0"
$script:LibmpvEntry = "native/windows/libmpv-2.dll"
$script:PlayerBridgeEntry = "native/windows/player_bridge.dll"

$script:KnownBadLibmpvSha256 = "07c68bb211f23a218ded0a36eb12207dc3aeb44e5318ffca6ce9dcc7c3173906"
$script:FixedLibmpvSha256 = "361e3a306707454a24e7d3558b2eb7a9ccc23a4f5ed396fe7e77f0a44908eda5"

$script:LegacyHeaderAbBridgeSha256 = "e7ad053989a3ff6b63a6a1567768150423c342e0414b9252a05b78fdf29c80f6"
$script:LegacyResumeAbBridgeSha256 = "4362a42413a1e1bd503a4e5ab0683511b9cba9e2a65ce38092e32f5561470371"

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-ZipEntryHash([string]$ArchivePath, [string]$EntryPath) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $entry = $zip.GetEntry($EntryPath)
        if ($null -eq $entry) { return $null }
        $stream = $entry.Open()
        try {
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try {
                return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "").ToLowerInvariant()
            } finally {
                $sha.Dispose()
            }
        } finally {
            $stream.Dispose()
        }
    } finally {
        $zip.Dispose()
    }
}

function Test-NuvioJar([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try {
            return ($null -ne $zip.GetEntry($script:LibmpvEntry)) -and
                   ($null -ne $zip.GetEntry($script:PlayerBridgeEntry))
        } finally {
            $zip.Dispose()
        }
    } catch {
        return $false
    }
}

function Test-JarSigned([string]$Path) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $signed = $zip.Entries | Where-Object {
            $_.FullName -match '^META-INF/.+\.(SF|RSA|DSA|EC)$'
        } | Select-Object -First 1
        return $null -ne $signed
    } finally {
        $zip.Dispose()
    }
}

function Get-NuvioSearchRoots {
    $roots = [Collections.Generic.List[string]]::new()

    $registryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($regPath in $registryPaths) {
        Get-ItemProperty $regPath -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "Nuvio*" -and $_.InstallLocation } |
            ForEach-Object { $roots.Add([string]$_.InstallLocation) }
    }

    $pf = [Environment]::GetFolderPath("ProgramFiles")
    $pfx86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    if ($pf) { $roots.Add((Join-Path $pf "Nuvio")) }
    if ($pfx86) { $roots.Add((Join-Path $pfx86 "Nuvio")) }

    if ($env:LOCALAPPDATA) {
        $roots.Add((Join-Path $env:LOCALAPPDATA "Programs\Nuvio"))
        $roots.Add((Join-Path $env:LOCALAPPDATA "Nuvio"))
    }

    return @($roots | Where-Object { $_ } | Select-Object -Unique)
}

function Find-NuvioJar([string]$ExplicitJarPath) {
    if ($ExplicitJarPath) {
        $resolved = (Resolve-Path -LiteralPath $ExplicitJarPath).Path
        if (-not (Test-NuvioJar $resolved)) {
            throw "Specified JAR is not the Nuvio desktop application JAR: $resolved"
        }
        return $resolved
    }

    $candidates = [Collections.Generic.List[object]]::new()
    foreach ($root in (Get-NuvioSearchRoots)) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }

        Get-ChildItem -LiteralPath $root -Recurse -File -Filter "*.jar" -ErrorAction SilentlyContinue |
            ForEach-Object {
                if (Test-NuvioJar $_.FullName) {
                    $candidates.Add($_)
                }
            }
    }

    $unique = @(
        $candidates |
            Group-Object FullName |
            ForEach-Object { $_.Group[0] } |
            Sort-Object LastWriteTimeUtc -Descending
    )

    if ($unique.Count -eq 0) {
        throw "Could not find the installed Nuvio desktop application JAR. Use -JarPath with the full path."
    }

    if ($unique.Count -gt 1) {
        Write-Host "Multiple Nuvio application JARs were found. Using the newest one:" -ForegroundColor Yellow
        $unique | ForEach-Object {
            Write-Host ("  {0}  [{1:u}]" -f $_.FullName, $_.LastWriteTimeUtc)
        }
    }

    return $unique[0].FullName
}

function Read-KeyValueFile([string]$Path) {
    $map = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $map }

    Get-Content -LiteralPath $Path | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            $map[$matches[1]] = $matches[2]
        }
    }
    return $map
}

function Write-FixState(
    [string]$StatePath,
    [string]$Jar,
    [string]$Backup,
    [string]$OriginalJarHash,
    [string]$PatchedJarHash
) {
    @(
        "FIX_VERSION=$script:FixVersion"
        "JAR=$Jar"
        "BACKUP=$Backup"
        "ORIGINAL_JAR_SHA256=$OriginalJarHash"
        "PATCHED_JAR_SHA256=$PatchedJarHash"
        "ORIGINAL_LIBMPV_SHA256=$script:KnownBadLibmpvSha256"
        "PATCH_LIBMPV_SHA256=$script:FixedLibmpvSha256"
    ) | Set-Content -LiteralPath $StatePath -Encoding UTF8
}

function Get-JarSidecarStatePath([string]$Jar) {
    return "$Jar.solyan-libmpv-fix-v1.state"
}

function Get-VersionedBackupPath([string]$Jar, [string]$OriginalJarHash) {
    $shortHash = $OriginalJarHash.Substring(0, 16)
    return "$Jar.solyan-libmpv-fix-v1-$shortHash.bak"
}

function Assert-NoLegacyBridgePatch([string]$Jar) {
    $bridgeHash = Get-ZipEntryHash $Jar $script:PlayerBridgeEntry
    if ($bridgeHash -eq $script:LegacyHeaderAbBridgeSha256) {
        throw "Legacy PlayTorrio-header A/B is still applied. Run its ROLLBACK.cmd first."
    }
    if ($bridgeHash -eq $script:LegacyResumeAbBridgeSha256) {
        throw "Legacy Windows-initial-resume A/B is still applied. Run its ROLLBACK.cmd first."
    }
}
