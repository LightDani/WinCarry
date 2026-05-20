# WinCarry

WinCarry is an early-stage PowerShell toolkit for reducing Windows reinstall friction.

It is intended to help users prepare for a Windows reinstall by scanning apps, generating manifests, backing up selected configuration, and later restoring/reinstalling selected apps through safe workflows.

Current status: alpha. The CLI skeleton, setup flow, and preflight system snapshot are implemented.

## What It Does Not Guarantee

WinCarry does not guarantee that every application will work after Windows reinstall without reinstall, repair, login, activation, registry registration, service setup, or driver setup.

The project intentionally avoids dangerous global Windows modifications such as changing `ProgramFilesDir` or treating symlinks/junctions as a universal app migration strategy.

## Current Scope

Implemented:

- `wincarry.ps1` CLI entry point
- interactive menu
- direct command routing
- `setup` command
- root folder creation
- initial `config/settings.json`
- basic logging
- dry-run output
- explicit `YES` confirmation before filesystem changes
- `preflight` system snapshot:
  - OS/version/architecture
  - current user and profile path
  - admin/root status
  - file-system drives and free space
  - package manager availability for `winget`, Chocolatey, and Scoop
  - root/protected-path validation
  - report/log output when the WinCarry root has been set up

Commands planned for later phases currently show placeholders and make no changes:

- `scan`
- `backup`
- `manifest`
- `restore`
- `report`
- `offline`
- `junction`

## Usage

Show help:

```powershell
.\wincarry.ps1 help
```

Run the interactive menu:

```powershell
.\wincarry.ps1
```

Preview setup:

```powershell
.\wincarry.ps1 setup -Root "D:\WinCarry" -DryRun
```

Run setup:

```powershell
.\wincarry.ps1 setup -Root "D:\WinCarry"
```

Setup requires typing `YES` before it changes files.

Run preflight:

```powershell
.\wincarry.ps1 preflight -Root "D:\WinCarry"
```

Preview preflight without writing a report or log:

```powershell
.\wincarry.ps1 preflight -Root "D:\WinCarry" -DryRun
```

## Windows PowerShell Verification

Run these from the repository directory on Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 help
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 scan
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 setup -Root "$env:TEMP\WinCarry-Test" -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 setup -Root "$env:TEMP\WinCarry-Test"
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 preflight -Root "$env:TEMP\WinCarry-Test" -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 preflight -Root "$env:TEMP\WinCarry-Test"
```

Expected result:

- help displays usage
- `scan` reports that it is planned for Phase 3 and makes no changes
- setup dry-run prints planned folders and creates nothing
- setup creates folder structure, `config/settings.json`, a copied `wincarry.ps1`, and a log after typing `YES`
- preflight dry-run prints the system snapshot and writes nothing
- preflight prints OS/user/admin/drive/package-manager/root details
- preflight writes a report under `reports` and updates the setup log when the root exists

## Linux PowerShell Verification

Run these from the repository directory on Linux with PowerShell 7 installed:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File wincarry.ps1 help
pwsh -NoProfile -ExecutionPolicy Bypass -File wincarry.ps1 scan
pwsh -NoProfile -ExecutionPolicy Bypass -File wincarry.ps1 setup -Root /tmp/WinCarry-Test-Phase1 -DryRun
pwsh -NoProfile -ExecutionPolicy Bypass -File wincarry.ps1 setup -Root /tmp/WinCarry-Test-Phase1
pwsh -NoProfile -ExecutionPolicy Bypass -File wincarry.ps1 preflight -Root /tmp/WinCarry-Test-Phase1 -DryRun
pwsh -NoProfile -ExecutionPolicy Bypass -File wincarry.ps1 preflight -Root /tmp/WinCarry-Test-Phase1
```

Use Linux-native paths such as `/tmp/...` when invoking `pwsh` from a Linux shell.
