param([string]$JarPath)

$ErrorActionPreference = "Stop"
$EntryName = "native/windows/player_bridge.dll"
$StateFile = Join-Path $PSScriptRoot "PATCH-STATE.txt"

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

$running = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "Nuvio*" }
if ($running) { throw "Nuvio is running. Close Nuvio completely before rollback." }

$jar = $JarPath
if (-not $jar -and (Test-Path -LiteralPath $StateFile)) {
    $state = @{}
    Get-Content -LiteralPath $StateFile | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') { $state[$matches[1]] = $matches[2] }
    }
    $jar = $state["JAR"]
}
if (-not $jar) { throw "PATCH-STATE.txt is missing. Re-run ROLLBACK.ps1 with -JarPath <full path to composeApp-desktop-*.jar>." }

$jar = (Resolve-Path -LiteralPath $jar).Path
$backup = "$jar.solyan-sfilm3-original.bak"
if (-not (Test-Path -LiteralPath $backup)) { throw "Rollback backup not found: $backup" }

$backupHash = Get-ZipEntryHash $backup $EntryName
if (-not $backupHash) { throw "Backup JAR is invalid or does not contain $EntryName" }

Copy-Item -LiteralPath $backup -Destination $jar -Force
$restoredHash = Get-ZipEntryHash $jar $EntryName
if ($restoredHash -ne $backupHash) { throw "Rollback verification failed." }

Write-Host ""
Write-Host "ROLLBACK OK" -ForegroundColor Green
Write-Host "Restored JAR: $jar"
Write-Host "Restored player_bridge SHA256: $restoredHash"
Write-Host "Original backup retained at: $backup"
