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
if ($running) { throw "Close Nuvio completely before rollback." }

$jar = $JarPath
if (-not $jar -and (Test-Path -LiteralPath $StateFile)) {
    $state = @{}
    Get-Content -LiteralPath $StateFile | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') { $state[$matches[1]] = $matches[2] }
    }
    $jar = $state["JAR"]
}
if (-not $jar) { throw "PATCH-STATE.txt missing. Use -JarPath." }

$jar = (Resolve-Path -LiteralPath $jar).Path
$backup = "$jar.solyan-sfilm3-resume-ab-original.bak"
if (-not (Test-Path -LiteralPath $backup)) { throw "Resume A/B backup not found: $backup" }

$backupEntryHash = Get-ZipEntryHash $backup $EntryName
if (-not $backupEntryHash) { throw "Backup JAR invalid." }

Copy-Item -LiteralPath $backup -Destination $jar -Force
if ((Get-ZipEntryHash $jar $EntryName) -ne $backupEntryHash) { throw "Rollback verification failed." }

Write-Host ""
Write-Host "RESUME A/B ROLLBACK OK" -ForegroundColor Green
Write-Host "Original JAR restored."
