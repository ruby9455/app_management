# App Management — psmux Edition

Windows PowerShell version of the tmux app manager. It uses [psmux](https://github.com/psmux/psmux)'s tmux-compatible command line to run every app in a named window of one persistent `app_manager` session.

## Requirements

- Windows 10/11 and PowerShell 7+
- `psmux` on `PATH` (its `tmux` alias also works)
- Python (`py` or `python`), plus `uv` or pip as required by each app

## Setup

Copy the example configuration and replace its placeholder paths:

```powershell
Copy-Item .\apps_example.json .\apps.json
notepad .\apps.json
```

`manager.ps1` will make that copy automatically on its first run if `apps.json` is absent.

## Usage

```powershell
.\manager.ps1                         # interactive manager + dashboard
.\manager.ps1 -AppName 'My App'        # start one app
.\manager.ps1 -All                     # start all apps
.\manager.ps1 -DryRun -All             # show launch commands
.\manager.ps1 -Attach                  # attach to psmux session
.\manager.ps1 -NoLanding               # skip/stop dashboard

.\start.ps1 all
.\start.ps1 attach
.\start.ps1 stop
.\start.ps1 list
```

The interactive commands mirror `app_management_tmux`: start by number/name (`0` for all), `s` stop, `r` restart, `u` update, `aa` add app, `ap` add custom process, `e` edit, `d` delete, `D` dashboard toggle, `l` list windows, and `t` attach/select.

## Session behaviour

The default session is `app_manager`; override it for a separate group with:

```powershell
$env:APP_MANAGER_PSMUX_SESSION = 'my_apps'
```

Each app gets a sanitized named psmux window. Stop and restart first send Ctrl+C, then close that window. The dashboard runs in `_Dashboard` on port `1111` and regenerates from `apps.json` for every browser request.

## App configuration

```json
{
  "Name": "My App",
  "Type": "Streamlit",
  "Port": 8501,
  "AppPath": "C:\\code\\my-app",
  "IndexPath": "app.py",
  "VenvPath": "C:\\code\\my-app\\.venv",
  "PackageManager": "uv"
}
```

Supported web types are `Streamlit`, `Django`, `Flask`, and `Dash`. An entry with `CustomCommand` is also supported for a long-running process. `PackageManager` defaults to `uv` when `pyproject.toml` is present, otherwise `pip`.
