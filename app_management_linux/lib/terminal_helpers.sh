#!/usr/bin/env bash
#
# lib/terminal_helpers.sh - Terminal/Zellij helper functions
#
# Source this file to use the functions:
#   source "$(dirname "${BASH_SOURCE[0]}")/terminal_helpers.sh"
#

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if running inside Zellij
is_in_zellij() {
    [[ -n "${ZELLIJ:-}" ]] || [[ -n "${ZELLIJ_SESSION_NAME:-}" ]]
}

# Check if Zellij is available
zellij_available() {
    command -v zellij &>/dev/null
}

# Create a new Zellij pane and run a command
# Usage: zellij_new_pane "App Name" "/path/to/working/dir" "command to run"
zellij_new_pane() {
    local pane_name="$1"
    local working_dir="$2"
    local command="$3"
    
    if is_in_zellij; then
        # Create new pane in current session
        zellij action new-pane -- bash -c "cd '$working_dir' && $command; exec bash"
    elif zellij_available; then
        # Start new Zellij session with the command
        zellij run -c -n "$pane_name" -- bash -c "cd '$working_dir' && $command; exec bash"
    else
        echo -e "${RED}Error: Zellij not available${NC}" >&2
        return 1
    fi
}

# Create a new Zellij tab
# Usage: zellij_new_tab "Tab Name" "/path/to/working/dir" "command"
zellij_new_tab() {
    local tab_name="$1"
    local working_dir="$2"
    local command="$3"
    
    if is_in_zellij; then
        zellij action new-tab -n "$tab_name" -- bash -c "cd '$working_dir' && $command; exec bash"
    else
        echo -e "${YELLOW}Warning: Not in Zellij session, running in current terminal${NC}" >&2
        bash -c "cd '$working_dir' && $command"
    fi
}

# Launch app in a new terminal (fallback when not in Zellij)
# Usage: launch_in_terminal "App Name" "/path/to/working/dir" "command"
launch_in_terminal() {
    local app_name="$1"
    local working_dir="$2"
    local command="$3"
    
    # Try various terminal emulators
    if [[ -n "${DISPLAY:-}" ]]; then
        if command -v gnome-terminal &>/dev/null; then
            gnome-terminal --title="$app_name" --working-directory="$working_dir" -- bash -c "$command; exec bash"
        elif command -v konsole &>/dev/null; then
            konsole --workdir "$working_dir" -e bash -c "$command; exec bash" &
        elif command -v xterm &>/dev/null; then
            xterm -title "$app_name" -e "cd '$working_dir' && $command; exec bash" &
        elif command -v kitty &>/dev/null; then
            kitty -d "$working_dir" --title "$app_name" bash -c "$command; exec bash" &
        elif command -v alacritty &>/dev/null; then
            alacritty --working-directory "$working_dir" --title "$app_name" -e bash -c "$command; exec bash" &
        elif command -v wezterm &>/dev/null; then
            wezterm start --cwd "$working_dir" -- bash -c "$command; exec bash" &
        else
            echo -e "${YELLOW}No graphical terminal found, running in tmux${NC}"
            run_in_tmux "$app_name" "$working_dir" "$command"
        fi
    else
        # No display, use tmux
        run_in_tmux "$app_name" "$working_dir" "$command"
    fi
}

# Run in tmux as fallback
# Usage: run_in_tmux "session_name" "/path/to/working/dir" "command"
run_in_tmux() {
    local session_name="${1// /_}"  # Replace spaces with underscores
    local working_dir="$2"
    local command="$3"
    
    if command -v tmux &>/dev/null; then
        tmux new-session -d -s "$session_name" -c "$working_dir" "$command"
        echo -e "${GREEN}Started tmux session: $session_name${NC}"
    else
        echo -e "${RED}Error: No terminal multiplexer available (tmux or zellij)${NC}" >&2
        return 1
    fi
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
    
    printf "${BLUE}%3d${NC} │ %-30s │ %-10s │ %-6s │ %b%s%b\n" \
        "$index" "$name" "$type" "$port" "$status_color" "$status_icon" "$NC"
}

# Print table header
print_table_header() {
    echo -e "${PURPLE}────┬────────────────────────────────┬────────────┬────────┬────────${NC}"
    printf "${PURPLE} # │ %-30s │ %-10s │ %-6s │ Status${NC}\n" "Name" "Type" "Port"
    echo -e "${PURPLE}────┼────────────────────────────────┼────────────┼────────┼────────${NC}"
}

# Print table footer
print_table_footer() {
    echo -e "${PURPLE}────┴────────────────────────────────┴────────────┴────────┴────────${NC}"
}

# Prompt for user input
prompt_input() {
    local prompt_text="$1"
    local default_value="${2:-}"
    local result
    
    if [[ -n "$default_value" ]]; then
        read -r -p "$prompt_text [$default_value]: " result
        result="${result:-$default_value}"
    else
        read -r -p "$prompt_text: " result
    fi
    
    echo "$result"
}

# Confirm action
confirm_action() {
    local prompt_text="${1:-Are you sure?}"
    local response
    
    read -r -p "$prompt_text [y/N]: " response
    [[ "${response,,}" =~ ^(yes|y)$ ]]
}
