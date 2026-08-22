function Show-OfflineSafeHeader {
    Write-Host ""
    Write-Host "Offline-Safe Mode"
    Write-Host ""
    Write-Host "This workflow skips package-manager scan/status commands and does not run package-manager install commands."
    Write-Host "It can still read local inventory sources, back up local configs, and generate manifests/reports."
}

function Invoke-OfflineManifestGeneration {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [switch]$DryRunOnly
    )

    $scan = New-AppScanSnapshot -RootPath $RootPath -OfflineSafe
    Show-AppScanSummary -Scan $scan

    $manifest = New-AppManifestFromScan -Scan $scan -OfflineSafe
    $timestamp = Get-FileTimestamp
    $paths = Get-ManifestArtifactPaths -RootPath $scan.root.resolvedRoot -Timestamp $timestamp
    Show-ManifestPlan -Manifest $manifest -Paths $paths -ActionLabel "Prepare Offline-Safe Manifest"
    Show-ManifestLauncherDependencyPlan -RootPath $scan.root.resolvedRoot

    if ($DryRunOnly) {
        Write-Host ""
        Write-Info "Dry-run only. No offline-safe manifest, restore script, launcher files, report, list, or log files were written."
        return
    }

    if (-not (Read-RequiredConfirmation -Prompt "Generate offline-safe manifest, restore scripts, and report files?")) {
        Write-Host ""
        Write-Info "Offline-safe manifest generation cancelled. No manifest or report files were written."
        return
    }

    Ensure-ManifestArtifactDirectories -RootPath $scan.root.resolvedRoot -IncludeRestoreScripts
    $launcherSync = Sync-WinCarryLauncherDependencies -RootPath $scan.root.resolvedRoot -Overwrite
    Write-ManifestArtifacts -Manifest $manifest -Paths $paths -IncludeManifestFiles

    $message = "Offline-safe manifest generated for root {0}; apps={1}; manual={2}; unsupported={3}; manifest={4}" -f $scan.root.resolvedRoot, $manifest.summary.appCount, $manifest.summary.manualReinstallCount, $manifest.summary.unsupportedCount, $paths.manifest
    Write-WinCarryLog -RootPath $scan.root.resolvedRoot -Operation "offline" -Result "success" -Message $message

    Write-Host ""
    Write-Info ("Offline-safe manifest written: {0}" -f $paths.manifest)
    Write-Info ("Latest manifest updated: {0}" -f $paths.latestManifest)
    Write-Info ("Restore script written: {0}" -f $paths.restoreScript)
    Write-Info ("Latest restore script updated: {0}" -f $paths.latestRestoreScript)
    if ($launcherSync.copied.Count -gt 0) {
        Write-Info ("Restore launcher dependencies synced: {0} file(s)" -f $launcherSync.copied.Count)
    } else {
        Write-Info "Restore launcher dependencies already current."
    }
    Write-Info ("Markdown report written: {0}" -f $paths.reportMarkdown)
    Write-Info ("Text report written: {0}" -f $paths.reportText)
    Write-Info ("Manual reinstall list written: {0}" -f $paths.manualReinstallList)
    Write-Info ("Unsupported list written: {0}" -f $paths.unsupportedList)
    Write-Info ("Log updated: {0}" -f (Get-LogPath -RootPath $scan.root.resolvedRoot))
}

function Invoke-Offline {
    param(
        [string]$RootPath,
        [switch]$DryRunOnly
    )

    if ([string]::IsNullOrWhiteSpace($RootPath)) {
        $RootPath = $script:DefaultRoot
    }

    $resolvedRoot = Resolve-DisplayPath -Path $RootPath
    Show-OfflineSafeHeader

    Write-Host ""
    Write-Host "Step 1: Config backup"
    Invoke-Backup -RootPath $resolvedRoot -DryRunOnly:$DryRunOnly

    Write-Host ""
    Write-Host "Step 2: Offline-safe scan, manifest, and reports"
    Invoke-OfflineManifestGeneration -RootPath $resolvedRoot -DryRunOnly:$DryRunOnly
}
