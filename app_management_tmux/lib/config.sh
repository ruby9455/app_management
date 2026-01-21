#!/usr/bin/env bash
#
# lib/config.sh - Configuration helpers for app management
#
# Source this file to use the functions:
#   source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
#

# Default configuration
DEFAULT_APPS_FILE="apps.json"
DEFAULT_NETWORK_URL_FALLBACK="http://10.17.62.232"
DEFAULT_EXTERNAL_URL_FALLBACK="http://203.1.252.70"
EXTERNAL_IP_TIMEOUT_SEC=5

# tmux session name for all apps
TMUX_SESSION_NAME="app_manager"

# Get the apps.json file path
# Usage: get_apps_json_path "/path/to/script/dir"
get_apps_json_path() {
    local script_dir="${1:-.}"
    local candidates=(
        "$script_dir/apps.json"
        "$script_dir/../apps.json"
        "$(pwd)/apps.json"
    )
    
    for candidate in "${candidates[@]}"; do
        if [[ -f "$candidate" ]]; then
            echo "$(realpath "$candidate")"
            return 0
        fi
    done
    
    echo "Error: apps.json not found" >&2
    return 1
}

# Get example apps.json file path
get_example_apps_json_path() {
    local script_dir="${1:-.}"
    local candidates=(
        "$script_dir/apps_example.json"
        "$script_dir/../apps_example.json"
        "$(pwd)/apps_example.json"
    )
    
    for candidate in "${candidates[@]}"; do
        if [[ -f "$candidate" ]]; then
            echo "$(realpath "$candidate")"
            return 0
        fi
    done
    
    return 1
}

# Load apps from JSON file
# Usage: load_apps "/path/to/apps.json"
# Returns JSON array
load_apps() {
    local json_file="$1"
    
    if [[ ! -f "$json_file" ]]; then
        echo "Error: Apps file not found: $json_file" >&2
        return 1
    fi
    
    if ! command -v jq &>/dev/null; then
        echo "Error: jq is required but not installed" >&2
        return 1
    fi
    
    cat "$json_file"
}

# Filter apps by supported types (or apps with CustomCommand)
# Usage: echo "$apps_json" | filter_supported_apps
filter_supported_apps() {
    jq '[.[] | select(.Type == "Streamlit" or .Type == "Django" or .Type == "Dash" or .Type == "Flask" or (.CustomCommand != null and .CustomCommand != ""))]'
}

# Get unique apps by name
# Usage: echo "$apps_json" | unique_apps_by_name
unique_apps_by_name() {
    jq 'unique_by(.Name | ascii_downcase)'
}

# Get app field value
# Usage: get_app_field "$app_json" "Name"
get_app_field() {
    local app_json="$1"
    local field="$2"
    echo "$app_json" | jq -r ".$field // empty"
}

# Check if app has a valid port
# Usage: has_valid_port "$app_json"
has_valid_port() {
    local app_json="$1"
    local port=$(get_app_field "$app_json" "Port")
    [[ -n "$port" && "$port" =~ ^[0-9]+$ && "$port" -gt 0 ]]
}

# Confirm action prompt
# Usage: confirm_action "Are you sure?"
confirm_action() {
    local message="${1:-Are you sure?}"
    local response
    read -r -p "$message [y/N]: " response
    [[ "${response,,}" =~ ^(y|yes)$ ]]
}
