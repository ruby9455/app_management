#!/usr/bin/env bash
#
# lib/tmux_helpers.sh - tmux helper functions for app management
#
# This module provides full control over tmux sessions, windows, and panes.
# Unlike Zellij, tmux supports:
#   - Killing specific windows by name
#   - Sending keys (like Ctrl+C) to panes
#   - Listing all windows with their status
#   - Attaching/detaching sessions programmatically
#
# Source this file to use the functions:
#   source "$(dirname "${BASH_SOURCE[0]}")/tmux_helpers.sh"
#

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default session name (can be overridden)
TMUX_SESSION_NAME="${TMUX_SESSION_NAME:-app_manager}"

# Check if tmux is available
tmux_available() {
    command -v tmux &>/dev/null
}

# Check if running inside tmux
is_in_tmux() {
    [[ -n "${TMUX:-}" ]]
}

# Check if the app manager session exists
tmux_session_exists() {
    tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null
}

# Create the app manager session if it doesn't exist
# Creates a dummy window that will be closed when the first app starts
ensure_tmux_session() {
    if ! tmux_session_exists; then
        # Create session in detached mode with a placeholder window
        tmux new-session -d -s "$TMUX_SESSION_NAME" -n "_placeholder" "echo 'App Manager Session'; sleep 1"
        echo -e "${GREEN}Created tmux session: $TMUX_SESSION_NAME${NC}"
    fi
}

# Get sanitized window name (tmux doesn't like special chars)
sanitize_window_name() {
    local name="$1"
    # Replace spaces and special chars with underscores
    echo "$name" | tr ' /:.' '_' | tr -cd '[:alnum:]_-'
}

# Check if a window with the given name exists
# Usage: tmux_window_exists "window_name"
tmux_window_exists() {
    local window_name="$1"
    local sanitized=$(sanitize_window_name "$window_name")
    
    if ! tmux_session_exists; then
        return 1
    fi
    
    tmux list-windows -t "$TMUX_SESSION_NAME" -F '#{window_name}' 2>/dev/null | grep -qx "$sanitized"
}

# Create a new tmux window and run a command
# Usage: tmux_new_window "App Name" "/path/to/working/dir" "command to run"
tmux_new_window() {
    local app_name="$1"
    local working_dir="$2"
    local command="$3"
    local window_name=$(sanitize_window_name "$app_name")
    
    ensure_tmux_session
    
    # Check if window already exists
    if tmux_window_exists "$app_name"; then
        echo -e "${YELLOW}Window '$app_name' already exists. Use restart to replace it.${NC}"
        return 1
    fi
    
    # Create new window with the command
    # The command runs in a bash shell that stays open after completion
    tmux new-window -t "$TMUX_SESSION_NAME" -n "$window_name" -c "$working_dir" \
        "echo -e '${CYAN}Starting: $app_name${NC}'; echo 'Directory: $working_dir'; echo '---'; $command; echo ''; echo -e '${YELLOW}[App exited. Press Enter to close this window]${NC}'; read"
    
    # Remove placeholder window if it exists
    tmux kill-window -t "$TMUX_SESSION_NAME:_placeholder" 2>/dev/null || true
    
    return 0
}

# Send Ctrl+C to a tmux window to gracefully stop the app
# Usage: tmux_send_ctrl_c "App Name"
tmux_send_ctrl_c() {
    local app_name="$1"
    local window_name=$(sanitize_window_name "$app_name")
    
    if ! tmux_window_exists "$app_name"; then
        echo -e "${YELLOW}Window '$app_name' not found${NC}"
        return 1
    fi
    
    tmux send-keys -t "$TMUX_SESSION_NAME:$window_name" C-c
    return 0
}

# Kill a tmux window by name
# Usage: tmux_kill_window "App Name"
tmux_kill_window() {
    local app_name="$1"
    local window_name=$(sanitize_window_name "$app_name")
    
    if ! tmux_window_exists "$app_name"; then
        echo -e "${YELLOW}Window '$app_name' not found${NC}"
        return 1
    fi
    
    tmux kill-window -t "$TMUX_SESSION_NAME:$window_name"
    echo -e "${GREEN}Killed window: $app_name${NC}"
    return 0
}

# Stop an app gracefully (Ctrl+C) then kill the window
# Usage: tmux_stop_app "App Name" [keep_window]
tmux_stop_app() {
    local app_name="$1"
    local keep_window="${2:-false}"
    local window_name=$(sanitize_window_name "$app_name")
    
    if ! tmux_window_exists "$app_name"; then
        return 1
    fi
    
    # Send Ctrl+C to gracefully stop
    tmux_send_ctrl_c "$app_name"
    sleep 1
    
    # Kill the window unless we're keeping it for restart
    if [[ "$keep_window" != "true" ]]; then
        tmux_kill_window "$app_name"
    fi
    
    return 0
}

