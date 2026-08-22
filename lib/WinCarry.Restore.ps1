function Get-RestoreReportPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$Timestamp
    )

    $reportFileName = "restore-{0}.md" -f $Timestamp
    return (Join-Path (Join-Path $RootPath "reports") $reportFileName)
}

function Resolve-RestoreRootPath {
    param(
        [string]$RootPath
    )

    if (-not [string]::IsNullOrWhiteSpace($RootPath)) {
        return (Resolve-DisplayPath -Path $RootPath)
    }

    $scriptDirectory = Resolve-DisplayPath -Path (Get-ScriptDirectory)
    if (-not [string]::IsNullOrWhiteSpace($scriptDirectory)) {
        $scriptManifest = Get-LatestManifestPath -RootPath $scriptDirectory
        if (Test-Path -LiteralPath $scriptManifest) {
            return $scriptDirectory
        }
    }

    return (Resolve-DisplayPath -Path $script:DefaultRoot)
}

function Resolve-RestoreManifestPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [string]$ManifestPath
    )

    if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
        return (Get-LatestManifestPath -RootPath $RootPath)
    }

    $expanded = [Environment]::ExpandEnvironmentVariables($ManifestPath)
    if ([System.IO.Path]::IsPathRooted($expanded)) {
        return (Resolve-DisplayPath -Path $expanded)
    }

    return (Resolve-DisplayPath -Path (Join-Path $RootPath $expanded))
}

function Test-SameDisplayPath {
    param(
        [string]$Left,
        [string]$Right
    )

    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) {
        return $false
    }

    $leftPath = (Resolve-DisplayPath -Path $Left).TrimEnd("\", "/")
    $rightPath = (Resolve-DisplayPath -Path $Right).TrimEnd("\", "/")

    if (Test-IsWindows) {
        return [string]::Equals($leftPath, $rightPath, [StringComparison]::OrdinalIgnoreCase)
    }

    return [string]::Equals($leftPath, $rightPath, [StringComparison]::Ordinal)
}

function Get-ManifestWinCarryRoot {
    param($Manifest)

    $root = Get-MapValue -Map $Manifest -Key "root"
    return [string](Get-MapValue -Map $root -Key "winCarryRoot")
}

function Read-WinCarryManifest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath
    )

    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        Write-Host ""
        Write-WarningText ("Manifest not found: {0}" -f $ManifestPath)
        Write-Info "Run manifest before restore, or copy the preserved WinCarry root that contains manifests\latest.json."
        return $null
    }

    try {
        return (Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json)
    } catch {
        Write-Host ""
        Write-ErrorText ("Could not read manifest: {0}" -f $_.Exception.Message)
        return $null
    }
}

function Get-CurrentPackageManagerStatusMap {
    param(
        [object[]]$PackageManagers
    )

    $map = [ordered]@{}
    foreach ($manager in @(ConvertTo-ArrayValue -Value $PackageManagers)) {
        $name = [string](Get-MapValue -Map $manager -Key "name")
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }
        $map[$name] = $manager
    }

    return $map
}

function Test-RestorePackageInstallable {
    param($Package)

    $manager = [string](Get-MapValue -Map $Package -Key "manager")
    $packageId = [string](Get-MapValue -Map $Package -Key "id")

    if ([string]::IsNullOrWhiteSpace($manager) -or [string]::IsNullOrWhiteSpace($packageId)) {
        return $false
    }

    if (@("winget", "chocolatey", "scoop") -notcontains $manager) {
        return $false
    }

    if ($packageId -match "^(MSIX|ARP)\\") {
        return $false
    }

    return $true
}

function Get-RestorePackageForApp {
    param($App)

    $packages = @(Get-AppPackages -App $App)
    if ($packages.Count -eq 0) {
        return $null
    }

    $strategy = [string](Get-MapValue -Map $App -Key "restoreStrategy")
    if ($strategy -eq "restore-via-scoop") {
        $preferences = @("scoop", "winget", "chocolatey")
    } else {
        $preferences = @("winget", "chocolatey", "scoop")
    }

    foreach ($preferredManager in $preferences) {
        foreach ($package in $packages) {
            $manager = [string](Get-MapValue -Map $package -Key "manager")
            if ($manager -ne $preferredManager) {
                continue
            }
            if (Test-RestorePackageInstallable -Package $package) {
                return $package
            }
        }
    }

    foreach ($package in $packages) {
        if (Test-RestorePackageInstallable -Package $package) {
            return $package
        }
    }

    return $null
}

function Test-AppSupportsPackageRestore {
    param($App)

    $strategy = [string](Get-MapValue -Map $App -Key "restoreStrategy")
    $confidence = [string](Get-MapValue -Map $App -Key "restoreConfidence")

    if ($confidence -eq "Unsupported") {
        return $false
    }

    if (@("restore-via-scoop", "reinstall-via-package-manager") -notcontains $strategy) {
        return $false
    }

    return ($null -ne (Get-RestorePackageForApp -App $App))
}

function Get-RestorableManifestApps {
    param($Manifest)

    $apps = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $Manifest -Key "apps"))
    return @($apps | Where-Object { Test-AppSupportsPackageRestore -App $_ })
}

function Get-RestorePackageManagerNameForApp {
    param($App)

    $package = Get-RestorePackageForApp -App $App
    return [string](Get-MapValue -Map $package -Key "manager")
}

function Get-ManifestConfigPathCount {
    param($Manifest)

    $count = 0
    foreach ($app in @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $Manifest -Key "apps"))) {
        $count += @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $app -Key "configPaths")).Count
    }

    $count += @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $Manifest -Key "unmatchedConfigPaths")).Count
    return $count
}


function Test-MapHasKey {
    param(
        $Map,
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if ($null -eq $Map) {
        return $false
    }

    if ($Map -is [System.Collections.IDictionary]) {
        return $Map.Contains($Key)
    }

    return ($null -ne $Map.PSObject.Properties[$Key])
}

function Set-MapValue {
    param(
        [Parameter(Mandatory = $true)]
        $Map,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        $Value
    )

    if ($Map -is [System.Collections.IDictionary]) {
        $Map[$Key] = $Value
        return
    }

    if ($null -ne $Map.PSObject.Properties[$Key]) {
        $Map.$Key = $Value
    } else {
        $Map | Add-Member -NotePropertyName $Key -NotePropertyValue $Value
    }
}

function Get-ConfigRestoreExistingBackupRootPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$Timestamp
    )

    return (Join-Path (Join-Path (Join-Path $RootPath "backups") $Timestamp) "existing-before-restore")
}

function Get-ConfigRestoreSourceInfo {
    param($ConfigPath)

    $backupPath = [string](Get-MapValue -Map $ConfigPath -Key "backupPath")
    $originalPath = [string](Get-MapValue -Map $ConfigPath -Key "originalPath")
    $sourcePath = ""
    $sourceExists = $false
    $sourceIsDirectory = $false

    if ([string]::IsNullOrWhiteSpace($backupPath)) {
        return [ordered]@{
            sourcePath = ""
            sourceExists = $false
            sourceIsDirectory = $false
        }
    }

    $resolvedBackupPath = Resolve-DisplayPath -Path $backupPath
    $hasDirectoryFlag = Test-MapHasKey -Map $ConfigPath -Key "isDirectory"
    $originalIsDirectory = $false
    if ($hasDirectoryFlag) {
        $originalIsDirectory = [bool](Get-MapValue -Map $ConfigPath -Key "isDirectory")
    }

    if ($hasDirectoryFlag -and $originalIsDirectory) {
        $sourcePath = $resolvedBackupPath
        $sourceExists = (Test-Path -LiteralPath $sourcePath -PathType Container)
        $sourceIsDirectory = $true
    } else {
        $leaf = Split-Path -Leaf $originalPath
        $fileCandidate = ""
        if (-not [string]::IsNullOrWhiteSpace($leaf)) {
            $fileCandidate = Join-Path $resolvedBackupPath $leaf
        }

        if (-not [string]::IsNullOrWhiteSpace($fileCandidate) -and (Test-Path -LiteralPath $fileCandidate -PathType Leaf)) {
            $sourcePath = Resolve-DisplayPath -Path $fileCandidate
            $sourceExists = $true
            $sourceIsDirectory = $false
        } elseif ($hasDirectoryFlag -and -not $originalIsDirectory) {
            $sourcePath = $fileCandidate
            $sourceExists = $false
            $sourceIsDirectory = $false
        } elseif (Test-Path -LiteralPath $resolvedBackupPath -PathType Container) {
            $sourcePath = $resolvedBackupPath
            $sourceExists = $true
            $sourceIsDirectory = $true
        } elseif (Test-Path -LiteralPath $resolvedBackupPath -PathType Leaf) {
            $sourcePath = $resolvedBackupPath
            $sourceExists = $true
            $sourceIsDirectory = $false
        }
    }

    return [ordered]@{
        sourcePath = $sourcePath
        sourceExists = $sourceExists
        sourceIsDirectory = $sourceIsDirectory
    }
}

