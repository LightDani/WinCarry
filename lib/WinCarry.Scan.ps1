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

