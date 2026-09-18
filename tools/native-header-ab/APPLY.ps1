param([string]$JarPath)

$ErrorActionPreference = "Stop"
$EntryName = "native/windows/player_bridge.dll"
$PatchDll = Join-Path $PSScriptRoot "player_bridge.dll"
$StateFile = Join-Path $PSScriptRoot "PATCH-STATE.txt"

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
                ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "").ToLowerInvariant()
            } finally { $sha.Dispose() }
        } finally { $stream.Dispose() }
    } finally { $zip.Dispose() }
}

function Test-AppJar([string]$Path) {
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try {
            if ($null -eq $zip.GetEntry($EntryName)) { return $false }
            $signed = $zip.Entries | Where-Object { $_.FullName -match '^META-INF/.+\.(SF|RSA|DSA|EC)$' } | Select-Object -First 1
            if ($null -ne $signed) {
                throw "Application JAR appears signed ($($signed.FullName)); refusing to modify it."
            }
            return $true
        } finally { $zip.Dispose() }
    } catch {
        if ($_.Exception.Message -like "*appears signed*") { throw }
        return $false
    }
}

function Find-NuvioJar {
    if ($JarPath) {
        $resolved = (Resolve-Path -LiteralPath $JarPath).Path
        if (-not (Test-AppJar $resolved)) { throw "Specified JAR does not contain $EntryName : $resolved" }
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

    $programFiles = [Environment]::GetFolderPath("ProgramFiles")
    $programFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    if ($programFiles) { $roots.Add((Join-Path $programFiles "Nuvio")) }
    if ($programFilesX86) { $roots.Add((Join-Path $programFilesX86 "Nuvio")) }
    if ($env:LOCALAPPDATA) {
        $roots.Add((Join-Path $env:LOCALAPPDATA "Programs\Nuvio"))
        $roots.Add((Join-Path $env:LOCALAPPDATA "Nuvio"))
    }

    $candidates = [Collections.Generic.List[string]]::new()
    foreach ($root in ($roots | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -Recurse -File -Filter "*.jar" -ErrorAction SilentlyContinue |
            ForEach-Object { if (Test-AppJar $_.FullName) { $candidates.Add($_.FullName) } }
    }

    $unique = @($candidates | Select-Object -Unique)
    if ($unique.Count -eq 0) {
        throw "Could not find the installed Nuvio application JAR. Re-run APPLY.ps1 with -JarPath <full path to composeApp-desktop-*.jar>."
    }
    if ($unique.Count -gt 1) {
        throw ("More than one Nuvio application JAR was found. Re-run with -JarPath and choose one." + [Environment]::NewLine + ($unique -join [Environment]::NewLine))
    }
    $unique[0]
}

$running = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "Nuvio*" }
if ($running) { throw "Nuvio is running. Close Nuvio completely before applying this A/B patch." }
if (-not (Test-Path -LiteralPath $PatchDll)) { throw "Missing patch DLL: $PatchDll" }

$jar = Find-NuvioJar
$patchHash = Get-Sha256 $PatchDll
$currentEntryHash = Get-ZipEntryHash $jar $EntryName
if ($currentEntryHash -eq $patchHash) {
    Write-Host "Patch already applied." -ForegroundColor Green
    Write-Host "JAR: $jar"
    Write-Host "DLL SHA256: $patchHash"
    exit 0
}

$backup = "$jar.solyan-sfilm3-original.bak"
if (Test-Path -LiteralPath $backup) {
    throw ("Original backup already exists: $backup" + [Environment]::NewLine + "Refusing to overwrite the rollback copy.")
}

$originalJarHash = Get-Sha256 $jar
$originalEntryHash = $currentEntryHash
Copy-Item -LiteralPath $jar -Destination $backup -Force
if ((Get-Sha256 $backup) -ne $originalJarHash) { throw "Backup verification failed. No patch was applied." }

$tempJar = "$jar.solyan-sfilm3-patching.tmp"
Copy-Item -LiteralPath $jar -Destination $tempJar -Force
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $stream = [System.IO.File]::Open($tempJar, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    try {
        $zip = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Update, $false)
        try {
            $oldEntry = $zip.GetEntry($EntryName)
            if ($null -eq $oldEntry) { throw "Expected JAR entry disappeared: $EntryName" }
            $oldEntry.Delete()
            $newEntry = $zip.CreateEntry($EntryName, [System.IO.Compression.CompressionLevel]::Optimal)
            $entryStream = $newEntry.Open()
            try {
                $bytes = [System.IO.File]::ReadAllBytes($PatchDll)
                $entryStream.Write($bytes, 0, $bytes.Length)
            } finally { $entryStream.Dispose() }
        } finally { $zip.Dispose() }
    } finally { $stream.Dispose() }

    $verifyHash = Get-ZipEntryHash $tempJar $EntryName
    if ($verifyHash -ne $patchHash) { throw "Patched JAR verification failed. Expected $patchHash, got $verifyHash" }
    Copy-Item -LiteralPath $tempJar -Destination $jar -Force
} finally {
    Remove-Item -LiteralPath $tempJar -Force -ErrorAction SilentlyContinue
}

$finalHash = Get-ZipEntryHash $jar $EntryName
if ($finalHash -ne $patchHash) {
    Copy-Item -LiteralPath $backup -Destination $jar -Force
    throw "Final verification failed. Original JAR was restored automatically."
}

@(
    "PATCH=PlayTorrio-compatible Windows HTTP identity A/B"
    "JAR=$jar"
    "BACKUP=$backup"
    "ORIGINAL_JAR_SHA256=$originalJarHash"
    "ORIGINAL_PLAYER_BRIDGE_SHA256=$originalEntryHash"
    "PATCH_PLAYER_BRIDGE_SHA256=$patchHash"
) | Set-Content -LiteralPath $StateFile -Encoding UTF8

Write-Host ""
Write-Host "PATCH APPLIED OK" -ForegroundColor Green
Write-Host "JAR: $jar"
Write-Host "Backup: $backup"
Write-Host "Original bridge SHA256: $originalEntryHash"
Write-Host "Patched bridge SHA256 : $patchHash"
Write-Host ""
Write-Host "Start Nuvio and test one SFilm3 series episode. SFilm2 can be used as control."
