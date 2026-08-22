# WinCarry

WinCarry is a PowerShell toolkit for preparing a Windows reinstall and reducing the work needed after the new Windows installation is ready.

This tool helps prepare and restore applications/configuration after Windows reinstall.
It does not guarantee that every application will work without reinstall, repair, login, or activation.

WinCarry is currently alpha software. Read every dry-run plan before allowing a write, and keep an external copy of the WinCarry root before reinstalling Windows.

## What WinCarry Does

WinCarry can:

- Create a portable WinCarry root folder, defaulting to `D:\WinCarry`.
- Capture a preflight system snapshot.
- Scan installed applications from local evidence sources.
- Deduplicate app evidence into logical app records.
- Classify apps by conservative restore strategy.
- Generate reinstall manifests and human-readable reports.
- Back up selected user configuration files.
- Generate restore launcher scripts under `restore-scripts`.
- Reinstall selected package-manager apps through `winget`, Chocolatey, or Scoop.
- Restore backed-up config files with conflict handling.
- Run an offline-safe workflow that skips package-manager scan/status/install commands.
- Create guarded directory junctions for advanced manual workflows.

## What WinCarry Does Not Guarantee

WinCarry does not guarantee that every application will work after Windows reinstall without reinstall, repair, login, activation, registry registration, service setup, driver setup, data migration, or account re-authentication.

It intentionally avoids dangerous global Windows changes such as rewriting `ProgramFilesDir` or treating symlinks/junctions as a universal app migration strategy.

## Requirements

- Windows for real scan, restore, and junction workflows.
- Windows PowerShell 5.1 or PowerShell 7+.
- Optional package managers, depending on what you want to restore:
  - `winget`
  - Chocolatey (`choco`)
  - Scoop (`scoop`)

Linux with PowerShell 7 can run parser and limited smoke checks, but it cannot reproduce Windows registry, Start Menu, package-manager, or junction behavior.

## Usage Examples

From the repository directory:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 help
```

Preview setup:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 setup -Root "D:\WinCarry" -DryRun
```

Create the WinCarry root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 setup -Root "D:\WinCarry"
```

Type `YES` when the plan is correct.

Prepare a reinstall manifest and reports:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 manifest -Root "D:\WinCarry" -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 manifest -Root "D:\WinCarry"
```

Back up known configuration files:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 backup -Root "D:\WinCarry" -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 backup -Root "D:\WinCarry"
```

Sensitive files are skipped by default. Type `INCLUDE` only if you intentionally want to back up sensitive files such as private keys or token-bearing config files.

After Windows reinstall, run from the preserved WinCarry root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\WinCarry\restore-scripts\restore-latest.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File D:\WinCarry\restore-scripts\restore-latest.ps1
```

## Commands

```text
.\wincarry.ps1
.\wincarry.ps1 setup [-Root D:\WinCarry] [-DryRun]
.\wincarry.ps1 preflight [-Root D:\WinCarry] [-DryRun]
.\wincarry.ps1 scan [-Root D:\WinCarry] [-DryRun]
.\wincarry.ps1 backup [-Root D:\WinCarry] [-DryRun]
.\wincarry.ps1 manifest [-Root D:\WinCarry] [-DryRun]
.\wincarry.ps1 report [-Root D:\WinCarry] [-DryRun]
.\wincarry.ps1 restore [-Root D:\WinCarry] [-Manifest path] [-DryRun]
.\wincarry.ps1 offline [-Root D:\WinCarry] [-DryRun]
.\wincarry.ps1 junction [-Root D:\WinCarry] [-DryRun]
.\wincarry.ps1 help
```

All modifying workflows print a plan first and require an explicit `YES` before changing files. Use `-DryRun` first.

## Typical Workflow Before Reinstall

1. Clone or download WinCarry.
2. Run `setup -Root "D:\WinCarry"`.
3. Run `preflight` and review the report.
4. Run `manifest -DryRun`, then `manifest`.
5. Run `backup -DryRun`, then `backup`.
6. Review files under:
   - `D:\WinCarry\manifests`
   - `D:\WinCarry\reports`
   - `D:\WinCarry\backups`
   - `D:\WinCarry\restore-scripts`
7. Copy or keep the entire WinCarry root somewhere that survives the Windows reinstall.

## Typical Workflow After Reinstall

1. Install PowerShell if needed.
2. Install any package managers you want WinCarry to use.
3. Open PowerShell in the preserved WinCarry root.
4. Run restore dry-run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\restore-scripts\restore-latest.ps1 -DryRun
```

5. Review the restore plan and skipped app sample.
6. Run restore:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\restore-scripts\restore-latest.ps1
```

