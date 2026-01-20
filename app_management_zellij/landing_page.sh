#!/usr/bin/env bash
#
# landing_page.sh - Host an HTML dashboard for all app URLs
#
# Serves a dashboard page showing all app URLs on a configurable port.
# The page auto-generates from apps.json and can be refreshed.
#
# USAGE
#   ./landing_page.sh               # Default: port 1111, localhost
#   ./landing_page.sh -p 8080       # Custom port
#   ./landing_page.sh -H 0.0.0.0    # Bind to all interfaces
#
# REQUIREMENTS
#   - Bash 4.0+
#   - jq (JSON processor)
#   - Python 3 (for http.server) or netcat
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper libraries
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/url_helpers.sh"
source "$SCRIPT_DIR/lib/terminal_helpers.sh"
source "$SCRIPT_DIR/lib/dashboard.sh"

# Configuration
PORT=1111
HOST_ADDRESS="0.0.0.0"
HTML_FILE="$SCRIPT_DIR/app_index.html"

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Host an HTML dashboard for all app URLs.

OPTIONS:
    -p, --port PORT       Port to serve on (default: 1111)
    -H, --host ADDRESS    Host address to bind (default: 0.0.0.0)
    -g, --generate-only   Generate HTML file without serving
    -h, --help            Show this help message

EXAMPLES:
    $(basename "$0")                       # Serve on port 1111
    $(basename "$0") -p 8080               # Serve on port 8080
    $(basename "$0") -H localhost -p 9000  # Localhost only, port 9000
    $(basename "$0") --generate-only       # Just generate HTML file

EOF
    exit 0
}

GENERATE_ONLY=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -H|--host)
            HOST_ADDRESS="$2"
            shift 2
            ;;
        -g|--generate-only)
            GENERATE_ONLY=true
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
    if ! command -v jq &>/dev/null; then
        echo -e "${RED}Error: jq is required but not installed${NC}"
        echo "Install with: sudo apt install jq"
        exit 1
    fi
}

# Generate the dashboard HTML file
generate_html() {
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
    
    local apps_json=$(cat "$json_path")
    
    # Detect URL prefixes
    local network_url=$(get_network_url_prefix)
    local external_url=$(get_external_url_prefix)
    local generic_url=$(get_generic_url_prefix)
    
    echo -e "${CYAN}Generating dashboard HTML...${NC}"
    echo "  Network URL: $network_url"
    echo "  External URL: $external_url"
    
    generate_dashboard_html "$apps_json" "$network_url" "$external_url" "$generic_url" > "$HTML_FILE"
    
    echo -e "${GREEN}Generated: $HTML_FILE${NC}"
}

# Simple HTTP server using Python
serve_with_python() {
    echo -e "${GREEN}Starting Python HTTP server on http://${HOST_ADDRESS}:${PORT}${NC}"
    echo -e "${CYAN}Dashboard URL: http://localhost:${PORT}/app_index.html${NC}"
    echo ""
    echo "Press Ctrl+C to stop the server"
    echo ""
    
    cd "$SCRIPT_DIR"
    
    if command -v python3 &>/dev/null; then
        python3 -m http.server "$PORT" --bind "$HOST_ADDRESS"
    elif command -v python &>/dev/null; then
        python -m http.server "$PORT" --bind "$HOST_ADDRESS"
    else
        echo -e "${RED}Error: Python not found${NC}"
        exit 1
    fi
}

# Alternative: Simple HTTP server with auto-regeneration
serve_with_regeneration() {
    echo -e "${GREEN}Starting HTTP server with auto-regeneration${NC}"
    echo -e "${CYAN}Dashboard URL: http://localhost:${PORT}${NC}"
    echo ""
    echo "The dashboard will regenerate on each request."
    echo "Press Ctrl+C to stop the server"
    echo ""
    
    # Check for Python
    if ! command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
        echo -e "${RED}Error: Python is required${NC}"
        exit 1
    fi
    
    local python_cmd="python3"
    command -v python3 &>/dev/null || python_cmd="python"
    
    # Create a simple CGI-like server that regenerates HTML
    cd "$SCRIPT_DIR"
    
    # Use Python to create a custom handler
    $python_cmd << 'PYTHON_SERVER'
import http.server
import socketserver
import subprocess
import os
import sys

PORT = int(os.environ.get('PORT', 1111))
HOST = os.environ.get('HOST', '0.0.0.0')
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) or '.'

class RegeneratingHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        # Regenerate HTML on root or app_index.html request
        if self.path in ('/', '/app_index.html', '/index.html'):
            try:
                # Run the generate function
                result = subprocess.run(
                    ['bash', '-c', f'source {SCRIPT_DIR}/lib/config.sh && source {SCRIPT_DIR}/lib/url_helpers.sh && source {SCRIPT_DIR}/lib/dashboard.sh && apps_json=$(cat {SCRIPT_DIR}/apps.json 2>/dev/null || echo "[]") && generate_dashboard_html "$apps_json" "$(get_network_url_prefix)" "$(get_external_url_prefix)" "$(get_generic_url_prefix)"'],
                    capture_output=True,
                    text=True,
                    cwd=SCRIPT_DIR
                )
                
                if result.returncode == 0 and result.stdout:
                    self.send_response(200)
                    self.send_header('Content-type', 'text/html; charset=utf-8')
                    self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
                    self.end_headers()
                    self.wfile.write(result.stdout.encode('utf-8'))
                    return
            except Exception as e:
                print(f"Error regenerating: {e}", file=sys.stderr)
            
            # Fallback to static file
            self.path = '/app_index.html'
        
        return super().do_GET()

with socketserver.TCPServer((HOST, PORT), RegeneratingHandler) as httpd:
    print(f"Serving on http://{HOST}:{PORT}")
    print(f"Dashboard: http://localhost:{PORT}/")
    httpd.serve_forever()
PYTHON_SERVER
}

# Main execution
main() {
    print_header "Landing Page Server"
    
    check_dependencies
    
    # Generate HTML file
    generate_html
    
    if $GENERATE_ONLY; then
        echo -e "${GREEN}HTML file generated. Exiting.${NC}"
        exit 0
    fi
    
    # Check if port is available
    if is_port_in_use "$PORT"; then
        echo -e "${YELLOW}Warning: Port $PORT is already in use${NC}"
        if confirm_action "Kill existing process?"; then
            kill_port "$PORT"
            sleep 1
        else
            echo "Choose a different port with -p option"
            exit 1
        fi
    fi
    
    # Export for Python server
    export PORT
    export HOST="$HOST_ADDRESS"
    
    # Start server
    serve_with_python
}

main
