# App Management for Linux

A Linux-native port of the Windows app management system, using **Zellij** as the terminal multiplexer instead of Windows Terminal.

## 🚀 Features

- **Interactive App Manager**: Start, stop, and monitor Streamlit, Django, Dash, and Flask apps
- **Dashboard Server**: Beautiful HTML dashboard showing all app URLs with copy-to-clipboard
- **Zellij Integration**: Split-pane workflow with manager and dashboard side-by-side
- **Auto-detection**: Automatically detects package managers (uv/pip), virtual environments, and network configuration
- **Flexible Configuration**: Apps configured via `apps.json`

## 📋 Requirements

### Required
- **Bash 4.0+** (usually pre-installed on Linux)
- **jq** - JSON processor for parsing apps.json
- **Python 3.8+** - For running apps and the dashboard server

### Recommended
- **Zellij** - Modern terminal multiplexer ([installation](https://zellij.dev/documentation/installation))
- **uv** - Fast Python package manager ([installation](https://docs.astral.sh/uv/getting-started/installation/))

### Optional (fallback terminal multiplexers)
- **tmux** - If Zellij is not available
- Various terminal emulators (gnome-terminal, konsole, kitty, alacritty, wezterm)

## 📦 Installation

### 1. Install Dependencies

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install jq python3 python3-pip

# Install Zellij
bash <(curl -L https://zellij.dev/launch)
# Or via cargo:
cargo install zellij
```

**Fedora/RHEL:**
```bash
sudo dnf install jq python3 python3-pip

# Install Zellij
cargo install zellij
```

**Arch Linux:**
```bash
sudo pacman -S jq python zellij
```

### 2. Install uv (Recommended)

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

### 3. Set Up App Management

```bash
# Clone or copy the app_management_linux folder
cd /path/to/app_management_linux

# Make scripts executable
chmod +x *.sh lib/*.sh

# Copy example apps file
cp apps_example.json apps.json

# Edit apps.json with your actual app configurations
nano apps.json
```

## 🎯 Usage

### Quick Start with Zellij

```bash
# Launch both manager and dashboard in split panes
./start.sh

# Use horizontal split (stacked)
./start.sh --horizontal
```

This opens Zellij with:
- **Left pane**: Interactive app manager
- **Right pane**: Dashboard HTTP server

### Individual Scripts

#### App Manager
```bash
# Interactive mode
./manager.sh

# Start a specific app
./manager.sh --app "My App Name"

# Start all apps
./manager.sh --all

# Dry run (preview commands)
./manager.sh --dry-run --all
```

#### Landing Page / Dashboard
```bash
# Start dashboard server (default: port 1111)
./landing_page.sh

# Custom port
./landing_page.sh --port 8080

# Generate HTML only (no server)
./landing_page.sh --generate-only
```

### Interactive Manager Commands

| Command | Description |
|---------|-------------|
| `1,2,3` | Start apps by index |
| `1-5` | Start range of apps |
| `App Name` | Start app by name |
| `0` or `all` | Start all apps |
| `s 1` | Stop app #1 |
| `r` | Refresh app list |
| `q` | Quit |

## 📁 Configuration

### apps.json Format

```json
[
  {
    "Name": "My Streamlit App",
    "Type": "Streamlit",
    "Port": 8501,
    "AppPath": "/home/user/projects/my-app",
    "IndexPath": "app/main.py",
    "VenvPath": "/home/user/projects/my-app/.venv",
    "PackageManager": "uv",
    "BasePath": "myapp"
  },
  {
    "Name": "My Django App",
    "Type": "Django",
    "Port": 8000,
    "AppPath": "/home/user/projects/django-app"
  }
]
```

### Supported App Types

| Type | Description | Required Fields |
|------|-------------|-----------------|
| `Streamlit` | Streamlit apps | `IndexPath`, `Port` |
| `Django` | Django projects | `Port` (manage.py auto-detected) |
| `Dash` | Plotly Dash apps | `IndexPath`, `Port` |
| `Flask` | Flask apps | `IndexPath`, `Port` |

### Optional Fields

| Field | Description |
|-------|-------------|
| `VenvPath` | Path to virtual environment |
| `PackageManager` | `uv` or `pip` (auto-detected if not specified) |
| `BasePath` | URL base path for Streamlit |
| `CustomCommand` | Custom Django management command |

## 🔧 Project Structure

```
app_management_linux/
├── start.sh              # Main entry point (Zellij launcher)
├── manager.sh            # Interactive app manager
├── landing_page.sh       # Dashboard HTTP server
├── apps.json             # Your app configurations
├── apps_example.json     # Example configuration
├── app_index.html        # Generated dashboard (auto-created)
├── lib/
│   ├── app_helpers.sh    # App management utilities
│   ├── config.sh         # Configuration helpers
│   ├── dashboard.sh      # HTML generation
│   ├── terminal_helpers.sh # Terminal/Zellij utilities
│   └── url_helpers.sh    # URL detection utilities
└── layouts/
    └── default.kdl       # Zellij layout configuration
```

## 🖥️ Zellij Tips

### Key Bindings (Default)

| Keys | Action |
|------|--------|
| `Ctrl+p` | Enter pane mode |
| `Ctrl+t` | Enter tab mode |
| `Ctrl+n` | Enter resize mode |
| `Ctrl+s` | Enter scroll mode |
| `Ctrl+q` | Quit Zellij |

### Pane Mode (`Ctrl+p`)
- `n` - New pane
- `d` - Close pane
- `h/j/k/l` or arrows - Move between panes
- `f` - Toggle fullscreen

### Tab Mode (`Ctrl+t`)
- `n` - New tab
- `x` - Close tab
- `r` - Rename tab
- `1-9` - Go to tab

## 🔄 Migration from Windows

When migrating from the Windows version:

1. Convert Windows paths to Linux paths:
   - `C:\Users\username\code\` → `/home/username/code/`
   - Use forward slashes

2. Update `apps.json`:
   - Change all `AppPath` entries to Linux paths
   - Change all `VenvPath` entries (use `/bin/activate` not `Scripts\Activate.ps1`)
   - Change `IndexPath` if using backslashes

3. Virtual environments:
   - Recreate venvs on Linux or use `uv` for automatic management
   - Linux uses `source venv/bin/activate` instead of Windows `.\venv\Scripts\Activate.ps1`

## 🐛 Troubleshooting

### "Permission denied" on scripts
```bash
chmod +x *.sh lib/*.sh
```

### "jq: command not found"
```bash
sudo apt install jq  # or dnf/pacman equivalent
```

### Port already in use
The manager will detect this and offer to kill the existing process, or:
```bash
# Find process on port
lsof -i :8000
# Or
ss -tulnp | grep :8000

# Kill it
kill $(lsof -ti :8000)
```

### Apps not starting
1. Check that `AppPath` exists and is correct
2. Check that `IndexPath` file exists
3. Verify Python/uv is installed
4. Run with `--dry-run` to see the generated commands

### Zellij not found
```bash
# Install via cargo
cargo install zellij

# Or download binary
bash <(curl -L https://zellij.dev/launch)
```

## 📝 License

Same license as the parent project.
