# WinCarry Scan Report

Created: 2026-08-23T09:00:00+07:00
Manifest schema: 1.0
WinCarry root: D:\WinCarry
Offline-safe mode: False

> Restore confidence is a risk classification, not a success rate or guarantee.

## System

- Computer: SAMPLE-PC
- Windows: Microsoft Windows 11 64-bit
- User: SAMPLE-PC\sample-user
- Profile: C:\Users\sample-user
- Admin/root: False

## Summary

- Apps: 3
- Evidence records: 6
- Manual reinstall / review: 1
- Unsupported / do not restore automatically: 1

## Classification Summary

- Installer-based / manual reinstall: 1
- Unsupported / risky: 1
- Winget reinstallable: 1

## Restore Confidence Summary

- Low: 1
- Medium: 1
- Unsupported: 1

## Package Managers

- chocolatey: available=False; version unknown
- scoop: available=False; version unknown
- winget: available=True; v1.11.0

## Manual Reinstall / Review List

| App | Classification | Restore confidence | Package | Reason |
| --- | --- | --- | --- | --- |
| Example Manual App | Installer-based / manual reinstall | Low | manual | Found uninstall registry metadata but no package-manager identity. |

## Unsupported / Do Not Restore Automatically

| App | Classification | Reason |
| --- | --- | --- |
| Example Runtime Component | Unsupported / risky | Runtime or SDK dependency should be installed by Windows, apps, or package managers as needed. |

## App Details

| App | Classification | Restore confidence | Strategy | Package | Evidence |
| --- | --- | --- | --- | --- | --- |
| Git | Winget reinstallable | Medium | reinstall-via-package-manager | winget:Git.Git | 3 |
| Example Manual App | Installer-based / manual reinstall | Low | manual-reinstall | manual | 1 |
| Example Runtime Component | Unsupported / risky | Unsupported | do-not-restore | manual | 1 |

## Notes

- This is a redacted sample report.
- Do not publish real reports without reviewing machine names, usernames, paths, package IDs, and config backup references.
- Restore confidence is not a guarantee that an app will work after reinstall.
