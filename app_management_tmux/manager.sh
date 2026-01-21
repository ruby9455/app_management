#!/usr/bin/env bash
#
# manager.sh - Interactive app manager for Linux using tmux
#
# Launch and manage Streamlit, Django, Dash, and Flask apps from apps.json.
# Each app runs in a named tmux window that can be stopped/restarted.
#
# USAGE
#   ./manager.sh                    # Interactive menu
#   ./manager.sh --app "AppName"    # Start specific app
#   ./manager.sh --all              # Start all apps
#   ./manager.sh --dry-run          # Show what would be run
#   ./manager.sh --attach           # Attach to tmux session
#
# REQUIREMENTS
#   - Bash 4.0+
#   - tmux 2.0+
#   - jq (JSON processor)
#   - Python apps: Python 3.8+, uv or pip
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper libraries
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/url_helpers.sh"
source "$SCRIPT_DIR/lib/app_helpers.sh"
source "$SCRIPT_DIR/lib/tmux_helpers.sh"
source "$SCRIPT_DIR/lib/json_helpers.sh"

# Command line arguments
APP_NAME=""
DRY_RUN=false
AUTO_START=false
START_ALL=false
ATTACH_MODE=false

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Launch and manage Python web apps (Streamlit, Django, Dash, Flask) using tmux.

OPTIONS:
    -a, --app NAME      Start a specific app by name
    -A, --all           Start all apps
    -d, --dry-run       Show what would be executed without running
    -t, --attach        Attach to the tmux session
    -h, --help          Show this help message

EXAMPLES:
    $(basename "$0")                    # Interactive menu
    $(basename "$0") --app "My App"     # Start specific app
    $(basename "$0") --all              # Start all apps
    $(basename "$0") --dry-run --all    # Preview what would run
    $(basename "$0") --attach           # Attach to tmux session

INTERACTIVE COMMANDS:
    [number(s)]   Start app(s) by index (e.g., 1,2,3)
    s [num]       Stop app by index
    S             Stop all running apps
    r [num]       Restart app by index
    a             Add a new app
    e [num]       Edit app
    d [num]       Delete app
    l             List tmux windows
    t             Attach to tmux session
    q             Quit

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--app)
            APP_NAME="$2"
            AUTO_START=true
            shift 2
            ;;
        -A|--all)
            START_ALL=true
            AUTO_START=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -t|--attach)
            ATTACH_MODE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Check dependencies
check_dependencies() {
    local missing=()
    
    if ! command -v jq &>/dev/null; then
        missing+=("jq")
    fi
    
    if ! command -v tmux &>/dev/null; then
        missing+=("tmux")
    fi
    
    if ! command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
        missing+=("python3")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}Error: Missing required dependencies: ${missing[*]}${NC}"
        echo ""
        echo "Install with:"
        echo "  Ubuntu/Debian: sudo apt install ${missing[*]}"
        echo "  Fedora/RHEL:   sudo dnf install ${missing[*]}"
        echo "  Arch:          sudo pacman -S ${missing[*]}"
        echo "  macOS:         brew install ${missing[*]}"
        exit 1
    fi
}

# Load apps from JSON
load_apps_json() {
    local json_path
    json_path=$(get_apps_json_path "$SCRIPT_DIR" 2>/dev/null) || {
        # apps.json not found - try to create from example
        local example_path="$SCRIPT_DIR/apps_example.json"
        local target_path="$SCRIPT_DIR/apps.json"
        
        if [[ -f "$example_path" ]]; then
            echo -e "${YELLOW}apps.json not found. Creating from apps_example.json...${NC}"
            cp "$example_path" "$target_path"
            echo -e "${GREEN}Created: $target_path${NC}"
            echo -e "${CYAN}Please edit apps.json with your actual app configurations.${NC}"
            echo ""
            json_path="$target_path"
        else
            echo -e "${RED}Error: Could not find apps.json or apps_example.json${NC}"
            echo "Please create apps.json in: $SCRIPT_DIR"
            exit 1
        fi
    }
    
    echo -e "${CYAN}Loading apps from: $json_path${NC}"
    
    APPS_JSON=$(cat "$json_path")
    APPS_JSON=$(echo "$APPS_JSON" | filter_supported_apps | unique_apps_by_name)
    APP_COUNT=$(echo "$APPS_JSON" | jq 'length')
    
    if [[ "$APP_COUNT" -eq 0 ]]; then
        echo -e "${YELLOW}No supported apps found in apps.json${NC}"
    fi
    
    echo -e "${GREEN}Found $APP_COUNT supported apps${NC}"
}