function Test-RestoreResultSucceededForApp {
    param(
        $App,
        [object[]]$SuccessfulRestoreResults
    )

    $appId = [string](Get-MapValue -Map $App -Key "id")
    $appName = [string](Get-MapValue -Map $App -Key "name")

    foreach ($result in @(ConvertTo-ArrayValue -Value $SuccessfulRestoreResults)) {
        if ([string](Get-MapValue -Map $result -Key "status") -ne "success") {
            continue
        }

        $resultAppId = [string](Get-MapValue -Map $result -Key "appId")
        $resultName = [string](Get-MapValue -Map $result -Key "name")
        if (-not [string]::IsNullOrWhiteSpace($appId) -and $resultAppId -eq $appId) {
            return $true
        }
        if (Test-StrongNameMatch -Left $appName -Right $resultName) {
            return $true
        }
    }

    return $false
}

function Find-CurrentDetectedAppForManifestApp {
    param(
        $ManifestApp,
        [object[]]$CurrentApps,
        [object[]]$SuccessfulRestoreResults = @()
    )

    $manifestAppName = [string](Get-MapValue -Map $ManifestApp -Key "name")
    if (Test-RestoreResultSucceededForApp -App $ManifestApp -SuccessfulRestoreResults $SuccessfulRestoreResults) {
        return [ordered]@{
            verified = $true
            method = "restored-in-this-run"
            matchedName = $manifestAppName
        }
    }

    $manifestPackages = @(Get-AppPackages -App $ManifestApp)
    foreach ($manifestPackage in $manifestPackages) {
        $manifestManager = [string](Get-MapValue -Map $manifestPackage -Key "manager")
        $manifestPackageId = Get-NormalizedPackageId -PackageId ([string](Get-MapValue -Map $manifestPackage -Key "id"))
        if ([string]::IsNullOrWhiteSpace($manifestPackageId)) {
            continue
        }

        foreach ($currentApp in @(ConvertTo-ArrayValue -Value $CurrentApps)) {
            foreach ($currentPackage in @(Get-AppPackages -App $currentApp)) {
                $currentManager = [string](Get-MapValue -Map $currentPackage -Key "manager")
                $currentPackageId = Get-NormalizedPackageId -PackageId ([string](Get-MapValue -Map $currentPackage -Key "id"))
                if ([string]::IsNullOrWhiteSpace($currentPackageId)) {
                    continue
                }
                if ($manifestPackageId -eq $currentPackageId -and ([string]::IsNullOrWhiteSpace($manifestManager) -or [string]::IsNullOrWhiteSpace($currentManager) -or $manifestManager -eq $currentManager)) {
                    return [ordered]@{
                        verified = $true
                        method = "package-match"
                        matchedName = [string](Get-MapValue -Map $currentApp -Key "name")
                    }
                }
            }
        }
    }

    foreach ($currentApp in @(ConvertTo-ArrayValue -Value $CurrentApps)) {
        $currentName = [string](Get-MapValue -Map $currentApp -Key "name")
        if (Test-StrongNameMatch -Left $manifestAppName -Right $currentName) {
            return [ordered]@{
                verified = $true
                method = "name-match"
                matchedName = $currentName
            }
        }
    }

    return [ordered]@{
        verified = $false
        method = "not-detected"
        matchedName = ""
    }
}


function Get-ConfigDefinitionForManifestConfigPath {
    param($ConfigPath)

    $name = [string](Get-MapValue -Map $ConfigPath -Key "name")
    $restorePathTemplate = [string](Get-MapValue -Map $ConfigPath -Key "restorePathTemplate")
    foreach ($definition in (Get-ConfigDefinitions)) {
        $definitionName = [string](Get-MapValue -Map $definition -Key "name")
        $definitionTemplate = [string](Get-MapValue -Map $definition -Key "restorePathTemplate")
        if (-not [string]::IsNullOrWhiteSpace($name) -and $definitionName -eq $name) {
            return $definition
        }
        if (-not [string]::IsNullOrWhiteSpace($restorePathTemplate) -and $definitionTemplate -eq $restorePathTemplate) {
            return $definition
        }
    }

    return $null
}

function Get-ConfigRestoreExpectedAppRecord {
    param($ConfigPath)

    $appName = [string](Get-MapValue -Map $ConfigPath -Key "appName")
    $appNamePattern = [string](Get-MapValue -Map $ConfigPath -Key "appNamePattern")
    if (-not [string]::IsNullOrWhiteSpace($appName) -or -not [string]::IsNullOrWhiteSpace($appNamePattern)) {
        return [ordered]@{
            appName = $appName
            appNamePattern = $appNamePattern
        }
    }

    $definition = Get-ConfigDefinitionForManifestConfigPath -ConfigPath $ConfigPath
    if ($null -eq $definition) {
        return $null
    }

    return [ordered]@{
        appName = [string](Get-MapValue -Map $definition -Key "appName")
        appNamePattern = [string](Get-MapValue -Map $definition -Key "appNamePattern")
    }
}

function New-ConfigRestoreCandidate {
    param(
        $App,
        [Parameter(Mandatory = $true)]
        $ConfigPath,
        [Parameter(Mandatory = $true)]
        [string]$ConflictPolicy,
        [object[]]$CurrentApps = @(),
        [object[]]$SuccessfulRestoreResults = @()
    )

    $linkedToApp = ($null -ne $App)
    $appId = ""
    $appName = "Unmatched config path"
    $appVerification = [ordered]@{
        verified = $false
        method = "no-linked-app"
        matchedName = ""
    }

    if ($linkedToApp) {
        $appId = [string](Get-MapValue -Map $App -Key "id")
        $appName = [string](Get-MapValue -Map $App -Key "name")
        $appVerification = Find-CurrentDetectedAppForManifestApp -ManifestApp $App -CurrentApps $CurrentApps -SuccessfulRestoreResults $SuccessfulRestoreResults
    }

    $expectedAppRecord = Get-ConfigRestoreExpectedAppRecord -ConfigPath $ConfigPath
    $expectedAppName = [string](Get-MapValue -Map $expectedAppRecord -Key "appName")
    $expectedAppMatchesLinkedApp = $true
    if ($linkedToApp -and $null -ne $expectedAppRecord) {
        $expectedAppMatchesLinkedApp = Test-ManifestAppMatchesConfigRecord -App $App -Record $expectedAppRecord
    }

    $name = [string](Get-MapValue -Map $ConfigPath -Key "name")
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = "Config path"
    }

    $restorePathTemplate = [string](Get-MapValue -Map $ConfigPath -Key "restorePathTemplate")
    $targetPath = Resolve-ConfigPathTemplate -Template $restorePathTemplate
    $sourceInfo = Get-ConfigRestoreSourceInfo -ConfigPath $ConfigPath
    $sourcePath = [string](Get-MapValue -Map $sourceInfo -Key "sourcePath")
    $sourceExists = [bool](Get-MapValue -Map $sourceInfo -Key "sourceExists")
    $sourceIsDirectory = [bool](Get-MapValue -Map $sourceInfo -Key "sourceIsDirectory")
    $backupStatus = [string](Get-MapValue -Map $ConfigPath -Key "backupStatus")
    $targetExists = $false
    if (-not [string]::IsNullOrWhiteSpace($targetPath)) {
        $targetExists = Test-Path -LiteralPath $targetPath
    }

    $insideProtectedPath = $false
    if (-not [string]::IsNullOrWhiteSpace($targetPath)) {
        $insideProtectedPath = Test-PathInsideProtectedPath -Path $targetPath -ProtectedPaths (Get-ProtectedPaths)
    }

    $status = "planned"
    $reason = "Ready to restore."
    $action = "restore"

    if ($ConflictPolicy -eq "skip") {
        $status = "skipped"
        $reason = "Config restore was not selected."
        $action = "none"
    } elseif (-not $linkedToApp) {
        $status = "skipped"
        $reason = "No linked manifest app is available for app verification."
        $action = "none"
    } elseif (-not $expectedAppMatchesLinkedApp) {
        $status = "skipped"
        if ([string]::IsNullOrWhiteSpace($expectedAppName)) {
            $reason = ("Config path does not appear intended for linked app: {0}. Regenerate the manifest after updating WinCarry." -f $appName)
        } else {
            $reason = ("Config path appears intended for {0}, but is linked to {1}. Regenerate the manifest after updating WinCarry." -f $expectedAppName, $appName)
        }
        $action = "none"
    } elseif (-not [bool](Get-MapValue -Map $appVerification -Key "verified")) {
        $status = "skipped"
        $reason = "Target app is not currently detected and was not restored successfully in this run."
        $action = "none"
    } elseif ($backupStatus -ne "backed_up") {
        $status = "skipped"
        $reason = ("Config backup status is not restorable: {0}." -f $backupStatus)
        $action = "none"
    } elseif ([string]::IsNullOrWhiteSpace($restorePathTemplate) -or [string]::IsNullOrWhiteSpace($targetPath)) {
        $status = "skipped"
        $reason = "Restore path template is missing or could not be resolved."
        $action = "none"
    } elseif ($insideProtectedPath) {
        $status = "skipped"
        $reason = "Resolved restore target is inside a protected Windows path."
        $action = "none"
    } elseif (-not $sourceExists) {
        $status = "skipped"
        $reason = "Backed-up config source was not found."
        $action = "none"
    } elseif ($targetExists -and $ConflictPolicy -eq "missing-only") {
        $status = "skipped"
        $reason = "Target config already exists; conflict policy is skip existing."
        $action = "none"
    } elseif ($targetExists -and $ConflictPolicy -eq "replace-existing") {
        $action = "backup-and-replace"
        $reason = "Existing config will be backed up before replacement."
    }

    return [ordered]@{
        appId = $appId
        appName = $appName
        linkedToApp = $linkedToApp
        expectedAppName = $expectedAppName
        expectedAppMatchesLinkedApp = $expectedAppMatchesLinkedApp
        name = $name
        type = [string](Get-MapValue -Map $ConfigPath -Key "type")
        originalPath = [string](Get-MapValue -Map $ConfigPath -Key "originalPath")
        restorePathTemplate = $restorePathTemplate
        sourceBackupPath = $sourcePath
        sourceExists = $sourceExists
        sourceIsDirectory = $sourceIsDirectory
        targetPath = $targetPath
        targetExists = $targetExists
        insideProtectedPath = $insideProtectedPath
        backupStatus = $backupStatus
        appVerified = [bool](Get-MapValue -Map $appVerification -Key "verified")
        appVerification = $appVerification
        conflictPolicy = $ConflictPolicy
        action = $action
        status = $status
        reason = $reason
        existingBackupPath = ""
        copiedFiles = 0
        error = ""
        warnings = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $ConfigPath -Key "warnings"))
    }
}

