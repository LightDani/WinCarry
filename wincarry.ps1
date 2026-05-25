<# 
WinCarry - Windows reinstall preparation toolkit.

Current implemented scope:
- CLI entry point and interactive menu
- Setup command
- Folder structure creation
- Initial settings file
- Basic logging
- Dry-run and confirmation helpers
- Preflight system snapshot
- App detection scan with raw evidence, deduplication, and classification
- Manifest and report generation
- Config detection and safe backup
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command = "menu",

    [string]$Root,

    [switch]$DryRun
)

$script:ToolName = "WinCarry"
$script:DefaultRoot = "D:\WinCarry"
$script:SettingsFileName = "settings.json"
$script:ScriptFileName = "wincarry.ps1"
$script:ScriptPath = $PSCommandPath

if ([string]::IsNullOrWhiteSpace($script:ScriptPath) -and $MyInvocation.MyCommand.Path) {
    $script:ScriptPath = $MyInvocation.MyCommand.Path
}

if ([string]::IsNullOrWhiteSpace($script:ScriptPath)) {
    $script:ScriptDirectory = (Get-Location).Path
} else {
    $script:ScriptDirectory = Split-Path -Parent $script:ScriptPath
}

$script:SupportedCommands = @(
    "menu",
    "setup",
    "preflight",
    "scan",
    "backup",
    "manifest",
    "restore",
    "report",
    "offline",
    "junction",
    "help"
)

function Get-ScriptDirectory {
    return $script:ScriptDirectory
}

function Get-CurrentScriptPath {
    if (-not [string]::IsNullOrWhiteSpace($script:ScriptPath)) {
        return $script:ScriptPath
    }

    $scriptDirectory = Get-ScriptDirectory
    return (Join-Path $scriptDirectory $script:ScriptFileName)
}

function Get-Timestamp {
    return (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")
}

function Get-FileTimestamp {
    return (Get-Date).ToString("yyyy-MM-dd_HHmm")
}

function Test-IsWindows {
    return ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
}

function Write-Info {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host $Message
}

function Write-WarningText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host ("WARNING: " + $Message) -ForegroundColor Yellow
}

function Write-ErrorText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host ("ERROR: " + $Message) -ForegroundColor Red
}

function Read-RequiredConfirmation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt
    )

    Write-Host ""
    Write-WarningText "This operation changes files on disk."
    $answer = Read-Host ($Prompt + " Type YES to continue")
    return ($answer -eq "YES")
}

function Get-WinCarryFolders {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    return @(
        $RootPath,
        (Join-Path $RootPath "config"),
        (Join-Path $RootPath "apps"),
        (Join-Path (Join-Path $RootPath "apps") "manual"),
        (Join-Path $RootPath "portable"),
        (Join-Path $RootPath "scoop"),
        (Join-Path (Join-Path $RootPath "scoop") "apps"),
        (Join-Path (Join-Path $RootPath "scoop") "buckets"),
        (Join-Path (Join-Path $RootPath "scoop") "cache"),
        (Join-Path (Join-Path $RootPath "scoop") "persist"),
        (Join-Path (Join-Path $RootPath "scoop") "shims"),
        (Join-Path $RootPath "manifests"),
        (Join-Path $RootPath "backups"),
        (Join-Path $RootPath "restore-scripts"),
        (Join-Path $RootPath "reports"),
        (Join-Path $RootPath "logs")
    )
}

function Get-SettingsPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    return (Join-Path (Join-Path $RootPath "config") $script:SettingsFileName)
}

function Get-LogPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $logFileName = "wincarry-{0}.log" -f (Get-Date).ToString("yyyy-MM-dd")
    return (Join-Path (Join-Path $RootPath "logs") $logFileName)
}

function Get-PreflightReportPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $reportFileName = "preflight-{0}.md" -f (Get-FileTimestamp)
    return (Join-Path (Join-Path $RootPath "reports") $reportFileName)
}

function Get-ScanOutputPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $scanFileName = "raw-scan-{0}.json" -f (Get-FileTimestamp)
    return (Join-Path (Join-Path $RootPath "reports") $scanFileName)
}

function Get-ManifestPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$Timestamp
    )

    $manifestFileName = "{0}_manifest.json" -f $Timestamp
    return (Join-Path (Join-Path $RootPath "manifests") $manifestFileName)
}

function Get-LatestManifestPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    return (Join-Path (Join-Path $RootPath "manifests") "latest.json")
}

function Get-ScanReportPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$Timestamp,

        [Parameter(Mandatory = $true)]
        [ValidateSet("md", "txt")]
        [string]$Extension
    )

    $reportFileName = "scan-{0}.{1}" -f $Timestamp, $Extension
    return (Join-Path (Join-Path $RootPath "reports") $reportFileName)
}

function Get-ManualReinstallListPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$Timestamp
    )

    $fileName = "manual-reinstall-{0}.txt" -f $Timestamp
    return (Join-Path (Join-Path $RootPath "reports") $fileName)
}

function Get-UnsupportedListPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$Timestamp
    )

    $fileName = "unsupported-{0}.txt" -f $Timestamp
    return (Join-Path (Join-Path $RootPath "reports") $fileName)
}

function Get-ManifestArtifactPaths {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$Timestamp
    )

    return [ordered]@{
        manifest = (Get-ManifestPath -RootPath $RootPath -Timestamp $Timestamp)
        latestManifest = (Get-LatestManifestPath -RootPath $RootPath)
        reportMarkdown = (Get-ScanReportPath -RootPath $RootPath -Timestamp $Timestamp -Extension "md")
        reportText = (Get-ScanReportPath -RootPath $RootPath -Timestamp $Timestamp -Extension "txt")
        manualReinstallList = (Get-ManualReinstallListPath -RootPath $RootPath -Timestamp $Timestamp)
        unsupportedList = (Get-UnsupportedListPath -RootPath $RootPath -Timestamp $Timestamp)
    }
}

function Get-ConfigBackupRootPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$Timestamp
    )

    return (Join-Path (Join-Path $RootPath "backups") $Timestamp)
}

function Get-ConfigBackupMetadataPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupRootPath
    )

    return (Join-Path $BackupRootPath "config-backup.json")
}

function Get-LatestConfigBackupMetadataPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    return (Join-Path (Join-Path $RootPath "backups") "latest-config-backup.json")
}

function Get-ConfigBackupReportPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$Timestamp
    )

    $reportFileName = "backup-{0}.md" -f $Timestamp
    return (Join-Path (Join-Path $RootPath "reports") $reportFileName)
}

function Write-WinCarryLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$Operation,

        [Parameter(Mandatory = $true)]
        [string]$Result,

        [string]$Message = ""
    )

    $logDirectory = Join-Path $RootPath "logs"
    if (-not (Test-Path -LiteralPath $logDirectory)) {
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    }

    $logPath = Get-LogPath -RootPath $RootPath
    $line = "[{0}] operation={1}; result={2}; message={3}" -f (Get-Timestamp), $Operation, $Result, $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}

function New-DefaultSettings {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    return [ordered]@{
        schemaVersion = "1.0"
        toolName = $script:ToolName
        root = $RootPath
        language = "en"
        defaultRestoreVersionPolicy = "latest"
        offlineSafeMode = $false
        autoBackupSafeConfigs = $true
        sensitiveBackupDefault = "skip"
        createdAt = (Get-Date).ToString("o")
        compatibility = [ordered]@{
            target = "PowerShell on Windows"
            policy = "Prefer syntax and APIs compatible with built-in Windows PowerShell and newer PowerShell versions."
        }
        packageManagerPreference = [ordered]@{
            devTools = @("scoop", "winget", "chocolatey")
            desktopApps = @("winget", "chocolatey", "scoop")
        }
        protectedPaths = @(
            "C:\Windows",
            "C:\Program Files",
            "C:\Program Files (x86)",
            "C:\ProgramData\Microsoft",
            "%LOCALAPPDATA%\Microsoft",
            "%APPDATA%\Microsoft"
        )
    }
}

function Resolve-DisplayPath {
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)

    try {
        if (Test-Path -LiteralPath $expanded) {
            $resolved = Resolve-Path -LiteralPath $expanded -ErrorAction Stop
            if ($resolved -and $resolved.Path) {
                return $resolved.Path
            }
        }
    } catch {
        # Fall back to .NET path normalization below.
    }

    try {
        return [System.IO.Path]::GetFullPath($expanded)
    } catch {
        return $expanded
    }
}

function Test-ContainsWindowsShortPathSegment {
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    return ($Path -match "~[0-9]")
}

function Convert-BytesToReadableSize {
    param(
        [Nullable[Int64]]$Bytes
    )

    if ($null -eq $Bytes) {
        return "unknown"
    }

    $size = [double]$Bytes
    $units = @("B", "KB", "MB", "GB", "TB")
    $index = 0

    while (($size -ge 1024) -and ($index -lt ($units.Count - 1))) {
        $size = $size / 1024
        $index++
    }

    return ("{0:N1} {1}" -f $size, $units[$index])
}

function Get-AdminStatus {
    if (Test-IsWindows) {
        try {
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = New-Object Security.Principal.WindowsPrincipal($identity)
            $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            return [ordered]@{
                isAdmin = $isAdmin
                label = $(if ($isAdmin) { "Administrator" } else { "Standard user" })
                check = "WindowsPrincipal"
            }
        } catch {
            return [ordered]@{
                isAdmin = $false
                label = "Unknown"
                check = "WindowsPrincipal failed: $($_.Exception.Message)"
            }
        }
    }

    $isRoot = ([Environment]::UserName -eq "root")
    return [ordered]@{
        isAdmin = $isRoot
        label = $(if ($isRoot) { "root" } else { "non-root" })
        check = "Non-Windows user check"
    }
}

function Get-OperatingSystemInfo {
    $caption = [System.Environment]::OSVersion.VersionString
    $version = [System.Environment]::OSVersion.Version.ToString()
    $architecture = $(if ([Environment]::Is64BitOperatingSystem) { "64-bit" } else { "32-bit" })

    if (Test-IsWindows) {
        try {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            if ($os.Caption) {
                $caption = $os.Caption
            }
            if ($os.Version) {
                $version = $os.Version
            }
        } catch {
            # Keep the .NET fallback values.
        }
    }

    return [ordered]@{
        caption = $caption
        version = $version
        architecture = $architecture
        platform = [System.Environment]::OSVersion.Platform.ToString()
    }
}

function Get-CurrentUserInfo {
    $profile = $env:USERPROFILE
    if ([string]::IsNullOrWhiteSpace($profile)) {
        $profile = $env:HOME
    }

    return [ordered]@{
        userName = [Environment]::UserName
        domainName = [Environment]::UserDomainName
        machineName = [Environment]::MachineName
        userProfile = (Resolve-DisplayPath -Path $profile)
        rawUserProfile = $profile
        profileUsesShortPath = (Test-ContainsWindowsShortPathSegment -Path $profile)
    }
}

function Get-FileSystemDrives {
    $drives = @()

    foreach ($drive in (Get-PSDrive -PSProvider FileSystem)) {
        $used = $null
        $free = $null
        $total = $null

        if ($null -ne $drive.Used) {
            $used = [Int64]$drive.Used
        }
        if ($null -ne $drive.Free) {
            $free = [Int64]$drive.Free
        }
        if (($null -ne $used) -and ($null -ne $free)) {
            $total = $used + $free
        }

        $drives += [ordered]@{
            name = $drive.Name
            root = $drive.Root
            provider = $drive.Provider.Name
            usedBytes = $used
            freeBytes = $free
            totalBytes = $total
            used = (Convert-BytesToReadableSize -Bytes $used)
            free = (Convert-BytesToReadableSize -Bytes $free)
            total = (Convert-BytesToReadableSize -Bytes $total)
        }
    }

    return $drives
}

function Get-CommandVersionText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandPath,

        [string[]]$Arguments = @("--version")
    )

    try {
        $output = & $CommandPath @Arguments 2>$null
        if ($null -eq $output) {
            return ""
        }

        $line = @($output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
        if ($line.Count -gt 0) {
            return [string]$line[0]
        }

        return ""
    } catch {
        return ""
    }
}

function Get-PackageManagerStatus {
    $definitions = @(
        [ordered]@{ name = "winget"; command = "winget"; versionArgs = @("--version") },
        [ordered]@{ name = "chocolatey"; command = "choco"; versionArgs = @("--version") },
        [ordered]@{ name = "scoop"; command = "scoop"; versionArgs = @("--version") }
    )

    $results = @()

    foreach ($definition in $definitions) {
        $command = Get-Command $definition.command -ErrorAction SilentlyContinue
        $available = ($null -ne $command)
        $version = ""
        $source = ""

        if ($available) {
            $source = $command.Source
            $version = Get-CommandVersionText -CommandPath $command.Source -Arguments $definition.versionArgs
        }

        $results += [ordered]@{
            name = $definition.name
            command = $definition.command
            available = $available
            version = $version
            source = $source
        }
    }

    return $results
}

function Get-ProtectedPaths {
    return @(
        "C:\Windows",
        "C:\Program Files",
        "C:\Program Files (x86)",
        "C:\ProgramData\Microsoft",
        "%LOCALAPPDATA%\Microsoft",
        "%APPDATA%\Microsoft"
    )
}

