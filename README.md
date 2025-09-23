# app_management

This repository contains PowerShell helpers to manage and run local apps. It includes two main scripts used in this guide:

- `run_apps_tab_html.ps1` — launches app tabs and dashboard (supports `-AppName`, `-AutoStart`, `-DryRun`)
- `generate_landing_page.ps1` — generates the HTML landing page and runs a small HTTP server

## Launch both scripts in split panes (Windows Terminal)

If you want to run `run_apps_tab_html.ps1` and `generate_landing_page.ps1` simultaneously in separate panes inside Windows Terminal, you have two options:

1) One-liner using `wt` (paste into PowerShell):

```powershell
wt -w 0 new-tab pwsh -NoExit -NoProfile -ExecutionPolicy Bypass -Command & 'C:\Users\rchan09\code\app_management\app_management\run_apps_tab_html.ps1' ; split-pane -H pwsh -NoExit -NoProfile -ExecutionPolicy Bypass -Command & 'C:\Users\rchan09\code\app_management\app_management\generate_landing_page.ps1'
```

Notes:
- Change `-H` to `-V` in `split-pane` for a vertical split.
- Ensure `wt.exe` (Windows Terminal) is installed and available on PATH.
- `-NoExit` keeps each pane open after the script completes so you can see output.

2) Use the provided wrapper script `start_manager_and_landing_page.ps1` (recommended):

This script opens a new tab in the existing Windows Terminal window and splits panes for both scripts.

```powershell
cd C:\Users\rchan09\code\app_management\app_management
.\start_manager_and_landing_page.ps1
```

Edge cases and troubleshooting:
- ExecutionPolicy: If scripts are blocked, run PowerShell as Administrator and set a policy (e.g., `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`) or use the wrapper which passes `-ExecutionPolicy Bypass`.
- Paths: The one-liner uses absolute paths. If you move the repo, update the paths or run the wrapper from the folder so it resolves scripts relative to itself.
- Windows Terminal: If `wt` isn't found, install Windows Terminal from the Microsoft Store or ensure `wt.exe` is on PATH.
 
Update (2025-09-23): The wrapper `start_manager_and_landing_page.ps1` now requests Windows Terminal to open the launched panes as a new tab in an existing Windows Terminal window (it passes `-w 0` to `wt`). This prevents spawning a separate WT window for each run and keeps the manager and index in the same terminal window as tabs/panes.

To use the wrapper:

```powershell
cd C:\Users\rchan09\code\app_management\app_management
.\start_manager_and_landing_page.ps1
```

If you prefer the original behavior (always open a new WT window), edit `start_manager_and_landing_page.ps1` and remove the `-w 0` arguments from the `wt` invocation.

## Modules layout

- `app_management/app_management/Modules/AppHelpers.psm1` — app list utilities (dedupe, field accessors, venv/package helpers, repo/venv updates)
- `app_management/app_management/Modules/TerminalHelpers.psm1` — Windows Terminal and window interaction helpers
- `app_management/app_management/Modules/ProcessHelpers.psm1` — Process-oriented actions extracted from scripts: stop apps by port, close idle tabs, update apps (stop → update → restart via Enter).

Notes:
- Scripts import these modules using paths relative to their own location; global installation isn’t required.
- PowerShell 7+ is required. The scripts include `#Requires -Version 7.0`.

## Running tests

A simple test script validates a few helpers. From the repo root:

```powershell
pwsh -File .\app_management\app_management\tests\Test-AppHelpers.ps1
pwsh -File .\app_management\app_management\tests\Test-TerminalHelpers.ps1
```

What it covers:
- `Normalize-AppsList` — filters unsupported types and de-duplicates by `Name`
- `Get-PackageManager` — returns `uv` when `pyproject.toml` is present, otherwise `pip`

Terminal helpers smoke test:
- `Get-WindowsTerminalPath` shape and availability
- `New-WindowsTerminalTab` basic non-throw behavior
