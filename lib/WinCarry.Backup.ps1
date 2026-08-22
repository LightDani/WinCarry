function Show-ConfigBackupPlan {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Candidates,

        [Parameter(Mandatory = $true)]
        [string]$BackupRootPath,

        [Parameter(Mandatory = $true)]
        [string]$ReportPath,

        [Parameter(Mandatory = $true)]
        [string]$MetadataPath
    )

    $safe = @($Candidates | Where-Object { [string](Get-MapValue -Map $_ -Key "type") -eq "safe" })
    $sensitive = @($Candidates | Where-Object { [string](Get-MapValue -Map $_ -Key "type") -eq "sensitive" })
    $detectOnly = @($Candidates | Where-Object { [string](Get-MapValue -Map $_ -Key "type") -eq "detect-only" })

    Write-Host ""
    Write-Host "Config Backup Plan"
    Write-Host ""
    Write-Host ("Backup root: {0}" -f $BackupRootPath)
    Write-Host ("Metadata: {0}" -f $MetadataPath)
    Write-Host ("Report: {0}" -f $ReportPath)
    Write-Host ""
    Write-Host ("Safe configs to back up: {0}" -f $safe.Count)
    foreach ($item in $safe) {
        Write-Host ("- {0}: {1}" -f (Get-MapValue -Map $item -Key "name"), (Get-MapValue -Map $item -Key "originalPath"))
    }
    Write-Host ""
    Write-Host ("Sensitive configs skipped by default: {0}" -f $sensitive.Count)
    foreach ($item in $sensitive) {
        Write-Host ("- {0}: {1}" -f (Get-MapValue -Map $item -Key "name"), (Get-MapValue -Map $item -Key "originalPath"))
        foreach ($warning in (ConvertTo-ArrayValue -Value (Get-MapValue -Map $item -Key "warnings"))) {
            Write-WarningText $warning
        }
    }
    Write-Host ""
    Write-Host ("Detect-only profiles: {0}" -f $detectOnly.Count)
    foreach ($item in $detectOnly) {
        Write-Host ("- {0}: {1}" -f (Get-MapValue -Map $item -Key "name"), (Get-MapValue -Map $item -Key "originalPath"))
    }
    Write-Host ""
    Write-Host "Folder copy exclusions: cache, logs, temp, tmp, crash, node_modules, *.log, *.tmp, *.cache"
}