function Test-PathInsideProtectedPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string[]]$ProtectedPaths
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    $normalizedPath = (Resolve-DisplayPath -Path $Path).TrimEnd("\", "/")

    foreach ($protectedPath in $ProtectedPaths) {
        $expandedProtectedPath = (Resolve-DisplayPath -Path $protectedPath).TrimEnd("\", "/")
        if ([string]::IsNullOrWhiteSpace($expandedProtectedPath)) {
            continue
        }

        if (Test-IsWindows) {
            if ($normalizedPath.StartsWith($expandedProtectedPath, [StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        } else {
            if ($normalizedPath.StartsWith($expandedProtectedPath, [StringComparison]::Ordinal)) {
                return $true
            }
        }
    }

    return $false
}

function Get-RootValidation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $resolvedRoot = Resolve-DisplayPath -Path $RootPath
    $protectedPaths = Get-ProtectedPaths
    $exists = Test-Path -LiteralPath $resolvedRoot
    $hasConfig = Test-Path -LiteralPath (Join-Path $resolvedRoot "config")
    $hasLogs = Test-Path -LiteralPath (Join-Path $resolvedRoot "logs")
    $hasReports = Test-Path -LiteralPath (Join-Path $resolvedRoot "reports")
    $insideProtectedPath = Test-PathInsideProtectedPath -Path $resolvedRoot -ProtectedPaths $protectedPaths
    $warnings = @()

    if (-not $exists) {
        $warnings += "Root does not exist yet. Run setup before expecting report/log output."
    }
    if ($insideProtectedPath) {
        $warnings += "Root appears to be inside a protected path. Choose a user-controlled drive/folder."
    }
    if (Test-ContainsWindowsShortPathSegment -Path $resolvedRoot) {
        $warnings += "Root path contains a Windows short-name segment such as '~1'. This is usually safe, but display may differ from Explorer."
    }

    return [ordered]@{
        requestedRoot = $RootPath
        resolvedRoot = $resolvedRoot
        exists = $exists
        hasConfig = $hasConfig
        hasLogs = $hasLogs
        hasReports = $hasReports
        insideProtectedPath = $insideProtectedPath
        protectedPaths = $protectedPaths
        warnings = $warnings
    }
}

function New-PreflightSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    return [ordered]@{
        createdAt = (Get-Date).ToString("o")
        toolName = $script:ToolName
        scriptPath = (Resolve-DisplayPath -Path (Get-CurrentScriptPath))
        root = (Get-RootValidation -RootPath $RootPath)
        os = (Get-OperatingSystemInfo)
        user = (Get-CurrentUserInfo)
        admin = (Get-AdminStatus)
        drives = @(Get-FileSystemDrives)
        packageManagers = @(Get-PackageManagerStatus)
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

function Invoke-ExternalCommandCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [string[]]$Arguments = @()
    )

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        return [ordered]@{
            available = $false
            command = $CommandName
            arguments = @($Arguments)
            source = ""
            exitCode = $null
            lines = @()
            error = "Command not found."
        }
    }

    try {
        $output = & $command.Source @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        $lines = @($output | ForEach-Object { [string]$_ })

        return [ordered]@{
            available = $true
            command = $CommandName
            arguments = @($Arguments)
            source = $command.Source
            exitCode = $exitCode
            lines = $lines
            error = ""
        }
    } catch {
        return [ordered]@{
            available = $true
            command = $CommandName
            arguments = @($Arguments)
            source = $command.Source
            exitCode = $LASTEXITCODE
            lines = @()
            error = $_.Exception.Message
        }
    }
}

function Convert-FixedWidthTable {
    param(
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines = @(),

        [Parameter(Mandatory = $true)]
        [string[]]$ColumnNames,

        [Parameter(Mandatory = $true)]
        [string[]]$RequiredColumnNames
    )

    if ($null -eq $Lines -or $Lines.Count -eq 0) {
        return @()
    }

    $headerIndex = -1
    $header = ""

    for ($index = 0; $index -lt $Lines.Count; $index++) {
        $candidate = $Lines[$index]
        $hasRequiredColumns = $true

        foreach ($requiredColumn in $RequiredColumnNames) {
            if ($candidate.IndexOf($requiredColumn, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
                $hasRequiredColumns = $false
                break
            }
        }

        if ($hasRequiredColumns) {
            $headerIndex = $index
            $header = $candidate
            break
        }
    }

    if ($headerIndex -lt 0) {
        return @()
    }

    $columns = @()
    foreach ($columnName in $ColumnNames) {
        $start = $header.IndexOf($columnName, [StringComparison]::OrdinalIgnoreCase)
        if ($start -ge 0) {
            $columns += [pscustomobject]@{
                name = $columnName
                start = [int]$start
                end = $null
            }
        }
    }

    $columns = @($columns | Sort-Object -Property @{ Expression = { [int]$_.start } }, @{ Expression = { [string]$_.name } })
    for ($index = 0; $index -lt $columns.Count; $index++) {
        $columns[$index].end = $null
        for ($nextIndex = $index + 1; $nextIndex -lt $columns.Count; $nextIndex++) {
            if ([int]$columns[$nextIndex].start -gt [int]$columns[$index].start) {
                $columns[$index].end = [int]$columns[$nextIndex].start
                break
            }
        }
    }

    $rows = @()
    for ($index = $headerIndex + 1; $index -lt $Lines.Count; $index++) {
        $line = $Lines[$index]
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $trimmed = $line.Trim()
        if ($trimmed -match "^[-\s]+$") {
            continue
        }
        if ($trimmed -match "^\S+\s+\d+%$") {
            continue
        }
        if ($trimmed -match "No installed package") {
            continue
        }

        $row = [ordered]@{}
        foreach ($column in $columns) {
            $columnStart = [int]$column.start
            $columnEnd = $column.end

            if ($columnStart -lt 0 -or $line.Length -le $columnStart) {
                $value = ""
            } else {
                if ($null -ne $columnEnd -and [int]$columnEnd -gt $columnStart) {
                    $safeEnd = [Math]::Min([int]$columnEnd, [int]$line.Length)
                    $length = $safeEnd - $columnStart
                } else {
                    $length = 0
                }

                if ($length -gt 0) {
                    $value = $line.Substring($columnStart, $length).Trim()
                } else {
                    $value = $line.Substring($columnStart).Trim()
                }
            }

            $row[$column.name] = $value
        }

        $hasRequiredValues = $true
        foreach ($requiredColumn in $RequiredColumnNames) {
            if (-not $row.Contains($requiredColumn) -or [string]::IsNullOrWhiteSpace($row[$requiredColumn])) {
                $hasRequiredValues = $false
                break
            }
        }

        if ($hasRequiredValues) {
            $rows += $row
        }
    }

    return $rows
}

function Convert-WingetListFallbackTable {
    param(
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines = @()
    )

    if ($null -eq $Lines -or $Lines.Count -eq 0) {
        return @()
    }

    $rows = @()
    $seenSeparator = $false

    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $trimmed = $line.Trim()
        if ($trimmed -match "^[-\s]+$") {
            $seenSeparator = $true
            continue
        }
        if ($trimmed -match "^\S+\s+\d+%$") {
            continue
        }
        if ($trimmed -match "No installed package") {
            continue
        }

        $parts = @($trimmed -split "\s{2,}" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($parts.Count -lt 2) {
            continue
        }

        if ($parts[1] -ieq "Id") {
            continue
        }
        if ((-not $seenSeparator) -and ($parts[0] -match "^(Name|Nama)$")) {
            continue
        }

        $name = $parts[0].Trim()
        $packageId = $parts[1].Trim()
        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($packageId)) {
            continue
        }

        $version = ""
        $available = ""
        $source = ""

        if ($parts.Count -ge 3) {
            $version = $parts[2].Trim()
        }
        if ($parts.Count -eq 4) {
            if ($parts[3] -match "^(winget|msstore)$") {
                $source = $parts[3].Trim()
            } else {
                $available = $parts[3].Trim()
            }
        }
        if ($parts.Count -ge 5) {
            $available = $parts[3].Trim()
            $source = $parts[4].Trim()
        }

        $rows += [ordered]@{
            Name = $name
            Id = $packageId
            Version = $version
            Available = $available
            Source = $source
        }
    }

    return $rows
}

function Get-CommandOutputSample {
    param(
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines = @(),

        [int]$Limit = 5
    )

    $sample = @()
    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $trimmed = $line.Trim()
        if ($trimmed.Length -gt 160) {
            $trimmed = $trimmed.Substring(0, 160) + "..."
        }

        $sample += $trimmed
        if ($sample.Count -ge $Limit) {
            break
        }
    }

    return $sample
}

function Convert-WingetCaptureToRows {
    param(
        [Parameter(Mandatory = $true)]
        $Capture
    )

    $warnings = @()
    $argumentText = (($Capture.arguments | ForEach-Object { [string]$_ }) -join " ").Trim()
    if ([string]::IsNullOrWhiteSpace($argumentText)) {
        $argumentText = "<none>"
    }

    if (-not [string]::IsNullOrWhiteSpace($Capture.error)) {
        $warnings += ("winget {0} failed: {1}" -f $argumentText, $Capture.error)
    }

    if (($null -ne $Capture.exitCode) -and ($Capture.exitCode -ne 0)) {
        $warnings += ("winget {0} exited with code {1}." -f $argumentText, $Capture.exitCode)
    }

    $rows = @(Convert-FixedWidthTable -Lines $Capture.lines -ColumnNames @("Name", "Id", "Version", "Available", "Source") -RequiredColumnNames @("Name", "Id"))
    $parser = "fixed-width"
    if ($rows.Count -eq 0) {
        $rows = @(Convert-WingetListFallbackTable -Lines $Capture.lines)
        $parser = "whitespace-fallback"
    }

    return [ordered]@{
        rows = $rows
        parser = $parser
        warnings = $warnings
        outputSample = @(Get-CommandOutputSample -Lines $Capture.lines)
        argumentText = $argumentText
    }
}

function New-ScanEvidenceRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$EvidenceType,

        [Parameter(Mandatory = $true)]
        $Data
    )

    return [ordered]@{
        source = $Source
        evidenceType = $EvidenceType
        detectedAt = (Get-Date).ToString("o")
        data = $Data
    }
}

function Get-MapValue {
    param(
        $Map,
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if ($null -eq $Map) {
        return ""
    }

    if ($Map -is [System.Collections.IDictionary]) {
        if ($Map.Contains($Key)) {
            return $Map[$Key]
        }

        return ""
    }

    $property = $Map.PSObject.Properties[$Key]
    if ($null -ne $property) {
        return $property.Value
    }

    return ""
}

function Add-UniqueValue {
    param(
        [object[]]$Values,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @($Values)
    }

    $existing = @($Values | Where-Object { $_ -eq $Value })
    if ($existing.Count -gt 0) {
        return @($Values)
    }

    return @($Values + $Value)
}

function Normalize-Whitespace {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    return (($Text.Trim() -replace "\s+", " "))
}

function Get-NormalizedName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return ""
    }

    $normalized = $Name.ToLowerInvariant()
    $normalized = $normalized -replace "\(.*?\)", " "
    $normalized = $normalized -replace "\b(x64|x86|64-bit|32-bit|user|machine|en-us|id-id)\b", " "
    $normalized = $normalized -replace "[^a-z0-9]+", " "
    return (Normalize-Whitespace -Text $normalized)
}

function Get-NameTokens {
    param([string]$Name)

    $normalized = Get-NormalizedName -Name $Name
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return @()
    }

    $stopWords = @("the", "inc", "llc", "ltd", "corp", "corporation", "company", "co", "microsoft")
    return @($normalized.Split(" ") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $stopWords -notcontains $_ })
}

function Test-StrongNameMatch {
    param(
        [string]$Left,
        [string]$Right
    )

    $leftNormalized = Get-NormalizedName -Name $Left
    $rightNormalized = Get-NormalizedName -Name $Right
    if ([string]::IsNullOrWhiteSpace($leftNormalized) -or [string]::IsNullOrWhiteSpace($rightNormalized)) {
        return $false
    }

    if ($leftNormalized -eq $rightNormalized) {
        return $true
    }

    $leftTokens = @(Get-NameTokens -Name $Left)
    $rightTokens = @(Get-NameTokens -Name $Right)
    if ($leftTokens.Count -eq 0 -or $rightTokens.Count -eq 0) {
        return $false
    }

    if ($leftTokens.Count -eq 1 -and $rightTokens.Count -eq 1) {
        return ($leftTokens[0] -eq $rightTokens[0])
    }

    $smaller = $leftTokens
    $larger = $rightTokens
    if ($rightTokens.Count -lt $leftTokens.Count) {
        $smaller = $rightTokens
        $larger = $leftTokens
    }

    if ($smaller.Count -lt 2) {
        return $false
    }

    foreach ($token in $smaller) {
        if ($larger -notcontains $token) {
            return $false
        }
    }

    return $true
}

function Get-NormalizedPublisher {
    param([string]$Publisher)

    $normalized = Get-NormalizedName -Name $Publisher
    $normalized = $normalized -replace "\b(inc|llc|ltd|corp|corporation|company|co)\b", " "
    return (Normalize-Whitespace -Text $normalized)
}

function Get-NormalizedPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }

    $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    $normalized = $expanded.Replace("/", "\").TrimEnd("\")
    return $normalized.ToLowerInvariant()
}

function Get-ExecutableNameFromPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }

    try {
        return ([System.IO.Path]::GetFileNameWithoutExtension($Path)).ToLowerInvariant()
    } catch {
        return ""
    }
}

