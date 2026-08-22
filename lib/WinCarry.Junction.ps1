function Get-JunctionBackupPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$Timestamp,

        [Parameter(Mandatory = $true)]
        [string]$SourcePath
    )

    $sourceName = Split-Path -Leaf $SourcePath
    if ([string]::IsNullOrWhiteSpace($sourceName)) {
        $sourceName = "source"
    }

    $backupRoot = Join-Path (Join-Path (Join-Path $RootPath "backups") $Timestamp) "junction"
    return (Join-Path $backupRoot $sourceName)
}

function Test-JunctionPathInsideRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $normalizedPath = ConvertTo-WinCarryComparablePath -Path $Path
    $normalizedRoot = ConvertTo-WinCarryComparablePath -Path $RootPath

    if ([string]::IsNullOrWhiteSpace($normalizedPath) -or [string]::IsNullOrWhiteSpace($normalizedRoot)) {
        return $false
    }

    if ($normalizedPath -eq $normalizedRoot) {
        return $true
    }

    foreach ($separator in @("\", "/")) {
        if ($normalizedPath.StartsWith(($normalizedRoot + $separator), [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Get-JunctionProtectedPathMatch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string[]]$ProtectedPaths
    )

    foreach ($protectedPath in $ProtectedPaths) {
        if ([string]::IsNullOrWhiteSpace($protectedPath)) {
            continue
        }

        $expandedProtectedPath = [Environment]::ExpandEnvironmentVariables($protectedPath)
        if (Test-JunctionPathInsideRoot -Path $Path -RootPath $expandedProtectedPath) {
            return $protectedPath
        }
    }

    return ""
}

function Test-JunctionReparsePoint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        return (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq [System.IO.FileAttributes]::ReparsePoint)
    } catch {
        return $false
    }
}

function Test-JunctionSourceLocks {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath
    )

    $lockedFiles = @()
    $inaccessibleFiles = @()

    try {
        $files = @(Get-ChildItem -LiteralPath $SourcePath -Recurse -Force -File -ErrorAction Stop)
    } catch {
        $inaccessibleFiles += ("Could not enumerate source folder: {0}" -f $_.Exception.Message)
        $files = @()
    }

    foreach ($file in $files) {
        $stream = $null
        try {
            $stream = [System.IO.File]::Open($file.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        } catch [System.IO.IOException] {
            $lockedFiles += $file.FullName
        } catch [System.UnauthorizedAccessException] {
            $inaccessibleFiles += $file.FullName
        } finally {
            if ($null -ne $stream) {
                $stream.Close()
            }
        }
    }

    return [ordered]@{
        lockedFiles = $lockedFiles
        inaccessibleFiles = $inaccessibleFiles
    }
}

