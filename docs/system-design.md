# WinCarry System Design

WinCarry is a PowerShell toolkit for preparing a Windows reinstall and reducing the manual work needed after the new Windows installation is ready.

The tool does not try to move an old Windows installation into a new one. It builds a reviewable record of the old machine, stores selected backup data in a preserved WinCarry root, then uses that root to guide reinstall and config restore on the new machine.

## Design Goals

- Keep every modifying operation behind dry-run output and explicit confirmation.
- Preserve reviewable artifacts that survive Windows reinstall.
- Prefer package-manager reinstall over copying installed application folders.
- Treat unknown, service-heavy, driver, runtime, security, and system-like apps conservatively.
- Restore user config only from known backup paths and with conflict handling.
- Keep offline-safe workflows from invoking package-manager scan, status, or install commands.

## Non-Goals

- WinCarry is not a full Windows image migration tool.
- WinCarry does not migrate licenses, activations, accounts, certificates, drivers, Windows services, databases, or arbitrary machine state.
- WinCarry does not guarantee that restored apps will run without repair, login, activation, or manual setup.
- Junction mode is not a universal replacement for reinstalling apps.

## Main Components

```mermaid
flowchart TD
  User["User in PowerShell"] --> Entry["wincarry.ps1"]
  Entry --> Router["Command router"]

  Router --> Setup["setup"]
  Router --> Preflight["preflight"]
  Router --> Scan["scan"]
  Router --> Backup["backup"]
  Router --> Manifest["manifest"]
  Router --> Report["report"]
  Router --> Restore["restore"]
  Router --> Offline["offline"]
  Router --> Junction["junction"]

  Setup --> Root["WinCarry root"]
  Preflight --> Reports["reports/"]
  Scan --> Evidence["Raw evidence"]
  Evidence --> Apps["Logical apps"]
  Apps --> Classification["Restore classification"]
  Classification --> ManifestFile["manifests/latest.json"]
  Manifest --> ManifestFile
  Manifest --> RestoreScripts["restore-scripts/"]
  Backup --> Backups["backups/"]
  Backup --> ConfigMetadata["backups/latest-config-backup.json"]
  Report --> Reports
  Restore --> PackageManagers["winget / choco / scoop"]
  Restore --> ConfigRestore["Config restore engine"]
  Offline --> ManifestFile
  Junction --> JunctionState["junction backups and rollback state"]

  Root --> Config["config/"]
  Root --> Backups
  Root --> Reports
  Root --> ManifestFile
  Root --> RestoreScripts
```

## Module Map

```mermaid
flowchart LR
  Entry["wincarry.ps1"] --> Core["lib/WinCarry.Core.ps1"]
  Entry --> Cli["lib/WinCarry.Cli.ps1"]
  Entry --> Preflight["lib/WinCarry.Preflight.ps1"]
  Entry --> Inventory["lib/WinCarry.Inventory.ps1"]
  Entry --> Scan["lib/WinCarry.Scan.ps1"]
  Entry --> Manifest["lib/WinCarry.ManifestCommands.ps1"]
  Entry --> Config["lib/WinCarry.Config.ps1"]
  Entry --> Backup["lib/WinCarry.Backup.ps1"]
  Entry --> Restore["lib/WinCarry.Restore.ps1"]
  Entry --> Offline["lib/WinCarry.Offline.ps1"]
  Entry --> Junction["lib/WinCarry.Junction.ps1"]

  Core --> Shared["paths, JSON, logging, prompts"]
  Cli --> Routing["help, setup, menu routing"]
  Inventory --> AppModel["evidence, dedupe, classification"]
  Config --> ConfigModel["known config definitions and backup metadata"]
  Restore --> RestorePlan["restore planning, package commands, config restore"]
```

## Artifact Model

The WinCarry root is the durable handoff between the old Windows installation and the new Windows installation.

```mermaid
flowchart TD
  Root["WinCarry root on preserved drive"] --> Config["config/settings.json"]
  Root --> Apps["apps/ and portable/"]
  Root --> Scoop["scoop/"]
  Root --> Manifests["manifests/"]
  Root --> Backups["backups/"]
  Root --> RestoreScripts["restore-scripts/"]
  Root --> Reports["reports/"]
  Root --> Logs["logs/"]

  Manifests --> LatestManifest["latest.json"]
  Manifests --> TimestampManifest["YYYY-MM-DD_HHMM_manifest.json"]
  Backups --> LatestBackup["latest-config-backup.json"]
  RestoreScripts --> RestoreLatest["restore-latest.ps1"]
  Reports --> HumanReports["scan, backup, restore, manual, unsupported reports"]
```

Important artifacts:

- `manifests/latest.json`: source of truth used by restore.
- `backups/latest-config-backup.json`: metadata for the latest config backup.
- `restore-scripts/restore-latest.ps1`: portable launcher for restore after reinstall.
- `reports/*.md` and `reports/*.txt`: human-readable review output.
- `logs/wincarry-YYYY-MM-DD.log`: operation audit log.

## End-to-End Tool Flow

This is the intended user journey from the old Windows installation to a new Windows installation where selected apps are installed again and can be opened.

