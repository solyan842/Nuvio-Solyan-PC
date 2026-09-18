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
            try { ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "").ToLowerInvariant() }
            finally { $sha.Dispose() }
        } finally { $stream.Dispose() }
    } finally { $zip.Dispose() }
}

function Test-AppJar([string]$Path) {
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try { return $null -ne $zip.GetEntry($EntryName) }
        finally { $zip.Dispose() }
    } catch { return $false }
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
            ForEach-Object { if (Test-AppJar $_.FullName) { $candidates.Add($_.FullName) } }
    }

    $unique = @($candidates | Select-Object -Unique)
    if ($unique.Count -eq 0) { throw "Could not find installed Nuvio JAR. Use -JarPath." }
    if ($unique.Count -gt 1) { throw ("More than one Nuvio JAR found." + [Environment]::NewLine + ($unique -join [Environment]::NewLine)) }
    $unique[0]
}

$running = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "Nuvio*" }
if ($running) { throw "Close Nuvio completely before applying this A/B patch." }
if (-not (Test-Path -LiteralPath $PatchDll)) { throw "Missing player_bridge.dll next to APPLY.ps1" }

$jar = Find-NuvioJar
$currentJarHash = Get-Sha256 $jar

# Do not stack on top of the previous PlayTorrio-header A/B.
$oldHeaderBackup = "$jar.solyan-sfilm3-original.bak"
if (Test-Path -LiteralPath $oldHeaderBackup) {
    $oldOriginalHash = Get-Sha256 $oldHeaderBackup
    if ($currentJarHash -ne $oldOriginalHash) {
        throw "Previous SFilm3 header A/B appears to still be applied. Run its ROLLBACK.cmd first, then retry."
    }
}

$patchHash = Get-Sha256 $PatchDll
$currentEntryHash = Get-ZipEntryHash $jar $EntryName
if ($currentEntryHash -eq $patchHash) {
    Write-Host "Resume A/B patch already applied." -ForegroundColor Green
    exit 0
}

$backup = "$jar.solyan-sfilm3-resume-ab-original.bak"
if (Test-Path -LiteralPath $backup) {
    throw "Resume A/B backup already exists: $backup"
}

Copy-Item -LiteralPath $jar -Destination $backup -Force
if ((Get-Sha256 $backup) -ne $currentJarHash) { throw "Backup verification failed." }

$tempJar = "$jar.solyan-sfilm3-resume-ab.tmp"
Copy-Item -LiteralPath $jar -Destination $tempJar -Force
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $stream = [System.IO.File]::Open($tempJar, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    try {
        $zip = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Update, $false)
        try {
            $old = $zip.GetEntry($EntryName)
            if ($null -eq $old) { throw "Missing $EntryName" }
            $old.Delete()
            $new = $zip.CreateEntry($EntryName, [System.IO.Compression.CompressionLevel]::Optimal)
            $es = $new.Open()
            try {
                $bytes = [System.IO.File]::ReadAllBytes($PatchDll)
                $es.Write($bytes, 0, $bytes.Length)
            } finally { $es.Dispose() }
        } finally { $zip.Dispose() }
    } finally { $stream.Dispose() }

    if ((Get-ZipEntryHash $tempJar $EntryName) -ne $patchHash) { throw "Patched DLL verification failed." }
    Copy-Item -LiteralPath $tempJar -Destination $jar -Force
} finally {
    Remove-Item -LiteralPath $tempJar -Force -ErrorAction SilentlyContinue
}

if ((Get-ZipEntryHash $jar $EntryName) -ne $patchHash) {
    Copy-Item -LiteralPath $backup -Destination $jar -Force
    throw "Final verification failed. Original JAR restored."
}

@(
    "PATCH=Windows native initial resume disabled A/B"
    "JAR=$jar"
    "BACKUP=$backup"
    "ORIGINAL_JAR_SHA256=$currentJarHash"
    "PATCH_PLAYER_BRIDGE_SHA256=$patchHash"
) | Set-Content -LiteralPath $StateFile -Encoding UTF8

Write-Host ""
Write-Host "RESUME A/B PATCH APPLIED OK" -ForegroundColor Green
Write-Host "Now start Nuvio and test the same SFilm3 series episode."