function New-JunctionPlan {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath,

        [Parameter(Mandatory = $true)]
        [string]$Timestamp
    )

    $resolvedRoot = Resolve-DisplayPath -Path $RootPath
    $resolvedSource = Resolve-DisplayPath -Path $SourcePath
    $resolvedTarget = Resolve-DisplayPath -Path $TargetPath
    $protectedPaths = Get-ProtectedPaths
    $errors = @()
    $warnings = @()
    $lockCheck = [ordered]@{ lockedFiles = @(); inaccessibleFiles = @() }

    if (-not (Test-IsWindows)) {
        $errors += "Junction mode is only available on Windows."
    }

    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        $errors += "Source folder is required."
    }

    if ([string]::IsNullOrWhiteSpace($TargetPath)) {
        $errors += "Target folder is required."
    }

    if (-not [string]::IsNullOrWhiteSpace($resolvedSource) -and -not [string]::IsNullOrWhiteSpace($resolvedTarget)) {
        if (Test-WinCarrySamePath -Left $resolvedSource -Right $resolvedTarget) {
            $errors += "Source and target must be different paths."
        }
    }

    $sourceExists = $false
    $sourceIsDirectory = $false
    if (-not [string]::IsNullOrWhiteSpace($resolvedSource) -and (Test-Path -LiteralPath $resolvedSource)) {
        $sourceExists = $true
        try {
            $sourceItem = Get-Item -LiteralPath $resolvedSource -Force -ErrorAction Stop
            $sourceIsDirectory = [bool]$sourceItem.PSIsContainer
        } catch {
            $errors += ("Could not inspect source folder: {0}" -f $_.Exception.Message)
        }
    } else {
        $errors += ("Source folder does not exist: {0}" -f $resolvedSource)
    }

    if ($sourceExists -and -not $sourceIsDirectory) {
        $errors += "Source path must be a folder, not a file."
    }

    if ($sourceExists -and (Test-JunctionReparsePoint -Path $resolvedSource)) {
        $errors += "Source folder is already a reparse point or junction."
    }

    if (-not [string]::IsNullOrWhiteSpace($resolvedTarget) -and (Test-Path -LiteralPath $resolvedTarget)) {
        $errors += ("Target path already exists. Choose a target path that does not exist yet: {0}" -f $resolvedTarget)
    }

    $targetParent = ""
    if (-not [string]::IsNullOrWhiteSpace($resolvedTarget)) {
        $targetParent = Split-Path -Parent $resolvedTarget
        if ([string]::IsNullOrWhiteSpace($targetParent)) {
            $errors += "Target path must have a parent folder."
        }
    }

    $sourceProtectedMatch = Get-JunctionProtectedPathMatch -Path $resolvedSource -ProtectedPaths $protectedPaths
    if (-not [string]::IsNullOrWhiteSpace($sourceProtectedMatch)) {
        $errors += ("Source is inside a protected path ({0})." -f $sourceProtectedMatch)
    }

    $targetProtectedMatch = Get-JunctionProtectedPathMatch -Path $resolvedTarget -ProtectedPaths $protectedPaths
    if (-not [string]::IsNullOrWhiteSpace($targetProtectedMatch)) {
        $errors += ("Target is inside a protected path ({0})." -f $targetProtectedMatch)
    }

    if (($errors.Count -eq 0) -and $sourceExists -and $sourceIsDirectory) {
        $lockCheck = Test-JunctionSourceLocks -SourcePath $resolvedSource
        foreach ($lockedFile in @(ConvertTo-ArrayValue -Value $lockCheck.lockedFiles)) {
            $errors += ("Locked file detected: {0}" -f $lockedFile)
        }
        foreach ($inaccessibleFile in @(ConvertTo-ArrayValue -Value $lockCheck.inaccessibleFiles)) {
            $errors += ("Inaccessible file detected: {0}" -f $inaccessibleFile)
        }
    }

    $backupPath = Get-JunctionBackupPath -RootPath $resolvedRoot -Timestamp $Timestamp -SourcePath $resolvedSource

    return [ordered]@{
        schemaVersion = "junction-plan.1"
        createdAt = (Get-Date).ToString("o")
        root = $resolvedRoot
        sourcePath = $resolvedSource
        targetPath = $resolvedTarget
        targetParent = $targetParent
        backupPath = $backupPath
        protectedPaths = $protectedPaths
        warnings = $warnings
        errors = $errors
        canProceed = ($errors.Count -eq 0)
        lockCheck = $lockCheck
        operations = @(
            "Copy source folder to backup path.",
            "Move source folder to target path.",
            "Create folder junction at source path pointing to target path.",
            "Verify source is a junction and target exists."
        )
    }
}

