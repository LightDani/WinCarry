# WinCarry

WinCarry is an early-stage PowerShell toolkit for reducing Windows reinstall friction.

It is intended to help users prepare for a Windows reinstall by scanning apps, generating manifests, backing up selected configuration, and later restoring/reinstalling selected apps through safe workflows.

Current status: alpha. Phase 1 only implements the CLI skeleton and setup flow.

## What It Does Not Guarantee

WinCarry does not guarantee that every application will work after Windows reinstall without reinstall, repair, login, activation, registry registration, service setup, or driver setup.

The project intentionally avoids dangerous global Windows modifications such as changing `ProgramFilesDir` or treating symlinks/junctions as a universal app migration strategy.

## Current Phase 1 Scope

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

## Windows PowerShell Verification

Run these from the repository directory on Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 help
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 scan
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 setup -Root "$env:TEMP\WinCarry-Test" -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 setup -Root "$env:TEMP\WinCarry-Test"
```

Expected result:

- help displays usage
- `scan` reports that it is planned for Phase 3 and makes no changes
- setup dry-run prints planned folders and creates nothing
- setup creates folder structure, `config/settings.json`, a copied `wincarry.ps1`, and a log after typing `YES`

## Linux PowerShell Verification

Run these from the repository directory on Linux with PowerShell 7 installed:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File wincarry.ps1 help
pwsh -NoProfile -ExecutionPolicy Bypass -File wincarry.ps1 scan
pwsh -NoProfile -ExecutionPolicy Bypass -File wincarry.ps1 setup -Root /tmp/WinCarry-Test-Phase1 -DryRun
pwsh -NoProfile -ExecutionPolicy Bypass -File wincarry.ps1 setup -Root /tmp/WinCarry-Test-Phase1
```

Use Linux-native paths such as `/tmp/...` when invoking `pwsh` from a Linux shell.