function Test-PathRelationship {
    param(
        [string]$LeftPath,
        [string]$RightPath
    )

    $left = Get-NormalizedPath -Path $LeftPath
    $right = Get-NormalizedPath -Path $RightPath
    if ([string]::IsNullOrWhiteSpace($left) -or [string]::IsNullOrWhiteSpace($right)) {
        return $false
    }

    if ($left -eq $right) {
        return $true
    }

    return ($left.StartsWith($right + "\") -or $right.StartsWith($left + "\"))
}

function Get-NormalizedPackageId {
    param([string]$PackageId)

    if ([string]::IsNullOrWhiteSpace($PackageId)) {
        return ""
    }

    return (($PackageId.Trim()).ToLowerInvariant())
}

function Get-ShortHash {
    param([string]$Text)

    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hashBytes = $sha1.ComputeHash($bytes)
        $hash = (($hashBytes | ForEach-Object { $_.ToString("x2") }) -join "")
        return $hash.Substring(0, 8)
    } finally {
        $sha1.Dispose()
    }
}

function New-StableAppId {
    param(
        [string]$Name,
        [string]$Publisher,
        [string]$PackageId,
        [string]$RegistryPath
    )

    $basis = ("{0}|{1}|{2}|{3}" -f $Name, $Publisher, $PackageId, $RegistryPath)
    $slug = (Get-NormalizedName -Name $Name) -replace "\s+", "-"
    if ([string]::IsNullOrWhiteSpace($slug)) {
        $slug = "unknown-app"
    }
    if ($slug.Length -gt 48) {
        $slug = $slug.Substring(0, 48).TrimEnd("-")
    }

    return ("app-{0}-{1}" -f $slug, (Get-ShortHash -Text $basis))
}

function Convert-EvidenceToAppCandidate {
    param(
        [Parameter(Mandatory = $true)]
        $Record,

        [Parameter(Mandatory = $true)]
        [int]$EvidenceIndex
    )

    $data = $Record.data
    $candidate = [ordered]@{
        source = [string]$Record.source
        evidenceType = [string]$Record.evidenceType
        evidenceIndex = $EvidenceIndex
        name = ""
        publisher = ""
        version = ""
        installLocation = ""
        executablePath = ""
        workingDirectory = ""
        packageManager = ""
        packageId = ""
        packageSource = ""
        registryPath = ""
        systemComponent = ""
        parentLabel = ""
        normalizedName = ""
        normalizedPublisher = ""
        normalizedInstallLocation = ""
        normalizedExecutablePath = ""
        normalizedPackageId = ""
        executableName = ""
    }

    switch ([string]$Record.source) {
        "registry" {
            $candidate.name = [string](Get-MapValue -Map $data -Key "displayName")
            $candidate.publisher = [string](Get-MapValue -Map $data -Key "publisher")
            $candidate.version = [string](Get-MapValue -Map $data -Key "displayVersion")
            $candidate.installLocation = [string](Get-MapValue -Map $data -Key "installLocation")
            $candidate.registryPath = [string](Get-MapValue -Map $data -Key "registryPath")
            $candidate.systemComponent = [string](Get-MapValue -Map $data -Key "systemComponent")
        }
        "winget" {
            $candidate.name = [string](Get-MapValue -Map $data -Key "name")
            $candidate.version = [string](Get-MapValue -Map $data -Key "version")
            $candidate.packageManager = "winget"
            $candidate.packageId = [string](Get-MapValue -Map $data -Key "packageId")
            $candidate.packageSource = [string](Get-MapValue -Map $data -Key "source")
        }
        "chocolatey" {
            $candidate.name = [string](Get-MapValue -Map $data -Key "packageName")
            $candidate.version = [string](Get-MapValue -Map $data -Key "version")
            $candidate.packageManager = "chocolatey"
            $candidate.packageId = [string](Get-MapValue -Map $data -Key "packageName")
        }
        "scoop" {
            $candidate.name = [string](Get-MapValue -Map $data -Key "name")
            $candidate.version = [string](Get-MapValue -Map $data -Key "version")
            $candidate.packageManager = "scoop"
            $candidate.packageId = [string](Get-MapValue -Map $data -Key "name")
            $candidate.packageSource = [string](Get-MapValue -Map $data -Key "bucket")
        }
        "startMenu" {
            $candidate.name = [string](Get-MapValue -Map $data -Key "name")
            $candidate.executablePath = [string](Get-MapValue -Map $data -Key "targetPath")
            $candidate.workingDirectory = [string](Get-MapValue -Map $data -Key "workingDirectory")
        }
        "knownFolder" {
            $candidate.name = [string](Get-MapValue -Map $data -Key "name")
            $candidate.installLocation = [string](Get-MapValue -Map $data -Key "path")
            $candidate.parentLabel = [string](Get-MapValue -Map $data -Key "parentLabel")
        }
    }

    $candidate.normalizedName = Get-NormalizedName -Name $candidate.name
    $candidate.normalizedPublisher = Get-NormalizedPublisher -Publisher $candidate.publisher
    $candidate.normalizedInstallLocation = Get-NormalizedPath -Path $candidate.installLocation
    $candidate.normalizedExecutablePath = Get-NormalizedPath -Path $candidate.executablePath
    $candidate.normalizedPackageId = Get-NormalizedPackageId -PackageId $candidate.packageId
    $candidate.executableName = Get-ExecutableNameFromPath -Path $candidate.executablePath

    if ([string]::IsNullOrWhiteSpace($candidate.name)) {
        return $null
    }

    return $candidate
}

function New-LogicalAppFromCandidate {
    param(
        [Parameter(Mandatory = $true)]
        $Candidate
    )

    $id = New-StableAppId -Name $Candidate.name -Publisher $Candidate.publisher -PackageId $Candidate.packageId -RegistryPath $Candidate.registryPath
    return [ordered]@{
        id = $id
        name = [string]$Candidate.name
        publisher = [string]$Candidate.publisher
        versionDetected = [string]$Candidate.version
        installLocation = [string]$Candidate.installLocation
        executablePath = [string]$Candidate.executablePath
        sources = @()
        package = $null
        packages = @()
        classification = "Unknown"
        restoreConfidence = "Unknown"
        restoreStrategy = "manual-review"
        reasons = @()
        warnings = @()
        evidence = @()
        evidenceCount = 0
        identity = [ordered]@{
            normalizedName = [string]$Candidate.normalizedName
            normalizedPublisher = [string]$Candidate.normalizedPublisher
            normalizedInstallLocation = [string]$Candidate.normalizedInstallLocation
            normalizedExecutablePath = [string]$Candidate.normalizedExecutablePath
            executableName = [string]$Candidate.executableName
            registryPath = [string]$Candidate.registryPath
            systemComponent = [string]$Candidate.systemComponent
            folderParent = [string]$Candidate.parentLabel
        }
    }
}

function Add-CandidateToLogicalApp {
    param(
        [Parameter(Mandatory = $true)]
        $App,

        [Parameter(Mandatory = $true)]
        $Candidate
    )

    $App.sources = Add-UniqueValue -Values $App.sources -Value $Candidate.source
    $App.evidence += [ordered]@{
        index = $Candidate.evidenceIndex
        source = [string]$Candidate.source
        evidenceType = [string]$Candidate.evidenceType
        name = [string]$Candidate.name
        publisher = [string]$Candidate.publisher
        version = [string]$Candidate.version
        installLocation = [string]$Candidate.installLocation
        executablePath = [string]$Candidate.executablePath
        packageManager = [string]$Candidate.packageManager
        packageId = [string]$Candidate.packageId
        systemComponent = [string]$Candidate.systemComponent
    }
    $App.evidenceCount = $App.evidence.Count

    if ([string]::IsNullOrWhiteSpace($App.publisher) -and -not [string]::IsNullOrWhiteSpace($Candidate.publisher)) {
        $App.publisher = [string]$Candidate.publisher
        $App.identity.normalizedPublisher = [string]$Candidate.normalizedPublisher
    }
    if ([string]::IsNullOrWhiteSpace($App.versionDetected) -and -not [string]::IsNullOrWhiteSpace($Candidate.version)) {
        $App.versionDetected = [string]$Candidate.version
    }
    if ([string]::IsNullOrWhiteSpace($App.installLocation) -and -not [string]::IsNullOrWhiteSpace($Candidate.installLocation)) {
        $App.installLocation = [string]$Candidate.installLocation
        $App.identity.normalizedInstallLocation = [string]$Candidate.normalizedInstallLocation
    }
    if ([string]::IsNullOrWhiteSpace($App.executablePath) -and -not [string]::IsNullOrWhiteSpace($Candidate.executablePath)) {
        $App.executablePath = [string]$Candidate.executablePath
        $App.identity.normalizedExecutablePath = [string]$Candidate.normalizedExecutablePath
        $App.identity.executableName = [string]$Candidate.executableName
    }
    if ([string]::IsNullOrWhiteSpace($App.identity.registryPath) -and -not [string]::IsNullOrWhiteSpace($Candidate.registryPath)) {
        $App.identity.registryPath = [string]$Candidate.registryPath
    }
    if ([string]::IsNullOrWhiteSpace($App.identity.systemComponent) -and -not [string]::IsNullOrWhiteSpace($Candidate.systemComponent)) {
        $App.identity.systemComponent = [string]$Candidate.systemComponent
    }
    if ([string]::IsNullOrWhiteSpace($App.identity.folderParent) -and -not [string]::IsNullOrWhiteSpace($Candidate.parentLabel)) {
        $App.identity.folderParent = [string]$Candidate.parentLabel
    }

    if (-not [string]::IsNullOrWhiteSpace($Candidate.packageManager) -and -not [string]::IsNullOrWhiteSpace($Candidate.packageId)) {
        $packageExists = $false
        foreach ($package in @($App.packages)) {
            if ($package.manager -eq $Candidate.packageManager -and $package.id -eq $Candidate.packageId) {
                $packageExists = $true
                break
            }
        }

        if (-not $packageExists) {
            $App.packages += [ordered]@{
                manager = [string]$Candidate.packageManager
                id = [string]$Candidate.packageId
                version = [string]$Candidate.version
                source = [string]$Candidate.packageSource
            }
        }
    }
}

function Find-LogicalAppMatch {
    param(
        [object[]]$Apps,
        [Parameter(Mandatory = $true)]
        $Candidate
    )

    $bestApp = $null
    $bestScore = 0

    foreach ($app in $Apps) {
        $score = 0

        if (-not [string]::IsNullOrWhiteSpace($Candidate.normalizedPackageId)) {
            foreach ($package in @($app.packages)) {
                if ($package.manager -eq $Candidate.packageManager -and (Get-NormalizedPackageId -PackageId $package.id) -eq $Candidate.normalizedPackageId) {
                    $score = [Math]::Max($score, 100)
                }
            }
        }

        if (Test-PathRelationship -LeftPath $Candidate.installLocation -RightPath $app.installLocation) {
            $score = [Math]::Max($score, 90)
        }
        if (Test-PathRelationship -LeftPath $Candidate.executablePath -RightPath $app.installLocation) {
            $score = [Math]::Max($score, 90)
        }

        if (Test-StrongNameMatch -Left $Candidate.name -Right $app.name) {
            $nameScore = 60
            if (-not [string]::IsNullOrWhiteSpace($Candidate.normalizedPublisher) -and $Candidate.normalizedPublisher -eq $app.identity.normalizedPublisher) {
                $nameScore += 20
            }
            if (-not [string]::IsNullOrWhiteSpace($Candidate.packageManager) -or @($app.packages).Count -gt 0) {
                $nameScore += 10
            }
            if ($Candidate.source -eq "knownFolder") {
                $nameScore -= 20
            }

            $score = [Math]::Max($score, $nameScore)
        }

        if ($score -gt $bestScore) {
            $bestScore = $score
            $bestApp = $app
        }
    }

    if ($bestScore -ge 60) {
        return $bestApp
    }

    return $null
}

function Test-AppTextMatch {
    param(
        [Parameter(Mandatory = $true)]
        $App,
        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    $text = ((@($App.name, $App.publisher, $App.installLocation, $App.executablePath, (@($App.packages) | ForEach-Object { $_.id })) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join " ").ToLowerInvariant()
    return ($text -match $Pattern)
}

function Test-AppEvidenceTextMatch {
    param(
        [Parameter(Mandatory = $true)]
        $App,

        [Parameter(Mandatory = $true)]
        [string]$Pattern,

        [string[]]$Fields = @("name", "publisher", "packageId")
    )

    foreach ($evidence in @($App.evidence)) {
        $parts = @()
        foreach ($field in $Fields) {
            $value = [string](Get-MapValue -Map $evidence -Key $field)
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $parts += $value
            }
        }

        if ($parts.Count -eq 0) {
            continue
        }

        $text = ($parts -join " ").ToLowerInvariant()
        if ($text -match $Pattern) {
            return $true
        }
    }

    return $false
}

function Set-LogicalAppClassification {
    param(
        [Parameter(Mandatory = $true)]
        $App
    )

    $classification = "Unknown"
    $confidence = "Unknown"
    $strategy = "manual-review"
    $reasons = @()
    $warnings = @()

    $sources = @($App.sources)
    $packages = @($App.packages)
    $hasWinget = (@($packages | Where-Object { $_.manager -eq "winget" }).Count -gt 0)
    $hasChocolatey = (@($packages | Where-Object { $_.manager -eq "chocolatey" }).Count -gt 0)
    $hasScoop = (@($packages | Where-Object { $_.manager -eq "scoop" }).Count -gt 0)
    $isKnownFolderOnly = ($sources.Count -eq 1 -and $sources[0] -eq "knownFolder")
    $hasSystemComponentEvidence = (@($App.evidence | Where-Object { [string](Get-MapValue -Map $_ -Key "systemComponent") -eq "1" }).Count -gt 0)

    $runtimePattern = "(visual c\+\+.*(redistribut|runtime|runt|minimum|additional|debug|uwp)|\.net.*(runtime|sdk|desktop runtime)|webview2 runtime|directx|windows sdk)"
    $driverPattern = "\b(driver|virtual display|virtual usb|chipset|firmware|printer driver|scanner driver|bluetooth driver|audio driver|display driver)\b"
    $securityPattern = "\b(antivirus|endpoint|edr|firewall|[a-z0-9]*vpn[a-z0-9]*|wireguard|security agent)\b"

    if (Test-AppEvidenceTextMatch -App $App -Pattern $runtimePattern -Fields @("name", "publisher", "packageId")) {
        $classification = "Unsupported / risky"
        $confidence = "Unsupported"
        $strategy = "do-not-restore"
        $reasons += "Runtime or SDK dependency should be installed by Windows, apps, or package managers as needed."
    } elseif (Test-AppEvidenceTextMatch -App $App -Pattern $driverPattern -Fields @("name", "publisher", "packageId")) {
        $classification = "Driver / system component"
        $confidence = "Unsupported"
        $strategy = "do-not-restore"
        $reasons += "Name or metadata indicates driver/device-level software."
    } elseif (Test-AppEvidenceTextMatch -App $App -Pattern $securityPattern -Fields @("name", "publisher", "packageId")) {
        $classification = "Unsupported / risky"
        $confidence = "Unsupported"
        $strategy = "do-not-restore"
        $reasons += "Security or network software may include services, drivers, certificates, or policy state."
    } elseif (Test-AppTextMatch -App $App -Pattern "\b(windowsapps|msstore)\b") {
        $classification = "Microsoft Store / UWP"
        $confidence = "Unsupported"
        $strategy = "manual-review"
        $reasons += "Microsoft Store/UWP app restore is outside the MVP automatic restore scope."
    } elseif (Test-AppTextMatch -App $App -Pattern "\b(docker desktop|postgresql|mysql|mariadb|sql server|mongodb|redis|vmware|virtualbox|hyper-v|wsl)\b") {
        $classification = "Service-heavy"
        $confidence = "Low"
        $strategy = "manual-review"
        $reasons += "App likely depends on services, data directories, networking, drivers, or local machine state."
    } elseif ($hasScoop) {
        $classification = "Scoop-managed"
        $confidence = "High"
        $strategy = "restore-via-scoop"
        $reasons += "Found Scoop package metadata."
    } elseif ($App.identity.folderParent -match "WinCarry portable|WinCarry manual apps") {
        $classification = "Portable / Self-contained"
        $confidence = "Medium"
        $strategy = "manual-review"
        $reasons += "Found app folder under a WinCarry-managed portable/manual location."
        if ($isKnownFolderOnly) {
            $warnings += "Folder presence alone is supporting evidence; verify the app manually before restore."
        }
    } elseif ($hasWinget) {
        $classification = "Winget reinstallable"
        $confidence = "Medium"
        $strategy = "reinstall-via-package-manager"
        $reasons += "Found winget package metadata."
    } elseif ($hasChocolatey) {
        $classification = "Chocolatey reinstallable"
        $confidence = "Medium"
        $strategy = "reinstall-via-package-manager"
        $reasons += "Found Chocolatey package metadata."
    } elseif ($hasSystemComponentEvidence) {
        $classification = "Unsupported / risky"
        $confidence = "Unsupported"
        $strategy = "do-not-restore"
        $reasons += "Registry marks this entry as a Windows system component."
    } elseif ($sources -contains "registry") {
        $classification = "Installer-based / manual reinstall"
        $confidence = "Low"
        $strategy = "manual-reinstall"
        $reasons += "Found uninstall registry metadata but no package-manager identity."
    } else {
        $classification = "Unknown"
        $confidence = "Unknown"
        $strategy = "manual-review"
        $reasons += "Evidence is not strong enough for an automatic restore strategy."
    }

    if ($packages.Count -gt 0) {
        $packageSummary = (($packages | ForEach-Object { "{0}:{1}" -f $_.manager, $_.id }) -join ", ")
        $reasons += ("Package evidence: {0}." -f $packageSummary)
    }
    if ($sources.Count -gt 0) {
        $reasons += ("Evidence sources: {0}." -f (($sources | Sort-Object) -join ", "))
    }
    if ($hasSystemComponentEvidence -and ($hasWinget -or $hasChocolatey -or $hasScoop)) {
        $warnings += "Registry also marks one entry as a system component; prefer package-manager reinstall and verify manually."
    }

    $App.classification = $classification
    $App.restoreConfidence = $confidence
    $App.restoreStrategy = $strategy
    $App.reasons = @($reasons)
    $App.warnings = @($warnings)

    if ($packages.Count -gt 0) {
        if ($hasScoop) {
            $App.package = @($packages | Where-Object { $_.manager -eq "scoop" } | Select-Object -First 1)[0]
        } elseif ($hasWinget) {
            $App.package = @($packages | Where-Object { $_.manager -eq "winget" } | Select-Object -First 1)[0]
        } elseif ($hasChocolatey) {
            $App.package = @($packages | Where-Object { $_.manager -eq "chocolatey" } | Select-Object -First 1)[0]
        }
    }
}

function New-LogicalAppsFromEvidence {
    param(
        [object[]]$Evidence
    )

    $apps = @()
    for ($index = 0; $index -lt $Evidence.Count; $index++) {
        $candidate = Convert-EvidenceToAppCandidate -Record $Evidence[$index] -EvidenceIndex $index
        if ($null -eq $candidate) {
            continue
        }

        $match = Find-LogicalAppMatch -Apps $apps -Candidate $candidate
        if ($null -eq $match) {
            $match = New-LogicalAppFromCandidate -Candidate $candidate
            $apps += $match
        }

        Add-CandidateToLogicalApp -App $match -Candidate $candidate
    }

    foreach ($app in $apps) {
        Set-LogicalAppClassification -App $app
    }

    return @($apps | Sort-Object -Property @{ Expression = { [string]$_.classification } }, @{ Expression = { [string]$_.name } })
}

function Get-ClassificationSummary {
    param([object[]]$Apps)

    $summary = [ordered]@{}
    foreach ($app in $Apps) {
        $key = [string]$app.classification
        if ([string]::IsNullOrWhiteSpace($key)) {
            $key = "Unknown"
        }

        if (-not $summary.Contains($key)) {
            $summary[$key] = 0
        }
        $summary[$key] = [int]$summary[$key] + 1
    }

    return $summary
}

function Get-ObjectKeys {
    param($Object)

    if ($null -eq $Object) {
        return @()
    }

    if ($Object -is [System.Collections.IDictionary]) {
        return @($Object.Keys)
    }

    return @($Object.PSObject.Properties.Name)
}

function ConvertTo-ArrayValue {
    param($Value)

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [System.Collections.IDictionary]) {
        return @($Value)
    }

    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) {
            return @()
        }

        return @($Value)
    }

    return @($Value | Where-Object { $null -ne $_ -and -not ($_ -is [string] -and [string]::IsNullOrWhiteSpace($_)) })
}

function Get-AppPackages {
    param($App)

    $packages = ConvertTo-ArrayValue -Value (Get-MapValue -Map $App -Key "packages")
    if ($packages.Count -gt 0) {
        return @($packages)
    }

    return @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $App -Key "package"))
}

function Test-AppHasPackageId {
    param($App)

    foreach ($package in (Get-AppPackages -App $App)) {
        $packageId = [string](Get-MapValue -Map $package -Key "id")
        if (-not [string]::IsNullOrWhiteSpace($packageId)) {
            return $true
        }
    }

    return $false
}

function Get-AppPackageSummaryText {
    param($App)

    $parts = @()
    foreach ($package in (Get-AppPackages -App $App)) {
        $manager = [string](Get-MapValue -Map $package -Key "manager")
        $packageId = [string](Get-MapValue -Map $package -Key "id")
        if ([string]::IsNullOrWhiteSpace($packageId)) {
            continue
        }
        if ([string]::IsNullOrWhiteSpace($manager)) {
            $parts += $packageId
        } else {
            $parts += ("{0}:{1}" -f $manager, $packageId)
        }
    }

    if ($parts.Count -eq 0) {
        return "manual"
    }

    return ($parts -join ", ")
}

function Get-AppReasonsText {
    param($App)

    $reasons = ConvertTo-ArrayValue -Value (Get-MapValue -Map $App -Key "reasons")
    if ($reasons.Count -eq 0) {
        return "No reason recorded."
    }

    return (($reasons | ForEach-Object { [string]$_ }) -join " ")
}

function Get-AppWarningsText {
    param($App)

    $warnings = ConvertTo-ArrayValue -Value (Get-MapValue -Map $App -Key "warnings")
    if ($warnings.Count -eq 0) {
        return ""
    }

    return (($warnings | ForEach-Object { [string]$_ }) -join " ")
}

function Get-ConfidenceSummary {
    param([object[]]$Apps)

    $summary = [ordered]@{}
    foreach ($app in $Apps) {
        $key = [string](Get-MapValue -Map $app -Key "restoreConfidence")
        if ([string]::IsNullOrWhiteSpace($key)) {
            $key = "Unknown"
        }
        if (-not $summary.Contains($key)) {
            $summary[$key] = 0
        }
        $summary[$key] = [int]$summary[$key] + 1
    }

    return $summary
}