function Show-JunctionPlan {
    param(
        [Parameter(Mandatory = $true)]
        $Plan
    )

    Write-Host ""
    Write-Host "Advanced Junction Mode"
    Write-Host ""
    Write-Host "This mode moves one folder and replaces it with a Windows junction. Use it only for manually reviewed app/config folders."
    Write-Host ""
    Write-Host ("Root: {0}" -f (Get-MapValue -Map $Plan -Key "root"))
    Write-Host ("Source folder: {0}" -f (Get-MapValue -Map $Plan -Key "sourcePath"))
    Write-Host ("Target folder: {0}" -f (Get-MapValue -Map $Plan -Key "targetPath"))
    Write-Host ("Backup path: {0}" -f (Get-MapValue -Map $Plan -Key "backupPath"))
    Write-Host ""
    Write-Host "Planned operations:"
    foreach ($operation in @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $Plan -Key "operations"))) {
        Write-Host ("- {0}" -f $operation)
    }

    $warnings = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $Plan -Key "warnings"))
    if ($warnings.Count -gt 0) {
        Write-Host ""
        Write-Host "Warnings"
        foreach ($warning in $warnings) {
            Write-WarningText $warning
        }
    }

    $errors = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $Plan -Key "errors"))
    if ($errors.Count -gt 0) {
        Write-Host ""
        Write-Host "Blocking issues"
        foreach ($errorMessage in $errors) {
            Write-ErrorText $errorMessage
        }
    }

    Write-Host ""
    if ([bool](Get-MapValue -Map $Plan -Key "canProceed")) {
        Write-Info "Plan status: ready."
    } else {
        Write-Info "Plan status: blocked. No junction can be created until blocking issues are resolved."
    }
}

function New-JunctionLink {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    if (-not (Test-IsWindows)) {
        throw "Junction links can only be created on Windows."
    }

    $command = 'mklink /J "{0}" "{1}"' -f $SourcePath, $TargetPath
    $output = & cmd.exe /c $command 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw ("mklink failed with exit code {0}: {1}" -f $exitCode, ($output -join " "))
    }
}

function Remove-JunctionLinkOnly {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    if (Test-IsWindows -and (Test-JunctionReparsePoint -Path $Path)) {
        $command = 'rmdir "{0}"' -f $Path
        $output = & cmd.exe /c $command 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            throw ("Could not remove junction path during rollback. Exit code {0}: {1}" -f $exitCode, ($output -join " "))
        }
    }
}

function Invoke-JunctionRollback {
    param(
        [Parameter(Mandatory = $true)]
        $Plan
    )

    $sourcePath = [string](Get-MapValue -Map $Plan -Key "sourcePath")
    $targetPath = [string](Get-MapValue -Map $Plan -Key "targetPath")

    try {
        if ((Test-Path -LiteralPath $sourcePath) -and (Test-JunctionReparsePoint -Path $sourcePath)) {
            Remove-JunctionLinkOnly -Path $sourcePath
        }

        if ((-not (Test-Path -LiteralPath $sourcePath)) -and (Test-Path -LiteralPath $targetPath)) {
            Move-Item -LiteralPath $targetPath -Destination $sourcePath -ErrorAction Stop
        }

        return "rollback-complete"
    } catch {
        return ("rollback-failed: {0}" -f $_.Exception.Message)
    }
}

function Invoke-JunctionPlan {
    param(
        [Parameter(Mandatory = $true)]
        $Plan
    )

    $sourcePath = [string](Get-MapValue -Map $Plan -Key "sourcePath")
    $targetPath = [string](Get-MapValue -Map $Plan -Key "targetPath")
    $targetParent = [string](Get-MapValue -Map $Plan -Key "targetParent")
    $backupPath = [string](Get-MapValue -Map $Plan -Key "backupPath")
    $backupParent = Split-Path -Parent $backupPath

    try {
        if (-not (Test-Path -LiteralPath $backupParent)) {
            New-Item -ItemType Directory -Path $backupParent -Force -ErrorAction Stop | Out-Null
        }
        if (-not (Test-Path -LiteralPath $targetParent)) {
            New-Item -ItemType Directory -Path $targetParent -Force -ErrorAction Stop | Out-Null
        }

        Copy-Item -LiteralPath $sourcePath -Destination $backupPath -Recurse -Force -ErrorAction Stop
        Move-Item -LiteralPath $sourcePath -Destination $targetPath -ErrorAction Stop
        New-JunctionLink -SourcePath $sourcePath -TargetPath $targetPath

        if (-not (Test-Path -LiteralPath $targetPath)) {
            throw "Target folder was not found after move."
        }
        if (-not (Test-JunctionReparsePoint -Path $sourcePath)) {
            throw "Source path was not verified as a junction after creation."
        }

        return [ordered]@{
            success = $true
            message = "Junction created successfully."
            rollback = "not-needed"
        }
    } catch {
        $rollbackStatus = Invoke-JunctionRollback -Plan $Plan
        return [ordered]@{
            success = $false
            message = $_.Exception.Message
            rollback = $rollbackStatus
        }
    }
}

