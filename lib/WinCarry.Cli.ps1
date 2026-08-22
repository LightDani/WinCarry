function Show-SetupPlan {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $settingsPath = Get-SettingsPath -RootPath $RootPath
    $destinationScript = Join-Path $RootPath $script:ScriptFileName
    $sourceScript = Get-CurrentScriptPath
    $sourceHelperRoot = Join-Path (Get-ScriptDirectory) $script:HelperFolderName
    $destinationHelperRoot = Join-Path $RootPath $script:HelperFolderName

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

    foreach ($helperScriptFileName in $script:HelperScriptFileNames) {
        $sourceHelperScript = Join-Path $sourceHelperRoot $helperScriptFileName
        $destinationHelperScript = Join-Path $destinationHelperRoot $helperScriptFileName
        if (($sourceHelperScript -ne $destinationHelperScript) -and (Test-Path -LiteralPath $sourceHelperScript)) {
            Write-Host ("- {0}" -f $destinationHelperScript)
        }
    }

    Write-Host ""
    Write-Host "Will preserve existing files:"
    Write-Host ("- Existing settings file will not be overwritten.")
    Write-Host ("- Existing script file in root will not be overwritten.")
    Write-Host ("- Existing helper scripts in root will not be overwritten.")
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

    $null = Sync-WinCarryLauncherDependencies -RootPath $RootPath

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
    Write-Host "  .\wincarry.ps1 restore [-Root D:\WinCarry] [-Manifest path] [-DryRun]"
    Write-Host "  .\wincarry.ps1 offline [-Root D:\WinCarry] [-DryRun]"
    Write-Host "  .\wincarry.ps1 junction [-Root D:\WinCarry] [-DryRun]"
    Write-Host ""
    Write-Host "Implemented: CLI shell, setup, preflight, app detection/classification, manifests, reports, restore scripts, config backup, package-manager restore, guarded config restore, advanced junction mode, and offline-safe mode."
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
            "6" {
                $rootInput = Read-Host ("WinCarry root [{0}]" -f $script:DefaultRoot)
                if ([string]::IsNullOrWhiteSpace($rootInput)) {
                    $rootInput = $script:DefaultRoot
                }
                Invoke-Restore -RootPath $rootInput
            }
            "7" {
                $rootInput = Read-Host ("WinCarry root [{0}]" -f $script:DefaultRoot)
                if ([string]::IsNullOrWhiteSpace($rootInput)) {
                    $rootInput = $script:DefaultRoot
                }
                Invoke-Report -RootPath $rootInput
            }
            "8" {
                $rootInput = Read-Host ("WinCarry root [{0}]" -f $script:DefaultRoot)
                if ([string]::IsNullOrWhiteSpace($rootInput)) {
                    $rootInput = $script:DefaultRoot
                }
                Invoke-Junction -RootPath $rootInput
            }
            "9" {
                $rootInput = Read-Host ("WinCarry root [{0}]" -f $script:DefaultRoot)
                if ([string]::IsNullOrWhiteSpace($rootInput)) {
                    $rootInput = $script:DefaultRoot
                }
                Invoke-Offline -RootPath $rootInput
            }
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
        "restore" { Invoke-Restore -RootPath $Root -ManifestPath $Manifest -DryRunOnly:$DryRun }
        "report" { Invoke-Report -RootPath $Root -DryRunOnly:$DryRun }
        "offline" { Invoke-Offline -RootPath $Root -DryRunOnly:$DryRun }
        "junction" { Invoke-Junction -RootPath $Root -DryRunOnly:$DryRun }
        "help" { Show-Help }
    }
}

