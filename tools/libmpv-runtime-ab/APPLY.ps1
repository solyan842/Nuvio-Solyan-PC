param([string]$JarPath)

$ErrorActionPreference = "Stop"

$LibmpvEntry = "native/windows/libmpv-2.dll"
$PlayerBridgeEntry = "native/windows/player_bridge.dll"
$PatchDll = Join-Path $PSScriptRoot "libmpv-2.dll"
$StateFile = Join-Path $PSScriptRoot "PATCH-STATE.txt"

$ExpectedOriginalLibmpvSha256 = "07c68bb211f23a218ded0a36eb12207dc3aeb44e5318ffca6ce9dcc7c3173906"
$HeaderAbBridgeSha256 = "e7ad053989a3ff6b63a6a1567768150423c342e0414b9252a05b78fdf29c80f6"
$ResumeAbBridgeSha256 = "4362a42413a1e1bd503a4e5ab0683511b9cba9e2a65ce38092e32f5561470371"

function Get-Sha256([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
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
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try {
            return ($null -ne $zip.GetEntry($LibmpvEntry)) -and ($null -ne $zip.GetEntry($PlayerBridgeEntry))
        } finally {
            $zip.Dispose()
        }
    } catch {
        return $false
    }
}

function Find-NuvioJar {
    if ($JarPath) {
        $resolved = (Resolve-Path -LiteralPath $JarPath).Path
        if (-not (Test-NuvioJar $resolved)) {
            throw "Specified JAR does not contain the Nuvio Windows native runtime: $resolved"
        }
        return $resolved
    }

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

    $candidates = [Collections.Generic.List[string]]::new()
    foreach ($root in ($roots | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -Recurse -File -Filter "*.jar" -ErrorAction SilentlyContinue |
            ForEach-Object {
                if (Test-NuvioJar $_.FullName) {
                    $candidates.Add($_.FullName)
                }
            }
    }

    $unique = @($candidates | Select-Object -Unique)
    if ($unique.Count -eq 0) {
        throw "Could not find the installed Nuvio application JAR. Re-run APPLY.ps1 with -JarPath <full path to composeApp-desktop-*.jar>."
    }
    if ($unique.Count -gt 1) {
        throw ("More than one Nuvio application JAR was found. Re-run with -JarPath and choose one." + [Environment]::NewLine + ($unique -join [Environment]::NewLine))
    }
    return $unique[0]
}

$running = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "Nuvio*" }
if ($running) {
    throw "Nuvio is running. Close Nuvio completely before applying this A/B runtime patch."
}
if (-not (Test-Path -LiteralPath $PatchDll)) {
    throw "Missing libmpv-2.dll next to APPLY.ps1"
}

$jar = Find-NuvioJar
$currentBridgeHash = Get-ZipEntryHash $jar $PlayerBridgeEntry
if ($currentBridgeHash -eq $HeaderAbBridgeSha256) {
    throw "The previous PlayTorrio-header A/B is still applied. Run its ROLLBACK.cmd first."
}
if ($currentBridgeHash -eq $ResumeAbBridgeSha256) {
    throw "The previous Windows-initial-resume A/B is still applied. Run its ROLLBACK.cmd first."
}

$patchHash = Get-Sha256 $PatchDll
$currentLibmpvHash = Get-ZipEntryHash $jar $LibmpvEntry
if ($currentLibmpvHash -eq $patchHash) {
    Write-Host "libmpv runtime A/B is already applied." -ForegroundColor Green
    Write-Host "JAR: $jar"
    Write-Host "libmpv SHA256: $patchHash"
    exit 0
}
if ($currentLibmpvHash -ne $ExpectedOriginalLibmpvSha256) {
    throw ("Installed Nuvio libmpv does not match the upstream runtime this A/B was built for." +
        [Environment]::NewLine +
        "Expected: $ExpectedOriginalLibmpvSha256" +
        [Environment]::NewLine +
        "Found:    $currentLibmpvHash" +
        [Environment]::NewLine +
        "No changes were made.")
}

$backup = "$jar.solyan-sfilm3-libmpv-ab-original.bak"
if (Test-Path -LiteralPath $backup) {
    throw ("Runtime A/B backup already exists: $backup" + [Environment]::NewLine + "Refusing to overwrite the rollback copy.")
}

$originalJarHash = Get-Sha256 $jar
Copy-Item -LiteralPath $jar -Destination $backup -Force
if ((Get-Sha256 $backup) -ne $originalJarHash) {
    throw "Backup verification failed. No patch was applied."
}

$tempJar = "$jar.solyan-sfilm3-libmpv-ab.tmp"
Copy-Item -LiteralPath $jar -Destination $tempJar -Force
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $stream = [System.IO.File]::Open(
        $tempJar,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )
    try {
        $zip = [System.IO.Compression.ZipArchive]::new(
            $stream,
            [System.IO.Compression.ZipArchiveMode]::Update,
            $false
        )
        try {
            $oldEntry = $zip.GetEntry($LibmpvEntry)
            if ($null -eq $oldEntry) {
                throw "Expected JAR entry disappeared: $LibmpvEntry"
            }
            $oldEntry.Delete()

            $newEntry = $zip.CreateEntry(
                $LibmpvEntry,
                [System.IO.Compression.CompressionLevel]::Optimal
            )
            $entryStream = $newEntry.Open()
            try {
                $bytes = [System.IO.File]::ReadAllBytes($PatchDll)
                $entryStream.Write($bytes, 0, $bytes.Length)
            } finally {
                $entryStream.Dispose()
            }
        } finally {
            $zip.Dispose()
        }
    } finally {
        $stream.Dispose()
    }

    $verifyHash = Get-ZipEntryHash $tempJar $LibmpvEntry
    if ($verifyHash -ne $patchHash) {
        throw "Patched JAR verification failed. Expected $patchHash, got $verifyHash"
    }

    Copy-Item -LiteralPath $tempJar -Destination $jar -Force
} finally {
    Remove-Item -LiteralPath $tempJar -Force -ErrorAction SilentlyContinue
}

$finalHash = Get-ZipEntryHash $jar $LibmpvEntry
if ($finalHash -ne $patchHash) {
    Copy-Item -LiteralPath $backup -Destination $jar -Force
    throw "Final verification failed. Original JAR was restored automatically."
}

@(
    "PATCH=PlayTorrio-equivalent 2026-09-15 libmpv runtime A/B"
    "JAR=$jar"
    "BACKUP=$backup"
    "ORIGINAL_JAR_SHA256=$originalJarHash"
    "ORIGINAL_LIBMPV_SHA256=$currentLibmpvHash"
    "PATCH_LIBMPV_SHA256=$patchHash"
) | Set-Content -LiteralPath $StateFile -Encoding UTF8

Write-Host ""
Write-Host "LIBMPV RUNTIME A/B PATCH APPLIED OK" -ForegroundColor Green
Write-Host "JAR: $jar"
Write-Host "Backup: $backup"
Write-Host "Original libmpv SHA256: $currentLibmpvHash"
Write-Host "Patched libmpv SHA256 : $patchHash"
Write-Host ""
Write-Host "Start Nuvio and test the same SFilm3 series episode."
