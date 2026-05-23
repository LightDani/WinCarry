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

    $runtimePattern = "(visual c\+\+.*(redistributable|runtime)|\.net.*(runtime|sdk|desktop runtime)|webview2 runtime|directx|windows sdk)"
    $driverPattern = "\b(driver|virtual display|virtual usb|chipset|firmware|printer driver|scanner driver|bluetooth driver|audio driver|display driver)\b"
    $securityPattern = "\b(antivirus|endpoint|edr|firewall|vpn|wireguard|openvpn|nordvpn|proton vpn|security agent)\b"

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
    } elseif ($hasSystemComponentEvidence) {
        $classification = "Unsupported / risky"
        $confidence = "Unsupported"
        $strategy = "do-not-restore"
        $reasons += "Registry marks this entry as a Windows system component."
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
    Write-Host "  .\wincarry.ps1 backup"
    Write-Host "  .\wincarry.ps1 manifest"
    Write-Host "  .\wincarry.ps1 restore"
    Write-Host "  .\wincarry.ps1 report"
    Write-Host "  .\wincarry.ps1 offline"
    Write-Host "  .\wincarry.ps1 junction"
    Write-Host ""
    Write-Host "Implemented: CLI shell, setup, preflight system snapshot, and app detection with classification."
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
            "4" { Show-CommandPlaceholder -CommandName "backup" -Phase "Phase 6" }
            "5" { Show-CommandPlaceholder -CommandName "manifest" -Phase "Phase 5" }
            "6" { Show-CommandPlaceholder -CommandName "restore" -Phase "Phase 7" }
            "7" { Show-CommandPlaceholder -CommandName "report" -Phase "Phase 5" }
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
        "backup" { Show-CommandPlaceholder -CommandName "backup" -Phase "Phase 6" }
        "manifest" { Show-CommandPlaceholder -CommandName "manifest" -Phase "Phase 5" }
        "restore" { Show-CommandPlaceholder -CommandName "restore" -Phase "Phase 7" }
        "report" { Show-CommandPlaceholder -CommandName "report" -Phase "Phase 5" }
        "offline" { Show-CommandPlaceholder -CommandName "offline" -Phase "Phase 11" }
        "junction" { Show-CommandPlaceholder -CommandName "junction" -Phase "Phase 10" }
        "help" { Show-Help }
    }
}

Invoke-CommandRouter -CommandName $Command
