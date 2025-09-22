# app_management

This repository contains PowerShell helpers to manage and run local apps. It includes two main scripts used in this guide:

- `run_apps_tab_html.ps1` - launches app tabs and dashboard
- `generate_app_index.ps1` - generates the HTML index and runs a small HTTP server

## Launch both scripts in split panes (Windows Terminal)

If you want to run `run_apps_tab_html.ps1` and `generate_app_index.ps1` simultaneously in separate panes inside Windows Terminal, you have two options:

1) One-liner using `wt` (paste into PowerShell):

```powershell
wt powershell -NoExit -NoProfile -ExecutionPolicy Bypass -Command & 'C:\Users\rchan09\code\app_management\run_apps_tab_html.ps1' ; split-pane -H powershell -NoExit -NoProfile -ExecutionPolicy Bypass -Command & 'C:\Users\rchan09\code\app_management\generate_app_index.ps1'
```

Notes:
- Change `-H` to `-V` in `split-pane` for a vertical split.
- Ensure `wt.exe` (Windows Terminal) is installed and available on PATH.
- `-NoExit` keeps each pane open after the script completes so you can see output.

2) Use the provided wrapper script `start_both.ps1` (recommended):

Place `start_both.ps1` in the same folder as the two scripts (already added). Run it from PowerShell in the repository or by double-clicking if your execution policy allows:

```powershell
cd C:\Users\rchan09\code\app_management; .\start_both.ps1
```

Edge cases and troubleshooting:
- ExecutionPolicy: If scripts are blocked, run PowerShell as Administrator and set a policy (e.g., `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`) or use the wrapper which passes `-ExecutionPolicy Bypass`.
- Paths: The one-liner uses absolute paths. If you move the repo, update the paths or run the wrapper from the folder so it resolves scripts relative to itself.
- Windows Terminal: If `wt` isn't found, install Windows Terminal from the Microsoft Store or ensure `wt.exe` is on PATH.
 
Update (2025-09-23): The wrapper `start_manager_and_landing_page.ps1` now requests Windows Terminal to open the launched panes as a new tab in an existing Windows Terminal window (it passes `-w 0` to `wt`). This prevents spawning a separate WT window for each run and keeps the manager and index in the same terminal window as tabs/panes.

To use the wrapper:

```powershell
cd C:\Users\rchan09\code\app_management
.\start_manager_and_landing_page.ps1
```

If you prefer the original behavior (always open a new WT window), edit `start_manager_and_landing_page.ps1` and remove the `-w 0` arguments from the `wt` invocation.
# app_management