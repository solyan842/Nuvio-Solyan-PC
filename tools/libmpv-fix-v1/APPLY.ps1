param([string]$JarPath)
. "$PSScriptRoot\COMMON.ps1"

$PatchDll = Join-Path $PSScriptRoot "libmpv-2.dll"
$LocalStateFile = Join-Path $PSScriptRoot "PATCH-STATE.txt"

try {
    $running = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "Nuvio*" }
    if ($running) {
        throw "Nuvio is running. Close Nuvio completely before applying the fix."
    }

    if (-not (Test-Path -LiteralPath $PatchDll -PathType Leaf)) {
        throw "Missing libmpv-2.dll next to APPLY.ps1"
    }

    $payloadHash = Get-Sha256 $PatchDll
    if ($payloadHash -ne $script:FixedLibmpvSha256) {
        throw "Patch payload SHA256 mismatch. Expected $script:FixedLibmpvSha256, got $payloadHash"
    }

    $jar = Find-NuvioJar $JarPath

    if (Test-JarSigned $jar) {
        throw "The installed Nuvio application JAR is signed. Refusing to modify it."
    }

    Assert-NoLegacyBridgePatch $jar

    $currentLibmpvHash = Get-ZipEntryHash $jar $script:LibmpvEntry
    $currentJarHash = Get-Sha256 $jar
    $sidecar = Get-JarSidecarStatePath $jar

    if ($currentLibmpvHash -eq $script:FixedLibmpvSha256) {
        $existingState = Read-KeyValueFile $sidecar
        if ($existingState.ContainsKey("BACKUP") -and (Test-Path -LiteralPath $existingState["BACKUP"])) {
            Write-Host ""
            Write-Host "ALREADY PATCHED" -ForegroundColor Green
            Write-Host "Stable fix is already present and rollback data is available."
            Write-Host "JAR: $jar"
            return
        }

        # Seamlessly adopt the successful legacy runtime A/B currently installed.
        $legacyBackup = "$jar.solyan-sfilm3-libmpv-ab-original.bak"
        if (Test-Path -LiteralPath $legacyBackup) {
            $legacyLibmpvHash = Get-ZipEntryHash $legacyBackup $script:LibmpvEntry
            if ($legacyLibmpvHash -eq $script:KnownBadLibmpvSha256) {
                $originalJarHash = Get-Sha256 $legacyBackup
                $stableBackup = Get-VersionedBackupPath $jar $originalJarHash

                if (-not (Test-Path -LiteralPath $stableBackup)) {
                    Copy-Item -LiteralPath $legacyBackup -Destination $stableBackup -Force
                }
                if ((Get-Sha256 $stableBackup) -ne $originalJarHash) {
                    throw "Could not verify migrated rollback backup."
                }

                Write-FixState $LocalStateFile $jar $stableBackup $originalJarHash $currentJarHash
                Write-FixState $sidecar $jar $stableBackup $originalJarHash $currentJarHash

                Write-Host ""
                Write-Host "PATCHED - STABLE STATE ADOPTED" -ForegroundColor Green
                Write-Host "The working runtime A/B has been adopted as Nuvio-SolYan-PC libmpv Fix v$script:FixVersion."
                Write-Host "No binary was changed during this adoption."
                Write-Host "Rollback backup: $stableBackup"
                return
            }
        }

        Write-Host ""
        Write-Host "ALREADY PATCHED" -ForegroundColor Green
        Write-Host "The fixed libmpv is present, but this package cannot prove where its rollback backup is."
        Write-Host "No changes were made."
        return
    }

    if ($currentLibmpvHash -ne $script:KnownBadLibmpvSha256) {
        Write-Host ""
        Write-Host "UPSTREAM RUNTIME CHANGED" -ForegroundColor Magenta
        Write-Host "Installed libmpv SHA256: $currentLibmpvHash"
        Write-Host "This is not the known bad Nuvio runtime, so the stable patch will NOT overwrite it."
        Write-Host "Verify the new Nuvio runtime before deciding whether any patch is still needed."
        return
    }

    $originalJarHash = $currentJarHash
    $backup = Get-VersionedBackupPath $jar $originalJarHash

    if (Test-Path -LiteralPath $backup) {
        if ((Get-Sha256 $backup) -ne $originalJarHash) {
            throw "Existing rollback backup has the wrong SHA256: $backup"
        }
        Write-Host "Reusing verified rollback backup: $backup"
    } else {
        Copy-Item -LiteralPath $jar -Destination $backup -Force
        if ((Get-Sha256 $backup) -ne $originalJarHash) {
            throw "Rollback backup verification failed. No patch was applied."
        }
    }

    $tempJar = "$jar.solyan-libmpv-fix-v1-patching.tmp"
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
                $oldEntry = $zip.GetEntry($script:LibmpvEntry)
                if ($null -eq $oldEntry) {
                    throw "Expected JAR entry disappeared: $script:LibmpvEntry"
                }
                $oldEntry.Delete()

                $newEntry = $zip.CreateEntry(
                    $script:LibmpvEntry,
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

        $verifyHash = Get-ZipEntryHash $tempJar $script:LibmpvEntry
        if ($verifyHash -ne $script:FixedLibmpvSha256) {
            throw "Patched JAR verification failed. Expected $script:FixedLibmpvSha256, got $verifyHash"
        }

        Copy-Item -LiteralPath $tempJar -Destination $jar -Force
    } finally {
        Remove-Item -LiteralPath $tempJar -Force -ErrorAction SilentlyContinue
    }

    $finalLibmpvHash = Get-ZipEntryHash $jar $script:LibmpvEntry
    if ($finalLibmpvHash -ne $script:FixedLibmpvSha256) {
        Copy-Item -LiteralPath $backup -Destination $jar -Force
        throw "Final verification failed. The original JAR was restored automatically."
    }

    $patchedJarHash = Get-Sha256 $jar
    Write-FixState $LocalStateFile $jar $backup $originalJarHash $patchedJarHash
    Write-FixState $sidecar $jar $backup $originalJarHash $patchedJarHash

    Write-Host ""
    Write-Host "PATCH APPLIED OK" -ForegroundColor Green
    Write-Host "Nuvio-SolYan-PC libmpv Fix v$script:FixVersion"
    Write-Host "JAR: $jar"
    Write-Host "Backup: $backup"
    Write-Host "Original libmpv: $script:KnownBadLibmpvSha256"
    Write-Host "Fixed libmpv   : $script:FixedLibmpvSha256"
    Write-Host ""
    Write-Host "Start Nuvio normally."
} catch {
    Write-Host ""
    Write-Host "PATCH FAILED - NO UNSAFE FALLBACK" -ForegroundColor Red
    Write-Host $_.Exception.Message
    Write-Host ""
    throw
}