function Invoke-Junction {
    param(
        [string]$RootPath,
        [switch]$DryRunOnly
    )

    if ([string]::IsNullOrWhiteSpace($RootPath)) {
        $RootPath = $script:DefaultRoot
    }

    Write-Host ""
    Write-Host "Advanced Junction Mode"
    Write-Host ""
    Write-Host "Source is the existing folder that will become the junction. Target must not exist yet."
    Write-Host ""
    $sourcePath = Read-Host "Source folder"
    $targetPath = Read-Host "Target folder"

    $timestamp = Get-FileTimestamp
    $plan = New-JunctionPlan -RootPath $RootPath -SourcePath $sourcePath -TargetPath $targetPath -Timestamp $timestamp
    Show-JunctionPlan -Plan $plan

    if ($DryRunOnly) {
        Write-Host ""
        Write-Info "Dry-run only. No backup, move, junction, or log files were written."
        return
    }

    if (-not [bool](Get-MapValue -Map $plan -Key "canProceed")) {
        Write-Host ""
        Write-Info "Junction cancelled. No files were changed."
        return
    }

    if (-not (Read-RequiredConfirmation -Prompt "Create folder junction?")) {
        Write-Host ""
        Write-Info "Junction cancelled. No files were changed."
        return
    }

    foreach ($folder in @("backups", "logs", "reports")) {
        $path = Join-Path ([string](Get-MapValue -Map $plan -Key "root")) $folder
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    $result = Invoke-JunctionPlan -Plan $plan
    if ([bool](Get-MapValue -Map $result -Key "success")) {
        Write-WinCarryLog -RootPath ([string](Get-MapValue -Map $plan -Key "root")) -Operation "junction" -Result "success" -Message ("Junction created source={0}; target={1}; backup={2}" -f (Get-MapValue -Map $plan -Key "sourcePath"), (Get-MapValue -Map $plan -Key "targetPath"), (Get-MapValue -Map $plan -Key "backupPath"))
        Write-Host ""
        Write-Info "Junction created."
        Write-Info ("Source junction: {0}" -f (Get-MapValue -Map $plan -Key "sourcePath"))
        Write-Info ("Target folder: {0}" -f (Get-MapValue -Map $plan -Key "targetPath"))
        Write-Info ("Backup path: {0}" -f (Get-MapValue -Map $plan -Key "backupPath"))
        Write-Info ("Log updated: {0}" -f (Get-LogPath -RootPath ([string](Get-MapValue -Map $plan -Key "root"))) )
    } else {
        Write-WinCarryLog -RootPath ([string](Get-MapValue -Map $plan -Key "root")) -Operation "junction" -Result "failed" -Message ("Junction failed source={0}; target={1}; rollback={2}; error={3}" -f (Get-MapValue -Map $plan -Key "sourcePath"), (Get-MapValue -Map $plan -Key "targetPath"), (Get-MapValue -Map $result -Key "rollback"), (Get-MapValue -Map $result -Key "message"))
        Write-Host ""
        Write-ErrorText ("Junction failed: {0}" -f (Get-MapValue -Map $result -Key "message"))
        Write-Info ("Rollback status: {0}" -f (Get-MapValue -Map $result -Key "rollback"))
        Write-Info ("Backup path: {0}" -f (Get-MapValue -Map $plan -Key "backupPath"))
        Write-Info ("Log updated: {0}" -f (Get-LogPath -RootPath ([string](Get-MapValue -Map $plan -Key "root"))) )
    }
}
