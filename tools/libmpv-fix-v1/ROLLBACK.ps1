. "$PSScriptRoot\COMMON.ps1"
param([string]$JarPath)

$LocalStateFile = Join-Path $PSScriptRoot "PATCH-STATE.txt"

try {
    $running = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "Nuvio*" }
    if ($running) {
        throw "Nuvio is running. Close Nuvio completely before rollback."
    }

    $jar = $null
    $state = @{}

    if ($JarPath) {
        $jar = Find-NuvioJar $JarPath
        $state = Read-KeyValueFile (Get-JarSidecarStatePath $jar)
    } else {
        $state = Read-KeyValueFile $LocalStateFile
        if ($state.ContainsKey("JAR")) {
            $jar = $state["JAR"]
        }

        if (-not $jar -or -not (Test-Path -LiteralPath $jar -PathType Leaf)) {
            $jar = Find-NuvioJar $null
            $state = Read-KeyValueFile (Get-JarSidecarStatePath $jar)
        }
    }

    if (-not $jar -or -not (Test-Path -LiteralPath $jar -PathType Leaf)) {
        throw "Could not resolve the patched Nuvio JAR."
    }

    if (-not $state.ContainsKey("BACKUP")) {
        $state = Read-KeyValueFile (Get-JarSidecarStatePath $jar)
    }
    if (-not $state.ContainsKey("BACKUP")) {
        throw "Stable rollback state was not found. No file was changed."
    }

    $backup = $state["BACKUP"]
    if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) {
        throw "Rollback backup is missing: $backup"
    }

    $originalJarHash = $state["ORIGINAL_JAR_SHA256"]
    $patchedJarHash = $state["PATCHED_JAR_SHA256"]
    $currentJarHash = Get-Sha256 $jar

    if ($currentJarHash -eq $originalJarHash) {
        Write-Host ""
        Write-Host "ALREADY ROLLED BACK" -ForegroundColor Green
        Write-Host "The installed JAR already matches the original backup."
        exit 0
    }

    if ($currentJarHash -ne $patchedJarHash) {
        throw ("The installed Nuvio JAR changed after this patch was applied." +
            [Environment]::NewLine +
            "Current SHA256: $currentJarHash" +
            [Environment]::NewLine +
            "Expected patched SHA256: $patchedJarHash" +
            [Environment]::NewLine +
            "Rollback was refused to avoid replacing a newer Nuvio version with an older JAR.")
    }

    if ((Get-Sha256 $backup) -ne $originalJarHash) {
        throw "Rollback backup SHA256 verification failed."
    }

    Copy-Item -LiteralPath $backup -Destination $jar -Force

    if ((Get-Sha256 $jar) -ne $originalJarHash) {
        throw "Rollback copy verification failed."
    }

    $restoredLibmpvHash = Get-ZipEntryHash $jar $script:LibmpvEntry
    if ($restoredLibmpvHash -ne $script:KnownBadLibmpvSha256) {
        throw "Rollback restored an unexpected libmpv runtime."
    }

    Write-Host ""
    Write-Host "ROLLBACK OK" -ForegroundColor Green
    Write-Host "Original Nuvio JAR restored exactly."
    Write-Host "JAR: $jar"
    Write-Host "Backup retained: $backup"
} catch {
    Write-Host ""
    Write-Host "ROLLBACK FAILED - NO UNSAFE FALLBACK" -ForegroundColor Red
    Write-Host $_.Exception.Message
    Write-Host ""
    throw
}