function Get-ManualReinstallApps {
    param([object[]]$Apps)

    $manualClassifications = @(
        "Installer-based / manual reinstall",
        "Unknown",
        "Portable / Self-contained",
        "Service-heavy"
    )

    return @($Apps | Where-Object {
        $confidence = [string](Get-MapValue -Map $_ -Key "restoreConfidence")
        $classification = [string](Get-MapValue -Map $_ -Key "classification")
        $strategy = [string](Get-MapValue -Map $_ -Key "restoreStrategy")
        $hasPackage = Test-AppHasPackageId -App $_

        ($confidence -ne "Unsupported") -and (
            (-not $hasPackage) -or
            ($strategy -eq "manual-reinstall") -or
            ($manualClassifications -contains $classification)
        )
    })
}

function Get-UnsupportedApps {
    param([object[]]$Apps)

    return @($Apps | Where-Object {
        $confidence = [string](Get-MapValue -Map $_ -Key "restoreConfidence")
        $classification = [string](Get-MapValue -Map $_ -Key "classification")
        ($confidence -eq "Unsupported") -or ($classification -eq "Unsupported / risky") -or ($classification -eq "Driver / system component") -or ($classification -eq "Microsoft Store / UWP")
    })
}

function New-AppSummaryRecord {
    param($App)

    return [ordered]@{
        id = [string](Get-MapValue -Map $App -Key "id")
        name = [string](Get-MapValue -Map $App -Key "name")
        classification = [string](Get-MapValue -Map $App -Key "classification")
        restoreConfidence = [string](Get-MapValue -Map $App -Key "restoreConfidence")
        restoreStrategy = [string](Get-MapValue -Map $App -Key "restoreStrategy")
        package = (Get-AppPackageSummaryText -App $App)
        reasons = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $App -Key "reasons"))
        warnings = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $App -Key "warnings"))
    }
}

function Convert-PackageManagerStatusToMap {
    param(
        [object[]]$PackageManagers,
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $map = [ordered]@{}
    foreach ($manager in $PackageManagers) {
        $name = [string](Get-MapValue -Map $manager -Key "name")
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        $entry = [ordered]@{
            available = [bool](Get-MapValue -Map $manager -Key "available")
            version = [string](Get-MapValue -Map $manager -Key "version")
            source = [string](Get-MapValue -Map $manager -Key "source")
        }
        if ($name -eq "scoop") {
            $entry["root"] = (Join-Path $RootPath "scoop")
        }

        $map[$name] = $entry
    }

    return $map
}

function Convert-AppForManifest {
    param(
        [Parameter(Mandatory = $true)]
        $App,

        [Parameter(Mandatory = $true)]
        [string]$DetectedAt
    )

    return [ordered]@{
        id = [string](Get-MapValue -Map $App -Key "id")
        name = [string](Get-MapValue -Map $App -Key "name")
        publisher = [string](Get-MapValue -Map $App -Key "publisher")
        versionDetected = [string](Get-MapValue -Map $App -Key "versionDetected")
        installLocation = [string](Get-MapValue -Map $App -Key "installLocation")
        executablePath = [string](Get-MapValue -Map $App -Key "executablePath")
        source = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $App -Key "sources"))
        package = (Get-MapValue -Map $App -Key "package")
        packages = @(Get-AppPackages -App $App)
        classification = [string](Get-MapValue -Map $App -Key "classification")
        restoreConfidence = [string](Get-MapValue -Map $App -Key "restoreConfidence")
        restoreStrategy = [string](Get-MapValue -Map $App -Key "restoreStrategy")
        reasons = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $App -Key "reasons"))
        warnings = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $App -Key "warnings"))
        configPaths = @()
        detectedAt = $DetectedAt
    }
}

function New-AppManifestFromScan {
    param(
        [Parameter(Mandatory = $true)]
        $Scan
    )

    $rootPath = [string]$Scan.root.resolvedRoot
    $os = Get-OperatingSystemInfo
    $user = Get-CurrentUserInfo
    $admin = Get-AdminStatus
    $packageManagers = @(Get-PackageManagerStatus)
    $apps = @($Scan.apps | ForEach-Object { Convert-AppForManifest -App $_ -DetectedAt $Scan.createdAt })
    $manualApps = @(Get-ManualReinstallApps -Apps $apps | ForEach-Object { New-AppSummaryRecord -App $_ })
    $unsupportedApps = @(Get-UnsupportedApps -Apps $apps | ForEach-Object { New-AppSummaryRecord -App $_ })

    $manifest = [ordered]@{
        schemaVersion = "1.0"
        createdAt = (Get-Date).ToString("o")
        toolName = $script:ToolName
        sourceScan = [ordered]@{
            schemaVersion = [string]$Scan.schemaVersion
            createdAt = [string]$Scan.createdAt
            evidenceCount = @($Scan.evidence).Count
            sourceCounts = $Scan.sources
            warnings = @($Scan.warnings)
        }
        machine = [ordered]@{
            computerName = [string]$user.machineName
            windowsVersion = ("{0} {1}" -f $os.caption, $os.architecture)
            osCaption = [string]$os.caption
            osVersion = [string]$os.version
            architecture = [string]$os.architecture
            userName = [string]$user.userName
            userDomain = [string]$user.domainName
            userProfile = [string]$user.userProfile
            isAdmin = [bool]$admin.isAdmin
        }
        root = [ordered]@{
            winCarryRoot = $rootPath
        }
        packageManagers = (Convert-PackageManagerStatusToMap -PackageManagers $packageManagers -RootPath $rootPath)
        summary = [ordered]@{
            appCount = $apps.Count
            evidenceCount = @($Scan.evidence).Count
            classificationSummary = (Get-ClassificationSummary -Apps $apps)
            restoreConfidenceSummary = (Get-ConfidenceSummary -Apps $apps)
            manualReinstallCount = $manualApps.Count
            unsupportedCount = $unsupportedApps.Count
        }
        apps = @($apps)
        manualReinstall = @($manualApps)
        unsupported = @($unsupportedApps)
    }

    Merge-LatestConfigBackupIntoManifest -Manifest $manifest -RootPath $rootPath | Out-Null
    return $manifest
}

function ConvertTo-MarkdownCell {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $clean = $Text -replace "[\r\n]+", " "
    return ($clean -replace "\|", "\|")
}

function Add-MapSummaryLines {
    param(
        [Parameter(Mandatory = $true)]
        $Lines,

        $Map
    )

    foreach ($key in (Get-ObjectKeys -Object $Map | Sort-Object)) {
        $value = Get-MapValue -Map $Map -Key $key
        $Lines.Add(("- {0}: {1}" -f $key, $value))
    }
}

function Convert-ManifestReportToMarkdown {
    param(
        [Parameter(Mandatory = $true)]
        $Manifest
    )

    $summary = Get-MapValue -Map $Manifest -Key "summary"
    $machine = Get-MapValue -Map $Manifest -Key "machine"
    $root = Get-MapValue -Map $Manifest -Key "root"
    $sourceScan = Get-MapValue -Map $Manifest -Key "sourceScan"
    $apps = ConvertTo-ArrayValue -Value (Get-MapValue -Map $Manifest -Key "apps")
    $manualApps = ConvertTo-ArrayValue -Value (Get-MapValue -Map $Manifest -Key "manualReinstall")
    $unsupportedApps = ConvertTo-ArrayValue -Value (Get-MapValue -Map $Manifest -Key "unsupported")
    $packageManagers = Get-MapValue -Map $Manifest -Key "packageManagers"

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# WinCarry Scan Report")
    $lines.Add("")
    $lines.Add(("Created: {0}" -f (Get-MapValue -Map $Manifest -Key "createdAt")))
    $lines.Add(("Manifest schema: {0}" -f (Get-MapValue -Map $Manifest -Key "schemaVersion")))
    $lines.Add(("WinCarry root: {0}" -f (Get-MapValue -Map $root -Key "winCarryRoot")))
    $lines.Add("")
    $lines.Add("> Restore confidence is a risk classification, not a success rate or guarantee.")
    $lines.Add("")

    $lines.Add("## System")
    $lines.Add("")
    $lines.Add(("- Computer: {0}" -f (Get-MapValue -Map $machine -Key "computerName")))
    $lines.Add(("- Windows: {0}" -f (Get-MapValue -Map $machine -Key "windowsVersion")))
    $lines.Add(("- User: {0}\\{1}" -f (Get-MapValue -Map $machine -Key "userDomain"), (Get-MapValue -Map $machine -Key "userName")))
    $lines.Add(("- Profile: {0}" -f (Get-MapValue -Map $machine -Key "userProfile")))
    $lines.Add(("- Is admin/root: {0}" -f (Get-MapValue -Map $machine -Key "isAdmin")))
    $lines.Add("")

    $lines.Add("## Summary")
    $lines.Add("")
    $lines.Add(("- Apps: {0}" -f (Get-MapValue -Map $summary -Key "appCount")))
    $lines.Add(("- Evidence records: {0}" -f (Get-MapValue -Map $summary -Key "evidenceCount")))
    $lines.Add(("- Manual reinstall / review: {0}" -f (Get-MapValue -Map $summary -Key "manualReinstallCount")))
    $lines.Add(("- Unsupported / do not restore automatically: {0}" -f (Get-MapValue -Map $summary -Key "unsupportedCount")))
    $lines.Add("")

    $lines.Add("## Classification Summary")
    $lines.Add("")
    Add-MapSummaryLines -Lines $lines -Map (Get-MapValue -Map $summary -Key "classificationSummary")
    $lines.Add("")

    $lines.Add("## Restore Confidence Summary")
    $lines.Add("")
    Add-MapSummaryLines -Lines $lines -Map (Get-MapValue -Map $summary -Key "restoreConfidenceSummary")
    $lines.Add("")

    $lines.Add("## Package Managers")
    $lines.Add("")
    foreach ($managerName in (Get-ObjectKeys -Object $packageManagers | Sort-Object)) {
        $manager = Get-MapValue -Map $packageManagers -Key $managerName
        $available = Get-MapValue -Map $manager -Key "available"
        $version = [string](Get-MapValue -Map $manager -Key "version")
        if ([string]::IsNullOrWhiteSpace($version)) {
            $version = "version unknown"
        }
        $lines.Add(("- {0}: available={1}; {2}" -f $managerName, $available, $version))
    }
    $lines.Add("")

    $warnings = ConvertTo-ArrayValue -Value (Get-MapValue -Map $sourceScan -Key "warnings")
    if ($warnings.Count -gt 0) {
        $lines.Add("## Scan Warnings")
        $lines.Add("")
        foreach ($warning in $warnings) {
            $lines.Add(("- {0}: {1}" -f (Get-MapValue -Map $warning -Key "source"), (Get-MapValue -Map $warning -Key "message")))
        }
        $lines.Add("")
    }

    $lines.Add("## Manual Reinstall / Review List")
    $lines.Add("")
    if ($manualApps.Count -eq 0) {
        $lines.Add("No manual reinstall/review apps recorded.")
    } else {
        $lines.Add("| App | Classification | Restore confidence | Package | Reason |")
        $lines.Add("| --- | --- | --- | --- | --- |")
        foreach ($app in $manualApps) {
            $lines.Add(("| {0} | {1} | {2} | {3} | {4} |" -f
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $app -Key "name")),
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $app -Key "classification")),
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $app -Key "restoreConfidence")),
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $app -Key "package")),
                (ConvertTo-MarkdownCell -Text (Get-AppReasonsText -App $app))))
        }
    }
    $lines.Add("")

    $lines.Add("## Unsupported / Do Not Restore Automatically")
    $lines.Add("")
    if ($unsupportedApps.Count -eq 0) {
        $lines.Add("No unsupported apps recorded.")
    } else {
        $lines.Add("| App | Classification | Reason |")
        $lines.Add("| --- | --- | --- |")
        foreach ($app in $unsupportedApps) {
            $lines.Add(("| {0} | {1} | {2} |" -f
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $app -Key "name")),
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $app -Key "classification")),
                (ConvertTo-MarkdownCell -Text (Get-AppReasonsText -App $app))))
        }
    }
    $lines.Add("")

    $lines.Add("## App Details")
    $lines.Add("")
    $lines.Add("| App | Classification | Restore confidence | Strategy | Package | Reasons | Warnings |")
    $lines.Add("| --- | --- | --- | --- | --- | --- | --- |")
    foreach ($app in $apps) {
        $lines.Add(("| {0} | {1} | {2} | {3} | {4} | {5} | {6} |" -f
            (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $app -Key "name")),
            (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $app -Key "classification")),
            (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $app -Key "restoreConfidence")),
            (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $app -Key "restoreStrategy")),
            (ConvertTo-MarkdownCell -Text (Get-AppPackageSummaryText -App $app)),
            (ConvertTo-MarkdownCell -Text (Get-AppReasonsText -App $app)),
            (ConvertTo-MarkdownCell -Text (Get-AppWarningsText -App $app))))
    }
    $lines.Add("")

    $lines.Add("## Next Recommended Steps")
    $lines.Add("")
    $lines.Add("- Review unsupported and manual reinstall lists before formatting Windows.")
    $lines.Add("- Do not assume apps installed outside C: will run after reinstall without repair, login, activation, services, or registry state.")
    $lines.Add("- Prefer package-manager reinstall or portable/Scoop workflows for future apps that should survive reinstall more cleanly.")

    return ($lines -join [Environment]::NewLine)
}

function Convert-ManifestReportToText {
    param(
        [Parameter(Mandatory = $true)]
        $Manifest
    )

    $summary = Get-MapValue -Map $Manifest -Key "summary"
    $machine = Get-MapValue -Map $Manifest -Key "machine"
    $root = Get-MapValue -Map $Manifest -Key "root"
    $apps = ConvertTo-ArrayValue -Value (Get-MapValue -Map $Manifest -Key "apps")
    $manualApps = ConvertTo-ArrayValue -Value (Get-MapValue -Map $Manifest -Key "manualReinstall")
    $unsupportedApps = ConvertTo-ArrayValue -Value (Get-MapValue -Map $Manifest -Key "unsupported")

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("WinCarry Scan Report")
    $lines.Add("")
    $lines.Add(("Created: {0}" -f (Get-MapValue -Map $Manifest -Key "createdAt")))
    $lines.Add(("Root: {0}" -f (Get-MapValue -Map $root -Key "winCarryRoot")))
    $lines.Add(("Computer: {0}" -f (Get-MapValue -Map $machine -Key "computerName")))
    $lines.Add(("Windows: {0}" -f (Get-MapValue -Map $machine -Key "windowsVersion")))
    $lines.Add("")
    $lines.Add("Restore confidence is a risk classification, not a success rate or guarantee.")
    $lines.Add("")
    $lines.Add("Summary")
    $lines.Add(("- Apps: {0}" -f (Get-MapValue -Map $summary -Key "appCount")))
    $lines.Add(("- Evidence records: {0}" -f (Get-MapValue -Map $summary -Key "evidenceCount")))
    $lines.Add(("- Manual reinstall / review: {0}" -f $manualApps.Count))
    $lines.Add(("- Unsupported / do not restore automatically: {0}" -f $unsupportedApps.Count))
    $lines.Add("")

    $lines.Add("Classification Summary")
    Add-MapSummaryLines -Lines $lines -Map (Get-MapValue -Map $summary -Key "classificationSummary")
    $lines.Add("")
    $lines.Add("Restore Confidence Summary")
    Add-MapSummaryLines -Lines $lines -Map (Get-MapValue -Map $summary -Key "restoreConfidenceSummary")
    $lines.Add("")

    $lines.Add("Manual Reinstall / Review List")
    foreach ($app in $manualApps) {
        $lines.Add(("- {0} [{1}, {2}] package={3}" -f (Get-MapValue -Map $app -Key "name"), (Get-MapValue -Map $app -Key "classification"), (Get-MapValue -Map $app -Key "restoreConfidence"), (Get-MapValue -Map $app -Key "package")))
        $lines.Add(("  Reason: {0}" -f (Get-AppReasonsText -App $app)))
    }
    if ($manualApps.Count -eq 0) {
        $lines.Add("- None")
    }
    $lines.Add("")

    $lines.Add("Unsupported / Do Not Restore Automatically")
    foreach ($app in $unsupportedApps) {
        $lines.Add(("- {0} [{1}]" -f (Get-MapValue -Map $app -Key "name"), (Get-MapValue -Map $app -Key "classification")))
        $lines.Add(("  Reason: {0}" -f (Get-AppReasonsText -App $app)))
    }
    if ($unsupportedApps.Count -eq 0) {
        $lines.Add("- None")
    }
    $lines.Add("")

    $lines.Add("App Details")
    foreach ($app in $apps) {
        $lines.Add(("- {0}" -f (Get-MapValue -Map $app -Key "name")))
        $lines.Add(("  Classification: {0}" -f (Get-MapValue -Map $app -Key "classification")))
        $lines.Add(("  Restore confidence: {0}" -f (Get-MapValue -Map $app -Key "restoreConfidence")))
        $lines.Add(("  Strategy: {0}" -f (Get-MapValue -Map $app -Key "restoreStrategy")))
        $lines.Add(("  Package: {0}" -f (Get-AppPackageSummaryText -App $app)))
        $lines.Add(("  Reasons: {0}" -f (Get-AppReasonsText -App $app)))
        $warnings = Get-AppWarningsText -App $app
        if (-not [string]::IsNullOrWhiteSpace($warnings)) {
            $lines.Add(("  Warnings: {0}" -f $warnings))
        }
    }

    return ($lines -join [Environment]::NewLine)
}

