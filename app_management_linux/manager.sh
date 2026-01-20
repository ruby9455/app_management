#!/usr/bin/env bash
#
# manager.sh - Interactive app manager for Linux
#
# Launch and manage Streamlit, Django, Dash, and Flask apps from apps.json.
# Each app runs in a new Zellij pane/tab or terminal window.
#
# USAGE
#   ./manager.sh                    # Interactive menu
#   ./manager.sh --app "AppName"    # Start specific app
#   ./manager.sh --all              # Start all apps
#   ./manager.sh --dry-run          # Show what would be run
#
# REQUIREMENTS
#   - Bash 4.0+
#   - jq (JSON processor)
#   - Zellij, tmux, or graphical terminal
#   - Python apps: Python 3.8+, uv or pip
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper libraries
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/url_helpers.sh"
source "$SCRIPT_DIR/lib/app_helpers.sh"
source "$SCRIPT_DIR/lib/terminal_helpers.sh"

# Command line arguments
APP_NAME=""
DRY_RUN=false
AUTO_START=false
START_ALL=false

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Launch and manage Python web apps (Streamlit, Django, Dash, Flask).

OPTIONS:
    -a, --app NAME      Start a specific app by name
    -A, --all           Start all apps
    -d, --dry-run       Show what would be executed without running
    -h, --help          Show this help message

EXAMPLES:
    $(basename "$0")                    # Interactive menu
    $(basename "$0") --app "My App"     # Start specific app
    $(basename "$0") --all              # Start all apps
    $(basename "$0") --dry-run --all    # Preview what would run

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
        exit 0
    fi
    
    echo -e "${GREEN}Found $APP_COUNT supported apps${NC}"
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
        if [[ "$port" != "N/A" && "$port" != "null" ]] && is_port_in_use "$port"; then
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
    if [[ -n "$port" && "$port" != "null" ]] && is_port_in_use "$port"; then
        echo -e "${YELLOW}Warning: Port $port already in use for '$name'${NC}"
        if ! confirm_action "Kill existing process and restart?"; then
            echo "Skipping $name"
            return 0
        fi
        kill_port "$port"
    fi
    
    echo -e "${GREEN}Starting '$name'...${NC}"
    
    # Launch in appropriate terminal
    if is_in_zellij; then
        zellij_new_tab "$name" "$working_dir" "$run_cmd"
        echo -e "${GREEN}Launched '$name' in new Zellij tab${NC}"
    elif zellij_available; then
        # Not in Zellij but have it available - use new pane
        launch_in_terminal "$name" "$working_dir" "$run_cmd"
        echo -e "${GREEN}Launched '$name' in terminal${NC}"
    else
        launch_in_terminal "$name" "$working_dir" "$run_cmd"
        echo -e "${GREEN}Launched '$name' in terminal${NC}"
    fi
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

# Stop an app by port
stop_app() {
    local app_json="$1"
    local name=$(echo "$app_json" | jq -r '.Name')
    local port=$(echo "$app_json" | jq -r '.Port // empty')
    
    if [[ -z "$port" || "$port" == "null" ]]; then
        echo -e "${YELLOW}Cannot stop '$name': no port defined${NC}"
        return 1
    fi
    
    if $DRY_RUN; then
        echo -e "${YELLOW}[DRY RUN] Would stop '$name' on port $port${NC}"
        return 0
    fi
    
    if is_port_in_use "$port"; then
        echo -e "${CYAN}Stopping '$name' on port $port...${NC}"
        kill_port "$port"
        echo -e "${GREEN}Stopped '$name'${NC}"
    else
        echo -e "${YELLOW}'$name' is not running${NC}"
    fi
}

# Interactive menu
interactive_menu() {
    while true; do
        display_apps
        
        echo ""
        echo -e "${CYAN}Commands:${NC}"
        echo "  [number(s)] - Start app(s) by index (e.g., 1,2,3 or 1-3)"
        echo "  [name]      - Start app by name"
        echo "  0 or all    - Start all apps"
        echo "  s [num]     - Stop app by index"
        echo "  r           - Refresh list"
        echo "  q           - Quit"
        echo ""
        
        read -r -p "Enter selection: " input
        
        case "${input,,}" in
            q|quit|exit)
                echo "Goodbye!"
                exit 0
                ;;
            r|refresh)
                load_apps_json
                continue
                ;;
            s\ *)
                # Stop command
                local stop_target="${input#s }"
                if [[ "$stop_target" =~ ^[0-9]+$ ]]; then
                    local index=$((stop_target - 1))
                    local app_json=$(echo "$APPS_JSON" | jq ".[$index] // empty")
                    if [[ -n "$app_json" && "$app_json" != "null" ]]; then
                        stop_app "$app_json"
                    else
                        echo -e "${RED}Invalid index: $stop_target${NC}"
                    fi
                else
                    echo -e "${YELLOW}Usage: s <number>${NC}"
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
    print_header "App Manager for Linux"
    
    check_dependencies
    
    # Detect URL prefixes
    echo -e "${CYAN}Detecting network configuration...${NC}"
    NETWORK_URL=$(get_network_url_prefix)
    EXTERNAL_URL=$(get_external_url_prefix)
    GENERIC_URL=$(get_generic_url_prefix)
    
    echo "  Network URL: $NETWORK_URL"
    echo "  External URL: $EXTERNAL_URL"
    echo "  Generic URL: $GENERIC_URL"
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