# Check if an app is running (by port or tmux window)
is_app_running() {
    local app_json="$1"
    local name=$(echo "$app_json" | jq -r '.Name')
    local port=$(echo "$app_json" | jq -r '.Port // empty')
    
    # Check tmux window first
    if tmux_window_exists "$name"; then
        return 0
    fi
    
    # Check port
    if [[ -n "$port" && "$port" != "null" ]] && is_port_in_use "$port"; then
        return 0
    fi
    
    return 1
}

# Display apps table
display_apps() {
    print_header "Available Apps"
    print_table_header
    
    local index=1
    echo "$APPS_JSON" | jq -c '.[]' | while IFS= read -r app; do
        local name=$(echo "$app" | jq -r '.Name // "Unknown"')
        local app_type=$(echo "$app" | jq -r '.Type // "Unknown"')
        local port=$(echo "$app" | jq -r '.Port // "N/A"')
        
        local status="stopped"
        
        # Check if running by tmux window or port
        if tmux_window_exists "$name"; then
            status="running"
        elif [[ "$port" != "N/A" && "$port" != "null" ]] && is_port_in_use "$port"; then
            status="running"
        fi
        
        print_app_info "$index" "$name" "$app_type" "$port" "$status"
        ((index++))
    done
    
    print_table_footer
}