function Convert-AppSummaryListToText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [object[]]$Apps
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add($Title)
    $lines.Add("")
    if ($Apps.Count -eq 0) {
        $lines.Add("No entries.")
        return ($lines -join [Environment]::NewLine)
    }

    foreach ($app in $Apps) {
        $lines.Add(("- {0}" -f (Get-MapValue -Map $app -Key "name")))
        $lines.Add(("  Classification: {0}" -f (Get-MapValue -Map $app -Key "classification")))
        $lines.Add(("  Restore confidence: {0}" -f (Get-MapValue -Map $app -Key "restoreConfidence")))
        $lines.Add(("  Strategy: {0}" -f (Get-MapValue -Map $app -Key "restoreStrategy")))
        $lines.Add(("  Package: {0}" -f (Get-MapValue -Map $app -Key "package")))
        $lines.Add(("  Reasons: {0}" -f (Get-AppReasonsText -App $app)))
        $warnings = Get-AppWarningsText -App $app
        if (-not [string]::IsNullOrWhiteSpace($warnings)) {
            $lines.Add(("  Warnings: {0}" -f $warnings))
        }
    }

    return ($lines -join [Environment]::NewLine)
}

function Resolve-ConfigPathTemplate {
    param([string]$Template)

    if ([string]::IsNullOrWhiteSpace($Template)) {
        return ""
    }

    $userProfile = $env:USERPROFILE
    if ([string]::IsNullOrWhiteSpace($userProfile)) {
        $userProfile = $env:HOME
    }

    $replacements = [ordered]@{
        "%USERPROFILE%" = $userProfile
        "%APPDATA%" = $env:APPDATA
        "%LOCALAPPDATA%" = $env:LOCALAPPDATA
        "%PROGRAMDATA%" = $env:PROGRAMDATA
    }

    $resolved = $Template
    foreach ($key in $replacements.Keys) {
        $value = [string]$replacements[$key]
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $resolved = $resolved.Replace($key, $value)
        }
    }

    if (-not (Test-IsWindows)) {
        $resolved = $resolved.Replace("\", [string][System.IO.Path]::DirectorySeparatorChar)
    }

    return (Resolve-DisplayPath -Path $resolved)
}

function Get-SafeFileName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return "config"
    }

    $safe = $Name.ToLowerInvariant() -replace "[^a-z0-9]+", "-"
    $safe = $safe.Trim("-")
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return "config"
    }
    if ($safe.Length -gt 64) {
        $safe = $safe.Substring(0, 64).TrimEnd("-")
    }
    return $safe
}

function New-ConfigDefinition {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("safe", "sensitive", "detect-only")]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$AppName,

        [Parameter(Mandatory = $true)]
        [string]$PathTemplate,

        [string]$RestorePathTemplate = "",
        [string]$AppNamePattern = "",
        [string]$BackupSlug = "",
        [string[]]$Warnings = @()
    )

    if ([string]::IsNullOrWhiteSpace($RestorePathTemplate)) {
        $RestorePathTemplate = $PathTemplate
    }
    if ([string]::IsNullOrWhiteSpace($AppNamePattern)) {
        $AppNamePattern = [regex]::Escape($AppName)
    }
    if ([string]::IsNullOrWhiteSpace($BackupSlug)) {
        $BackupSlug = Get-SafeFileName -Name $Name
    }

    return [ordered]@{
        type = $Type
        name = $Name
        appName = $AppName
        appNamePattern = $AppNamePattern
        pathTemplate = $PathTemplate
        restorePathTemplate = $RestorePathTemplate
        backupSlug = $BackupSlug
        warnings = @($Warnings)
    }
}

function Convert-ConfigDefinitionToCandidate {
    param($Definition)

    $pathTemplate = [string](Get-MapValue -Map $Definition -Key "pathTemplate")
    $resolvedPath = Resolve-ConfigPathTemplate -Template $pathTemplate
    if ([string]::IsNullOrWhiteSpace($resolvedPath) -or -not (Test-Path -LiteralPath $resolvedPath)) {
        return $null
    }

    $item = Get-Item -LiteralPath $resolvedPath -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return $null
    }

    return [ordered]@{
        type = [string](Get-MapValue -Map $Definition -Key "type")
        name = [string](Get-MapValue -Map $Definition -Key "name")
        appName = [string](Get-MapValue -Map $Definition -Key "appName")
        appNamePattern = [string](Get-MapValue -Map $Definition -Key "appNamePattern")
        originalPath = $item.FullName
        restorePathTemplate = [string](Get-MapValue -Map $Definition -Key "restorePathTemplate")
        backupSlug = [string](Get-MapValue -Map $Definition -Key "backupSlug")
        isDirectory = [bool]$item.PSIsContainer
        warnings = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $Definition -Key "warnings"))
    }
}

function Get-ConfigDefinitions {
    $definitions = @()

    $definitions += New-ConfigDefinition -Type "safe" -Name "VS Code User Settings" -AppName "Visual Studio Code" -AppNamePattern "visual studio code|vs code|code" -PathTemplate "%APPDATA%\Code\User" -BackupSlug "vscode-user"
    $definitions += New-ConfigDefinition -Type "safe" -Name "VS Code Insiders User Settings" -AppName "Visual Studio Code" -AppNamePattern "visual studio code|vs code|code" -PathTemplate "%APPDATA%\Code - Insiders\User" -BackupSlug "vscode-insiders-user"
    $definitions += New-ConfigDefinition -Type "safe" -Name "VSCodium User Settings" -AppName "VSCodium" -AppNamePattern "vscodium" -PathTemplate "%APPDATA%\VSCodium\User" -BackupSlug "vscodium-user"
    $definitions += New-ConfigDefinition -Type "safe" -Name "Git global config" -AppName "Git" -AppNamePattern "\bgit\b" -PathTemplate "%USERPROFILE%\.gitconfig" -BackupSlug "gitconfig"
    $definitions += New-ConfigDefinition -Type "safe" -Name "Git global ignore" -AppName "Git" -AppNamePattern "\bgit\b" -PathTemplate "%USERPROFILE%\.gitignore_global" -BackupSlug "gitignore-global"
    $definitions += New-ConfigDefinition -Type "safe" -Name "Windows Terminal settings" -AppName "Windows Terminal" -AppNamePattern "windows terminal" -PathTemplate "%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" -BackupSlug "windows-terminal-settings"
    $definitions += New-ConfigDefinition -Type "safe" -Name "Windows Terminal Preview settings" -AppName "Windows Terminal" -AppNamePattern "windows terminal" -PathTemplate "%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json" -BackupSlug "windows-terminal-preview-settings"
    $definitions += New-ConfigDefinition -Type "safe" -Name "PowerShell WindowsPowerShell current-user profile" -AppName "PowerShell" -AppNamePattern "powershell" -PathTemplate "%USERPROFILE%\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1" -BackupSlug "powershell-windows-profile"
    $definitions += New-ConfigDefinition -Type "safe" -Name "PowerShell WindowsPowerShell all-hosts profile" -AppName "PowerShell" -AppNamePattern "powershell" -PathTemplate "%USERPROFILE%\Documents\WindowsPowerShell\profile.ps1" -BackupSlug "powershell-windows-allhosts-profile"
    $definitions += New-ConfigDefinition -Type "safe" -Name "PowerShell 7 current-user profile" -AppName "PowerShell" -AppNamePattern "powershell" -PathTemplate "%USERPROFILE%\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" -BackupSlug "powershell-7-profile"
    $definitions += New-ConfigDefinition -Type "safe" -Name "PowerShell 7 all-hosts profile" -AppName "PowerShell" -AppNamePattern "powershell" -PathTemplate "%USERPROFILE%\Documents\PowerShell\profile.ps1" -BackupSlug "powershell-7-allhosts-profile"
    $definitions += New-ConfigDefinition -Type "safe" -Name "npm global config folder" -AppName "Node.js" -AppNamePattern "node|npm" -PathTemplate "%APPDATA%\npm\etc" -BackupSlug "npm-etc" -Warnings @("Files named npmrc are treated as sensitive if copied from user profile; review npm tokens before restore.")
    $definitions += New-ConfigDefinition -Type "safe" -Name "pnpm config" -AppName "pnpm" -AppNamePattern "pnpm|node" -PathTemplate "%LOCALAPPDATA%\pnpm\config" -BackupSlug "pnpm-config"
    $definitions += New-ConfigDefinition -Type "safe" -Name "pnpm roaming config" -AppName "pnpm" -AppNamePattern "pnpm|node" -PathTemplate "%APPDATA%\pnpm\config" -BackupSlug "pnpm-roaming-config"
    $definitions += New-ConfigDefinition -Type "safe" -Name "Yarn config" -AppName "Yarn" -AppNamePattern "yarn|node" -PathTemplate "%LOCALAPPDATA%\Yarn\Config" -BackupSlug "yarn-config"
    $definitions += New-ConfigDefinition -Type "safe" -Name "Yarn rc" -AppName "Yarn" -AppNamePattern "yarn|node" -PathTemplate "%USERPROFILE%\.yarnrc" -BackupSlug "yarnrc"
    $definitions += New-ConfigDefinition -Type "safe" -Name "Yarn Berry rc" -AppName "Yarn" -AppNamePattern "yarn|node" -PathTemplate "%USERPROFILE%\.yarnrc.yml" -BackupSlug "yarnrc-yml"
    $definitions += New-ConfigDefinition -Type "safe" -Name "Python pip user config" -AppName "Python" -AppNamePattern "python|pip" -PathTemplate "%APPDATA%\pip\pip.ini" -BackupSlug "pip-user-config"
    $definitions += New-ConfigDefinition -Type "safe" -Name "Python pip home config" -AppName "Python" -AppNamePattern "python|pip" -PathTemplate "%USERPROFILE%\pip\pip.ini" -BackupSlug "pip-home-config"
    $definitions += New-ConfigDefinition -Type "safe" -Name "SSH client config" -AppName "OpenSSH" -AppNamePattern "ssh|openssh|git" -PathTemplate "%USERPROFILE%\.ssh\config" -BackupSlug "ssh-config" -Warnings @("SSH host aliases may reveal server names. Private keys are handled separately as sensitive files.")
    $definitions += New-ConfigDefinition -Type "safe" -Name "SSH known hosts" -AppName "OpenSSH" -AppNamePattern "ssh|openssh|git" -PathTemplate "%USERPROFILE%\.ssh\known_hosts" -BackupSlug "ssh-known-hosts" -Warnings @("Known hosts can reveal server names.")

    $definitions += New-ConfigDefinition -Type "sensitive" -Name "npm user config" -AppName "Node.js" -AppNamePattern "node|npm" -PathTemplate "%USERPROFILE%\.npmrc" -BackupSlug "npmrc" -Warnings @(".npmrc can contain package registry tokens. Skipped by default.")
    $definitions += New-ConfigDefinition -Type "sensitive" -Name "Docker client config" -AppName "Docker Desktop" -AppNamePattern "docker" -PathTemplate "%USERPROFILE%\.docker\config.json" -BackupSlug "docker-config" -Warnings @("Docker config can contain registry credentials. Skipped by default.")
    $definitions += New-ConfigDefinition -Type "sensitive" -Name "Home .env" -AppName "Shell" -AppNamePattern "shell|powershell" -PathTemplate "%USERPROFILE%\.env" -BackupSlug "home-env" -Warnings @(".env files commonly contain secrets. Skipped by default.")

    $definitions += New-ConfigDefinition -Type "detect-only" -Name "Google Chrome profile" -AppName "Google Chrome" -AppNamePattern "chrome" -PathTemplate "%LOCALAPPDATA%\Google\Chrome\User Data" -BackupSlug "chrome-profile" -Warnings @("Browser profiles can include cookies, sessions, passwords, and tokens. Detect-only in MVP.")
    $definitions += New-ConfigDefinition -Type "detect-only" -Name "Microsoft Edge profile" -AppName "Microsoft Edge" -AppNamePattern "edge" -PathTemplate "%LOCALAPPDATA%\Microsoft\Edge\User Data" -BackupSlug "edge-profile" -Warnings @("Browser profiles can include cookies, sessions, passwords, and tokens. Detect-only in MVP.")
    $definitions += New-ConfigDefinition -Type "detect-only" -Name "Mozilla Firefox profiles" -AppName "Mozilla Firefox" -AppNamePattern "firefox|mozilla" -PathTemplate "%APPDATA%\Mozilla\Firefox\Profiles" -BackupSlug "firefox-profiles" -Warnings @("Browser profiles can include cookies, sessions, passwords, and tokens. Detect-only in MVP.")
    $definitions += New-ConfigDefinition -Type "detect-only" -Name "Discord profile" -AppName "Discord" -AppNamePattern "discord" -PathTemplate "%APPDATA%\discord" -BackupSlug "discord-profile" -Warnings @("Chat app profiles can include sessions and tokens. Detect-only in MVP.")
    $definitions += New-ConfigDefinition -Type "detect-only" -Name "Slack profile" -AppName "Slack" -AppNamePattern "slack" -PathTemplate "%APPDATA%\Slack" -BackupSlug "slack-profile" -Warnings @("Chat app profiles can include sessions and tokens. Detect-only in MVP.")
    $definitions += New-ConfigDefinition -Type "detect-only" -Name "Microsoft Teams profile" -AppName "Microsoft Teams" -AppNamePattern "teams" -PathTemplate "%APPDATA%\Microsoft\Teams" -BackupSlug "teams-profile" -Warnings @("Chat app profiles can include sessions and tokens. Detect-only in MVP.")
    $definitions += New-ConfigDefinition -Type "detect-only" -Name "Telegram Desktop profile" -AppName "Telegram Desktop" -AppNamePattern "telegram" -PathTemplate "%APPDATA%\Telegram Desktop" -BackupSlug "telegram-profile" -Warnings @("Chat app profiles can include sessions and tokens. Detect-only in MVP.")

    return @($definitions)
}

function Get-DiscoveredConfigCandidates {
    $candidates = @()
    foreach ($definition in (Get-ConfigDefinitions)) {
        $candidate = Convert-ConfigDefinitionToCandidate -Definition $definition
        if ($null -ne $candidate) {
            $candidates += $candidate
        }
    }

    $sshRoot = Resolve-ConfigPathTemplate -Template "%USERPROFILE%\.ssh"
    if (-not [string]::IsNullOrWhiteSpace($sshRoot) -and (Test-Path -LiteralPath $sshRoot)) {
        $privateKeyNames = @("id_rsa", "id_dsa", "id_ecdsa", "id_ed25519")
        foreach ($name in $privateKeyNames) {
            $path = Join-Path $sshRoot $name
            if (Test-Path -LiteralPath $path) {
                $candidates += [ordered]@{
                    type = "sensitive"
                    name = ("SSH private key: {0}" -f $name)
                    appName = "OpenSSH"
                    appNamePattern = "ssh|openssh|git"
                    originalPath = (Resolve-DisplayPath -Path $path)
                    restorePathTemplate = ("%USERPROFILE%\.ssh\{0}" -f $name)
                    backupSlug = ("ssh-private-key-{0}" -f $name)
                    isDirectory = $false
                    warnings = @("SSH private keys grant access to remote systems. Skipped by default.")
                }
            }
        }
    }

    $userProfile = Resolve-ConfigPathTemplate -Template "%USERPROFILE%"
    if (-not [string]::IsNullOrWhiteSpace($userProfile) -and (Test-Path -LiteralPath $userProfile)) {
        foreach ($envFile in @(Get-ChildItem -LiteralPath $userProfile -Force -File -Filter ".env*" -ErrorAction SilentlyContinue)) {
            if ($envFile.Name -eq ".env" -or $envFile.Name.StartsWith(".env.")) {
                $candidates += [ordered]@{
                    type = "sensitive"
                    name = ("Environment file: {0}" -f $envFile.Name)
                    appName = "Shell"
                    appNamePattern = "shell|powershell"
                    originalPath = $envFile.FullName
                    restorePathTemplate = ("%USERPROFILE%\{0}" -f $envFile.Name)
                    backupSlug = ("env-{0}" -f (Get-SafeFileName -Name $envFile.Name))
                    isDirectory = $false
                    warnings = @("Environment files commonly contain secrets. Skipped by default.")
                }
            }
        }
    }

    return @($candidates)
}

