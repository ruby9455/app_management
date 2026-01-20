#!/usr/bin/env bash
#
# start.sh - Launch Zellij with two panes running the app management scripts
#
# USAGE
#   ./start.sh              # Default side-by-side (vertical split)
#   ./start.sh --horizontal # Stacked horizontal split
#
# REQUIREMENTS
#   - Zellij must be installed (https://zellij.dev/)
#   - Bash 4.0+
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
SPLIT_DIRECTION="vertical"  # Default: side-by-side (like Windows Terminal -V)
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--horizontal)
            SPLIT_DIRECTION="horizontal"
            shift
            ;;
        -v|--vertical)
            SPLIT_DIRECTION="vertical"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--horizontal|-h] [--vertical|-v]"
            exit 1
            ;;
    esac
done

# Find script paths
find_script() {
    local name="$1"
    local candidates=(
        "$SCRIPT_DIR/$name"
        "$(dirname "$SCRIPT_DIR")/$name"
        "$(dirname "$(dirname "$SCRIPT_DIR")")/$name"
        "$(pwd)/$name"
    )
    
    for candidate in "${candidates[@]}"; do
        if [[ -f "$candidate" ]]; then
            echo "$(realpath "$candidate")"
            return 0
        fi
    done
    return 1
}

MANAGER_SCRIPT=$(find_script "manager.sh") || {
    echo "Error: Cannot find 'manager.sh'. Checked script directory, parent folders, and current directory."
    exit 1
}

LANDING_PAGE_SCRIPT=$(find_script "landing_page.sh") || {
    echo "Error: Cannot find 'landing_page.sh'. Checked script directory, parent folders, and current directory."
    exit 1
}

echo "Resolved script paths:"
echo "  manager.sh: $MANAGER_SCRIPT"
echo "  landing_page.sh: $LANDING_PAGE_SCRIPT"

# Check for Zellij
if ! command -v zellij &>/dev/null; then
    echo "Error: Zellij is not installed or not in PATH."
    echo "Install with: cargo install zellij"
    echo "Or see: https://zellij.dev/documentation/installation"
    exit 1
fi

echo "Zellij found at: $(command -v zellij)"

# Create a temporary Zellij layout file
LAYOUT_FILE=$(mktemp --suffix=.kdl)
trap "rm -f '$LAYOUT_FILE'" EXIT

if [[ "$SPLIT_DIRECTION" == "horizontal" ]]; then
    # Horizontal split (stacked - one on top of the other)
    cat > "$LAYOUT_FILE" << EOF
layout {
    pane split_direction="horizontal" {
        pane {
            command "bash"
            args "-c" "$MANAGER_SCRIPT"
            name "App Manager"
        }
        pane {
            command "bash"
            args "-c" "$LANDING_PAGE_SCRIPT"
            name "Landing Page"
        }
    }
}
EOF
else
    # Vertical split (side by side - default)
    cat > "$LAYOUT_FILE" << EOF
layout {
    pane split_direction="vertical" {
        pane {
            command "bash"
            args "-c" "$MANAGER_SCRIPT"
            name "App Manager"
        }
        pane {
            command "bash"
            args "-c" "$LANDING_PAGE_SCRIPT"
            name "Landing Page"
        }
    }
}
EOF
fi

echo "Split orientation: $SPLIT_DIRECTION"
echo "Launching Zellij..."

# Launch Zellij with the layout
# Use --layout to specify our custom layout
zellij --layout "$LAYOUT_FILE"