7. Choose restore mode, version policy, and config restore mode only after reviewing the plan.

## PowerShell Execution Policy Notes

The examples use:

```powershell
-ExecutionPolicy Bypass
```

That bypass applies to the current `powershell.exe` process invocation. It does not permanently change the machine execution policy.

If your environment blocks scripts through Group Policy, App Control, antivirus, or corporate endpoint management, follow your organization's policy instead of bypassing it.

## Supported and Unsupported Categories

WinCarry classifies apps conservatively. Restore confidence is a risk classification, not a success rate or guarantee.

Automatic package-manager restore can be planned for:

- `Winget reinstallable`: package metadata was found for `winget`.
- `Chocolatey reinstallable`: package metadata was found for Chocolatey.
- `Scoop-managed`: package metadata was found for Scoop.

Automatic restore still requires an installable package ID and the relevant package manager to be available on the restore machine.

Manual review or manual reinstall categories include:

- `Portable / Self-contained`: app folder was found under WinCarry-managed portable/manual locations.
- `Installer-based / manual reinstall`: uninstall registry metadata exists but no package-manager identity was found.
- `Service-heavy`: app likely depends on services, data directories, networking, drivers, or local machine state.
- `Unknown`: evidence is not strong enough for an automatic strategy.

Unsupported or do-not-restore-automatically categories include:

- `Microsoft Store / UWP`: Store/UWP restore is outside automatic restore scope.
- `Driver / system component`: device/system-level software should not be copied or restored automatically.
- `Unsupported / risky`: runtime, SDK, security, VPN, driver, or system-like component that should not be automatically restored.

Manual and unsupported lists are generated so you can review everything that WinCarry will not reinstall automatically.

## Security Warnings

- Manifests and reports can contain application names, package IDs, install paths, usernames, machine names, and profile paths.
- Do not publish real generated reports or manifests without reviewing and redacting them.
- Config backup can contain secrets. Sensitive files are skipped by default, but you can override that with `INCLUDE`.
- Backed-up SSH keys, npm tokens, cloud credentials, and `.env` files can grant access to remote systems.
- Restore can run package-manager install commands. Review the plan before typing `YES`.
- Junction mode moves folders and creates reparse points. It is advanced and should be used only after a dry-run review.

## Offline-Safe Mode

Use offline-safe mode when you want local backup, scan, manifest, and report generation without package-manager scan/status/install behavior:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 offline -Root "D:\WinCarry" -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 offline -Root "D:\WinCarry"
```

Offline-safe mode still reads local inventory/config sources. It is offline-safe with respect to package-manager and network-dependent package operations; it is not a no-file-read sandbox mode.

Manifests generated in offline-safe mode block package-manager restore commands when passed to `restore`.

## Advanced Junction Mode

Junction mode is for advanced manual cases only:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 junction -Root "D:\WinCarry" -DryRun
```

It blocks protected paths, requires explicit confirmation, backs up the source folder, moves the source to the target, creates a directory junction, verifies the result, and attempts rollback on failure.

Do not use junction mode as a general replacement for reinstalling apps.

## Known Limitations

- Alpha software. Review every plan and keep independent backups.
- WinCarry does not migrate licenses, activations, accounts, certificates, device drivers, Windows services, databases, or app-specific machine state.
- Store/UWP apps are not automatically restored.
- Service-heavy apps require manual review.
- Runtime and SDK dependencies should generally be installed by Windows, apps, or package managers as needed.
- Package-manager inventory output can vary by version and locale.
- Scoop detected-version restore currently installs the latest package instead of pinning a historical version.
- Config restore is conservative and limited to known paths detected by WinCarry.
- Linux verification does not prove Windows runtime behavior.

## Repository Files

- `wincarry.ps1`: entry point.
- `lib/`: helper scripts loaded by the entry point.
- `.github/workflows/windows-smoke.yml`: Windows GitHub Actions smoke tests.
- `examples/sample-manifest.json`: small redacted sample manifest.
- `examples/sample-report.md`: small redacted sample report.

## Verification

Local syntax check with PowerShell:

```powershell
$files = @((Get-Item -LiteralPath .\wincarry.ps1)) + @(Get-ChildItem -LiteralPath .\lib -Filter "*.ps1" | Sort-Object Name)
foreach ($file in $files) {
  $errors = @()
  $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw -LiteralPath $file.FullName), [ref]$errors)
  if ($errors.Count -gt 0) {
    $errors | Format-List
    throw "Syntax errors in $($file.FullName)"
  }
}
```

GitHub Actions runs Windows smoke tests on push, pull request, and manual dispatch.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See [LICENSE](LICENSE).
