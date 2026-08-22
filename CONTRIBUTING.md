# Contributing to WinCarry

Thanks for helping improve WinCarry. This project changes filesystem state and can run package-manager install commands, so contributions should be conservative and easy to review.

## Development Rules

- Keep behavior dry-run first where practical.
- Require explicit `YES` confirmation before filesystem changes.
- Do not add broad Windows mutations such as changing `ProgramFilesDir`.
- Do not treat copied app folders or junctions as a universal migration strategy.
- Keep generated reports clear about risk and limitations.
- Preserve compatibility with Windows PowerShell 5.1 unless there is a strong reason not to.
- Avoid external PowerShell module dependencies for the MVP.

## Before Opening a Pull Request

Run a syntax check:

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

Run the help command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\wincarry.ps1 help
```

For behavior changes, add or update Windows smoke coverage in `.github/workflows/windows-smoke.yml` when possible.

## Pull Request Checklist

- The change has a narrow scope.
- Dry-run behavior is preserved or added.
- Write operations require visible confirmation.
- Reports and warnings do not overpromise portability.
- Sensitive data is not committed in examples, fixtures, reports, or manifests.
- GitHub Actions passes.

## Security Notes

Do not include real generated manifests, reports, logs, config backups, private keys, tokens, `.env` files, or machine-specific paths from your personal system in pull requests.

Use redacted fixture data under `examples/` or GitHub Actions temp folders instead.