function Test-ExcludedConfigPath {
    param([string]$RelativePath)

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        return $false
    }

    $segments = @($RelativePath -split "[\\/]+")
    foreach ($segment in $segments) {
        $name = $segment.ToLowerInvariant()
        if ($name -match "^(cache|caches|code cache|gpucache|gpu cache|logs?|temp|tmp|crashpad|crashes|crash dumps|node_modules)$") {
            return $true
        }
    }

    $leaf = ([System.IO.Path]::GetFileName($RelativePath)).ToLowerInvariant()
    return ($leaf -match "\.(log|tmp|cache)$")
}

function Test-SensitiveConfigPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    $normalized = (Get-NormalizedPath -Path $Path)
    $leaf = ([System.IO.Path]::GetFileName($Path)).ToLowerInvariant()
    if ($leaf -eq ".npmrc") { return $true }
    if ($leaf -eq ".env" -or $leaf.StartsWith(".env.")) { return $true }
    if ($leaf -match "^(id_rsa|id_dsa|id_ecdsa|id_ed25519)$") { return $true }
    if ($leaf -match "\.(pem|key|pfx|p12)$") { return $true }
    if ($normalized -match "[\\/]\.docker[\\/]config\.json$") { return $true }

    return $false
}

function Copy-ConfigCandidate {
    param(
        [Parameter(Mandatory = $true)]
        $Candidate,

        [Parameter(Mandatory = $true)]
        [string]$ConfigsRootPath,

        [switch]$IncludeSensitive
    )

    $source = [string](Get-MapValue -Map $Candidate -Key "originalPath")
    $slug = [string](Get-MapValue -Map $Candidate -Key "backupSlug")
    if ([string]::IsNullOrWhiteSpace($slug)) {
        $slug = Get-SafeFileName -Name ([string](Get-MapValue -Map $Candidate -Key "name"))
    }
    $destinationRoot = Join-Path $ConfigsRootPath $slug
    $copied = 0
    $skipped = 0
    $skippedSensitive = 0

    try {
        $item = Get-Item -LiteralPath $source -Force -ErrorAction Stop
        if ($item.PSIsContainer) {
            if (-not (Test-Path -LiteralPath $destinationRoot)) {
                New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
            }

            $sourceRoot = ([System.IO.Path]::GetFullPath($item.FullName)).TrimEnd("\", "/")
            foreach ($child in @(Get-ChildItem -LiteralPath $item.FullName -Force -Recurse -ErrorAction SilentlyContinue)) {
                $childFullPath = [System.IO.Path]::GetFullPath($child.FullName)
                $relative = $childFullPath.Substring($sourceRoot.Length).TrimStart([char[]]@("\", "/"))
                if (Test-ExcludedConfigPath -RelativePath $relative) {
                    $skipped++
                    continue
                }
                if (-not $child.PSIsContainer -and (Test-SensitiveConfigPath -Path $child.FullName) -and -not $IncludeSensitive) {
                    $skippedSensitive++
                    continue
                }

                $destination = Join-Path $destinationRoot $relative
                if ($child.PSIsContainer) {
                    if (-not (Test-Path -LiteralPath $destination)) {
                        New-Item -ItemType Directory -Path $destination -Force | Out-Null
                    }
                } else {
                    $destinationParent = Split-Path -Parent $destination
                    if (-not (Test-Path -LiteralPath $destinationParent)) {
                        New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
                    }
                    Copy-Item -LiteralPath $child.FullName -Destination $destination -Force
                    $copied++
                }
            }
        } else {
            if ((Test-SensitiveConfigPath -Path $item.FullName) -and -not $IncludeSensitive) {
                $skippedSensitive++
                return [ordered]@{
                    backupPath = ""
                    backupStatus = "skipped_sensitive"
                    copiedFiles = 0
                    skippedFiles = 0
                    skippedSensitiveFiles = $skippedSensitive
                    error = ""
                }
            }

            if (-not (Test-Path -LiteralPath $destinationRoot)) {
                New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
            }
            $destination = Join-Path $destinationRoot $item.Name
            Copy-Item -LiteralPath $item.FullName -Destination $destination -Force
            $copied++
        }

        return [ordered]@{
            backupPath = $destinationRoot
            backupStatus = "backed_up"
            copiedFiles = $copied
            skippedFiles = $skipped
            skippedSensitiveFiles = $skippedSensitive
            error = ""
        }
    } catch {
        return [ordered]@{
            backupPath = ""
            backupStatus = "failed"
            copiedFiles = $copied
            skippedFiles = $skipped
            skippedSensitiveFiles = $skippedSensitive
            error = $_.Exception.Message
        }
    }
}

function New-ConfigBackupRecord {
    param(
        [Parameter(Mandatory = $true)]
        $Candidate,

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [string]$BackupPath = "",
        [int]$CopiedFiles = 0,
        [int]$SkippedFiles = 0,
        [int]$SkippedSensitiveFiles = 0,
        [string]$ErrorMessage = ""
    )

    return [ordered]@{
        type = [string](Get-MapValue -Map $Candidate -Key "type")
        name = [string](Get-MapValue -Map $Candidate -Key "name")
        appName = [string](Get-MapValue -Map $Candidate -Key "appName")
        appNamePattern = [string](Get-MapValue -Map $Candidate -Key "appNamePattern")
        originalPath = [string](Get-MapValue -Map $Candidate -Key "originalPath")
        restorePathTemplate = [string](Get-MapValue -Map $Candidate -Key "restorePathTemplate")
        backupPath = $BackupPath
        backupStatus = $Status
        copiedFiles = $CopiedFiles
        skippedFiles = $SkippedFiles
        skippedSensitiveFiles = $SkippedSensitiveFiles
        error = $ErrorMessage
        warnings = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $Candidate -Key "warnings"))
    }
}

function New-ConfigBackupMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$BackupRootPath,

        [Parameter(Mandatory = $true)]
        [object[]]$ConfigRecords,

        [Parameter(Mandatory = $true)]
        [object[]]$DetectOnlyRecords,

        [bool]$IncludeSensitive
    )

    return [ordered]@{
        schemaVersion = "config-backup.1"
        createdAt = (Get-Date).ToString("o")
        toolName = $script:ToolName
        root = [ordered]@{
            winCarryRoot = $RootPath
        }
        backupRoot = $BackupRootPath
        includeSensitive = $IncludeSensitive
        exclusions = @("cache", "logs", "temp", "tmp", "crash", "node_modules", "*.log", "*.tmp", "*.cache")
        configs = @($ConfigRecords)
        detectOnly = @($DetectOnlyRecords)
        summary = [ordered]@{
            backedUp = @($ConfigRecords | Where-Object { $_.backupStatus -eq "backed_up" }).Count
            skippedSensitive = @($ConfigRecords | Where-Object { $_.backupStatus -eq "skipped_sensitive" }).Count
            failed = @($ConfigRecords | Where-Object { $_.backupStatus -eq "failed" }).Count
            detectOnly = @($DetectOnlyRecords).Count
        }
    }
}

function Convert-ConfigBackupReportToMarkdown {
    param(
        [Parameter(Mandatory = $true)]
        $Metadata
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $summary = Get-MapValue -Map $Metadata -Key "summary"
    $configs = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $Metadata -Key "configs"))
    $detectOnly = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $Metadata -Key "detectOnly"))

    $lines.Add("# WinCarry Config Backup Report")
    $lines.Add("")
    $lines.Add(("Created: {0}" -f (Get-MapValue -Map $Metadata -Key "createdAt")))
    $lines.Add(("Backup root: {0}" -f (Get-MapValue -Map $Metadata -Key "backupRoot")))
    $lines.Add(("Included sensitive configs: {0}" -f (Get-MapValue -Map $Metadata -Key "includeSensitive")))
    $lines.Add("")
    $lines.Add("## Summary")
    $lines.Add("")
    $lines.Add(("- Backed up: {0}" -f (Get-MapValue -Map $summary -Key "backedUp")))
    $lines.Add(("- Skipped sensitive: {0}" -f (Get-MapValue -Map $summary -Key "skippedSensitive")))
    $lines.Add(("- Failed: {0}" -f (Get-MapValue -Map $summary -Key "failed")))
    $lines.Add(("- Detect-only: {0}" -f (Get-MapValue -Map $summary -Key "detectOnly")))
    $lines.Add("")
    $lines.Add("## Backups")
    $lines.Add("")
    if ($configs.Count -eq 0) {
        $lines.Add("No config candidates were found.")
    } else {
        foreach ($record in $configs) {
            $lines.Add(("- {0}: {1}" -f (Get-MapValue -Map $record -Key "name"), (Get-MapValue -Map $record -Key "backupStatus")))
            $lines.Add(("  Original: {0}" -f (Get-MapValue -Map $record -Key "originalPath")))
            $backupPath = [string](Get-MapValue -Map $record -Key "backupPath")
            if (-not [string]::IsNullOrWhiteSpace($backupPath)) {
                $lines.Add(("  Backup: {0}" -f $backupPath))
            }
            $lines.Add(("  Restore template: {0}" -f (Get-MapValue -Map $record -Key "restorePathTemplate")))
            $warnings = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $record -Key "warnings"))
            foreach ($warning in $warnings) {
                $lines.Add(("  Warning: {0}" -f $warning))
            }
            $errorText = [string](Get-MapValue -Map $record -Key "error")
            if (-not [string]::IsNullOrWhiteSpace($errorText)) {
                $lines.Add(("  Error: {0}" -f $errorText))
            }
        }
    }
    $lines.Add("")
    $lines.Add("## Detect Only")
    $lines.Add("")
    if ($detectOnly.Count -eq 0) {
        $lines.Add("No detect-only profiles were found.")
    } else {
        foreach ($record in $detectOnly) {
            $lines.Add(("- {0}: {1}" -f (Get-MapValue -Map $record -Key "name"), (Get-MapValue -Map $record -Key "originalPath")))
            foreach ($warning in (ConvertTo-ArrayValue -Value (Get-MapValue -Map $record -Key "warnings"))) {
                $lines.Add(("  Warning: {0}" -f $warning))
            }
        }
    }

    return ($lines -join [Environment]::NewLine)
}

function Add-PropertyIfMissing {
    param(
        [Parameter(Mandatory = $true)]
        $Object,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        $Value
    )

    if ($Object -is [System.Collections.IDictionary]) {
        if (-not $Object.Contains($Name)) {
            $Object[$Name] = $Value
        }
        return
    }

    if ($null -eq $Object.PSObject.Properties[$Name]) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Find-ManifestAppForConfigRecord {
    param(
        [Parameter(Mandatory = $true)]
        $Manifest,

        [Parameter(Mandatory = $true)]
        $Record
    )

    $pattern = [string](Get-MapValue -Map $Record -Key "appNamePattern")
    if ([string]::IsNullOrWhiteSpace($pattern)) {
        $pattern = [regex]::Escape([string](Get-MapValue -Map $Record -Key "appName"))
    }

    foreach ($app in @(Get-MapValue -Map $Manifest -Key "apps")) {
        $name = [string](Get-MapValue -Map $app -Key "name")
        if (-not [string]::IsNullOrWhiteSpace($name) -and $name.ToLowerInvariant() -match $pattern.ToLowerInvariant()) {
            return $app
        }
    }

    return $null
}

function New-ManifestConfigPathRecord {
    param(
        [Parameter(Mandatory = $true)]
        $Record
    )

    return [ordered]@{
        type = [string](Get-MapValue -Map $Record -Key "type")
        name = [string](Get-MapValue -Map $Record -Key "name")
        originalPath = [string](Get-MapValue -Map $Record -Key "originalPath")
        restorePathTemplate = [string](Get-MapValue -Map $Record -Key "restorePathTemplate")
        backupPath = [string](Get-MapValue -Map $Record -Key "backupPath")
        backupStatus = [string](Get-MapValue -Map $Record -Key "backupStatus")
        warnings = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $Record -Key "warnings"))
    }
}

function Add-ConfigPathToApp {
    param(
        [Parameter(Mandatory = $true)]
        $App,

        [Parameter(Mandatory = $true)]
        $ConfigPath
    )

    Add-PropertyIfMissing -Object $App -Name "configPaths" -Value @()
    $existing = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $App -Key "configPaths"))
    $originalPath = [string](Get-MapValue -Map $ConfigPath -Key "originalPath")
    $name = [string](Get-MapValue -Map $ConfigPath -Key "name")
    $exists = $false
    foreach ($item in $existing) {
        if ([string](Get-MapValue -Map $item -Key "originalPath") -eq $originalPath -and [string](Get-MapValue -Map $item -Key "name") -eq $name) {
            $exists = $true
            break
        }
    }

    if (-not $exists) {
        $App.configPaths = @($existing + @($ConfigPath))
    }
}

function Merge-ConfigBackupIntoManifest {
    param(
        [Parameter(Mandatory = $true)]
        $Manifest,

        [Parameter(Mandatory = $true)]
        $BackupMetadata
    )

    Add-PropertyIfMissing -Object $Manifest -Name "configBackups" -Value @()
    Add-PropertyIfMissing -Object $Manifest -Name "unmatchedConfigPaths" -Value @()

    $backupSummary = [ordered]@{
        createdAt = [string](Get-MapValue -Map $BackupMetadata -Key "createdAt")
        backupRoot = [string](Get-MapValue -Map $BackupMetadata -Key "backupRoot")
        includeSensitive = [bool](Get-MapValue -Map $BackupMetadata -Key "includeSensitive")
        summary = (Get-MapValue -Map $BackupMetadata -Key "summary")
    }
    $existingBackups = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $Manifest -Key "configBackups"))
    $Manifest.configBackups = @($existingBackups + @($backupSummary))

    foreach ($record in @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $BackupMetadata -Key "configs"))) {
        $status = [string](Get-MapValue -Map $record -Key "backupStatus")
        if ($status -ne "backed_up") {
            continue
        }

        $configPath = New-ManifestConfigPathRecord -Record $record
        $app = Find-ManifestAppForConfigRecord -Manifest $Manifest -Record $record
        if ($null -eq $app) {
            $existingUnmatched = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $Manifest -Key "unmatchedConfigPaths"))
            $Manifest.unmatchedConfigPaths = @($existingUnmatched + @($configPath))
        } else {
            Add-ConfigPathToApp -App $app -ConfigPath $configPath
        }
    }
}

