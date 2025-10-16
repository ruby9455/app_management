# app_management

This repository contains a set of PowerShell scripts and helper modules to manage, launch,
and generate a dashboard for locally-hosted Python web apps (Streamlit, Django, Dash, Flask).
The project is designed to be run from the `app_management` folder; modules are imported
relative to the scripts (no global module installation required).

Top-level scripts
-----------------

- `app_manager.ps1` (primary manager)
	- Interactive app manager: list/start/stop/restart/update apps declared in `apps.json`.
	- Launches apps in Windows Terminal tabs (preferred) or falls back to new PowerShell windows.
	- Detects package manager (`uv` when `pyproject.toml` exists, otherwise `pip`), finds venvs,
		and supports update hooks (git pull, dependency sync).
	- Key options: `-AppName`, `-DryRun`, `-AutoStart`.

- `landing_page.ps1` (HTML landing page server / generator)
	- Generates `app_index.html` using the `Dashboard` module and serves it over HTTP (default port 1111).
	- Regenerates HTML on each request so the page reflects current app states.

- `start.ps1` (wrapper)
	- Helper to launch the two scripts concurrently in Windows Terminal using `wt` (opens a new tab
		and splits panes). Resolves absolute pwsh/wt paths and verifies the scripts exist.

Helper modules (in `Modules/`)
-----------------------------

- `AppHelpers.psm1`
	- App-list utilities: normalize/dedupe apps, field getters/setters, venv detection, package manager
		detection, fuzzy index-file picker, repo/venv update helpers.

- `TerminalHelpers.psm1`
	- Windows Terminal helpers and window/tab interaction: detect `wt.exe`, create new tabs, and
		best-effort UI automation to send Enter/close a tab when needed.

- `UrlHelpers.psm1`, `NetworkHelpers.psm1`, `Dashboard.psm1`, `ProcessHelpers.psm1`, `LaunchHelpers.psm1`, `ConfigHelpers.psm1`
	- Small focused helpers used across the scripts: URL prefix detection (local/external/generic),
		port/process utilities (check listener, wait for port), HTML dashboard generation, and process helpers.

Key behaviors and requirements
-----------------------------

- PowerShell 7+ is required. Scripts include `#Requires -Version 7.0`.
- Windows Terminal (`wt.exe`) is the preferred frontend. When `wt` is not available the scripts
	attempt to launch apps in separate PowerShell windows.
- Apps.json
	- `apps.json` (in the same folder) is the canonical source of app definitions. An example
		is included as `apps_example.json`.

How to run
----------

From the repo root or the `app_management` folder, run the manager and landing page.

Run manager interactively:

```powershell
pwsh -File .\app_management\app_manager.ps1
```

Generate and host the landing page (default port 1111):

```powershell
pwsh -File .\app_management\landing_page.ps1
```

Launch both in Windows Terminal (wrapper):

```powershell
cd .\app_management
.\start.ps1
```

Or use wt directly (example):

```powershell
wt -w 0 new-tab pwsh -NoExit -NoProfile -ExecutionPolicy Bypass -File .\app_management\app_manager.ps1 ; split-pane -H pwsh -NoExit -NoProfile -ExecutionPolicy Bypass -File .\app_management\landing_page.ps1
```

Tests
-----

There are some lightweight PowerShell tests in `app_management/tests/`. From the repo root:

```powershell
pwsh -File .\app_management\tests\Test-AppHelpers.ps1
pwsh -File .\app_management\tests\Test-TerminalHelpers.ps1
```
