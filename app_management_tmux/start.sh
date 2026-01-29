#!/usr/bin/env bash
#
# start.sh - Quick start helper for app manager
#
# This script provides quick access to common operations.
# Default mode launches both the interactive manager and landing page server in tmux panes.
#
# USAGE
#   ./start.sh              # Start manager and landing page in tmux panes
#   ./start.sh all          # Start all apps
#   ./start.sh attach       # Attach to tmux session
#   ./start.sh stop         # Stop all apps
#   ./start.sh list         # List tmux windows
#   ./start.sh manager      # Start only the manager (interactive)
#   ./start.sh landing      # Start only the landing page server
#   ./start.sh help         # Show this help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

show_help() {
    echo "App Manager - Quick Start"
    echo ""
    echo "Usage: $(basename "$0") [command]"
    echo ""
    echo "Commands:"
    echo "  (none)    Start manager and landing page (default)"
    echo "  all       Start all apps immediately"
    echo "  attach    Attach to tmux session"
    echo "  stop      Stop all running apps"
    echo "  list      List tmux windows"
    echo "  manager   Start only the interactive manager"
    echo "  landing   Start only the landing page server"
    echo "  help      Show this help"
    echo ""
}

case "${1:-}" in
    all)
        echo -e "${CYAN}Starting all apps...${NC}"
        "$SCRIPT_DIR/manager.sh" --all
        ;;
    attach|a)
        echo -e "${CYAN}Attaching to tmux session...${NC}"
        "$SCRIPT_DIR/manager.sh" --attach
        ;;
    stop|s)
        echo -e "${CYAN}Stopping all apps...${NC}"
        source "$SCRIPT_DIR/lib/config.sh"
        source "$SCRIPT_DIR/lib/tmux_helpers.sh"
        tmux_kill_all_windows
        ;;
    list|l)
        source "$SCRIPT_DIR/lib/config.sh"
        source "$SCRIPT_DIR/lib/tmux_helpers.sh"
        tmux_list_windows
        ;;
    manager)
        echo -e "${CYAN}Starting interactive manager...${NC}"
        "$SCRIPT_DIR/manager.sh"
        ;;
    landing)
        echo -e "${CYAN}Starting landing page server on port 1111...${NC}"
        "$SCRIPT_DIR/landing_page.sh"
        ;;
    help|h|-h|--help)
        show_help
        ;;
    "")
        # Default: launch both manager and landing page in tmux panes
        echo -e "${CYAN}Launching App Manager with Landing Page...${NC}"
        
        # Source config to get URL detection
        source "$SCRIPT_DIR/lib/config.sh"
        source "$SCRIPT_DIR/lib/url_helpers.sh"
        
        # Detect network URLs
        NETWORK_URL=$(get_network_url_prefix)
        EXTERNAL_URL=$(get_external_url_prefix)
        
        echo -e "${BLUE}Network configuration:${NC}"
        echo -e "  ${CYAN}Network:${NC}  ${NETWORK_URL}:1111${NC}"
        echo -e "  ${CYAN}External:${NC} ${EXTERNAL_URL}:1111${NC}"
        echo ""
        
        # Check if tmux is available
        if ! command -v tmux &> /dev/null; then
            echo -e "${YELLOW}tmux is not installed. Running manager and landing page sequentially.${NC}"
            echo -e "${CYAN}To use panes, install tmux: sudo apt install tmux${NC}"
            
            # Run landing page in background, manager in foreground
            "$SCRIPT_DIR/landing_page.sh" &
            LANDING_PID=$!
            
            trap "kill $LANDING_PID 2>/dev/null || true" EXIT
            
            echo -e "${GREEN}Landing page server started in background (PID: $LANDING_PID)${NC}"
            echo -e "${GREEN}Starting interactive manager...${NC}"
            "$SCRIPT_DIR/manager.sh"
            
            kill $LANDING_PID 2>/dev/null || true
        else
            # Create a new tmux session with two panes
            SESSION_NAME="app-manager-$(date +%s)"
            PANE_HEIGHT="-h"
            
            # Create session with first pane for manager
            tmux new-session -d -s "$SESSION_NAME" -x 180 -y 50 "$SCRIPT_DIR/manager.sh"
            
            # Split pane vertically and run landing page in the right pane
            tmux split-window -h -t "$SESSION_NAME" "$SCRIPT_DIR/landing_page.sh"
            
            # Attach to the session
            tmux attach-session -t "$SESSION_NAME"
        fi
        ;;
    *)
        # Try to start app by name
        echo -e "${CYAN}Starting app: $1${NC}"
        "$SCRIPT_DIR/manager.sh" --app "$1"
        ;;
esac