# Restart an app in the same window
# Usage: tmux_restart_app "App Name" "/path/to/working/dir" "command"
tmux_restart_app() {
    local app_name="$1"
    local working_dir="$2"
    local command="$3"
    local window_name=$(sanitize_window_name "$app_name")
    
    # Stop the app first
    if tmux_window_exists "$app_name"; then
        tmux_stop_app "$app_name" "true"
        sleep 1
        # Kill and recreate window
        tmux_kill_window "$app_name" 2>/dev/null
    fi
    
    # Start fresh
    tmux_new_window "$app_name" "$working_dir" "$command"
}

# List all windows in the app manager session
# Usage: tmux_list_windows
tmux_list_windows() {
    if ! tmux_session_exists; then
        echo -e "${YELLOW}No tmux session found${NC}"
        return 1
    fi
    
    echo -e "${CYAN}tmux windows in session '$TMUX_SESSION_NAME':${NC}"
    tmux list-windows -t "$TMUX_SESSION_NAME" -F '  #{window_index}: #{window_name} (#{window_panes} pane(s))' 2>/dev/null
}

# Get list of running window names
# Usage: get_running_window_names
get_running_window_names() {
    if ! tmux_session_exists; then
        return
    fi
    
    tmux list-windows -t "$TMUX_SESSION_NAME" -F '#{window_name}' 2>/dev/null | grep -v "^_placeholder$"
}

# Kill all windows in the session
# Usage: tmux_kill_all_windows
tmux_kill_all_windows() {
    if ! tmux_session_exists; then
        echo -e "${YELLOW}No tmux session found${NC}"
        return 1
    fi
    
    # Get all window names
    local windows=$(tmux list-windows -t "$TMUX_SESSION_NAME" -F '#{window_name}' 2>/dev/null)
    
    for window in $windows; do
        if [[ "$window" != "_placeholder" ]]; then
            tmux send-keys -t "$TMUX_SESSION_NAME:$window" C-c 2>/dev/null
        fi
    done
    
    sleep 1
    
    # Kill the entire session
    tmux kill-session -t "$TMUX_SESSION_NAME" 2>/dev/null
    echo -e "${GREEN}Killed all windows and session${NC}"
}

# Attach to the tmux session
# Usage: tmux_attach
tmux_attach() {
    if ! tmux_session_exists; then
        echo -e "${YELLOW}No tmux session found. Start some apps first.${NC}"
        return 1
    fi
    
    if is_in_tmux; then
        # Already in tmux, switch to session
        tmux switch-client -t "$TMUX_SESSION_NAME"
    else
        tmux attach-session -t "$TMUX_SESSION_NAME"
    fi
}

# Select/focus a specific window
# Usage: tmux_select_window "App Name"
tmux_select_window() {
    local app_name="$1"
    local window_name=$(sanitize_window_name "$app_name")
    
    if ! tmux_window_exists "$app_name"; then
        echo -e "${YELLOW}Window '$app_name' not found${NC}"
        return 1
    fi
    
    tmux select-window -t "$TMUX_SESSION_NAME:$window_name"
}

# Print a colored header
print_header() {
    local text="$1"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $text${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Print app info in a formatted way
print_app_info() {
    local index="$1"
    local name="$2"
    local type="$3"
    local port="$4"
    local status="$5"
    
    local status_color="$RED"
    local status_icon="○"
    if [[ "$status" == "running" ]]; then
        status_color="$GREEN"
        status_icon="●"
    fi
    
    printf "${BLUE}%3d${NC} │ %-30s │ %-10s │ %-6s │ %b%s %s%b\n" \
        "$index" "$name" "$type" "$port" "$status_color" "$status_icon" "$status" "$NC"
}

# Print table header
print_table_header() {
    echo -e "${PURPLE}────┬────────────────────────────────┬────────────┬────────┬──────────${NC}"
    printf "${PURPLE} # │ %-30s │ %-10s │ %-6s │ Status${NC}\n" "Name" "Type" "Port"
    echo -e "${PURPLE}────┼────────────────────────────────┼────────────┼────────┼──────────${NC}"
}

# Print table footer
print_table_footer() {
    echo -e "${PURPLE}────┴────────────────────────────────┴────────────┴────────┴──────────${NC}"
}

# Prompt for user input with color
prompt_input() {
    local prompt="$1"
    local response
    echo -ne "${CYAN}$prompt${NC}"
    read -r response
    echo "$response"
}