function Merge-LatestConfigBackupIntoManifest {
    param(
        [Parameter(Mandatory = $true)]
        $Manifest,

        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $latestConfigBackupPath = Get-LatestConfigBackupMetadataPath -RootPath $RootPath
    if (-not (Test-Path -LiteralPath $latestConfigBackupPath)) {
        return $false
    }

    try {
        $metadata = Get-Content -Raw -LiteralPath $latestConfigBackupPath | ConvertFrom-Json
        Merge-ConfigBackupIntoManifest -Manifest $Manifest -BackupMetadata $metadata
        return $true
    } catch {
        return $false
    }
}

function Get-RegistryUninstallEvidence {
    $records = @()
    $warnings = @()

    if (-not (Test-IsWindows)) {
        return [ordered]@{
            records = $records
            warnings = @("Registry uninstall scan skipped because this is not Windows.")
        }
    }

    $registryRoots = @(
        [ordered]@{ hive = "HKLM"; view = "64-bit"; path = "Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Uninstall" },
        [ordered]@{ hive = "HKLM"; view = "32-bit"; path = "Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" },
        [ordered]@{ hive = "HKCU"; view = "user"; path = "Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall" }
    )

    foreach ($root in $registryRoots) {
        if (-not (Test-Path -LiteralPath $root.path)) {
            $warnings += ("Registry path not found: {0}" -f $root.path)
            continue
        }

        try {
            foreach ($key in (Get-ChildItem -LiteralPath $root.path -ErrorAction Stop)) {
                try {
                    $property = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
                    if ([string]::IsNullOrWhiteSpace($property.DisplayName)) {
                        continue
                    }

                    $data = [ordered]@{
                        displayName = [string]$property.DisplayName
                        displayVersion = [string]$property.DisplayVersion
                        publisher = [string]$property.Publisher
                        installLocation = [string]$property.InstallLocation
                        uninstallString = [string]$property.UninstallString
                        quietUninstallString = [string]$property.QuietUninstallString
                        estimatedSize = [string]$property.EstimatedSize
                        systemComponent = [string]$property.SystemComponent
                        installDate = [string]$property.InstallDate
                        registryPath = [string]$key.Name
                        hive = [string]$root.hive
                        registryView = [string]$root.view
                    }

                    $records += (New-ScanEvidenceRecord -Source "registry" -EvidenceType "uninstall-key" -Data $data)
                } catch {
                    $warnings += ("Failed to read registry key {0}: {1}" -f $key.Name, $_.Exception.Message)
                }
            }
        } catch {
            $warnings += ("Failed to enumerate registry path {0}: {1}" -f $root.path, $_.Exception.Message)
        }
    }

    return [ordered]@{
        records = $records
        warnings = $warnings
    }
}

function Get-WingetEvidence {
    $records = @()
    $warnings = @()
    $capture = Invoke-ExternalCommandCapture -CommandName "winget" -Arguments @("list", "--source", "winget", "--disable-interactivity")

    if (-not $capture.available) {
        return [ordered]@{
            records = $records
            warnings = @("winget not found.")
        }
    }

    $parsed = Convert-WingetCaptureToRows -Capture $capture
    $rows = @($parsed.rows)
    $selectedCapture = $capture
    $selectedParsed = $parsed

    if ($rows.Count -eq 0) {
        $fallbackCapture = Invoke-ExternalCommandCapture -CommandName "winget" -Arguments @("list", "--disable-interactivity")
        $fallbackParsed = Convert-WingetCaptureToRows -Capture $fallbackCapture
        $fallbackRows = @($fallbackParsed.rows)

        if ($fallbackRows.Count -gt 0) {
            $warnings += $parsed.warnings
            $warnings += ("winget {0} returned no parseable package rows; used fallback command: {1}." -f $parsed.argumentText, $fallbackParsed.argumentText)
            $warnings += $fallbackParsed.warnings
            $rows = $fallbackRows
            $selectedCapture = $fallbackCapture
            $selectedParsed = $fallbackParsed
        } else {
            $warnings += $parsed.warnings
            if ($parsed.outputSample.Count -gt 0) {
                $warnings += ("winget {0} output sample: {1}" -f $parsed.argumentText, ($parsed.outputSample -join " | "))
            }

            $warnings += $fallbackParsed.warnings
            if ($fallbackParsed.outputSample.Count -gt 0) {
                $warnings += ("winget {0} output sample: {1}" -f $fallbackParsed.argumentText, ($fallbackParsed.outputSample -join " | "))
            }

            $selectedCapture = $fallbackCapture
            $selectedParsed = $fallbackParsed
        }
    } else {
        $warnings += $parsed.warnings
    }

    foreach ($row in $rows) {
        $data = [ordered]@{
            name = [string]$row["Name"]
            packageId = [string]$row["Id"]
            version = [string]$row["Version"]
            available = [string]$row["Available"]
            source = [string]$row["Source"]
            commandSource = [string]$selectedCapture.source
            commandArguments = [string]$selectedParsed.argumentText
            exitCode = [string]$selectedCapture.exitCode
            parser = [string]$selectedParsed.parser
        }

        $records += (New-ScanEvidenceRecord -Source "winget" -EvidenceType "package-manager-list" -Data $data)
    }

    $nonEmptyLines = @($selectedCapture.lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($records.Count -eq 0) {
        if ($nonEmptyLines.Count -gt 0) {
            $warnings += "winget output was captured but no table rows were parsed."
        } else {
            $warnings += "winget returned no output."
        }
    }

    return [ordered]@{
        records = $records
        warnings = $warnings
    }
}

function Get-ChocolateyEvidence {
    $records = @()
    $warnings = @()
    $capture = Invoke-ExternalCommandCapture -CommandName "choco" -Arguments @("list", "--local-only", "--limit-output")

    if (-not $capture.available) {
        return [ordered]@{
            records = $records
            warnings = @("Chocolatey not found.")
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($capture.error)) {
        $warnings += ("choco list failed: {0}" -f $capture.error)
    }

    foreach ($line in $capture.lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $trimmed = $line.Trim()
        if ($trimmed -match "packages installed" -or $trimmed -match "^Chocolatey") {
            continue
        }

        $parts = $trimmed.Split("|")
        if ($parts.Count -ge 2) {
            $name = $parts[0].Trim()
            $version = $parts[1].Trim()
        } else {
            $tokens = $trimmed -split "\s+"
            if ($tokens.Count -lt 2) {
                continue
            }
            $name = $tokens[0]
            $version = $tokens[1]
        }

        $data = [ordered]@{
            packageName = $name
            version = $version
            commandSource = [string]$capture.source
            exitCode = [string]$capture.exitCode
        }

        $records += (New-ScanEvidenceRecord -Source "chocolatey" -EvidenceType "package-manager-list" -Data $data)
    }

    return [ordered]@{
        records = $records
        warnings = $warnings
    }
}

function Get-ScoopEvidence {
    $records = @()
    $warnings = @()
    $capture = Invoke-ExternalCommandCapture -CommandName "scoop" -Arguments @("list")

    if (-not $capture.available) {
        return [ordered]@{
            records = $records
            warnings = @("Scoop not found.")
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($capture.error)) {
        $warnings += ("scoop list failed: {0}" -f $capture.error)
    }

    $rows = Convert-FixedWidthTable -Lines $capture.lines -ColumnNames @("Name", "Version", "Source", "Updated", "Info") -RequiredColumnNames @("Name")
    foreach ($row in $rows) {
        $data = [ordered]@{
            name = [string]$row["Name"]
            version = [string]$row["Version"]
            bucket = [string]$row["Source"]
            updated = [string]$row["Updated"]
            info = [string]$row["Info"]
            commandSource = [string]$capture.source
            exitCode = [string]$capture.exitCode
        }

        $records += (New-ScanEvidenceRecord -Source "scoop" -EvidenceType "package-manager-list" -Data $data)
    }

    $nonEmptyLines = @($capture.lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($records.Count -eq 0) {
        if ($nonEmptyLines.Count -gt 0) {
            $warnings += "Scoop output was captured but no table rows were parsed."
        } else {
            $warnings += "Scoop returned no output."
        }
    }

    return [ordered]@{
        records = $records
        warnings = $warnings
    }
}

function Get-StartMenuShortcutEvidence {
    $records = @()
    $warnings = @()

    $startMenuRoots = @()
    if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
        $startMenuRoots += (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs")
    }
    if (-not [string]::IsNullOrWhiteSpace($env:PROGRAMDATA)) {
        $startMenuRoots += (Join-Path $env:PROGRAMDATA "Microsoft\Windows\Start Menu\Programs")
    }

    if ($startMenuRoots.Count -eq 0) {
        return [ordered]@{
            records = $records
            warnings = @("Start Menu shortcut roots are not available in this environment.")
        }
    }

    $shell = $null
    if (Test-IsWindows) {
        try {
            $shell = New-Object -ComObject WScript.Shell
        } catch {
            $warnings += ("Failed to create WScript.Shell COM object for shortcut target parsing: {0}" -f $_.Exception.Message)
        }
    } else {
        $warnings += "Start Menu shortcut target parsing skipped because this is not Windows."
    }

    foreach ($root in $startMenuRoots) {
        $resolvedRoot = Resolve-DisplayPath -Path $root
        if (-not (Test-Path -LiteralPath $resolvedRoot)) {
            $warnings += ("Start Menu path not found: {0}" -f $resolvedRoot)
            continue
        }

        foreach ($shortcut in (Get-ChildItem -LiteralPath $resolvedRoot -Filter "*.lnk" -Recurse -File -ErrorAction SilentlyContinue)) {
            $targetPath = ""
            $workingDirectory = ""
            $arguments = ""

            if ($null -ne $shell) {
                try {
                    $shortcutObject = $shell.CreateShortcut($shortcut.FullName)
                    $targetPath = [string]$shortcutObject.TargetPath
                    $workingDirectory = [string]$shortcutObject.WorkingDirectory
                    $arguments = [string]$shortcutObject.Arguments
                } catch {
                    $warnings += ("Failed to read shortcut target {0}: {1}" -f $shortcut.FullName, $_.Exception.Message)
                }
            }

            $data = [ordered]@{
                name = [System.IO.Path]::GetFileNameWithoutExtension($shortcut.Name)
                shortcutPath = [string]$shortcut.FullName
                targetPath = $targetPath
                workingDirectory = $workingDirectory
                arguments = $arguments
                root = $resolvedRoot
            }

            $records += (New-ScanEvidenceRecord -Source "startMenu" -EvidenceType "shortcut" -Data $data)
        }
    }

    return [ordered]@{
        records = $records
        warnings = $warnings
    }
}

function Get-KnownFolderEvidence {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $records = @()
    $warnings = @()
    $knownFolders = @()

    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $knownFolders += [ordered]@{ label = "Program Files"; path = $env:ProgramFiles }
    }
    if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
        $knownFolders += [ordered]@{ label = "Program Files (x86)"; path = ${env:ProgramFiles(x86)} }
    }
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $knownFolders += [ordered]@{ label = "LocalAppData Programs"; path = (Join-Path $env:LOCALAPPDATA "Programs") }
    }

    $knownFolders += [ordered]@{ label = "WinCarry manual apps"; path = (Join-Path (Join-Path $RootPath "apps") "manual") }
    $knownFolders += [ordered]@{ label = "WinCarry portable"; path = (Join-Path $RootPath "portable") }
    $knownFolders += [ordered]@{ label = "WinCarry scoop apps"; path = (Join-Path (Join-Path $RootPath "scoop") "apps") }

    foreach ($knownFolder in $knownFolders) {
        $resolvedPath = Resolve-DisplayPath -Path $knownFolder.path
        if (-not (Test-Path -LiteralPath $resolvedPath)) {
            $warnings += ("Known folder not found: {0} ({1})" -f $knownFolder.label, $resolvedPath)
            continue
        }

        foreach ($child in (Get-ChildItem -LiteralPath $resolvedPath -Directory -ErrorAction SilentlyContinue)) {
            $data = [ordered]@{
                name = [string]$child.Name
                path = [string]$child.FullName
                parentLabel = [string]$knownFolder.label
                parentPath = [string]$resolvedPath
                evidenceOnly = "Folder presence is supporting evidence only; it is not proof of an installed app."
            }

            $records += (New-ScanEvidenceRecord -Source "knownFolder" -EvidenceType "folder-presence" -Data $data)
        }
    }

    return [ordered]@{
        records = $records
        warnings = $warnings
    }
}

function Add-ScanSourceResult {
    param(
        [Parameter(Mandatory = $true)]
        $Scan,

        [Parameter(Mandatory = $true)]
        [string]$SourceName,

        [Parameter(Mandatory = $true)]
        $Result
    )

    foreach ($record in $Result.records) {
        $Scan["evidence"] += $record
    }

    $Scan["sources"][$SourceName] = [ordered]@{
        count = $Result.records.Count
        warnings = @($Result.warnings)
    }

    foreach ($warning in $Result.warnings) {
        $Scan["warnings"] += [ordered]@{
            source = $SourceName
            message = $warning
        }
    }
}

function New-AppScanSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $resolvedRoot = Resolve-DisplayPath -Path $RootPath
    $scan = [ordered]@{
        schemaVersion = "raw-scan.1"
        createdAt = (Get-Date).ToString("o")
        toolName = $script:ToolName
        scriptPath = (Resolve-DisplayPath -Path (Get-CurrentScriptPath))
        root = [ordered]@{
            requestedRoot = $RootPath
            resolvedRoot = $resolvedRoot
            exists = (Test-Path -LiteralPath $resolvedRoot)
        }
        notes = @(
            "Raw detection evidence is preserved for auditability.",
            "Logical app records are deduplicated and classified using conservative Phase 4 rules.",
            "Known-folder records remain supporting evidence unless matched with stronger signals."
        )
        sources = [ordered]@{}
        warnings = @()
        evidence = @()
        apps = @()
        classificationSummary = [ordered]@{}
    }

    Add-ScanSourceResult -Scan $scan -SourceName "registry" -Result (Get-RegistryUninstallEvidence)
    Add-ScanSourceResult -Scan $scan -SourceName "winget" -Result (Get-WingetEvidence)
    Add-ScanSourceResult -Scan $scan -SourceName "chocolatey" -Result (Get-ChocolateyEvidence)
    Add-ScanSourceResult -Scan $scan -SourceName "scoop" -Result (Get-ScoopEvidence)
    Add-ScanSourceResult -Scan $scan -SourceName "startMenu" -Result (Get-StartMenuShortcutEvidence)
    Add-ScanSourceResult -Scan $scan -SourceName "knownFolder" -Result (Get-KnownFolderEvidence -RootPath $resolvedRoot)

    $scan["apps"] = @(New-LogicalAppsFromEvidence -Evidence $scan.evidence)
    $scan["classificationSummary"] = Get-ClassificationSummary -Apps $scan.apps

    return $scan
}

function Show-AppScanSummary {
    param(
        [Parameter(Mandatory = $true)]
        $Scan
    )

    Write-Host ""
    Write-Host "Raw App Detection Scan"
    Write-Host ""
    Write-Host ("Created: {0}" -f $Scan.createdAt)
    Write-Host ("Root: {0}" -f $Scan.root.resolvedRoot)
    Write-Host ""
    Write-Host "Sources"

    foreach ($sourceName in $Scan.sources.Keys) {
        $source = $Scan.sources[$sourceName]
        Write-Host ("- {0}: {1} record(s)" -f $sourceName, $source.count)
    }

    Write-Host ""
    Write-Host ("Total evidence records: {0}" -f $Scan.evidence.Count)

    if ($null -ne $Scan.apps) {
        Write-Host ""
        Write-Host ("Logical apps: {0}" -f $Scan.apps.Count)

        if ($null -ne $Scan.classificationSummary -and $Scan.classificationSummary.Count -gt 0) {
            Write-Host ""
            Write-Host "Classifications"
            foreach ($classification in $Scan.classificationSummary.Keys) {
                Write-Host ("- {0}: {1}" -f $classification, $Scan.classificationSummary[$classification])
            }
        }
    }

    if ($Scan.warnings.Count -gt 0) {
        Write-Host ""
        Write-Host "Warnings"
        foreach ($warning in $Scan.warnings) {
            Write-WarningText ("{0}: {1}" -f $warning.source, $warning.message)
        }
    }

    $sample = @($Scan.evidence | Select-Object -First 10)
    if ($sample.Count -gt 0) {
        Write-Host ""
        Write-Host "Sample evidence"
        foreach ($record in $sample) {
            $name = ""
            if ($record.data.Contains("displayName")) {
                $name = $record.data.displayName
            } elseif ($record.data.Contains("name")) {
                $name = $record.data.name
            } elseif ($record.data.Contains("packageName")) {
                $name = $record.data.packageName
            }

            if ([string]::IsNullOrWhiteSpace($name)) {
                $name = "(unnamed)"
            }

            Write-Host ("- [{0}] {1}" -f $record.source, $name)
        }
    }
}

function Invoke-Scan {
    param(
        [string]$RootPath,
        [switch]$DryRunOnly
    )

    if ([string]::IsNullOrWhiteSpace($RootPath)) {
        $RootPath = $script:DefaultRoot
    }

    $scan = New-AppScanSnapshot -RootPath $RootPath
    Show-AppScanSummary -Scan $scan

    $scanPath = Get-ScanOutputPath -RootPath $scan.root.resolvedRoot
    $logPath = Get-LogPath -RootPath $scan.root.resolvedRoot

    Write-Host ""
    if ($DryRunOnly) {
        Write-Info "Dry-run only. No scan output or log file was written."
        Write-Info ("Would write raw scan JSON if reports folder exists: {0}" -f $scanPath)
        Write-Info ("Would write log if logs folder exists: {0}" -f $logPath)
        return
    }

    $reportDirectory = Split-Path -Parent $scanPath
    if (Test-Path -LiteralPath $reportDirectory) {
        $scanJson = $scan | ConvertTo-Json -Depth 16
        Set-Content -LiteralPath $scanPath -Value $scanJson -Encoding UTF8
        Write-Info ("Raw scan written: {0}" -f $scanPath)
    } else {
        Write-WarningText ("Raw scan not written because folder does not exist: {0}" -f $reportDirectory)
    }

    $logDirectory = Split-Path -Parent $logPath
    if (Test-Path -LiteralPath $logDirectory) {
        $sourceSummary = (($scan.sources.Keys | ForEach-Object { "{0}:{1}" -f $_, $scan.sources[$_].count }) -join ",")
        $classificationSummary = (($scan.classificationSummary.Keys | ForEach-Object { "{0}:{1}" -f $_, $scan.classificationSummary[$_] }) -join ",")
        $message = "App scan completed for root {0}; evidence={1}; apps={2}; sources={3}; classifications={4}" -f $scan.root.resolvedRoot, $scan.evidence.Count, $scan.apps.Count, $sourceSummary, $classificationSummary
        Write-WinCarryLog -RootPath $scan.root.resolvedRoot -Operation "scan" -Result "success" -Message $message
        Write-Info ("Log updated: {0}" -f $logPath)
    } else {
        Write-WarningText ("Log not written because folder does not exist: {0}" -f $logDirectory)
    }
}

function Show-ManifestPlan {
    param(
        [Parameter(Mandatory = $true)]
        $Manifest,

        [Parameter(Mandatory = $true)]
        $Paths,

        [Parameter(Mandatory = $true)]
        [string]$ActionLabel
    )

    $summary = Get-MapValue -Map $Manifest -Key "summary"
    Write-Host ""
    Write-Host $ActionLabel
    Write-Host ""
    Write-Host ("Apps: {0}" -f (Get-MapValue -Map $summary -Key "appCount"))
    Write-Host ("Manual reinstall / review: {0}" -f (Get-MapValue -Map $summary -Key "manualReinstallCount"))
    Write-Host ("Unsupported / do not restore automatically: {0}" -f (Get-MapValue -Map $summary -Key "unsupportedCount"))
    Write-Host ""
    Write-Host "Will write:"

    foreach ($key in (Get-ObjectKeys -Object $Paths)) {
        Write-Host ("- {0}" -f (Get-MapValue -Map $Paths -Key $key))
    }
}

function Ensure-ManifestArtifactDirectories {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    foreach ($folder in @("manifests", "reports", "logs")) {
        $path = Join-Path $RootPath $folder
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }
}

function Write-ManifestArtifacts {
    param(
        [Parameter(Mandatory = $true)]
        $Manifest,

        [Parameter(Mandatory = $true)]
        $Paths,

        [switch]$IncludeManifestFiles
    )

    if ($IncludeManifestFiles) {
        $manifestJson = $Manifest | ConvertTo-Json -Depth 20
        Set-Content -LiteralPath $Paths.manifest -Value $manifestJson -Encoding UTF8
        Set-Content -LiteralPath $Paths.latestManifest -Value $manifestJson -Encoding UTF8
    }

    $markdown = Convert-ManifestReportToMarkdown -Manifest $Manifest
    $text = Convert-ManifestReportToText -Manifest $Manifest
    $manualText = Convert-AppSummaryListToText -Title "WinCarry Manual Reinstall / Review List" -Apps (ConvertTo-ArrayValue -Value (Get-MapValue -Map $Manifest -Key "manualReinstall"))
    $unsupportedText = Convert-AppSummaryListToText -Title "WinCarry Unsupported / Do Not Restore Automatically List" -Apps (ConvertTo-ArrayValue -Value (Get-MapValue -Map $Manifest -Key "unsupported"))

    Set-Content -LiteralPath $Paths.reportMarkdown -Value $markdown -Encoding UTF8
    Set-Content -LiteralPath $Paths.reportText -Value $text -Encoding UTF8
    Set-Content -LiteralPath $Paths.manualReinstallList -Value $manualText -Encoding UTF8
    Set-Content -LiteralPath $Paths.unsupportedList -Value $unsupportedText -Encoding UTF8
}

function Invoke-Manifest {
    param(
        [string]$RootPath,
        [switch]$DryRunOnly
    )

    if ([string]::IsNullOrWhiteSpace($RootPath)) {
        $RootPath = $script:DefaultRoot
    }

    $scan = New-AppScanSnapshot -RootPath $RootPath
    Show-AppScanSummary -Scan $scan

    $manifest = New-AppManifestFromScan -Scan $scan
    $timestamp = Get-FileTimestamp
    $paths = Get-ManifestArtifactPaths -RootPath $scan.root.resolvedRoot -Timestamp $timestamp
    Show-ManifestPlan -Manifest $manifest -Paths $paths -ActionLabel "Prepare Reinstall Manifest"

    if ($DryRunOnly) {
        Write-Host ""
        Write-Info "Dry-run only. No manifest, report, list, or log files were written."
        return
    }

    if (-not (Read-RequiredConfirmation -Prompt "Generate WinCarry manifest and report files?")) {
        Write-Host ""
        Write-Info "Manifest generation cancelled. No files were changed."
        return
    }

    Ensure-ManifestArtifactDirectories -RootPath $scan.root.resolvedRoot
    Write-ManifestArtifacts -Manifest $manifest -Paths $paths -IncludeManifestFiles

    $message = "Manifest generated for root {0}; apps={1}; manual={2}; unsupported={3}; manifest={4}" -f $scan.root.resolvedRoot, $manifest.summary.appCount, $manifest.summary.manualReinstallCount, $manifest.summary.unsupportedCount, $paths.manifest
    Write-WinCarryLog -RootPath $scan.root.resolvedRoot -Operation "manifest" -Result "success" -Message $message

    Write-Host ""
    Write-Info ("Manifest written: {0}" -f $paths.manifest)
    Write-Info ("Latest manifest updated: {0}" -f $paths.latestManifest)
    Write-Info ("Markdown report written: {0}" -f $paths.reportMarkdown)
    Write-Info ("Text report written: {0}" -f $paths.reportText)
    Write-Info ("Manual reinstall list written: {0}" -f $paths.manualReinstallList)
    Write-Info ("Unsupported list written: {0}" -f $paths.unsupportedList)
    Write-Info ("Log updated: {0}" -f (Get-LogPath -RootPath $scan.root.resolvedRoot))
}

function Invoke-Report {
    param(
        [string]$RootPath,
        [switch]$DryRunOnly
    )

    if ([string]::IsNullOrWhiteSpace($RootPath)) {
        $RootPath = $script:DefaultRoot
    }

    $resolvedRoot = Resolve-DisplayPath -Path $RootPath
    $latestManifestPath = Get-LatestManifestPath -RootPath $resolvedRoot
    if (-not (Test-Path -LiteralPath $latestManifestPath)) {
        Write-Host ""
        Write-WarningText ("Latest manifest not found: {0}" -f $latestManifestPath)
        Write-Info "Run the manifest command first."
        return
    }

    $manifest = Get-Content -Raw -LiteralPath $latestManifestPath | ConvertFrom-Json
    $timestamp = Get-FileTimestamp
    $paths = Get-ManifestArtifactPaths -RootPath $resolvedRoot -Timestamp $timestamp
    Show-ManifestPlan -Manifest $manifest -Paths ([ordered]@{
        reportMarkdown = $paths.reportMarkdown
        reportText = $paths.reportText
        manualReinstallList = $paths.manualReinstallList
        unsupportedList = $paths.unsupportedList
    }) -ActionLabel "Generate Reports From Latest Manifest"

    if ($DryRunOnly) {
        Write-Host ""
        Write-Info "Dry-run only. No report, list, or log files were written."
        return
    }

    if (-not (Read-RequiredConfirmation -Prompt "Generate report files from latest manifest?")) {
        Write-Host ""
        Write-Info "Report generation cancelled. No files were changed."
        return
    }

    Ensure-ManifestArtifactDirectories -RootPath $resolvedRoot
    Write-ManifestArtifacts -Manifest $manifest -Paths $paths

    $message = "Reports generated from latest manifest {0}; report={1}" -f $latestManifestPath, $paths.reportMarkdown
    Write-WinCarryLog -RootPath $resolvedRoot -Operation "report" -Result "success" -Message $message

    Write-Host ""
    Write-Info ("Markdown report written: {0}" -f $paths.reportMarkdown)
    Write-Info ("Text report written: {0}" -f $paths.reportText)
    Write-Info ("Manual reinstall list written: {0}" -f $paths.manualReinstallList)
    Write-Info ("Unsupported list written: {0}" -f $paths.unsupportedList)
    Write-Info ("Log updated: {0}" -f (Get-LogPath -RootPath $resolvedRoot))
}

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

function Show-SetupPlan {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $settingsPath = Get-SettingsPath -RootPath $RootPath
    $destinationScript = Join-Path $RootPath $script:ScriptFileName
    $sourceScript = Get-CurrentScriptPath

    Write-Host ""
    Write-Host "Dry Run Plan"
    Write-Host ""
    Write-Host ("WinCarry root: {0}" -f $RootPath)
    Write-Host ""
    Write-Host "Will ensure folders exist:"

    foreach ($folder in (Get-WinCarryFolders -RootPath $RootPath)) {
        Write-Host ("- {0}" -f $folder)
    }

    Write-Host ""
    Write-Host "Will create if missing:"
    Write-Host ("- {0}" -f $settingsPath)

    if ($sourceScript -ne $destinationScript) {
        Write-Host ("- {0}" -f $destinationScript)
    }

    Write-Host ""
    Write-Host "Will preserve existing files:"
    Write-Host ("- Existing settings file will not be overwritten.")
    Write-Host ("- Existing script file in root will not be overwritten.")
}

function Invoke-Setup {
    param(
        [string]$RootPath,
        [switch]$DryRunOnly
    )

    if ([string]::IsNullOrWhiteSpace($RootPath)) {
        $RootPath = $script:DefaultRoot
    }

    Show-SetupPlan -RootPath $RootPath

    if ($DryRunOnly) {
        Write-Host ""
        Write-Info "Dry-run only. No files were changed."
        return
    }

    if (-not (Read-RequiredConfirmation -Prompt "Create/update the WinCarry folder structure?")) {
        Write-Host ""
        Write-Info "Setup cancelled. No files were changed."
        return
    }

    foreach ($folder in (Get-WinCarryFolders -RootPath $RootPath)) {
        if (-not (Test-Path -LiteralPath $folder)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
        }
    }

    $settingsPath = Get-SettingsPath -RootPath $RootPath
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        $settings = New-DefaultSettings -RootPath $RootPath
        $settingsJson = $settings | ConvertTo-Json -Depth 8
        Set-Content -LiteralPath $settingsPath -Value $settingsJson -Encoding UTF8
    }

    $sourceScript = Get-CurrentScriptPath
    $destinationScript = Join-Path $RootPath $script:ScriptFileName

    if (($sourceScript -ne $destinationScript) -and (Test-Path -LiteralPath $sourceScript) -and (-not (Test-Path -LiteralPath $destinationScript))) {
        Copy-Item -LiteralPath $sourceScript -Destination $destinationScript
    }

    Write-WinCarryLog -RootPath $RootPath -Operation "setup" -Result "success" -Message ("Root initialized at {0}" -f $RootPath)

    Write-Host ""
    Write-Info "Setup complete."
    Write-Info ("Root: {0}" -f $RootPath)
    Write-Info ("Settings: {0}" -f $settingsPath)
    Write-Info ("Log: {0}" -f (Get-LogPath -RootPath $RootPath))
}