```mermaid
flowchart TD
  A["Old Windows: user clones or downloads WinCarry"] --> B["Preview WinCarry root setup"]
  B --> C{"Folder plan looks correct?"}
  C -- "No" --> C1["Choose another root or stop"]
  C -- "Yes" --> D["Create WinCarry root"]
  D --> E["Type YES"]
  E --> F["WinCarry root folders are created"]

  F --> G["Capture preflight snapshot"]
  G --> H["Review OS, user, drives, privilege, package managers"]

  H --> I["Preview manifest generation"]
  I --> J["Scan registry, package managers, Start Menu, known folders"]
  J --> K["Deduplicate evidence into logical apps"]
  K --> L["Classify restore strategy and confidence"]
  L --> M{"Manifest plan acceptable?"}
  M -- "No" --> M1["Stop and review warnings or unsupported apps"]
  M -- "Yes" --> N["Generate manifest and reports"]
  N --> O["Type YES"]
  O --> P["Write manifests, reports, manual lists, restore scripts"]

  P --> Q["Preview config backup"]
  Q --> R["Review known config paths and sensitive-file skips"]
  R --> S{"Backup plan acceptable?"}
  S -- "No" --> S1["Stop or adjust expectations"]
  S -- "Yes" --> T["Back up known config files"]
  T --> U["Type YES"]
  U --> V["Write config backups and backup metadata"]

  V --> W["Keep or copy the whole WinCarry root"]
  W --> X["Reinstall Windows"]
  X --> Y["New Windows: install PowerShell and package managers if needed"]
  Y --> Z["Open preserved WinCarry root"]
  Z --> AA["Preview restore from preserved root"]
  AA --> AB["Review package-manager commands, skipped apps, config conflicts"]
  AB --> AC{"Restore plan acceptable?"}
  AC -- "No" --> AC1["Stop and manually review reports"]
  AC -- "Yes" --> AD["Run restore from preserved root"]
  AD --> AE["Choose restore mode and version policy"]
  AE --> AF["Type YES after final plan"]
  AF --> AG["Run planned package-manager install commands"]
  AG --> AH["Choose config restore mode"]
  AH --> AI["Skip, restore missing only, or back up and replace"]
  AI --> AJ["Write restore report and log"]
  AJ --> AK["Open restored apps"]
  AK --> AL{"Apps run correctly?"}
  AL -- "Yes" --> AM["Restore workflow complete for those apps"]
  AL -- "No" --> AN["Use manual report for repair, login, activation, or manual reinstall"]
```

## Before Reinstall Flow

The before-reinstall phase gathers evidence and creates durable restore inputs.

```mermaid
sequenceDiagram
  actor User
  participant CLI as wincarry.ps1
  participant Root as WinCarry root
  participant Inventory as Inventory sources
  participant Manifest as Manifest/report writer
  participant Backup as Config backup

  User->>CLI: preview setup command
  CLI-->>User: folder and file plan
  User->>CLI: execute setup command
  CLI-->>User: require YES
  User->>CLI: YES
  CLI->>Root: create folders, settings, root launcher

  User->>CLI: run preflight command
  CLI->>Root: write report and log

  User->>CLI: preview manifest command
  CLI->>Inventory: collect local evidence
  Inventory-->>CLI: raw evidence
  CLI->>CLI: dedupe and classify apps
  CLI-->>User: manifest/report plan

  User->>CLI: execute manifest command
  CLI-->>User: require YES
  User->>CLI: YES
  CLI->>Manifest: write latest manifest, reports, restore scripts

  User->>CLI: preview backup command
  CLI-->>User: config backup plan
  User->>CLI: execute backup command
  CLI-->>User: require YES
  User->>CLI: YES
  CLI->>Backup: copy known config files
  Backup->>Root: write backups and backup metadata
```

## After Reinstall Flow

The after-reinstall phase uses the preserved root as the source of truth.

```mermaid
sequenceDiagram
  actor User
  participant Script as restore-scripts/restore-latest.ps1
  participant CLI as wincarry.ps1 restore
  participant Manifest as manifests/latest.json
  participant PM as Package managers
  participant Config as Config restore
  participant Reports as reports/
  participant App as Restored app

  User->>Script: preview restore launcher command
  Script->>CLI: run restore dry-run with latest manifest
  CLI->>Manifest: read restore source of truth
  CLI->>PM: check available package managers
  CLI-->>User: restore plan, skipped apps, config conflicts

  User->>Script: execute restore launcher command
  Script->>CLI: run restore with latest manifest
  CLI-->>User: choose restore mode
  CLI-->>User: choose version policy
  CLI-->>User: require YES
  User->>CLI: YES
  CLI->>PM: run selected install commands
  PM-->>CLI: command results
  CLI-->>User: choose config restore mode
  User->>CLI: config mode
  CLI->>Config: restore selected configs with conflict policy
  Config-->>CLI: copied, skipped, backed-up conflicts
  CLI->>Reports: write restore report and log
  User->>App: open application
  App-->>User: app runs, or user performs manual repair/login/activation
```

## Restore Decision Flow