function Get-ConfigRestoreSummary {
    param(
        [object[]]$Candidates,
        [Parameter(Mandatory = $true)]
        [string]$ConflictPolicy,
        [Parameter(Mandatory = $true)]
        [string]$ExistingBackupRootPath
    )

    $candidateList = @(ConvertTo-ArrayValue -Value $Candidates)
    return [ordered]@{
        availableConfigPathCount = $candidateList.Count
        linkedConfigPathCount = @($candidateList | Where-Object { [bool](Get-MapValue -Map $_ -Key "linkedToApp") }).Count
        unmatchedConfigPathCount = @($candidateList | Where-Object { -not [bool](Get-MapValue -Map $_ -Key "linkedToApp") }).Count
        appVerifiedCount = @($candidateList | Where-Object { [bool](Get-MapValue -Map $_ -Key "appVerified") }).Count
        existingTargetCount = @($candidateList | Where-Object { [bool](Get-MapValue -Map $_ -Key "targetExists") }).Count
        plannedRestoreCount = @($candidateList | Where-Object { [string](Get-MapValue -Map $_ -Key "status") -eq "planned" }).Count
        restoredCount = @($candidateList | Where-Object { [string](Get-MapValue -Map $_ -Key "status") -eq "restored" }).Count
        skippedCount = @($candidateList | Where-Object { [string](Get-MapValue -Map $_ -Key "status") -eq "skipped" }).Count
        failedCount = @($candidateList | Where-Object { [string](Get-MapValue -Map $_ -Key "status") -eq "failed" }).Count
        conflictPolicy = $ConflictPolicy
        existingBackupRootPath = $ExistingBackupRootPath
    }
}

function Update-ConfigRestoreSummary {
    param(
        [Parameter(Mandatory = $true)]
        $ConfigRestore
    )

    $summary = Get-ConfigRestoreSummary -Candidates (Get-MapValue -Map $ConfigRestore -Key "candidates") -ConflictPolicy ([string](Get-MapValue -Map $ConfigRestore -Key "conflictPolicy")) -ExistingBackupRootPath ([string](Get-MapValue -Map $ConfigRestore -Key "existingBackupRootPath"))
    Set-MapValue -Map $ConfigRestore -Key "summary" -Value $summary
}

function New-ConfigRestorePlan {
    param(
        [Parameter(Mandatory = $true)]
        $Manifest,

        [Parameter(Mandatory = $true)]
        [string]$ConflictPolicy,

        [Parameter(Mandatory = $true)]
        [string]$ExistingBackupRootPath,

        [object[]]$CurrentApps = @(),
        [object[]]$SuccessfulRestoreResults = @()
    )

    $candidates = @()
    foreach ($app in @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $Manifest -Key "apps"))) {
        foreach ($configPath in @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $app -Key "configPaths"))) {
            $candidates += New-ConfigRestoreCandidate -App $app -ConfigPath $configPath -ConflictPolicy $ConflictPolicy -CurrentApps $CurrentApps -SuccessfulRestoreResults $SuccessfulRestoreResults
        }
    }

    foreach ($configPath in @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $Manifest -Key "unmatchedConfigPaths"))) {
        $candidates += New-ConfigRestoreCandidate -App $null -ConfigPath $configPath -ConflictPolicy $ConflictPolicy -CurrentApps $CurrentApps -SuccessfulRestoreResults $SuccessfulRestoreResults
    }

    $summary = Get-ConfigRestoreSummary -Candidates $candidates -ConflictPolicy $ConflictPolicy -ExistingBackupRootPath $ExistingBackupRootPath
    return [ordered]@{
        phase = "Phase 8"
        attempted = $false
        executed = $false
        conflictPolicy = $ConflictPolicy
        existingBackupRootPath = $ExistingBackupRootPath
        candidates = @($candidates)
        summary = $summary
    }
}

function Show-ConfigRestorePlan {
    param(
        [Parameter(Mandatory = $true)]
        $ConfigRestore
    )

    $summary = Get-MapValue -Map $ConfigRestore -Key "summary"
    $candidates = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $ConfigRestore -Key "candidates"))

    Write-Host ""
    Write-Host "Config Restore Plan"
    Write-Host ""
    Write-Host ("Conflict policy: {0}" -f (Get-MapValue -Map $summary -Key "conflictPolicy"))
    Write-Host ("Existing-config backup root: {0}" -f (Get-MapValue -Map $summary -Key "existingBackupRootPath"))
    Write-Host ("Available config paths: {0}" -f (Get-MapValue -Map $summary -Key "availableConfigPathCount"))
    Write-Host ("Linked to app: {0}" -f (Get-MapValue -Map $summary -Key "linkedConfigPathCount"))
    Write-Host ("App verified: {0}" -f (Get-MapValue -Map $summary -Key "appVerifiedCount"))
    Write-Host ("Existing target conflicts: {0}" -f (Get-MapValue -Map $summary -Key "existingTargetCount"))
    Write-Host ("Planned config restores: {0}" -f (Get-MapValue -Map $summary -Key "plannedRestoreCount"))
    Write-Host ("Skipped config paths: {0}" -f (Get-MapValue -Map $summary -Key "skippedCount"))

    Write-Host ""
    Write-Host "Config Restore Sample"
    if ($candidates.Count -eq 0) {
        Write-Host "- None"
        return
    }

    foreach ($candidate in @($candidates | Select-Object -First 10)) {
        $statusText = [string](Get-MapValue -Map $candidate -Key "status")
        $reason = [string](Get-MapValue -Map $candidate -Key "reason")
        Write-Host ("- {0} / {1}: {2}" -f (Get-MapValue -Map $candidate -Key "appName"), (Get-MapValue -Map $candidate -Key "name"), $statusText)
        Write-Host ("  Target: {0}" -f (Get-MapValue -Map $candidate -Key "targetPath"))
        if (-not [string]::IsNullOrWhiteSpace($reason)) {
            Write-Host ("  Reason: {0}" -f $reason)
        }
    }
    if ($candidates.Count -gt 10) {
        Write-Host ("- ... {0} more config path(s) in the restore report" -f ($candidates.Count - 10))
    }
}

