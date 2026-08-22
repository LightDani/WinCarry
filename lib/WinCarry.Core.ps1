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
        (Join-Path $RootPath $script:HelperFolderName),
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

