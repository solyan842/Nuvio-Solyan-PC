param([string]$JarPath)
. "$PSScriptRoot\COMMON.ps1"

try {
    $jar = Find-NuvioJar $JarPath
    $libmpvHash = Get-ZipEntryHash $jar $script:LibmpvEntry
    $bridgeHash = Get-ZipEntryHash $jar $script:PlayerBridgeEntry
    $jarHash = Get-Sha256 $jar

    $state = "UNKNOWN"
    $detail = "Runtime hash is not recognized."

    if ($bridgeHash -eq $script:LegacyHeaderAbBridgeSha256) {
        $state = "OLD_AB_BRIDGE_ACTIVE"
        $detail = "Legacy header A/B is still active. Roll it back before using the stable fix."
    } elseif ($bridgeHash -eq $script:LegacyResumeAbBridgeSha256) {
        $state = "OLD_AB_BRIDGE_ACTIVE"
        $detail = "Legacy initial-resume A/B is still active. Roll it back before using the stable fix."
    } elseif ($libmpvHash -eq $script:FixedLibmpvSha256) {
        $state = "PATCHED"
        $detail = "Stable libmpv fix is present."
    } elseif ($libmpvHash -eq $script:KnownBadLibmpvSha256) {
        $state = "NEEDS_PATCH"
        $detail = "Nuvio is using the known Windows libmpv runtime that causes the SFilm3/VSMOV series bug."
    } else {
        $state = "UPSTREAM_CHANGED"
        $detail = "Nuvio now ships a different libmpv runtime. Do not overwrite it automatically; verify the new upstream runtime first."
    }

    $sidecar = Get-JarSidecarStatePath $jar
    $sidecarState = Read-KeyValueFile $sidecar
    $rollbackReady = $false
    if ($sidecarState.ContainsKey("BACKUP")) {
        $rollbackReady = Test-Path -LiteralPath $sidecarState["BACKUP"]
    } elseif ($libmpvHash -eq $script:FixedLibmpvSha256) {
        $legacyBackup = "$jar.solyan-sfilm3-libmpv-ab-original.bak"
        if (Test-Path -LiteralPath $legacyBackup) {
            $rollbackReady = (Get-ZipEntryHash $legacyBackup $script:LibmpvEntry) -eq $script:KnownBadLibmpvSha256
        }
    }

    Write-Host ""
    Write-Host "Nuvio-SolYan-PC libmpv Fix v$script:FixVersion" -ForegroundColor Cyan
    Write-Host "STATUS: $state" -ForegroundColor $(if ($state -eq "PATCHED") { "Green" } elseif ($state -eq "NEEDS_PATCH") { "Yellow" } else { "Magenta" })
    Write-Host $detail
    Write-Host ""
    Write-Host "JAR: $jar"
    Write-Host "JAR SHA256: $jarHash"
    Write-Host "libmpv SHA256: $libmpvHash"
    Write-Host "Rollback ready: $rollbackReady"
    Write-Host ""
} catch {
    Write-Host ""
    Write-Host "STATUS ERROR" -ForegroundColor Red
    Write-Host $_.Exception.Message
    Write-Host ""
    throw
}
