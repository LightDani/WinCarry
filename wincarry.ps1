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
- Manifest, restore script, and report generation
- Config detection and safe backup
- Restore dry-run, package-manager reinstall flow, and guarded config restore
- Advanced guarded junction mode
- Offline-safe backup, manifest, report, and restore blocking mode
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command = "menu",

    [string]$Root,
    [string]$Manifest,

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

$script:HelperFolderName = "lib"
$script:HelperScriptFileNames = @(
    "WinCarry.Core.ps1",
    "WinCarry.Preflight.ps1",
    "WinCarry.Inventory.ps1",
    "WinCarry.Config.ps1",
    "WinCarry.Scan.ps1",
    "WinCarry.ManifestCommands.ps1",
    "WinCarry.Backup.ps1",
    "WinCarry.Restore.ps1",
    "WinCarry.Junction.ps1",
    "WinCarry.Offline.ps1",
    "WinCarry.Cli.ps1"
)

foreach ($helperScriptFileName in $script:HelperScriptFileNames) {
    $helperScriptPath = Join-Path (Join-Path $script:ScriptDirectory $script:HelperFolderName) $helperScriptFileName
    if (-not (Test-Path -LiteralPath $helperScriptPath)) {
        Write-Host ("ERROR: Required WinCarry helper script was not found: {0}" -f $helperScriptPath) -ForegroundColor Red
        exit 1
    }

    . $helperScriptPath
}

Invoke-CommandRouter -CommandName $Command
