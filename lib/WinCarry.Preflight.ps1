function New-PreflightSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [switch]$OfflineSafe
    )

    return [ordered]@{
        createdAt = (Get-Date).ToString("o")
        toolName = $script:ToolName
        scriptPath = (Resolve-DisplayPath -Path (Get-CurrentScriptPath))
        offlineSafeMode = [bool]$OfflineSafe
        root = (Get-RootValidation -RootPath $RootPath)
        os = (Get-OperatingSystemInfo)
        user = (Get-CurrentUserInfo)
        admin = (Get-AdminStatus)
        drives = @(Get-FileSystemDrives)
        packageManagers = @(Get-PackageManagerStatus -OfflineSafe:$OfflineSafe)
    }
}

function Convert-PreflightSnapshotToMarkdown {
    param(
        [Parameter(Mandatory = $true)]
        $Snapshot
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# WinCarry Preflight Snapshot")
    $lines.Add("")
    $lines.Add(("Created: {0}" -f $Snapshot.createdAt))
    $lines.Add(("Script: {0}" -f $Snapshot.scriptPath))
    $lines.Add(("Offline-safe mode: {0}" -f $Snapshot.offlineSafeMode))
    $lines.Add("")
    $lines.Add("## Root")
    $lines.Add("")
    $lines.Add(("- Requested: {0}" -f $Snapshot.root.requestedRoot))
    $lines.Add(("- Resolved: {0}" -f $Snapshot.root.resolvedRoot))
    $lines.Add(("- Exists: {0}" -f $Snapshot.root.exists))
    $lines.Add(("- Has config folder: {0}" -f $Snapshot.root.hasConfig))
    $lines.Add(("- Has logs folder: {0}" -f $Snapshot.root.hasLogs))
    $lines.Add(("- Has reports folder: {0}" -f $Snapshot.root.hasReports))
    $lines.Add(("- Inside protected path: {0}" -f $Snapshot.root.insideProtectedPath))

    if ($Snapshot.root.warnings.Count -gt 0) {
        $lines.Add("")
        $lines.Add("Warnings:")
        foreach ($warning in $Snapshot.root.warnings) {
            $lines.Add(("- {0}" -f $warning))
        }
    }

    $lines.Add("")
    $lines.Add("## OS")
    $lines.Add("")
    $lines.Add(("- Caption: {0}" -f $Snapshot.os.caption))
    $lines.Add(("- Version: {0}" -f $Snapshot.os.version))
    $lines.Add(("- Architecture: {0}" -f $Snapshot.os.architecture))
    $lines.Add(("- Platform: {0}" -f $Snapshot.os.platform))

    $lines.Add("")
    $lines.Add("## User")
    $lines.Add("")
    $lines.Add(("- Machine: {0}" -f $Snapshot.user.machineName))
    $lines.Add(("- Domain: {0}" -f $Snapshot.user.domainName))
    $lines.Add(("- User: {0}" -f $Snapshot.user.userName))
    $lines.Add(("- Profile: {0}" -f $Snapshot.user.userProfile))
    $lines.Add(("- Raw profile: {0}" -f $Snapshot.user.rawUserProfile))
    $lines.Add(("- Profile uses short path: {0}" -f $Snapshot.user.profileUsesShortPath))

    $lines.Add("")
    $lines.Add("## Privilege")
    $lines.Add("")
    $lines.Add(("- Status: {0}" -f $Snapshot.admin.label))
    $lines.Add(("- Is admin/root: {0}" -f $Snapshot.admin.isAdmin))
    $lines.Add(("- Check: {0}" -f $Snapshot.admin.check))

    $lines.Add("")
    $lines.Add("## Drives")
    $lines.Add("")
    foreach ($drive in $Snapshot.drives) {
        $lines.Add(("- {0} ({1}) free {2} / total {3}" -f $drive.name, $drive.root, $drive.free, $drive.total))
    }

    $lines.Add("")
    $lines.Add("## Package Managers")
    $lines.Add("")
    foreach ($manager in $Snapshot.packageManagers) {
        if ($manager.available) {
            $versionText = $manager.version
            if ([string]::IsNullOrWhiteSpace($versionText)) {
                $versionText = "version unknown"
            }
            $lines.Add(("- {0}: available ({1}) at {2}" -f $manager.name, $versionText, $manager.source))
        } elseif ($manager.offlineSafeSkipped) {
            $lines.Add(("- {0}: skipped by offline-safe mode" -f $manager.name))
        } else {
            $lines.Add(("- {0}: not found" -f $manager.name))
        }
    }

    return ($lines -join [Environment]::NewLine)
}

function Show-PreflightSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        $Snapshot
    )

    Write-Host ""
    Write-Host "Preflight System Snapshot"
    Write-Host ""
    Write-Host ("Created: {0}" -f $Snapshot.createdAt)
    Write-Host ("Script: {0}" -f $Snapshot.scriptPath)
    Write-Host ("Offline-safe mode: {0}" -f $Snapshot.offlineSafeMode)
    Write-Host ""
    Write-Host "Root"
    Write-Host ("- Requested: {0}" -f $Snapshot.root.requestedRoot)
    Write-Host ("- Resolved: {0}" -f $Snapshot.root.resolvedRoot)
    Write-Host ("- Exists: {0}" -f $Snapshot.root.exists)
    Write-Host ("- Has logs folder: {0}" -f $Snapshot.root.hasLogs)
    Write-Host ("- Has reports folder: {0}" -f $Snapshot.root.hasReports)
    Write-Host ("- Inside protected path: {0}" -f $Snapshot.root.insideProtectedPath)

    foreach ($warning in $Snapshot.root.warnings) {
        Write-WarningText $warning
    }

    Write-Host ""
    Write-Host "OS"
    Write-Host ("- {0}" -f $Snapshot.os.caption)
    Write-Host ("- Version: {0}" -f $Snapshot.os.version)
    Write-Host ("- Architecture: {0}" -f $Snapshot.os.architecture)
    Write-Host ("- Platform: {0}" -f $Snapshot.os.platform)

    Write-Host ""
    Write-Host "User"
    Write-Host ("- Machine: {0}" -f $Snapshot.user.machineName)
    Write-Host ("- User: {0}\{1}" -f $Snapshot.user.domainName, $Snapshot.user.userName)
    Write-Host ("- Profile: {0}" -f $Snapshot.user.userProfile)
    if ($Snapshot.user.profileUsesShortPath) {
        Write-WarningText "User profile path contains a Windows short-name segment such as '~1'."
    }

    Write-Host ""
    Write-Host "Privilege"
    Write-Host ("- Status: {0}" -f $Snapshot.admin.label)
    Write-Host ("- Is admin/root: {0}" -f $Snapshot.admin.isAdmin)

    Write-Host ""
    Write-Host "Drives"
    foreach ($drive in $Snapshot.drives) {
        Write-Host ("- {0} ({1}) free {2} / total {3}" -f $drive.name, $drive.root, $drive.free, $drive.total)
    }

    Write-Host ""
    Write-Host "Package Managers"
    foreach ($manager in $Snapshot.packageManagers) {
        if ($manager.available) {
            $versionText = $manager.version
            if ([string]::IsNullOrWhiteSpace($versionText)) {
                $versionText = "version unknown"
            }
            Write-Host ("- {0}: available ({1})" -f $manager.name, $versionText)
        } elseif ($manager.offlineSafeSkipped) {
            Write-Host ("- {0}: skipped by offline-safe mode" -f $manager.name)
        } else {
            Write-Host ("- {0}: not found" -f $manager.name)
        }
    }
}