function Invoke-Backup {
    param(
        [string]$RootPath,
        [switch]$DryRunOnly
    )

    if ([string]::IsNullOrWhiteSpace($RootPath)) {
        $RootPath = $script:DefaultRoot
    }

    $resolvedRoot = Resolve-DisplayPath -Path $RootPath
    $timestamp = Get-FileTimestamp
    $backupRoot = Get-ConfigBackupRootPath -RootPath $resolvedRoot -Timestamp $timestamp
    $configsRoot = Join-Path $backupRoot "configs"
    $metadataPath = Get-ConfigBackupMetadataPath -BackupRootPath $backupRoot
    $latestMetadataPath = Get-LatestConfigBackupMetadataPath -RootPath $resolvedRoot
    $reportPath = Get-ConfigBackupReportPath -RootPath $resolvedRoot -Timestamp $timestamp
    $logPath = Get-LogPath -RootPath $resolvedRoot
    $candidates = @(Get-DiscoveredConfigCandidates)

    Show-ConfigBackupPlan -Candidates $candidates -BackupRootPath $backupRoot -ReportPath $reportPath -MetadataPath $metadataPath

    if ($DryRunOnly) {
        Write-Host ""
        Write-Info "Dry-run only. No config backup, metadata, report, manifest, or log files were written."
        return
    }

    $sensitiveCandidates = @($candidates | Where-Object { [string](Get-MapValue -Map $_ -Key "type") -eq "sensitive" })
    $includeSensitive = $false
    if ($sensitiveCandidates.Count -gt 0) {
        Write-Host ""
        Write-WarningText "Sensitive configs were detected and will be skipped by default."
        Write-WarningText "They may contain private keys, access tokens, registry credentials, or environment secrets."
        $sensitiveAnswer = Read-Host "Type INCLUDE to back up sensitive configs, or press Enter to skip"
        $includeSensitive = ($sensitiveAnswer -eq "INCLUDE")
    }

    if (-not (Read-RequiredConfirmation -Prompt "Back up detected WinCarry config files?")) {
        Write-Host ""
        Write-Info "Config backup cancelled. No files were changed."
        return
    }

    foreach ($folder in @($backupRoot, $configsRoot, (Join-Path $resolvedRoot "reports"), (Join-Path $resolvedRoot "logs"), (Join-Path $resolvedRoot "backups"))) {
        if (-not (Test-Path -LiteralPath $folder)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
        }
    }

    $configRecords = @()
    $detectOnlyRecords = @()
    foreach ($candidate in $candidates) {
        $type = [string](Get-MapValue -Map $candidate -Key "type")
        if ($type -eq "detect-only") {
            $detectOnlyRecords += New-ConfigBackupRecord -Candidate $candidate -Status "detected_only"
            continue
        }

        if ($type -eq "sensitive" -and -not $includeSensitive) {
            $configRecords += New-ConfigBackupRecord -Candidate $candidate -Status "skipped_sensitive"
            continue
        }

        $copyResult = Copy-ConfigCandidate -Candidate $candidate -ConfigsRootPath $configsRoot -IncludeSensitive:$includeSensitive
        $configRecords += New-ConfigBackupRecord -Candidate $candidate -Status ([string]$copyResult.backupStatus) -BackupPath ([string]$copyResult.backupPath) -CopiedFiles ([int]$copyResult.copiedFiles) -SkippedFiles ([int]$copyResult.skippedFiles) -SkippedSensitiveFiles ([int]$copyResult.skippedSensitiveFiles) -ErrorMessage ([string]$copyResult.error)
    }

    $metadata = New-ConfigBackupMetadata -RootPath $resolvedRoot -BackupRootPath $backupRoot -ConfigRecords $configRecords -DetectOnlyRecords $detectOnlyRecords -IncludeSensitive $includeSensitive
    $metadataJson = $metadata | ConvertTo-Json -Depth 16
    Set-Content -LiteralPath $metadataPath -Value $metadataJson -Encoding UTF8
    Set-Content -LiteralPath $latestMetadataPath -Value $metadataJson -Encoding UTF8
    Set-Content -LiteralPath $reportPath -Value (Convert-ConfigBackupReportToMarkdown -Metadata $metadata) -Encoding UTF8

    $latestManifestPath = Get-LatestManifestPath -RootPath $resolvedRoot
    $manifestUpdated = $false
    if (Test-Path -LiteralPath $latestManifestPath) {
        try {
            $manifest = Get-Content -Raw -LiteralPath $latestManifestPath | ConvertFrom-Json
            Merge-ConfigBackupIntoManifest -Manifest $manifest -BackupMetadata $metadata
            Set-Content -LiteralPath $latestManifestPath -Value ($manifest | ConvertTo-Json -Depth 20) -Encoding UTF8
            $manifestUpdated = $true
        } catch {
            Write-WarningText ("Latest manifest was not updated: {0}" -f $_.Exception.Message)
        }
    } else {
        Write-WarningText ("Latest manifest not found, so config mappings were not added to a manifest yet: {0}" -f $latestManifestPath)
        Write-Info "Run manifest after backup to include the latest config backup metadata."
    }

    $message = "Config backup completed for root {0}; backedUp={1}; skippedSensitive={2}; failed={3}; detectOnly={4}; manifestUpdated={5}" -f $resolvedRoot, $metadata.summary.backedUp, $metadata.summary.skippedSensitive, $metadata.summary.failed, $metadata.summary.detectOnly, $manifestUpdated
    Write-WinCarryLog -RootPath $resolvedRoot -Operation "backup" -Result "success" -Message $message

    Write-Host ""
    Write-Info ("Config backup metadata written: {0}" -f $metadataPath)
    Write-Info ("Latest config backup metadata updated: {0}" -f $latestMetadataPath)
    Write-Info ("Backup report written: {0}" -f $reportPath)
    if ($manifestUpdated) {
        Write-Info ("Latest manifest updated with config paths: {0}" -f $latestManifestPath)
    }
    Write-Info ("Log updated: {0}" -f $logPath)
}