function Show-CommandPlaceholder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [Parameter(Mandatory = $true)]
        [string]$Phase
    )

    Write-Host ""
    Write-Info ("'{0}' is planned for {1}." -f $CommandName, $Phase)
    Write-Info "No changes were made."
}

function Show-Help {
    Write-Host ""
    Write-Host "WinCarry"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\wincarry.ps1"
    Write-Host "  .\wincarry.ps1 setup [-Root D:\WinCarry] [-DryRun]"
    Write-Host "  .\wincarry.ps1 preflight [-Root D:\WinCarry] [-DryRun]"
    Write-Host "  .\wincarry.ps1 scan [-Root D:\WinCarry] [-DryRun]"
    Write-Host "  .\wincarry.ps1 manifest [-Root D:\WinCarry] [-DryRun]"
    Write-Host "  .\wincarry.ps1 report [-Root D:\WinCarry] [-DryRun]"
    Write-Host "  .\wincarry.ps1 backup [-Root D:\WinCarry] [-DryRun]"
    Write-Host "  .\wincarry.ps1 restore"
    Write-Host "  .\wincarry.ps1 offline"
    Write-Host "  .\wincarry.ps1 junction"
    Write-Host ""
    Write-Host "Implemented: CLI shell, setup, preflight, app detection/classification, manifests, reports, and config backup."
    Write-Host "Later-phase commands currently show placeholders and make no changes."
}

function Show-MainMenu {
    while ($true) {
        Write-Host ""
        Write-Host "WinCarry"
        Write-Host ""
        Write-Host "What do you want to do?"
        Write-Host ""
        Write-Host "[1] Setup WinCarry folder"
        Write-Host "[2] Preflight system snapshot"
        Write-Host "[3] Scan installed apps"
        Write-Host "[4] Backup app config"
        Write-Host "[5] Prepare reinstall manifest"
        Write-Host "[6] Restore after Windows reinstall"
        Write-Host "[7] View reports"
        Write-Host "[8] Advanced / Experimental: create junction"
        Write-Host "[9] Offline-safe mode"
        Write-Host "[0] Exit"
        Write-Host ""

        $choice = Read-Host "Choose an option"

        switch ($choice) {
            "1" {
                $rootInput = Read-Host ("WinCarry root [{0}]" -f $script:DefaultRoot)
                if ([string]::IsNullOrWhiteSpace($rootInput)) {
                    $rootInput = $script:DefaultRoot
                }
                Invoke-Setup -RootPath $rootInput
            }
            "2" {
                $rootInput = Read-Host ("WinCarry root [{0}]" -f $script:DefaultRoot)
                if ([string]::IsNullOrWhiteSpace($rootInput)) {
                    $rootInput = $script:DefaultRoot
                }
                Invoke-Preflight -RootPath $rootInput
            }
            "3" {
                $rootInput = Read-Host ("WinCarry root [{0}]" -f $script:DefaultRoot)
                if ([string]::IsNullOrWhiteSpace($rootInput)) {
                    $rootInput = $script:DefaultRoot
                }
                Invoke-Scan -RootPath $rootInput
            }
            "4" {
                $rootInput = Read-Host ("WinCarry root [{0}]" -f $script:DefaultRoot)
                if ([string]::IsNullOrWhiteSpace($rootInput)) {
                    $rootInput = $script:DefaultRoot
                }
                Invoke-Backup -RootPath $rootInput
            }
            "5" {
                $rootInput = Read-Host ("WinCarry root [{0}]" -f $script:DefaultRoot)
                if ([string]::IsNullOrWhiteSpace($rootInput)) {
                    $rootInput = $script:DefaultRoot
                }
                Invoke-Manifest -RootPath $rootInput
            }
            "6" { Show-CommandPlaceholder -CommandName "restore" -Phase "Phase 7" }
            "7" {
                $rootInput = Read-Host ("WinCarry root [{0}]" -f $script:DefaultRoot)
                if ([string]::IsNullOrWhiteSpace($rootInput)) {
                    $rootInput = $script:DefaultRoot
                }
                Invoke-Report -RootPath $rootInput
            }
            "8" { Show-CommandPlaceholder -CommandName "junction" -Phase "Phase 10" }
            "9" { Show-CommandPlaceholder -CommandName "offline" -Phase "Phase 11" }
            "0" {
                Write-Host ""
                Write-Info "Goodbye."
                return
            }
            default {
                Write-Host ""
                Write-WarningText "Unknown menu option."
            }
        }
    }
}

function Invoke-CommandRouter {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName
    )

    $normalizedCommand = $CommandName.ToLowerInvariant()

    if ($script:SupportedCommands -notcontains $normalizedCommand) {
        Write-ErrorText ("Unknown command: {0}" -f $CommandName)
        Show-Help
        exit 1
    }

    switch ($normalizedCommand) {
        "menu" { Show-MainMenu }
        "setup" { Invoke-Setup -RootPath $Root -DryRunOnly:$DryRun }
        "preflight" { Invoke-Preflight -RootPath $Root -DryRunOnly:$DryRun }
        "scan" { Invoke-Scan -RootPath $Root -DryRunOnly:$DryRun }
        "backup" { Invoke-Backup -RootPath $Root -DryRunOnly:$DryRun }
        "manifest" { Invoke-Manifest -RootPath $Root -DryRunOnly:$DryRun }
        "restore" { Show-CommandPlaceholder -CommandName "restore" -Phase "Phase 7" }
        "report" { Invoke-Report -RootPath $Root -DryRunOnly:$DryRun }
        "offline" { Show-CommandPlaceholder -CommandName "offline" -Phase "Phase 11" }
        "junction" { Show-CommandPlaceholder -CommandName "junction" -Phase "Phase 10" }
        "help" { Show-Help }
    }
}

Invoke-CommandRouter -CommandName $Command
