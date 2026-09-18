param([string]$JarPath)

$ErrorActionPreference = "Stop"
$LibmpvEntry = "native/windows/libmpv-2.dll"
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

$running = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "Nuvio*" }
if ($running) {
    throw "Nuvio is running. Close Nuvio completely before rollback."
}

$jar = $JarPath
if (-not $jar -and (Test-Path -LiteralPath $StateFile)) {
    $state = @{}
    Get-Content -LiteralPath $StateFile | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            $state[$matches[1]] = $matches[2]
        }
    }
    $jar = $state["JAR"]
}
if (-not $jar) {
    throw "PATCH-STATE.txt is missing. Re-run ROLLBACK.ps1 with -JarPath <full path to composeApp-desktop-*.jar>."
}

$jar = (Resolve-Path -LiteralPath $jar).Path
$backup = "$jar.solyan-sfilm3-libmpv-ab-original.bak"
if (-not (Test-Path -LiteralPath $backup)) {
    throw "Runtime A/B rollback backup not found: $backup"
}

$backupHash = Get-Sha256 $backup
$backupLibmpvHash = Get-ZipEntryHash $backup $LibmpvEntry
if (-not $backupLibmpvHash) {
    throw "Backup JAR is invalid or does not contain $LibmpvEntry"
}

Copy-Item -LiteralPath $backup -Destination $jar -Force
$restoredJarHash = Get-Sha256 $jar
$restoredLibmpvHash = Get-ZipEntryHash $jar $LibmpvEntry

if ($restoredJarHash -ne $backupHash -or $restoredLibmpvHash -ne $backupLibmpvHash) {
    throw "Rollback verification failed."
}

Write-Host ""
Write-Host "LIBMPV RUNTIME A/B ROLLBACK OK" -ForegroundColor Green
Write-Host "Restored JAR: $jar"
Write-Host "Restored libmpv SHA256: $restoredLibmpvHash"
Write-Host "Original backup retained at: $backup"
