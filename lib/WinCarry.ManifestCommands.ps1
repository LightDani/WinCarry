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
    Write-Host ("Offline-safe mode: {0}" -f [bool](Get-MapValue -Map $Manifest -Key "offlineSafeMode"))
    Write-Host ""
    Write-Host "Will write:"

    foreach ($key in (Get-ObjectKeys -Object $Paths)) {
        Write-Host ("- {0}" -f (Get-MapValue -Map $Paths -Key $key))
    }
}


function Show-ManifestLauncherDependencyPlan {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $launcherPaths = Get-WinCarryLauncherDependencyPaths -RootPath $RootPath
    Write-Host ""
    Write-Host "Will sync restore launcher dependencies:"
    Write-Host ("- {0}" -f $launcherPaths.entrypoint)
    Write-Host ("- {0} (helper scripts)" -f $launcherPaths.helperRoot)
    Write-Host "Existing WinCarry launcher files in the target root may be overwritten."
}

function Ensure-ManifestArtifactDirectories {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [switch]$IncludeRestoreScripts
    )

    $folders = @("manifests", "reports", "logs")
    if ($IncludeRestoreScripts) {
        $folders += "restore-scripts"
    }

    foreach ($folder in $folders) {
        $path = Join-Path $RootPath $folder
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }
}

function New-RestoreScriptContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestFileName
    )

    $template = @'
<#
WinCarry generated restore launcher.
Run from the preserved WinCarry root after Windows reinstall.
#>

[CmdletBinding()]
param(
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$scriptPath = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($scriptPath) -and $MyInvocation.MyCommand.Path) {
    $scriptPath = $MyInvocation.MyCommand.Path
}

if ([string]::IsNullOrWhiteSpace($scriptPath)) {
    throw "Cannot determine restore script path."
}

$restoreScriptDirectory = Split-Path -Parent $scriptPath
$winCarryRoot = Split-Path -Parent $restoreScriptDirectory
$winCarryScript = Join-Path $winCarryRoot "wincarry.ps1"
$manifestPath = Join-Path (Join-Path $winCarryRoot "manifests") "__MANIFEST_FILE_NAME__"

if (-not (Test-Path -LiteralPath $winCarryScript)) {
    throw ("WinCarry entrypoint not found: {0}" -f $winCarryScript)
}

if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw ("Intended manifest not found: {0}" -f $manifestPath)
}

if ($DryRun) {
    & $winCarryScript restore -Root $winCarryRoot -Manifest $manifestPath -DryRun
} else {
    & $winCarryScript restore -Root $winCarryRoot -Manifest $manifestPath
}
'@

    return $template.Replace("__MANIFEST_FILE_NAME__", $ManifestFileName)
}

function Write-RestoreScripts {
    param(
        [Parameter(Mandatory = $true)]
        $Paths
    )

    $manifestFileName = Split-Path -Leaf ([string](Get-MapValue -Map $Paths -Key "manifest"))
    Set-Content -LiteralPath $Paths.restoreScript -Value (New-RestoreScriptContent -ManifestFileName $manifestFileName) -Encoding UTF8
    Set-Content -LiteralPath $Paths.latestRestoreScript -Value (New-RestoreScriptContent -ManifestFileName "latest.json") -Encoding UTF8
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
        Write-RestoreScripts -Paths $Paths
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
    Show-ManifestLauncherDependencyPlan -RootPath $scan.root.resolvedRoot

    if ($DryRunOnly) {
        Write-Host ""
        Write-Info "Dry-run only. No manifest, restore script, launcher files, report, list, or log files were written."
        return
    }

    if (-not (Read-RequiredConfirmation -Prompt "Generate WinCarry manifest, restore scripts, and launcher files?")) {
        Write-Host ""
        Write-Info "Manifest generation cancelled. No files were changed."
        return
    }

    Ensure-ManifestArtifactDirectories -RootPath $scan.root.resolvedRoot -IncludeRestoreScripts
    $launcherSync = Sync-WinCarryLauncherDependencies -RootPath $scan.root.resolvedRoot -Overwrite
    Write-ManifestArtifacts -Manifest $manifest -Paths $paths -IncludeManifestFiles

    $message = "Manifest generated for root {0}; apps={1}; manual={2}; unsupported={3}; manifest={4}" -f $scan.root.resolvedRoot, $manifest.summary.appCount, $manifest.summary.manualReinstallCount, $manifest.summary.unsupportedCount, $paths.manifest
    Write-WinCarryLog -RootPath $scan.root.resolvedRoot -Operation "manifest" -Result "success" -Message $message

    Write-Host ""
    Write-Info ("Manifest written: {0}" -f $paths.manifest)
    Write-Info ("Latest manifest updated: {0}" -f $paths.latestManifest)
    Write-Info ("Restore script written: {0}" -f $paths.restoreScript)
    Write-Info ("Latest restore script updated: {0}" -f $paths.latestRestoreScript)
    if ($launcherSync.copied.Count -gt 0) {
        Write-Info ("Restore launcher dependencies synced: {0} file(s)" -f $launcherSync.copied.Count)
    } else {
        Write-Info "Restore launcher dependencies already current."
    }
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