function Read-ConfigRestorePolicy {
    param($ConfigRestore)

    $summary = Get-MapValue -Map $ConfigRestore -Key "summary"
    Write-Host ""
    Write-Host "Config Restore"
    Write-Host ""
    Write-Host ("Available config paths: {0}" -f (Get-MapValue -Map $summary -Key "availableConfigPathCount"))
    Write-Host ("Existing target conflicts: {0}" -f (Get-MapValue -Map $summary -Key "existingTargetCount"))
    Write-Host "[1] Skip config restore (default)"
    Write-Host "[2] Restore missing configs only"
    Write-Host "[3] Back up existing configs, then replace"
    Write-Host ""

    $choice = Read-Host "Choose config restore mode [1]"
    switch ($choice) {
        "2" { return "missing-only" }
        "3" { return "replace-existing" }
        default { return "skip" }
    }
}

function Backup-ExistingConfigTarget {
    param(
        [Parameter(Mandatory = $true)]
        $Candidate,

        [Parameter(Mandatory = $true)]
        [string]$ExistingBackupRootPath,

        [Parameter(Mandatory = $true)]
        [int]$Index
    )

    $targetPath = [string](Get-MapValue -Map $Candidate -Key "targetPath")
    if ([string]::IsNullOrWhiteSpace($targetPath) -or -not (Test-Path -LiteralPath $targetPath)) {
        return ""
    }

    if (-not (Test-Path -LiteralPath $ExistingBackupRootPath)) {
        New-Item -ItemType Directory -Path $ExistingBackupRootPath -Force | Out-Null
    }

    $safeName = Get-SafeFileName -Name ("{0}-{1}" -f (Get-MapValue -Map $Candidate -Key "appName"), (Get-MapValue -Map $Candidate -Key "name"))
    $backupDestination = Join-Path $ExistingBackupRootPath ("{0:000}-{1}" -f $Index, $safeName)
    if (-not (Test-Path -LiteralPath $backupDestination)) {
        New-Item -ItemType Directory -Path $backupDestination -Force | Out-Null
    }

    Copy-Item -LiteralPath $targetPath -Destination $backupDestination -Recurse -Force
    return (Resolve-DisplayPath -Path $backupDestination)
}

function Copy-ConfigRestoreSource {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath,

        [bool]$SourceIsDirectory
    )

    if ($SourceIsDirectory) {
        if (-not (Test-Path -LiteralPath $TargetPath)) {
            New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
        }

        foreach ($child in @(Get-ChildItem -LiteralPath $SourcePath -Force -ErrorAction SilentlyContinue)) {
            Copy-Item -LiteralPath $child.FullName -Destination $TargetPath -Recurse -Force
        }

        return @((Get-ChildItem -LiteralPath $SourcePath -Force -File -Recurse -ErrorAction SilentlyContinue)).Count
    }

    $targetParent = Split-Path -Parent $TargetPath
    if (-not [string]::IsNullOrWhiteSpace($targetParent) -and -not (Test-Path -LiteralPath $targetParent)) {
        New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
    }

    Copy-Item -LiteralPath $SourcePath -Destination $TargetPath -Force
    return 1
}

function Invoke-ConfigRestorePlan {
    param(
        [Parameter(Mandatory = $true)]
        $ConfigRestore
    )

    $candidates = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $ConfigRestore -Key "candidates"))
    $backupRoot = [string](Get-MapValue -Map $ConfigRestore -Key "existingBackupRootPath")
    $policy = [string](Get-MapValue -Map $ConfigRestore -Key "conflictPolicy")
    $index = 0

    Set-MapValue -Map $ConfigRestore -Key "attempted" -Value $true
    Set-MapValue -Map $ConfigRestore -Key "executed" -Value $true

    foreach ($candidate in $candidates) {
        if ([string](Get-MapValue -Map $candidate -Key "status") -ne "planned") {
            continue
        }

        $index++
        $targetPath = [string](Get-MapValue -Map $candidate -Key "targetPath")
        $sourcePath = [string](Get-MapValue -Map $candidate -Key "sourceBackupPath")
        $sourceIsDirectory = [bool](Get-MapValue -Map $candidate -Key "sourceIsDirectory")

        try {
            if (Test-Path -LiteralPath $targetPath) {
                if ($policy -ne "replace-existing") {
                    Set-MapValue -Map $candidate -Key "status" -Value "skipped"
                    Set-MapValue -Map $candidate -Key "reason" -Value "Target config already exists; conflict policy is skip existing."
                    continue
                }

                $existingBackupPath = Backup-ExistingConfigTarget -Candidate $candidate -ExistingBackupRootPath $backupRoot -Index $index
                Set-MapValue -Map $candidate -Key "existingBackupPath" -Value $existingBackupPath
                Remove-Item -LiteralPath $targetPath -Recurse -Force
            }

            $copiedFiles = Copy-ConfigRestoreSource -SourcePath $sourcePath -TargetPath $targetPath -SourceIsDirectory:$sourceIsDirectory
            Set-MapValue -Map $candidate -Key "status" -Value "restored"
            Set-MapValue -Map $candidate -Key "reason" -Value "Config restored."
            Set-MapValue -Map $candidate -Key "copiedFiles" -Value $copiedFiles
            Write-Info ("Config restored: {0} -> {1}" -f (Get-MapValue -Map $candidate -Key "name"), $targetPath)
        } catch {
            Set-MapValue -Map $candidate -Key "status" -Value "failed"
            Set-MapValue -Map $candidate -Key "reason" -Value "Config restore failed."
            Set-MapValue -Map $candidate -Key "error" -Value $_.Exception.Message
            Write-WarningText ("Config restore failed for {0}: {1}" -f (Get-MapValue -Map $candidate -Key "name"), $_.Exception.Message)
        }
    }

    Update-ConfigRestoreSummary -ConfigRestore $ConfigRestore
    return $ConfigRestore
}

function Read-RestoreSelectionMode {
    param($Manifest)

    $restorableApps = @(Get-RestorableManifestApps -Manifest $Manifest)
    $highConfidenceApps = @($restorableApps | Where-Object { [string](Get-MapValue -Map $_ -Key "restoreConfidence") -eq "High" })
    $scoopApps = @($restorableApps | Where-Object { (Get-RestorePackageManagerNameForApp -App $_) -eq "scoop" })
    $manualApps = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $Manifest -Key "manualReinstall"))
    $unsupportedApps = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $Manifest -Key "unsupported"))

    Write-Host ""
    Write-Host "Restore Selection"
    Write-Host ""
    Write-Host ("[1] High-confidence apps only ({0})" -f $highConfidenceApps.Count)
    Write-Host ("[2] Package-manager apps ({0})" -f $restorableApps.Count)
    Write-Host "[3] Selected apps by index"
    Write-Host ("[4] Scoop apps only ({0})" -f $scoopApps.Count)
    Write-Host ("[5] Manual review only ({0})" -f ($manualApps.Count + $unsupportedApps.Count))
    Write-Host ""

    $choice = Read-Host "Choose restore mode [2]"
    if ([string]::IsNullOrWhiteSpace($choice)) {
        return "package-manager"
    }

    switch ($choice) {
        "1" { return "high-confidence" }
        "2" { return "package-manager" }
        "3" { return "selected" }
        "4" { return "scoop" }
        "5" { return "manual-review" }
        default {
            Write-WarningText "Unknown restore mode. Using package-manager apps."
            return "package-manager"
        }
    }
}

function Read-RestoreVersionPolicy {
    Write-Host ""
    Write-Host "Version Policy"
    Write-Host ""
    Write-Host "[1] Install latest available package version"
    Write-Host "[2] Request detected version when supported"
    Write-Host ""

    $choice = Read-Host "Choose version policy [1]"
    if ($choice -eq "2") {
        return "detected"
    }

    return "latest"
}

function Show-RestoreAppSelection {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Apps
    )

    Write-Host ""
    Write-Host "Restorable Apps"
    Write-Host ""

    if ($Apps.Count -eq 0) {
        Write-Host "No package-manager restorable apps are available."
        return
    }

    for ($index = 0; $index -lt $Apps.Count; $index++) {
        $app = $Apps[$index]
        $package = Get-RestorePackageForApp -App $app
        $manager = [string](Get-MapValue -Map $package -Key "manager")
        $packageId = [string](Get-MapValue -Map $package -Key "id")
        Write-Host ("[{0}] {1} [{2}, {3}] {4}:{5}" -f ($index + 1), (Get-MapValue -Map $app -Key "name"), (Get-MapValue -Map $app -Key "classification"), (Get-MapValue -Map $app -Key "restoreConfidence"), $manager, $packageId)
    }
}