function Invoke-Preflight {
    param(
        [string]$RootPath,
        [switch]$DryRunOnly
    )

    if ([string]::IsNullOrWhiteSpace($RootPath)) {
        $RootPath = $script:DefaultRoot
    }

    $snapshot = New-PreflightSnapshot -RootPath $RootPath
    Show-PreflightSnapshot -Snapshot $snapshot

    $reportPath = Get-PreflightReportPath -RootPath $snapshot.root.resolvedRoot
    $logPath = Get-LogPath -RootPath $snapshot.root.resolvedRoot

    Write-Host ""
    if ($DryRunOnly) {
        Write-Info "Dry-run only. No report or log file was written."
        Write-Info ("Would write report if reports folder exists: {0}" -f $reportPath)
        Write-Info ("Would write log if logs folder exists: {0}" -f $logPath)
        return
    }

    $reportDirectory = Split-Path -Parent $reportPath
    if (Test-Path -LiteralPath $reportDirectory) {
        $markdown = Convert-PreflightSnapshotToMarkdown -Snapshot $snapshot
        Set-Content -LiteralPath $reportPath -Value $markdown -Encoding UTF8
        Write-Info ("Report written: {0}" -f $reportPath)
    } else {
        Write-WarningText ("Report not written because folder does not exist: {0}" -f $reportDirectory)
    }

    $logDirectory = Split-Path -Parent $logPath
    if (Test-Path -LiteralPath $logDirectory) {
        $message = "Preflight completed for root {0}; admin={1}; packageManagers={2}" -f $snapshot.root.resolvedRoot, $snapshot.admin.isAdmin, (($snapshot.packageManagers | ForEach-Object { "{0}:{1}" -f $_.name, $_.available }) -join ",")
        Write-WinCarryLog -RootPath $snapshot.root.resolvedRoot -Operation "preflight" -Result "success" -Message $message
        Write-Info ("Log updated: {0}" -f $logPath)
    } else {
        Write-WarningText ("Log not written because folder does not exist: {0}" -f $logDirectory)
    }
}