# Start a single app
start_app() {
    local app_json="$1"
    
    local name=$(echo "$app_json" | jq -r '.Name')
    local app_path=$(echo "$app_json" | jq -r '.AppPath')
    local app_type=$(echo "$app_json" | jq -r '.Type')
    local port=$(echo "$app_json" | jq -r '.Port // empty')
    local index_path=$(echo "$app_json" | jq -r '.IndexPath // empty')
    
    # Validate app
    if [[ -z "$name" ]]; then
        echo -e "${RED}Error: App missing Name${NC}"
        return 1
    fi
    
    if [[ -z "$app_path" || ! -d "$app_path" ]]; then
        echo -e "${RED}Error: AppPath not found: $app_path${NC}"
        return 1
    fi
    
    # Check if index file exists for web apps
    local is_web_type=false
    [[ "$app_type" == "Streamlit" || "$app_type" == "Flask" || "$app_type" == "Dash" ]] && is_web_type=true
    
    if $is_web_type && [[ -n "$index_path" ]]; then
        local full_index_path
        if [[ "$index_path" == /* ]]; then
            full_index_path="$index_path"
        else
            full_index_path="$app_path/$index_path"
        fi
        
        if [[ ! -f "$full_index_path" ]]; then
            echo -e "${RED}Error: IndexPath not found: $full_index_path${NC}"
            return 1
        fi
    fi
    
    # Resolve working directory
    local working_dir=$(realpath "$app_path")
    
    # Build run command
    local run_cmd
    run_cmd=$(build_app_run_command "$app_json" "$working_dir") || {
        echo -e "${RED}Error: Could not build run command for $name${NC}"
        return 1
    }
    
    if $DRY_RUN; then
        echo -e "${YELLOW}[DRY RUN] Would start '$name' in '$working_dir'${NC}"
        echo -e "${CYAN}  Command: $run_cmd${NC}"
        return 0
    fi
    
    # Check if already running
    if tmux_window_exists "$name"; then
        echo -e "${YELLOW}Warning: '$name' already has a tmux window${NC}"
        if ! confirm_action "Kill existing window and restart?"; then
            echo "Skipping $name"
            return 0
        fi
        tmux_kill_window "$name"
        sleep 1
    elif [[ -n "$port" && "$port" != "null" ]] && is_port_in_use "$port"; then
        echo -e "${YELLOW}Warning: Port $port already in use${NC}"
        if ! confirm_action "Kill process on port $port and start?"; then
            echo "Skipping $name"
            return 0
        fi
        kill_port "$port"
        wait_for_port_free "$port" 5
    fi
    
    echo -e "${GREEN}Starting '$name' in tmux...${NC}"
    
    # Launch in tmux window
    tmux_new_window "$name" "$working_dir" "$run_cmd"
    echo -e "${GREEN}Launched '$name' in tmux window${NC}"
}

# Stop a single app
stop_app() {
    local app_json="$1"
    local name=$(echo "$app_json" | jq -r '.Name')
    local port=$(echo "$app_json" | jq -r '.Port // empty')
    
    if $DRY_RUN; then
        echo -e "${YELLOW}[DRY RUN] Would stop '$name'${NC}"
        return 0
    fi
    
    local stopped=false
    
    # Stop tmux window first (sends Ctrl+C and kills window)
    if tmux_window_exists "$name"; then
        echo -e "${CYAN}Stopping '$name' tmux window...${NC}"
        tmux_stop_app "$name"
        stopped=true
    fi
    
    # Also kill any process on the port
    if [[ -n "$port" && "$port" != "null" ]] && is_port_in_use "$port"; then
        echo -e "${CYAN}Killing process on port $port...${NC}"
        kill_port "$port"
        stopped=true
    fi
    
    if $stopped; then
        echo -e "${GREEN}Stopped '$name'${NC}"
    else
        echo -e "${YELLOW}'$name' was not running${NC}"
    fi
}

# Restart a single app
restart_app() {
    local app_json="$1"
    local name=$(echo "$app_json" | jq -r '.Name')
    local app_path=$(echo "$app_json" | jq -r '.AppPath')
    
    if $DRY_RUN; then
        echo -e "${YELLOW}[DRY RUN] Would restart '$name'${NC}"
        return 0
    fi
    
    echo -e "${CYAN}Restarting '$name'...${NC}"
    
    # Stop it first
    stop_app "$app_json"
    
    # Wait for port to be free
    local port=$(echo "$app_json" | jq -r '.Port // empty')
    if [[ -n "$port" && "$port" != "null" ]]; then
        wait_for_port_free "$port" 5
    fi
    
    # Start it again
    start_app "$app_json"
}

# Update a single app (git pull + sync venv + restart)
update_app() {
    local app_json="$1"
    local name=$(echo "$app_json" | jq -r '.Name')
    local app_path=$(echo "$app_json" | jq -r '.AppPath')
    local package_manager=$(echo "$app_json" | jq -r '.PackageManager // empty')
    
    if $DRY_RUN; then
        echo -e "${YELLOW}[DRY RUN] Would update '$name'${NC}"
        return 0
    fi
    
    echo -e "${CYAN}===== Updating '$name' =====${NC}"
    
    # Stop the app first
    stop_app "$app_json"
    
    # Wait for port to be free
    local port=$(echo "$app_json" | jq -r '.Port // empty')
    if [[ -n "$port" && "$port" != "null" ]]; then
        wait_for_port_free "$port" 5
    fi
    
    # Git pull
    if [[ -d "$app_path/.git" ]]; then
        echo -e "${CYAN}Pulling latest changes from git...${NC}"
        pushd "$app_path" > /dev/null
        if git pull; then
            echo -e "${GREEN}Git pull successful${NC}"
        else
            echo -e "${YELLOW}Git pull failed or no changes${NC}"
        fi
        popd > /dev/null
    else
        echo -e "${YELLOW}No git repository found in '$app_path'${NC}"
    fi
    
    # Update virtual environment
    if [[ -z "$package_manager" || "$package_manager" == "null" ]]; then
        package_manager=$(detect_package_manager "$app_path")
    fi
    
    echo -e "${CYAN}Updating dependencies with $package_manager...${NC}"
    pushd "$app_path" > /dev/null
    
    if [[ "$package_manager" == "uv" ]]; then
        if uv sync; then
            echo -e "${GREEN}Dependencies updated with uv sync${NC}"
        else
            echo -e "${YELLOW}Failed to update dependencies${NC}"
        fi
    else
        # pip - look for requirements.txt
        local requirements_file=""
        if [[ -f "requirements.txt" ]]; then
            requirements_file="requirements.txt"
        elif [[ -f "requirements/base.txt" ]]; then
            requirements_file="requirements/base.txt"
        fi
        
        if [[ -n "$requirements_file" ]]; then
            local venv_path=$(echo "$app_json" | jq -r '.VenvPath // empty')
            local pip_cmd="pip"
            
            if [[ -n "$venv_path" && "$venv_path" != "null" && -f "$venv_path/bin/pip" ]]; then
                pip_cmd="$venv_path/bin/pip"
            elif [[ -f ".venv/bin/pip" ]]; then
                pip_cmd=".venv/bin/pip"
            elif [[ -f "venv/bin/pip" ]]; then
                pip_cmd="venv/bin/pip"
            fi
            
            if $pip_cmd install -r "$requirements_file"; then
                echo -e "${GREEN}Dependencies updated with pip${NC}"
            else
                echo -e "${YELLOW}Failed to update dependencies${NC}"
            fi
        else
            echo -e "${YELLOW}No requirements file found${NC}"
        fi
    fi
    popd > /dev/null
    
    # Restart the app
    echo -e "${CYAN}Starting '$name'...${NC}"
    start_app "$app_json"
    
    echo -e "${GREEN}Update complete for '$name'${NC}"
}

# Start apps by selection
start_selected_apps() {
    local selection="$1"
    
    # Handle "all" or "0"
    if [[ "$selection" == "0" || "${selection,,}" == "all" ]]; then
        echo "$APPS_JSON" | jq -c '.[]' | while IFS= read -r app; do
            start_app "$app"
            sleep 0.5  # Small delay between launches
        done
        return
    fi
    
    # Parse comma-separated values
    IFS=',' read -ra items <<< "$selection"
    
    for item in "${items[@]}"; do
        item=$(echo "$item" | xargs)  # Trim whitespace
        [[ -z "$item" ]] && continue
        
        local app_json=""
        
        if [[ "$item" =~ ^[0-9]+$ ]]; then
            # Numeric index (1-based)
            local index=$((item - 1))
            app_json=$(echo "$APPS_JSON" | jq ".[$index] // empty")
        else
            # Name match (case-insensitive)
            app_json=$(echo "$APPS_JSON" | jq --arg name "$item" \
                '[.[] | select(.Name | ascii_downcase == ($name | ascii_downcase))][0] // empty')
        fi
        
        if [[ -n "$app_json" && "$app_json" != "null" ]]; then
            start_app "$app_json"
            sleep 0.5
        else
            echo -e "${YELLOW}Warning: Could not find app: $item${NC}"
        fi
    done
}

# Stop all running apps
stop_all_apps() {
    if $DRY_RUN; then
        echo -e "${YELLOW}[DRY RUN] Would stop all apps${NC}"
        return 0
    fi
    
    echo -e "${CYAN}Stopping all apps...${NC}"
    
    # Stop each app
    echo "$APPS_JSON" | jq -c '.[]' | while IFS= read -r app; do
        local name=$(echo "$app" | jq -r '.Name')
        if tmux_window_exists "$name" || is_app_running "$app"; then
            stop_app "$app"
        fi
    done
    
    echo -e "${GREEN}All apps stopped${NC}"
}

# Add a new app interactively
add_new_app() {
    local json_file="$SCRIPT_DIR/apps.json"
    
    print_header "Add New App"
    
    # Get app path
    read -r -p "Enter app path (absolute path): " app_path
    if [[ -z "$app_path" || "$app_path" == "back" ]]; then
        echo "Cancelled."
        return
    fi
    
    # Expand ~ if used
    app_path="${app_path/#\~/$HOME}"
    
    if [[ ! -d "$app_path" ]]; then
        echo -e "${RED}Error: Directory does not exist: $app_path${NC}"
        return 1
    fi
    
    app_path=$(realpath "$app_path")
    
    # Get app name (default to directory name)
    local default_name=$(basename "$app_path")
    read -r -p "Enter app name [$default_name]: " app_name
    app_name="${app_name:-$default_name}"
    
    # Check for duplicate
    if app_name_exists "$json_file" "$app_name"; then
        echo -e "${RED}Error: An app named '$app_name' already exists${NC}"
        return 1
    fi
    
    # Detect app type
    local detected_type=$(detect_app_type "$app_path")
    echo -e "${CYAN}Detected type: $detected_type${NC}"
    
    local app_type
    if [[ "$detected_type" == "Unknown" ]]; then
        echo "Select app type:"
        echo "  1) Streamlit"
        echo "  2) Django"
        echo "  3) Flask"
        echo "  4) Dash"
        read -r -p "Enter choice [1-4]: " type_choice
        case "$type_choice" in
            1) app_type="Streamlit" ;;
            2) app_type="Django" ;;
            3) app_type="Flask" ;;
            4) app_type="Dash" ;;
            *) app_type="Streamlit" ;;
        esac
    else
        read -r -p "Use detected type '$detected_type'? [Y/n]: " use_detected
        if [[ -z "$use_detected" || "${use_detected,,}" =~ ^(y|yes)$ ]]; then
            app_type="$detected_type"
        else
            echo "Select app type:"
            echo "  1) Streamlit"
            echo "  2) Django"
            echo "  3) Flask"
            echo "  4) Dash"
            read -r -p "Enter choice [1-4]: " type_choice
            case "$type_choice" in
                1) app_type="Streamlit" ;;
                2) app_type="Django" ;;
                3) app_type="Flask" ;;
                4) app_type="Dash" ;;
                *) app_type="$detected_type" ;;
            esac
        fi
    fi
    
    # Get package manager
    local pkg_manager=$(detect_package_manager "$app_path")
    echo -e "${CYAN}Detected package manager: $pkg_manager${NC}"
    
    # Find venv
    local venv_path=$(find_venv "$app_path" 2>/dev/null || echo "")
    if [[ -n "$venv_path" ]]; then
        echo -e "${CYAN}Found venv: $venv_path${NC}"
    fi
    
    # Get index path for web apps
    local index_path=""
    if [[ "$app_type" == "Streamlit" || "$app_type" == "Flask" || "$app_type" == "Dash" ]]; then
        echo -e "${CYAN}Select the main/index Python file:${NC}"
        index_path=$(select_index_file "$app_path")
        if [[ -z "$index_path" ]]; then
            read -r -p "Enter index file path (relative to app): " index_path
        fi
    fi
    
    # Get port
    local port=$(get_port_number)
    
    # Build and save the app
    local new_app=$(build_app_json "$app_name" "$app_type" "$port" "$app_path" "$index_path" "$venv_path" "$pkg_manager")
    
    echo ""
    echo -e "${CYAN}New app configuration:${NC}"
    echo "$new_app" | jq .
    echo ""
    
    read -r -p "Save this app? [Y/n]: " confirm
    if [[ -z "$confirm" || "${confirm,,}" =~ ^(y|yes)$ ]]; then
        add_app_to_json "$json_file" "$new_app"
        echo -e "${GREEN}App '$app_name' added successfully!${NC}"
    else
        echo "Cancelled."
    fi
}

# Add a new process (custom command) interactively
add_new_process() {
    local json_file="$SCRIPT_DIR/apps.json"
    
    print_header "Add New Process (Custom Command)"
    
    echo "Examples:"
    echo "  - Django mgmt cmd: continuous_cache_update"
    echo "  - Python module: python -m app.db.backup.local_cache_scheduler"
    echo "  - Any script: python scripts/my_task.py"
    echo ""
    
    # Get working directory path
    read -r -p "Enter working directory path (absolute path): " app_path
    if [[ -z "$app_path" || "$app_path" == "back" ]]; then
        echo "Cancelled."
        return
    fi
    
    # Expand ~ if used
    app_path="${app_path/#\~/$HOME}"
    
    if [[ ! -d "$app_path" ]]; then
        echo -e "${RED}Error: Directory does not exist: $app_path${NC}"
        return 1
    fi
    
    app_path=$(realpath "$app_path")
    
    # Get process name
    local default_name=$(basename "$app_path")
    read -r -p "Enter process name [$default_name]: " app_name
    app_name="${app_name:-$default_name}"
    
    # Check for duplicate
    if app_name_exists "$json_file" "$app_name"; then
        echo -e "${RED}Error: A process/app named '$app_name' already exists${NC}"
        return 1
    fi
    
    # Get custom command
    read -r -p "Enter command to run: " custom_command
    if [[ -z "$custom_command" ]]; then
        echo -e "${RED}Error: Command is required${NC}"
        return 1
    fi
    
    # Get package manager
    local pkg_manager=$(detect_package_manager "$app_path")
    echo -e "${CYAN}Detected package manager: $pkg_manager${NC}"
    
    # Find venv (optional for custom commands)
    local venv_path=$(find_venv "$app_path" 2>/dev/null || echo "")
    if [[ -n "$venv_path" ]]; then
        echo -e "${CYAN}Found venv: $venv_path${NC}"
    fi
    
    # Build process JSON
    local new_app=$(build_process_json "$app_name" "$app_path" "$custom_command" "$venv_path" "$pkg_manager")
    
    echo ""
    echo -e "${CYAN}New process configuration:${NC}"
    echo "$new_app" | jq .
    echo ""
    
    read -r -p "Save this process? [Y/n]: " confirm
    if [[ -z "$confirm" || "${confirm,,}" =~ ^(y|yes)$ ]]; then
        add_app_to_json "$json_file" "$new_app"
        echo -e "${GREEN}Process '$app_name' added successfully!${NC}"
    else
        echo "Cancelled."
    fi
}

# Edit an existing app
edit_app() {
    local target="$1"
    local json_file="$SCRIPT_DIR/apps.json"
    
    if [[ ! "$target" =~ ^[0-9]+$ ]]; then
        echo -e "${YELLOW}Usage: e <number>${NC}"
        return
    fi
    
    local index=$((target - 1))
    local app_json=$(echo "$APPS_JSON" | jq ".[$index] // empty")
    
    if [[ -z "$app_json" || "$app_json" == "null" ]]; then
        echo -e "${RED}Invalid index: $target${NC}"
        return
    fi
    
    local app_name=$(echo "$app_json" | jq -r '.Name')
    print_header "Edit App: $app_name"
    
    echo "Current configuration:"
    echo "$app_json" | jq .
    echo ""
    
    # Edit each field
    local current_name=$(echo "$app_json" | jq -r '.Name')
    read -r -p "Name [$current_name]: " new_name
    new_name="${new_name:-$current_name}"
    
    local current_type=$(echo "$app_json" | jq -r '.Type')
    read -r -p "Type [$current_type]: " new_type
    new_type="${new_type:-$current_type}"
    
    local current_port=$(echo "$app_json" | jq -r '.Port')
    read -r -p "Port [$current_port]: " new_port
    new_port="${new_port:-$current_port}"
    
    local current_app_path=$(echo "$app_json" | jq -r '.AppPath')
    read -r -p "AppPath [$current_app_path]: " new_app_path
    new_app_path="${new_app_path:-$current_app_path}"
    
    local current_index=$(echo "$app_json" | jq -r '.IndexPath // ""')
    local new_index=""
    if [[ "$new_type" == "Streamlit" || "$new_type" == "Flask" || "$new_type" == "Dash" ]]; then
        read -r -p "IndexPath [$current_index]: " new_index
        new_index="${new_index:-$current_index}"
    fi
    
    local current_venv=$(echo "$app_json" | jq -r '.VenvPath // ""')
    read -r -p "VenvPath [$current_venv]: " new_venv
    new_venv="${new_venv:-$current_venv}"
    
    local current_pm=$(echo "$app_json" | jq -r '.PackageManager // ""')
    read -r -p "PackageManager [$current_pm]: " new_pm
    new_pm="${new_pm:-$current_pm}"
    
    # Build updated app
    local updated_app=$(build_app_json "$new_name" "$new_type" "$new_port" "$new_app_path" "$new_index" "$new_venv" "$new_pm")
    
    echo ""
    echo -e "${CYAN}Updated configuration:${NC}"
    echo "$updated_app" | jq .
    echo ""
    
    read -r -p "Save changes? [Y/n]: " confirm
    if [[ -z "$confirm" || "${confirm,,}" =~ ^(y|yes)$ ]]; then
        update_app_in_json "$json_file" "$current_name" "$updated_app"
        echo -e "${GREEN}App '$new_name' updated successfully!${NC}"
    else
        echo "Cancelled."
    fi
}

# Delete an app
delete_app() {
    local target="$1"
    local json_file="$SCRIPT_DIR/apps.json"
    
    if [[ ! "$target" =~ ^[0-9]+$ ]]; then
        echo -e "${YELLOW}Usage: d <number>${NC}"
        return
    fi
    
    local index=$((target - 1))
    local app_json=$(echo "$APPS_JSON" | jq ".[$index] // empty")
    
    if [[ -z "$app_json" || "$app_json" == "null" ]]; then
        echo -e "${RED}Invalid index: $target${NC}"
        return
    fi
    
    local app_name=$(echo "$app_json" | jq -r '.Name')
    
    echo -e "${YELLOW}About to delete app: $app_name${NC}"
    echo "$app_json" | jq .
    echo ""
    
    read -r -p "Are you sure you want to delete this app? [y/N]: " confirm
    if [[ "${confirm,,}" =~ ^(y|yes)$ ]]; then
        # Stop the app if running
        if tmux_window_exists "$app_name"; then
            tmux_stop_app "$app_name"
        fi
        
        remove_app_from_json "$json_file" "$app_name"
        echo -e "${GREEN}App '$app_name' deleted successfully!${NC}"
    else
        echo "Cancelled."
    fi
}

# Interactive menu
interactive_menu() {
    while true; do
        load_apps_json
        display_apps
        
        echo ""
        echo -e "${CYAN}Commands:${NC}"
        echo "  [number(s)] - Start app(s) by index (e.g., 1,2,3)"
        echo "  [name]      - Start app by name"
        echo "  0 or all    - Start all apps"
        echo "  s [num]     - Stop app by index"
        echo "  S           - Stop all running apps"
        echo "  r [num]     - Restart app by index"
        echo "  u [num]     - Update app from repo (0 for all)"
        echo "  a           - Add a new app"
        echo "  p           - Add a new process (custom command)"
        echo "  e [num]     - Edit app by index"
        echo "  d [num]     - Delete app by index"
        echo "  l           - List tmux windows"
        echo "  t           - Attach to tmux session"
        echo "  R           - Refresh list"
        echo "  q           - Quit"
        echo ""
        
        read -r -p "Enter selection: " input
        
        case "${input,,}" in
            q|quit|exit)
                echo "Goodbye!"
                exit 0
                ;;
            r|R|refresh)
                if [[ "$input" == "R" ]]; then
                    continue
                fi
                # r with number means restart
                if [[ "$input" =~ ^r\ +([0-9]+)$ ]]; then
                    local restart_target="${BASH_REMATCH[1]}"
                    local idx=$((restart_target - 1))
                    local app_json=$(echo "$APPS_JSON" | jq ".[$idx] // empty")
                    if [[ -n "$app_json" && "$app_json" != "null" ]]; then
                        restart_app "$app_json"
                    else
                        echo -e "${RED}Invalid index: $restart_target${NC}"
                    fi
                else
                    continue
                fi
                ;;
            a|add)
                add_new_app
                ;;
            p|process)
                add_new_process
                ;;
            l|list)
                tmux_list_windows || true
                ;;
            t|attach)
                echo -e "${CYAN}Attaching to tmux session... (Ctrl+B, D to detach)${NC}"
                sleep 1
                tmux_attach || echo -e "${YELLOW}No tmux session to attach to${NC}"
                ;;
            s)
                # Just 's' alone - show usage
                echo -e "${YELLOW}Usage: s <number> to stop an app${NC}"
                ;;
            "S")
                # Capital S - stop all
                stop_all_apps || true
                ;;
            e\ *|e[0-9]*)
                # Edit command
                local edit_target="${input#e }"
                edit_target="${edit_target#e}"
                edit_app "$edit_target"
                ;;
            d\ *|d[0-9]*)
                # Delete command
                local delete_target="${input#d }"
                delete_target="${delete_target#d}"
                delete_app "$delete_target"
                ;;
            s\ *|s[0-9]*)
                # Stop command
                local stop_target="${input#s }"
                stop_target="${stop_target#s}"
                if [[ "$stop_target" =~ ^[0-9]+$ ]]; then
                    local idx=$((stop_target - 1))
                    local app_json=$(echo "$APPS_JSON" | jq ".[$idx] // empty")
                    if [[ -n "$app_json" && "$app_json" != "null" ]]; then
                        stop_app "$app_json" || true
                    else
                        echo -e "${RED}Invalid index: $stop_target${NC}"
                    fi
                else
                    echo -e "${YELLOW}Usage: s <number>${NC}"
                fi
                ;;
            r\ *|r[0-9]*)
                # Restart command
                local restart_target="${input#r }"
                restart_target="${restart_target#r}"
                if [[ "$restart_target" =~ ^[0-9]+$ ]]; then
                    local idx=$((restart_target - 1))
                    local app_json=$(echo "$APPS_JSON" | jq ".[$idx] // empty")
                    if [[ -n "$app_json" && "$app_json" != "null" ]]; then
                        restart_app "$app_json" || true
                    else
                        echo -e "${RED}Invalid index: $restart_target${NC}"
                    fi
                else
                    echo -e "${YELLOW}Usage: r <number>${NC}"
                fi
                ;;
            u\ *|u[0-9]*|u0)
                # Update command (git pull + sync venv + restart)
                local update_target="${input#u }"
                update_target="${update_target#u}"
                if [[ "$update_target" == "0" ]]; then
                    # Update all apps
                    echo -e "${CYAN}Updating all apps...${NC}"
                    echo "$APPS_JSON" | jq -c '.[]' | while IFS= read -r app; do
                        update_app "$app" || true
                    done
                elif [[ "$update_target" =~ ^[0-9]+$ ]]; then
                    local idx=$((update_target - 1))
                    local app_json=$(echo "$APPS_JSON" | jq ".[$idx] // empty")
                    if [[ -n "$app_json" && "$app_json" != "null" ]]; then
                        update_app "$app_json" || true
                    else
                        echo -e "${RED}Invalid index: $update_target${NC}"
                    fi
                else
                    echo -e "${YELLOW}Usage: u <number> or u 0 for all${NC}"
                fi
                ;;
            *)
                if [[ -n "$input" ]]; then
                    start_selected_apps "$input"
                fi
                ;;
        esac
        
        echo ""
        echo "Press Enter to continue..."
        read -r
    done
}

# Main execution
main() {
    # Handle attach mode first
    if $ATTACH_MODE; then
        tmux_attach
        exit 0
    fi
    
    print_header "App Manager for Linux (tmux)"
    
    check_dependencies
    
    # Detect URL prefixes
    echo -e "${CYAN}Detecting network configuration...${NC}"
    NETWORK_URL=$(get_network_url_prefix)
    EXTERNAL_URL=$(get_external_url_prefix)
    GENERIC_URL=$(get_generic_url_prefix)
    
    echo "  Network URL:  $NETWORK_URL"
    echo "  External URL: $EXTERNAL_URL"
    echo "  Generic URL:  $GENERIC_URL"
    echo ""
    
    load_apps_json
    
    if $AUTO_START; then
        if $START_ALL; then
            echo -e "${CYAN}Starting all apps...${NC}"
            start_selected_apps "all"
        elif [[ -n "$APP_NAME" ]]; then
            echo -e "${CYAN}Starting app: $APP_NAME${NC}"
            start_selected_apps "$APP_NAME"
        fi
    else
        interactive_menu
    fi
}

main