function Select-RestoreAppsByIndex {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Apps
    )

    Show-RestoreAppSelection -Apps $Apps
    if ($Apps.Count -eq 0) {
        return @()
    }

    $answer = Read-Host "Enter app numbers separated by commas"
    if ([string]::IsNullOrWhiteSpace($answer)) {
        Write-WarningText "No app numbers entered. No install commands will be planned."
        return @()
    }

    $selected = @()
    $seen = @{}
    foreach ($part in ($answer -split ",")) {
        $trimmed = $part.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }

        $number = 0
        if (-not [int]::TryParse($trimmed, [ref]$number)) {
            Write-WarningText ("Ignoring invalid app number: {0}" -f $trimmed)
            continue
        }

        if ($number -lt 1 -or $number -gt $Apps.Count) {
            Write-WarningText ("Ignoring out-of-range app number: {0}" -f $number)
            continue
        }

        if (-not $seen.ContainsKey($number)) {
            $seen[$number] = $true
            $selected += $Apps[$number - 1]
        }
    }

    return @($selected)
}

function Select-RestoreApps {
    param(
        [Parameter(Mandatory = $true)]
        $Manifest,

        [Parameter(Mandatory = $true)]
        [string]$SelectionMode
    )

    $restorableApps = @(Get-RestorableManifestApps -Manifest $Manifest)

    switch ($SelectionMode) {
        "high-confidence" {
            return @($restorableApps | Where-Object { [string](Get-MapValue -Map $_ -Key "restoreConfidence") -eq "High" })
        }
        "scoop" {
            return @($restorableApps | Where-Object { (Get-RestorePackageManagerNameForApp -App $_) -eq "scoop" })
        }
        "selected" {
            return @(Select-RestoreAppsByIndex -Apps $restorableApps)
        }
        "manual-review" {
            return @()
        }
        default {
            return @($restorableApps)
        }
    }
}

function Get-RestoreAppKey {
    param($App)

    $id = [string](Get-MapValue -Map $App -Key "id")
    if (-not [string]::IsNullOrWhiteSpace($id)) {
        return $id
    }

    return [string](Get-MapValue -Map $App -Key "name")
}

function Format-RestoreCommandArgument {
    param([string]$Value)

    if ($null -eq $Value) {
        return '""'
    }

    if ($Value -notmatch "[\s'`"]") {
        return $Value
    }

    $escaped = $Value -replace '"', '\"'
    return ('"{0}"' -f $escaped)
}

function Get-RestoreCommandLineText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [string[]]$Arguments = @()
    )

    $parts = @($CommandName)
    foreach ($argument in @($Arguments)) {
        $parts += (Format-RestoreCommandArgument -Value ([string]$argument))
    }

    return ($parts -join " ")
}

function Get-RestoreDetectedVersion {
    param(
        $App,
        $Package
    )

    $version = [string](Get-MapValue -Map $Package -Key "version")
    if (-not [string]::IsNullOrWhiteSpace($version)) {
        return $version
    }

    return [string](Get-MapValue -Map $App -Key "versionDetected")
}

function New-RestoreSkippedRecord {
    param(
        $App,
        [Parameter(Mandatory = $true)]
        [string]$Reason
    )

    return [ordered]@{
        appId = [string](Get-MapValue -Map $App -Key "id")
        name = [string](Get-MapValue -Map $App -Key "name")
        classification = [string](Get-MapValue -Map $App -Key "classification")
        restoreConfidence = [string](Get-MapValue -Map $App -Key "restoreConfidence")
        restoreStrategy = [string](Get-MapValue -Map $App -Key "restoreStrategy")
        package = (Get-AppPackageSummaryText -App $App)
        reason = $Reason
    }
}

function New-RestoreCommandPlanItem {
    param(
        [Parameter(Mandatory = $true)]
        $App,

        [Parameter(Mandatory = $true)]
        $Package,

        [Parameter(Mandatory = $true)]
        [string]$VersionPolicy
    )

    $manager = [string](Get-MapValue -Map $Package -Key "manager")
    $packageId = [string](Get-MapValue -Map $Package -Key "id")
    $packageSource = [string](Get-MapValue -Map $Package -Key "source")
    $detectedVersion = Get-RestoreDetectedVersion -App $App -Package $Package
    $commandName = ""
    $arguments = @()
    $warnings = @()

    if ($manager -eq "winget") {
        $commandName = "winget"
        $arguments = @("install", "--id", $packageId, "--exact", "--silent", "--accept-package-agreements", "--accept-source-agreements", "--disable-interactivity")
        if (-not [string]::IsNullOrWhiteSpace($packageSource)) {
            $arguments += @("--source", $packageSource)
        }
        if ($VersionPolicy -eq "detected" -and -not [string]::IsNullOrWhiteSpace($detectedVersion)) {
            $arguments += @("--version", $detectedVersion)
        }
    } elseif ($manager -eq "chocolatey") {
        $commandName = "choco"
        $arguments = @("install", $packageId, "-y", "--no-progress")
        if ($VersionPolicy -eq "detected" -and -not [string]::IsNullOrWhiteSpace($detectedVersion)) {
            $arguments += ("--version={0}" -f $detectedVersion)
        }
    } elseif ($manager -eq "scoop") {
        $commandName = "scoop"
        $arguments = @("install", $packageId)
        if ($VersionPolicy -eq "detected" -and -not [string]::IsNullOrWhiteSpace($detectedVersion)) {
            $warnings += "Scoop version pinning is not generated in Phase 7; latest available package will be installed."
        }
    }

    return [ordered]@{
        appId = [string](Get-MapValue -Map $App -Key "id")
        name = [string](Get-MapValue -Map $App -Key "name")
        classification = [string](Get-MapValue -Map $App -Key "classification")
        restoreConfidence = [string](Get-MapValue -Map $App -Key "restoreConfidence")
        restoreStrategy = [string](Get-MapValue -Map $App -Key "restoreStrategy")
        manager = $manager
        packageId = $packageId
        detectedVersion = $detectedVersion
        versionPolicy = $VersionPolicy
        command = $commandName
        arguments = @($arguments)
        commandLine = (Get-RestoreCommandLineText -CommandName $commandName -Arguments $arguments)
        warnings = @($warnings)
        status = "planned"
    }
}

function New-RestorePlan {
    param(
        [Parameter(Mandatory = $true)]
        $Manifest,

        [Parameter(Mandatory = $true)]
        $Preflight,

        [Parameter(Mandatory = $true)]
        [string]$ManifestPath,

        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$SelectionMode,

        [Parameter(Mandatory = $true)]
        [string]$VersionPolicy,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$SelectedApps,

        [string[]]$Warnings = @()
    )

    $apps = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $Manifest -Key "apps"))
    $restorableApps = @(Get-RestorableManifestApps -Manifest $Manifest)
    $manualApps = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $Manifest -Key "manualReinstall"))
    $unsupportedApps = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $Manifest -Key "unsupported"))
    $packageManagerMap = Get-CurrentPackageManagerStatusMap -PackageManagers $Preflight.packageManagers
    $selectedMap = @{}
    foreach ($selectedApp in @($SelectedApps)) {
        $selectedMap[(Get-RestoreAppKey -App $selectedApp)] = $true
    }

    $commands = @()
    $skipped = @()
    foreach ($app in $apps) {
        $isRestorable = Test-AppSupportsPackageRestore -App $app
        $isSelected = $selectedMap.ContainsKey((Get-RestoreAppKey -App $app))

        if (-not $isRestorable) {
            $skipped += New-RestoreSkippedRecord -App $app -Reason "Not eligible for automatic package-manager restore."
            continue
        }

        if (-not $isSelected) {
            $skipped += New-RestoreSkippedRecord -App $app -Reason "Not selected for this restore run."
            continue
        }

        $package = Get-RestorePackageForApp -App $app
        if ($null -eq $package) {
            $skipped += New-RestoreSkippedRecord -App $app -Reason "No installable package-manager ID was found."
            continue
        }

        $manager = [string](Get-MapValue -Map $package -Key "manager")
        $managerStatus = Get-MapValue -Map $packageManagerMap -Key $manager
        $available = [bool](Get-MapValue -Map $managerStatus -Key "available")
        if (-not $available) {
            $skipped += New-RestoreSkippedRecord -App $app -Reason ("Package manager not available on this machine: {0}." -f $manager)
            continue
        }

        $commands += New-RestoreCommandPlanItem -App $app -Package $package -VersionPolicy $VersionPolicy
    }

    return [ordered]@{
        schemaVersion = "restore-plan.1"
        createdAt = (Get-Date).ToString("o")
        manifestPath = $ManifestPath
        manifestCreatedAt = [string](Get-MapValue -Map $Manifest -Key "createdAt")
        manifestRoot = (Get-ManifestWinCarryRoot -Manifest $Manifest)
        currentRoot = $RootPath
        selectionMode = $SelectionMode
        versionPolicy = $VersionPolicy
        warnings = @($Warnings)
        preflight = $Preflight
        packageManagers = $packageManagerMap
        commands = @($commands)
        skipped = @($skipped)
        manualReview = @($manualApps)
        unsupported = @($unsupportedApps)
        configRestore = [ordered]@{
            phase = "Phase 8"
            attempted = $false
            executed = $false
            conflictPolicy = "skip"
            existingBackupRootPath = ""
            candidates = @()
            summary = [ordered]@{
                availableConfigPathCount = (Get-ManifestConfigPathCount -Manifest $Manifest)
                linkedConfigPathCount = 0
                unmatchedConfigPathCount = 0
                appVerifiedCount = 0
                existingTargetCount = 0
                plannedRestoreCount = 0
                restoredCount = 0
                skippedCount = 0
                failedCount = 0
                conflictPolicy = "skip"
                existingBackupRootPath = ""
            }
        }
        summary = [ordered]@{
            manifestAppCount = $apps.Count
            restorableCandidateCount = $restorableApps.Count
            selectedAppCount = @($SelectedApps).Count
            plannedInstallCount = $commands.Count
            skippedCount = $skipped.Count
            manualReviewCount = $manualApps.Count
            unsupportedCount = $unsupportedApps.Count
            configPathCount = (Get-ManifestConfigPathCount -Manifest $Manifest)
        }
    }
}