Restore is intentionally conservative. A package-manager app can be restored automatically only when the manifest has a package identity and the relevant package manager is currently available.

```mermaid
flowchart TD
  A["Read manifests/latest.json"] --> B{"offlineSafeMode true?"}
  B -- "Yes" --> C["Block package-manager install commands"]
  C --> D["Write review report only"]

  B -- "No" --> E["Check current winget, choco, scoop availability"]
  E --> F["Filter apps by selected restore mode"]
  F --> G{"App has package identity?"}
  G -- "No" --> H["Skip: manual review or unsupported"]
  G -- "Yes" --> I{"Package manager available?"}
  I -- "No" --> J["Skip: manager unavailable"]
  I -- "Yes" --> K["Plan install command"]
  K --> L{"User types YES?"}
  L -- "No" --> M["Cancel without install"]
  L -- "Yes" --> N["Run package-manager install"]
  N --> O["Record result in restore report"]
```

## Config Restore Flow

Config restore happens after the package-manager restore decision. The default mode is to skip config restore unless the user chooses otherwise.

```mermaid
flowchart TD
  A["Manifest contains config paths"] --> B["Build config restore plan"]
  B --> C["Resolve target path on current user profile"]
  C --> D{"Target already exists?"}
  D -- "No" --> E["Eligible for missing-only restore"]
  D -- "Yes" --> F["Conflict"]
  F --> G{"User selects replace mode?"}
  G -- "No" --> H["Skip existing target"]
  G -- "Yes" --> I["Back up existing target first"]
  I --> J["Copy backed-up config to target"]
  E --> J
  J --> K["Record copied/skipped/conflict status"]
```

## Offline-Safe Flow

Offline-safe mode is useful when the user wants local artifacts without package-manager scan, status, or install behavior.

```mermaid
flowchart TD
  A["Preview offline-safe workflow"] --> B["Preview config backup"]
  B --> C["Preview offline scan"]
  C --> D["Skip winget/choco/scoop scan"]
  D --> E["Preview offline-safe manifest"]

  F["Execute offline-safe workflow"] --> G["Require YES for backup/manifest writes"]
  G --> H["Write backup, manifest, reports, restore scripts"]
  H --> I["Manifest sets offlineSafeMode = true"]
  I --> J["Future restore blocks package-manager install commands"]
```

## Safety Gates

Every workflow that can write files or execute install commands follows the same basic control pattern.

```mermaid
flowchart TD
  A["Command starts"] --> B["Build plan"]
  B --> C["Print human-readable plan"]
  C --> D{"DryRun?"}
  D -- "Yes" --> E["Write nothing"]
  D -- "No" --> F["Ask for exact confirmation"]
  F --> G{"User typed YES?"}
  G -- "No" --> H["Cancel safely"]
  G -- "Yes" --> I["Perform scoped operation"]
  I --> J["Write report/log"]
```

## Success Criteria

A WinCarry restore should be considered successful only for the apps that pass post-restore user validation.

```mermaid
flowchart LR
  A["Package command succeeded"] --> B["App appears installed"]
  B --> C["User opens app"]
  C --> D{"App works for real task?"}
  D -- "Yes" --> E["Restored for this app"]
  D -- "No" --> F["Needs manual repair, login, activation, data restore, or reinstall"]
```

Package-manager success is not the same as application success. The final proof is opening the application and confirming that the user's required workflow works on the new Windows installation.

## Practical User Checklist

Before reinstall, run these commands from the cloned WinCarry repository folder. Replace `D:\WinCarry` with your chosen preserved root if needed.

1. Preview root setup.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 setup -Root "D:\WinCarry" -DryRun
```

2. Create the WinCarry root after the plan looks correct.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 setup -Root "D:\WinCarry"
```

3. Capture the preflight snapshot and review the report.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 preflight -Root "D:\WinCarry"
```

4. Preview manifest generation.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 manifest -Root "D:\WinCarry" -DryRun
```

5. Generate the manifest, reports, and restore scripts after the plan looks correct.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 manifest -Root "D:\WinCarry"
```

6. Preview config backup.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 backup -Root "D:\WinCarry" -DryRun
```

7. Back up known config files after the backup plan looks correct.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 backup -Root "D:\WinCarry"
```

8. Review the generated handoff artifacts.

```powershell
Get-ChildItem "D:\WinCarry\reports"
Get-ChildItem "D:\WinCarry\manifests"
Get-ChildItem "D:\WinCarry\backups"
Get-ChildItem "D:\WinCarry\restore-scripts"
```

9. Keep or copy the whole `D:\WinCarry` root somewhere that survives reinstall.

After reinstall, run these commands from the new Windows installation after the preserved WinCarry root is available.

1. Preview restore from the preserved root.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\WinCarry\restore-scripts\restore-latest.ps1" -DryRun
```

2. Run restore after the dry-run plan looks correct.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\WinCarry\restore-scripts\restore-latest.ps1"
```

3. Review the latest restore report.

```powershell
Get-ChildItem "D:\WinCarry\reports\restore-*.md" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
```

4. Open each important restored application and confirm that the real workflow works.

5. Use the generated reports for anything that needs manual reinstall, repair, login, activation, or data restore.
