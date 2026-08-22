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

    $definitions += New-ConfigDefinition -Type "safe" -Name "VS Code User Settings" -AppName "Visual Studio Code" -AppNamePattern "visual studio code|vs code|\bcode\b" -PathTemplate "%APPDATA%\Code\User" -BackupSlug "vscode-user"
    $definitions += New-ConfigDefinition -Type "safe" -Name "VS Code Insiders User Settings" -AppName "Visual Studio Code" -AppNamePattern "visual studio code|vs code|\bcode\b" -PathTemplate "%APPDATA%\Code - Insiders\User" -BackupSlug "vscode-insiders-user"
    $definitions += New-ConfigDefinition -Type "safe" -Name "VSCodium User Settings" -AppName "VSCodium" -AppNamePattern "vscodium" -PathTemplate "%APPDATA%\VSCodium\User" -BackupSlug "vscodium-user"
    $definitions += New-ConfigDefinition -Type "safe" -Name "Git global config" -AppName "Git" -AppNamePattern "\bgit\b" -PathTemplate "%USERPROFILE%\.gitconfig" -BackupSlug "gitconfig"
    $definitions += New-ConfigDefinition -Type "safe" -Name "Git global ignore" -AppName "Git" -AppNamePattern "\bgit\b" -PathTemplate "%USERPROFILE%\.gitignore_global" -BackupSlug "gitignore-global"
    $definitions += New-ConfigDefinition -Type "safe" -Name "Windows Terminal settings" -AppName "Windows Terminal" -AppNamePattern "windows terminal" -PathTemplate "%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" -BackupSlug "windows-terminal-settings"
    $definitions += New-ConfigDefinition -Type "safe" -Name "Windows Terminal Preview settings" -AppName "Windows Terminal" -AppNamePattern "windows terminal" -PathTemplate "%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json" -BackupSlug "windows-terminal-preview-settings"
    $definitions += New-ConfigDefinition -Type "safe" -Name "PowerShell WindowsPowerShell current-user profile" -AppName "PowerShell" -AppNamePattern "^(windows powershell|powershell 7|microsoft powershell|powershell)$" -PathTemplate "%USERPROFILE%\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1" -BackupSlug "powershell-windows-profile"
    $definitions += New-ConfigDefinition -Type "safe" -Name "PowerShell WindowsPowerShell all-hosts profile" -AppName "PowerShell" -AppNamePattern "^(windows powershell|powershell 7|microsoft powershell|powershell)$" -PathTemplate "%USERPROFILE%\Documents\WindowsPowerShell\profile.ps1" -BackupSlug "powershell-windows-allhosts-profile"
    $definitions += New-ConfigDefinition -Type "safe" -Name "PowerShell 7 current-user profile" -AppName "PowerShell" -AppNamePattern "^(windows powershell|powershell 7|microsoft powershell|powershell)$" -PathTemplate "%USERPROFILE%\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" -BackupSlug "powershell-7-profile"
    $definitions += New-ConfigDefinition -Type "safe" -Name "PowerShell 7 all-hosts profile" -AppName "PowerShell" -AppNamePattern "^(windows powershell|powershell 7|microsoft powershell|powershell)$" -PathTemplate "%USERPROFILE%\Documents\PowerShell\profile.ps1" -BackupSlug "powershell-7-allhosts-profile"
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
        isDirectory = [bool](Get-MapValue -Map $Candidate -Key "isDirectory")
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
        [AllowEmptyCollection()]
        [object[]]$ConfigRecords,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
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

function Test-ManifestAppMatchesConfigRecord {
    param(
        $App,
        [Parameter(Mandatory = $true)]
        $Record
    )

    $name = [string](Get-MapValue -Map $App -Key "name")
    if ([string]::IsNullOrWhiteSpace($name)) {
        return $false
    }

    $appName = [string](Get-MapValue -Map $Record -Key "appName")
    if (-not [string]::IsNullOrWhiteSpace($appName) -and (Test-StrongNameMatch -Left $appName -Right $name)) {
        return $true
    }

    $pattern = [string](Get-MapValue -Map $Record -Key "appNamePattern")
    if ([string]::IsNullOrWhiteSpace($pattern)) {
        if ([string]::IsNullOrWhiteSpace($appName)) {
            return $false
        }
        $pattern = [regex]::Escape($appName)
    }

    $normalizedName = Get-NormalizedName -Name $name
    try {
        if ($name.ToLowerInvariant() -match $pattern.ToLowerInvariant()) {
            return $true
        }
        if (-not [string]::IsNullOrWhiteSpace($normalizedName) -and $normalizedName -match $pattern.ToLowerInvariant()) {
            return $true
        }
    } catch {
        return $false
    }

    return $false
}

function Find-ManifestAppForConfigRecord {
    param(
        [Parameter(Mandatory = $true)]
        $Manifest,

        [Parameter(Mandatory = $true)]
        $Record
    )

    foreach ($app in @(Get-MapValue -Map $Manifest -Key "apps")) {
        if (Test-ManifestAppMatchesConfigRecord -App $app -Record $Record) {
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
        appName = [string](Get-MapValue -Map $Record -Key "appName")
        appNamePattern = [string](Get-MapValue -Map $Record -Key "appNamePattern")
        originalPath = [string](Get-MapValue -Map $Record -Key "originalPath")
        restorePathTemplate = [string](Get-MapValue -Map $Record -Key "restorePathTemplate")
        isDirectory = [bool](Get-MapValue -Map $Record -Key "isDirectory")
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
    foreach ($app in @(Get-MapValue -Map $Manifest -Key "apps")) {
        Add-PropertyIfMissing -Object $app -Name "configPaths" -Value @()
        $app.configPaths = @()
    }
    $Manifest.unmatchedConfigPaths = @()

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