function Show-RestorePlan {
    param(
        [Parameter(Mandatory = $true)]
        $Plan
    )

    $summary = Get-MapValue -Map $Plan -Key "summary"
    Write-Host ""
    Write-Host "Restore Plan"
    Write-Host ""
    Write-Host ("Manifest: {0}" -f (Get-MapValue -Map $Plan -Key "manifestPath"))
    Write-Host ("Manifest root: {0}" -f (Get-MapValue -Map $Plan -Key "manifestRoot"))
    Write-Host ("Current root: {0}" -f (Get-MapValue -Map $Plan -Key "currentRoot"))
    Write-Host ("Selection mode: {0}" -f (Get-MapValue -Map $Plan -Key "selectionMode"))
    Write-Host ("Version policy: {0}" -f (Get-MapValue -Map $Plan -Key "versionPolicy"))

    foreach ($warning in @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $Plan -Key "warnings"))) {
        Write-WarningText $warning
    }

    Write-Host ""
    Write-Host "Summary"
    Write-Host ("- Manifest apps: {0}" -f (Get-MapValue -Map $summary -Key "manifestAppCount"))
    Write-Host ("- Package-manager candidates: {0}" -f (Get-MapValue -Map $summary -Key "restorableCandidateCount"))
    Write-Host ("- Selected apps: {0}" -f (Get-MapValue -Map $summary -Key "selectedAppCount"))
    Write-Host ("- Planned install commands: {0}" -f (Get-MapValue -Map $summary -Key "plannedInstallCount"))
    Write-Host ("- Skipped apps: {0}" -f (Get-MapValue -Map $summary -Key "skippedCount"))
    Write-Host ("- Manual reinstall / review: {0}" -f (Get-MapValue -Map $summary -Key "manualReviewCount"))
    Write-Host ("- Unsupported / do not restore automatically: {0}" -f (Get-MapValue -Map $summary -Key "unsupportedCount"))
    $configRestore = Get-MapValue -Map $Plan -Key "configRestore"
    $configSummary = Get-MapValue -Map $configRestore -Key "summary"
    Write-Host ("- Config paths available: {0}" -f (Get-MapValue -Map $summary -Key "configPathCount"))
    Write-Host ("- Planned config restores: {0}" -f (Get-MapValue -Map $configSummary -Key "plannedRestoreCount"))
    Write-Host ("- Existing config conflicts: {0}" -f (Get-MapValue -Map $configSummary -Key "existingTargetCount"))

    Write-Host ""
    Write-Host "Current Package Managers"
    foreach ($managerName in (Get-ObjectKeys -Object (Get-MapValue -Map $Plan -Key "packageManagers") | Sort-Object)) {
        $manager = Get-MapValue -Map (Get-MapValue -Map $Plan -Key "packageManagers") -Key $managerName
        $version = [string](Get-MapValue -Map $manager -Key "version")
        if ([string]::IsNullOrWhiteSpace($version)) {
            $version = "version unknown"
        }
        Write-Host ("- {0}: available={1}; {2}" -f $managerName, (Get-MapValue -Map $manager -Key "available"), $version)
    }

    Write-Host ""
    Write-Host "Install Commands"
    $commands = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $Plan -Key "commands"))
    if ($commands.Count -eq 0) {
        Write-Host "- None"
    } else {
        foreach ($command in $commands) {
            Write-Host ("- {0}: {1}" -f (Get-MapValue -Map $command -Key "name"), (Get-MapValue -Map $command -Key "commandLine"))
            foreach ($warning in @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $command -Key "warnings"))) {
                Write-WarningText $warning
            }
        }
    }

    $skipped = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $Plan -Key "skipped"))
    Write-Host ""
    Write-Host "Skipped App Sample"
    if ($skipped.Count -eq 0) {
        Write-Host "- None"
    } else {
        foreach ($item in @($skipped | Select-Object -First 20)) {
            Write-Host ("- {0}: {1}" -f (Get-MapValue -Map $item -Key "name"), (Get-MapValue -Map $item -Key "reason"))
        }
        if ($skipped.Count -gt 20) {
            Write-Host ("- ... {0} more skipped app(s) in the restore report" -f ($skipped.Count - 20))
        }
    }

    Show-ConfigRestorePlan -ConfigRestore (Get-MapValue -Map $Plan -Key "configRestore")
}

function Invoke-RestoreCommandPlan {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Commands
    )

    $results = @()
    foreach ($command in @($Commands)) {
        $commandName = [string](Get-MapValue -Map $command -Key "command")
        $arguments = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $command -Key "arguments") | ForEach-Object { [string]$_ })
        $commandLine = [string](Get-MapValue -Map $command -Key "commandLine")

        Write-Host ""
        Write-Info ("Running: {0}" -f $commandLine)
        $capture = Invoke-ExternalCommandCapture -CommandName $commandName -Arguments $arguments
        $status = "failed"
        $message = ""

        if (-not [bool](Get-MapValue -Map $capture -Key "available")) {
            $message = "Command not found."
        } elseif (-not [string]::IsNullOrWhiteSpace([string](Get-MapValue -Map $capture -Key "error"))) {
            $message = [string](Get-MapValue -Map $capture -Key "error")
        } elseif ([int](Get-MapValue -Map $capture -Key "exitCode") -eq 0) {
            $status = "success"
            $message = "Command exited successfully."
        } else {
            $message = ("Command exited with code {0}." -f (Get-MapValue -Map $capture -Key "exitCode"))
        }

        if ($status -eq "success") {
            Write-Info ("Success: {0}" -f (Get-MapValue -Map $command -Key "name"))
        } else {
            Write-WarningText ("Failed: {0} - {1}" -f (Get-MapValue -Map $command -Key "name"), $message)
        }

        $results += [ordered]@{
            appId = [string](Get-MapValue -Map $command -Key "appId")
            name = [string](Get-MapValue -Map $command -Key "name")
            manager = [string](Get-MapValue -Map $command -Key "manager")
            packageId = [string](Get-MapValue -Map $command -Key "packageId")
            commandLine = $commandLine
            status = $status
            exitCode = (Get-MapValue -Map $capture -Key "exitCode")
            message = $message
            outputSample = @(Get-CommandOutputSample -Lines (Get-MapValue -Map $capture -Key "lines"))
        }
    }

    return @($results)
}

