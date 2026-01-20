#!/usr/bin/env bash
#
# start.sh - Quick start helper for app manager
#
# This script provides quick access to common operations.
#
# USAGE
#   ./start.sh              # Start interactive manager
#   ./start.sh all          # Start all apps
#   ./start.sh attach       # Attach to tmux session
#   ./start.sh stop         # Stop all apps
#   ./start.sh list         # List tmux windows
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

show_help() {
    echo "App Manager - Quick Start"
    echo ""
    echo "Usage: $(basename "$0") [command]"
    echo ""
    echo "Commands:"
    echo "  (none)    Start interactive manager"
    echo "  all       Start all apps"
    echo "  attach    Attach to tmux session"
    echo "  stop      Stop all running apps"
    echo "  list      List tmux windows"
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
    help|h|-h|--help)
        show_help
        ;;
    "")
        "$SCRIPT_DIR/manager.sh"
        ;;
    *)
        # Try to start app by name
        echo -e "${CYAN}Starting app: $1${NC}"
        "$SCRIPT_DIR/manager.sh" --app "$1"
        ;;
esac
