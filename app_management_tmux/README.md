# App Management - tmux Edition

A Bash-based app manager for Linux using **tmux** as the terminal multiplexer.

## Why tmux over Zellij?

**tmux** provides full programmatic control that Zellij lacks:
- ✅ **Kill specific windows/panes by name** - `tmux kill-window -t session:window`
- ✅ **Send keys to panes** - Stop apps gracefully with Ctrl+C
- ✅ **Query running windows** - List all windows and their status
- ✅ **Session management** - Attach/detach sessions reliably
- ✅ **Mature and stable** - 15+ years of development

Zellij doesn't support programmatically stopping/killing specific panes by name, which breaks stop/restart functionality.

## Features

- **Start apps** - Launch Python apps (Streamlit, Django, Flask, Dash) in tmux windows
- **Stop apps** - Kill apps by terminating their tmux window or sending Ctrl+C
- **Restart apps** - Stop and start apps in the same window
- **Add/Edit/Delete apps** - Manage your apps.json configuration
- **Port detection** - Check which apps are running
- **Auto-detection** - Detect app type and package manager
- **Dashboard generation** - Generate HTML dashboard with app links

## Requirements

- Bash 4.0+
- tmux 2.0+
- jq (JSON processor)
- Python 3.8+ (for running apps)
- Optional: uv or pip

### Install Dependencies

```bash
# Ubuntu/Debian
sudo apt install tmux jq

# Fedora/RHEL
sudo dnf install tmux jq

# Arch
sudo pacman -S tmux jq

# macOS
brew install tmux jq
```

## Usage

### Interactive Mode
```bash
./manager.sh
```

### Command Line
```bash
# Start a specific app
./manager.sh --app "My App"

# Start all apps
./manager.sh --all

# Dry run (show what would be executed)
./manager.sh --dry-run --all

# Attach to the tmux session
./manager.sh --attach
```

### Inside the Interactive Menu
```
Commands:
  [number(s)]   - Start app(s) by index (e.g., 1,2,3)
  [name]        - Start app by name
  0 or all      - Start all apps
  s [num]       - Stop app by index
  S             - Stop all running apps
  r [num]       - Restart app by index
  a             - Add a new app
  e [num]       - Edit app by index
  d [num]       - Delete app by index
  l             - List tmux windows (running apps)
  t             - Attach to tmux session
  R             - Refresh list
  q             - Quit
```

## Configuration

Apps are defined in `apps.json`. Copy from `apps_example.json` to get started:

```bash
cp apps_example.json apps.json
```

### App Configuration

```json
{
    "Name": "My App",
    "Type": "Streamlit",
    "Port": 8501,
    "AppPath": "/path/to/app",
    "IndexPath": "app.py",
    "VenvPath": "/path/to/venv",
    "PackageManager": "uv"
}
```

**Supported Types**: `Streamlit`, `Django`, `Flask`, `Dash`

**Package Managers**: `uv` (auto-detected from pyproject.toml) or `pip`

## Session Structure

All apps run in a single tmux session named `app_manager`:
- Each app gets its own named window
- Windows can be attached to see output
- Windows persist until explicitly closed

```bash
# List all windows
tmux list-windows -t app_manager

# Attach to session
tmux attach -t app_manager

# Detach: Press Ctrl+B, then D
```

## Files

```
app_management_tmux/
├── manager.sh          # Main manager script
├── start.sh            # Quick start helper
├── apps.json           # Your app configurations
├── apps_example.json   # Example configuration
├── README.md           # This file
└── lib/
    ├── config.sh       # Configuration helpers
    ├── app_helpers.sh  # App management functions
    ├── tmux_helpers.sh # tmux-specific functions
    ├── json_helpers.sh # JSON manipulation
    └── url_helpers.sh  # URL/network detection
```