function Convert-RestoreReportToMarkdown {
    param(
        [Parameter(Mandatory = $true)]
        $Plan,

        [object[]]$Results = @()
    )

    $summary = Get-MapValue -Map $Plan -Key "summary"
    $preflight = Get-MapValue -Map $Plan -Key "preflight"
    $commands = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $Plan -Key "commands"))
    $skipped = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $Plan -Key "skipped"))
    $results = @(ConvertTo-ArrayValue -Value $Results)
    $successCount = @($results | Where-Object { [string](Get-MapValue -Map $_ -Key "status") -eq "success" }).Count
    $failedCount = @($results | Where-Object { [string](Get-MapValue -Map $_ -Key "status") -eq "failed" }).Count

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# WinCarry Restore Report")
    $lines.Add("")
    $lines.Add(("Created: {0}" -f (Get-MapValue -Map $Plan -Key "createdAt")))
    $lines.Add(("Manifest: {0}" -f (Get-MapValue -Map $Plan -Key "manifestPath")))
    $lines.Add(("Manifest root: {0}" -f (Get-MapValue -Map $Plan -Key "manifestRoot")))
    $lines.Add(("Current root: {0}" -f (Get-MapValue -Map $Plan -Key "currentRoot")))
    $lines.Add(("Selection mode: {0}" -f (Get-MapValue -Map $Plan -Key "selectionMode")))
    $lines.Add(("Version policy: {0}" -f (Get-MapValue -Map $Plan -Key "versionPolicy")))
    $lines.Add("")
    $lines.Add("> Restore reinstalls selected apps through package managers, then can restore backed-up configs after app verification.")
    $lines.Add("")

    $warnings = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $Plan -Key "warnings"))
    if ($warnings.Count -gt 0) {
        $lines.Add("## Warnings")
        $lines.Add("")
        foreach ($warning in $warnings) {
            $lines.Add(("- {0}" -f $warning))
        }
        $lines.Add("")
    }

    $lines.Add("## System")
    $lines.Add("")
    $lines.Add(("- Windows: {0}" -f (Get-MapValue -Map $preflight.os -Key "caption")))
    $lines.Add(("- Version: {0}" -f (Get-MapValue -Map $preflight.os -Key "version")))
    $lines.Add(("- User: {0}\\{1}" -f (Get-MapValue -Map $preflight.user -Key "domainName"), (Get-MapValue -Map $preflight.user -Key "userName")))
    $lines.Add(("- Profile: {0}" -f (Get-MapValue -Map $preflight.user -Key "userProfile")))
    $lines.Add(("- Is admin/root: {0}" -f (Get-MapValue -Map $preflight.admin -Key "isAdmin")))
    $lines.Add("")

    $lines.Add("## Summary")
    $lines.Add("")
    $lines.Add(("- Manifest apps: {0}" -f (Get-MapValue -Map $summary -Key "manifestAppCount")))
    $lines.Add(("- Package-manager candidates: {0}" -f (Get-MapValue -Map $summary -Key "restorableCandidateCount")))
    $lines.Add(("- Selected apps: {0}" -f (Get-MapValue -Map $summary -Key "selectedAppCount")))
    $lines.Add(("- Planned install commands: {0}" -f (Get-MapValue -Map $summary -Key "plannedInstallCount")))
    $lines.Add(("- Successful commands: {0}" -f $successCount))
    $lines.Add(("- Failed commands: {0}" -f $failedCount))
    $lines.Add(("- Skipped apps: {0}" -f (Get-MapValue -Map $summary -Key "skippedCount")))
    $lines.Add(("- Manual reinstall / review: {0}" -f (Get-MapValue -Map $summary -Key "manualReviewCount")))
    $lines.Add(("- Unsupported / do not restore automatically: {0}" -f (Get-MapValue -Map $summary -Key "unsupportedCount")))
    $configRestore = Get-MapValue -Map $Plan -Key "configRestore"
    $configSummary = Get-MapValue -Map $configRestore -Key "summary"
    $lines.Add(("- Config paths available: {0}" -f (Get-MapValue -Map $summary -Key "configPathCount")))
    $lines.Add(("- Planned config restores: {0}" -f (Get-MapValue -Map $configSummary -Key "plannedRestoreCount")))
    $lines.Add(("- Restored configs: {0}" -f (Get-MapValue -Map $configSummary -Key "restoredCount")))
    $lines.Add(("- Failed config restores: {0}" -f (Get-MapValue -Map $configSummary -Key "failedCount")))
    $lines.Add("")

    $lines.Add("## Package Managers")
    $lines.Add("")
    foreach ($managerName in (Get-ObjectKeys -Object (Get-MapValue -Map $Plan -Key "packageManagers") | Sort-Object)) {
        $manager = Get-MapValue -Map (Get-MapValue -Map $Plan -Key "packageManagers") -Key $managerName
        $version = [string](Get-MapValue -Map $manager -Key "version")
        if ([string]::IsNullOrWhiteSpace($version)) {
            $version = "version unknown"
        }
        $lines.Add(("- {0}: available={1}; {2}; source={3}" -f $managerName, (Get-MapValue -Map $manager -Key "available"), $version, (Get-MapValue -Map $manager -Key "source")))
    }
    $lines.Add("")

    $lines.Add("## Planned Commands")
    $lines.Add("")
    if ($commands.Count -eq 0) {
        $lines.Add("No install commands were planned.")
    } else {
        $lines.Add("| App | Manager | Package | Command |")
        $lines.Add("| --- | --- | --- | --- |")
        foreach ($command in $commands) {
            $lines.Add(("| {0} | {1} | {2} | `{3}` |" -f
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $command -Key "name")),
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $command -Key "manager")),
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $command -Key "packageId")),
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $command -Key "commandLine"))))
        }
    }
    $lines.Add("")

    if ($results.Count -gt 0) {
        $lines.Add("## Execution Results")
        $lines.Add("")
        $lines.Add("| App | Status | Exit code | Message |")
        $lines.Add("| --- | --- | --- | --- |")
        foreach ($result in $results) {
            $lines.Add(("| {0} | {1} | {2} | {3} |" -f
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $result -Key "name")),
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $result -Key "status")),
                (ConvertTo-MarkdownCell -Text ([string](Get-MapValue -Map $result -Key "exitCode"))),
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $result -Key "message"))))
        }
        $lines.Add("")
    }

    $lines.Add("## Skipped Apps")
    $lines.Add("")
    if ($skipped.Count -eq 0) {
        $lines.Add("No apps were skipped.")
    } else {
        $lines.Add("| App | Classification | Strategy | Reason |")
        $lines.Add("| --- | --- | --- | --- |")
        foreach ($item in $skipped) {
            $lines.Add(("| {0} | {1} | {2} | {3} |" -f
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $item -Key "name")),
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $item -Key "classification")),
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $item -Key "restoreStrategy")),
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $item -Key "reason"))))
        }
    }
    $lines.Add("")

    $lines.Add("## Config Restore")
    $lines.Add("")
    $configRestore = Get-MapValue -Map $Plan -Key "configRestore"
    $configSummary = Get-MapValue -Map $configRestore -Key "summary"
    $configCandidates = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $configRestore -Key "candidates"))
    $lines.Add(("- Attempted: {0}" -f (Get-MapValue -Map $configRestore -Key "attempted")))
    $lines.Add(("- Executed: {0}" -f (Get-MapValue -Map $configRestore -Key "executed")))
    $lines.Add(("- Conflict policy: {0}" -f (Get-MapValue -Map $configSummary -Key "conflictPolicy")))
    $lines.Add(("- Existing-config backup root: {0}" -f (Get-MapValue -Map $configSummary -Key "existingBackupRootPath")))
    $lines.Add(("- Available config paths: {0}" -f (Get-MapValue -Map $configSummary -Key "availableConfigPathCount")))
    $lines.Add(("- Linked to app: {0}" -f (Get-MapValue -Map $configSummary -Key "linkedConfigPathCount")))
    $lines.Add(("- App verified: {0}" -f (Get-MapValue -Map $configSummary -Key "appVerifiedCount")))
    $lines.Add(("- Existing target conflicts: {0}" -f (Get-MapValue -Map $configSummary -Key "existingTargetCount")))
    $lines.Add(("- Planned config restores: {0}" -f (Get-MapValue -Map $configSummary -Key "plannedRestoreCount")))
    $lines.Add(("- Restored configs: {0}" -f (Get-MapValue -Map $configSummary -Key "restoredCount")))
    $lines.Add(("- Skipped config paths: {0}" -f (Get-MapValue -Map $configSummary -Key "skippedCount")))
    $lines.Add(("- Failed config restores: {0}" -f (Get-MapValue -Map $configSummary -Key "failedCount")))
    $lines.Add("")

    if ($configCandidates.Count -eq 0) {
        $lines.Add("No config paths were available in the manifest.")
    } else {
        $lines.Add("| App | Config | Status | Target | Reason | Existing backup |")
        $lines.Add("| --- | --- | --- | --- | --- | --- |")
        foreach ($candidate in $configCandidates) {
            $reason = [string](Get-MapValue -Map $candidate -Key "reason")
            $errorText = [string](Get-MapValue -Map $candidate -Key "error")
            if (-not [string]::IsNullOrWhiteSpace($errorText)) {
                $reason = ("{0} Error: {1}" -f $reason, $errorText).Trim()
            }
            $lines.Add(("| {0} | {1} | {2} | {3} | {4} | {5} |" -f
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $candidate -Key "appName")),
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $candidate -Key "name")),
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $candidate -Key "status")),
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $candidate -Key "targetPath")),
                (ConvertTo-MarkdownCell -Text $reason),
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $candidate -Key "existingBackupPath"))))
        }
    }

    return ($lines -join [Environment]::NewLine)
}

function Ensure-RestoreArtifactDirectories {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    foreach ($folder in @("reports", "logs", "backups")) {
        $path = Join-Path $RootPath $folder
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }
}

function Invoke-Restore {
    param(
        [string]$RootPath,
        [string]$ManifestPath,
        [switch]$DryRunOnly
    )

    $resolvedRoot = Resolve-RestoreRootPath -RootPath $RootPath
    $restoreManifestPath = Resolve-RestoreManifestPath -RootPath $resolvedRoot -ManifestPath $ManifestPath
    $manifest = Read-WinCarryManifest -ManifestPath $restoreManifestPath
    if ($null -eq $manifest) {
        return
    }

    $preflight = New-PreflightSnapshot -RootPath $resolvedRoot
    $warnings = @()
    foreach ($warning in @(ConvertTo-ArrayValue -Value $preflight.root.warnings)) {
        $warnings += $warning
    }

    $manifestRoot = Get-ManifestWinCarryRoot -Manifest $manifest
    $rootMismatch = $false
    if (-not [string]::IsNullOrWhiteSpace($manifestRoot) -and -not (Test-SameDisplayPath -Left $manifestRoot -Right $resolvedRoot)) {
        $rootMismatch = $true
        $warnings += ("Manifest root differs from current root. Manifest={0}; current={1}." -f $manifestRoot, $resolvedRoot)
    }

    if ($rootMismatch -and -not $DryRunOnly) {
        Write-Host ""
        Write-WarningText "The manifest was created for a different WinCarry root path."
        Write-WarningText ("Manifest root: {0}" -f $manifestRoot)
        Write-WarningText ("Current root: {0}" -f $resolvedRoot)
        if (-not (Read-RequiredConfirmation -Prompt "Continue restore using the current root?")) {
            Write-Host ""
            Write-Info "Restore cancelled. No install commands were run."
            return
        }
    }

    if ($DryRunOnly) {
        $selectionMode = "package-manager"
        $versionPolicy = "latest"
        $selectedApps = @(Select-RestoreApps -Manifest $manifest -SelectionMode $selectionMode)
    } else {
        $selectionMode = Read-RestoreSelectionMode -Manifest $manifest
        if ($selectionMode -eq "manual-review") {
            $versionPolicy = "latest"
        } else {
            $versionPolicy = Read-RestoreVersionPolicy
        }
        $selectedApps = @(Select-RestoreApps -Manifest $manifest -SelectionMode $selectionMode)
    }

    $timestamp = Get-FileTimestamp
    $reportPath = Get-RestoreReportPath -RootPath $resolvedRoot -Timestamp $timestamp
    $logPath = Get-LogPath -RootPath $resolvedRoot
    $existingConfigBackupRoot = Get-ConfigRestoreExistingBackupRootPath -RootPath $resolvedRoot -Timestamp $timestamp
    $currentScan = New-AppScanSnapshot -RootPath $resolvedRoot
    $currentApps = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $currentScan -Key "apps"))

    $plan = New-RestorePlan -Manifest $manifest -Preflight $preflight -ManifestPath $restoreManifestPath -RootPath $resolvedRoot -SelectionMode $selectionMode -VersionPolicy $versionPolicy -SelectedApps $selectedApps -Warnings $warnings
    $configPreview = New-ConfigRestorePlan -Manifest $manifest -ConflictPolicy "missing-only" -ExistingBackupRootPath $existingConfigBackupRoot -CurrentApps $currentApps
    Set-MapValue -Map $plan -Key "configRestore" -Value $configPreview
    Show-RestorePlan -Plan $plan

    if ($DryRunOnly) {
        Write-Host ""
        Write-Info "Dry-run only. No install commands, config files, report, or log file were written."
        Write-Info ("Would write restore report if reports folder exists: {0}" -f $reportPath)
        Write-Info ("Would write log if logs folder exists: {0}" -f $logPath)
        return
    }

    $commands = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $plan -Key "commands"))
    if ($commands.Count -eq 0) {
        if (-not (Read-RequiredConfirmation -Prompt "Continue restore and write review report?")) {
            Write-Host ""
            Write-Info "Restore cancelled. No files were changed."
            return
        }
        $results = @()
    } else {
        if (-not (Read-RequiredConfirmation -Prompt "Run selected package-manager restore commands?")) {
            Write-Host ""
            Write-Info "Restore cancelled. No install commands were run."
            return
        }
        $results = @(Invoke-RestoreCommandPlan -Commands $commands)
    }

    $configPreviewSummary = Get-MapValue -Map (Get-MapValue -Map $plan -Key "configRestore") -Key "summary"
    if ([int](Get-MapValue -Map $configPreviewSummary -Key "availableConfigPathCount") -eq 0) {
        Write-Host ""
        Write-Info "No backed-up config paths are available in the manifest."
        $configPolicy = "skip"
    } else {
        $configPolicy = Read-ConfigRestorePolicy -ConfigRestore (Get-MapValue -Map $plan -Key "configRestore")
    }
    $configPlan = New-ConfigRestorePlan -Manifest $manifest -ConflictPolicy $configPolicy -ExistingBackupRootPath $existingConfigBackupRoot -CurrentApps $currentApps -SuccessfulRestoreResults $results
    Set-MapValue -Map $plan -Key "configRestore" -Value $configPlan

    if ($configPolicy -eq "skip") {
        Write-Host ""
        Write-Info "Config restore skipped by user selection."
    } else {
        Show-ConfigRestorePlan -ConfigRestore $configPlan
        $plannedConfigRestores = [int](Get-MapValue -Map (Get-MapValue -Map $configPlan -Key "summary") -Key "plannedRestoreCount")
        if ($plannedConfigRestores -eq 0) {
            Write-Host ""
            Write-Info "No config paths are eligible for restore with the selected policy."
        } elseif (Read-RequiredConfirmation -Prompt "Restore backed-up config files?") {
            Invoke-ConfigRestorePlan -ConfigRestore $configPlan | Out-Null
        } else {
            Write-Host ""
            Write-Info "Config restore cancelled. No config files were changed."
        }
    }

    Ensure-RestoreArtifactDirectories -RootPath $resolvedRoot
    Set-Content -LiteralPath $reportPath -Value (Convert-RestoreReportToMarkdown -Plan $plan -Results $results) -Encoding UTF8

    $successCount = @($results | Where-Object { [string](Get-MapValue -Map $_ -Key "status") -eq "success" }).Count
    $failedCount = @($results | Where-Object { [string](Get-MapValue -Map $_ -Key "status") -eq "failed" }).Count
    $configSummary = Get-MapValue -Map (Get-MapValue -Map $plan -Key "configRestore") -Key "summary"
    $message = "Restore completed for root {0}; selected={1}; planned={2}; success={3}; failed={4}; skipped={5}; configsRestored={6}; configFailed={7}; report={8}" -f $resolvedRoot, $plan.summary.selectedAppCount, $plan.summary.plannedInstallCount, $successCount, $failedCount, $plan.summary.skippedCount, (Get-MapValue -Map $configSummary -Key "restoredCount"), (Get-MapValue -Map $configSummary -Key "failedCount"), $reportPath
    Write-WinCarryLog -RootPath $resolvedRoot -Operation "restore" -Result "success" -Message $message

    Write-Host ""
    Write-Info ("Restore report written: {0}" -f $reportPath)
    Write-Info ("Log updated: {0}" -f $logPath)
    if ($failedCount -gt 0) {
        Write-WarningText ("{0} restore command(s) failed. Review the restore report before continuing." -f $failedCount)
    }
    if ([int](Get-MapValue -Map $configSummary -Key "failedCount") -gt 0) {
        Write-WarningText ("{0} config restore(s) failed. Review the restore report before continuing." -f (Get-MapValue -Map $configSummary -Key "failedCount"))
    }
}

