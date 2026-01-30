#!/usr/bin/env bash
#
# landing_page.sh - Host an HTML dashboard for all app URLs on port 1111
#
# USAGE
#   ./landing_page.sh              # Start server on default port 1111
#   ./landing_page.sh 8080         # Start server on custom port
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${1:-1111}"

# Colors
RED='\033[0;31m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Track Python PID for cleanup
PYTHON_PID=""
CLEANUP_DONE=false

# Cleanup function to kill Python server
cleanup() {
    # Prevent running cleanup twice
    if [[ "$CLEANUP_DONE" == "true" ]]; then
        return
    fi
    CLEANUP_DONE=true
    
    echo ""
    echo -e "${YELLOW}Shutting down server...${NC}"
    
    # Kill the Python process if we have its PID
    if [[ -n "$PYTHON_PID" ]]; then
        kill "$PYTHON_PID" 2>/dev/null || true
        wait "$PYTHON_PID" 2>/dev/null || true
    fi
    
    # Also kill any Python servers on our port range
    pkill -f "python3.*http.server" 2>/dev/null || true
    
    # Kill any remaining Python processes listening on landing page ports
    for p in {1111..1120}; do
        fuser -k ${p}/tcp 2>/dev/null || true
    done
    
    echo -e "${GREEN}Server stopped${NC}"
}

# Trap signals for cleanup (not EXIT to avoid double cleanup)
trap cleanup SIGTERM SIGINT

# Source helper libraries
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/url_helpers.sh"
source "$SCRIPT_DIR/lib/dashboard.sh"

# Path to HTML file
HTML_FILE="$SCRIPT_DIR/app_index.html"

# Function to generate HTML
generate_html() {
    # Load apps.json
    local apps_json_file=$(get_apps_json_path "$SCRIPT_DIR")
    
    if [[ ! -f "$apps_json_file" ]]; then
        echo "<html><body><p>apps.json not found at $apps_json_file</p></body></html>"
        return
    fi

    local apps_json=$(cat "$apps_json_file")
    
    # Detect URL prefixes
    local network_url=$(get_network_url_prefix)
    local external_url=$(get_external_url_prefix)
    local generic_url=$(get_generic_url_prefix)
    
    # Generate HTML using dashboard module
    generate_dashboard_html "$apps_json" "$network_url" "$external_url" "$generic_url"
}

# Check if HTML file exists, if not generate it
if [[ -f "$HTML_FILE" ]]; then
    echo -e "${BLUE}Dashboard found at: $HTML_FILE${NC}"
else
    echo -e "${BLUE}Generating dashboard HTML...${NC}"
    generate_html > "$HTML_FILE"
    echo -e "${GREEN}Dashboard generated and saved to: $HTML_FILE${NC}"
fi

# Detect network URLs
NETWORK_URL=$(get_network_url_prefix)
EXTERNAL_URL=$(get_external_url_prefix)
GENERIC_URL=$(get_generic_url_prefix)

echo -e "${BLUE}Detecting network configuration...${NC}"
echo -e "  ${CYAN}Network URL:${NC}  ${NETWORK_URL}${NC}"
echo -e "  ${CYAN}External URL:${NC} ${EXTERNAL_URL}${NC}"
echo -e "  ${CYAN}Generic URL:${NC}  ${GENERIC_URL}${NC}"
echo ""

# Try to use Python's built-in HTTP server if available (more reliable)
if command -v python3 &> /dev/null; then
    echo -e "${GREEN}Starting HTTP server on port $PORT${NC}"
    echo ""
    echo -e "Access the dashboard at:"
    echo -e "  ${GREEN}Network:${NC}   ${NETWORK_URL}:${PORT}${NC}"
    echo -e "  ${GREEN}External:${NC}  ${EXTERNAL_URL}:${PORT}${NC}"
    echo -e "  ${GREEN}Local:${NC}     http://localhost:${PORT}${NC}"
    echo ""
    
    # Pass variables to Python using environment
    export SCRIPT_DIR
    export PORT
    
    # Start Python server in background and capture its PID
    python3 << 'PYTHON_EOF' &
import http.server
import socketserver
import os
import sys
import subprocess
import json

SCRIPT_DIR = os.environ['SCRIPT_DIR']
PORT_NUM = int(os.environ['PORT'])

class DashboardHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path in ('/', '/index.html'):
            try:
                # Call bash to generate HTML using subprocess
                bash_cmd = f"""
set -euo pipefail
SCRIPT_DIR='{SCRIPT_DIR}' 
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/url_helpers.sh"
source "$SCRIPT_DIR/lib/dashboard.sh"

apps_json_file=$(get_apps_json_path "$SCRIPT_DIR")
if [[ ! -f "$apps_json_file" ]]; then
    echo "<html><body><p>apps.json not found</p></body></html>"
    exit 0
fi

apps_json=$(cat "$apps_json_file")
network_url=$(get_network_url_prefix)
external_url=$(get_external_url_prefix)
generic_url=$(get_generic_url_prefix)

generate_dashboard_html "$apps_json" "$network_url" "$external_url" "$generic_url"
"""
                
                result = subprocess.run(
                    ['bash', '-c', bash_cmd],
                    capture_output=True,
                    text=True,
                    timeout=10,
                    cwd=SCRIPT_DIR
                )
                
                html_content = result.stdout.strip()
                
                if not html_content:
                    html_content = f"<html><body><p>Error generating HTML</p><pre>{result.stderr}</pre></body></html>"
                
                self.send_response(200)
                self.send_header('Content-type', 'text/html; charset=utf-8')
                self.send_header('Content-Length', str(len(html_content)))
                self.end_headers()
                self.wfile.write(html_content.encode())
            except Exception as e:
                error_msg = f'Error: {str(e)}'
                self.send_response(500)
                self.send_header('Content-type', 'text/plain')
                self.send_header('Content-Length', str(len(error_msg)))
                self.end_headers()
                self.wfile.write(error_msg.encode())
        else:
            self.send_response(404)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'404 - Not Found')
    
    def log_message(self, format, *args):
        pass

HOST = '0.0.0.0'

try:
    with socketserver.TCPServer((HOST, PORT_NUM), DashboardHandler) as httpd:
        httpd.serve_forever()
except OSError as e:
    if 'Address already in use' in str(e):
        print(f"Port {PORT_NUM} is busy, trying next port...", file=sys.stderr)
        for p in range(PORT_NUM+1, PORT_NUM+20):
            try:
                with socketserver.TCPServer((HOST, p), DashboardHandler) as httpd:
                    print(f"Server started on port {p}", file=sys.stderr)
                    httpd.serve_forever()
                break
            except OSError:
                continue
    else:
        raise
PYTHON_EOF
    
    # Capture the PID of the background Python process
    PYTHON_PID=$!
    
    echo -e "${CYAN}Server running (PID: $PYTHON_PID)${NC}"
    
    # Check if we have an interactive TTY
    if [[ -t 0 ]]; then
        # Interactive mode - wait for Enter to stop
        echo -e "${CYAN}Press Enter to stop the server${NC}"
        read -r
        cleanup
    else
        # Non-interactive mode (e.g., SSH command) - run as daemon
        echo -e "${CYAN}Running in background mode (no TTY detected)${NC}"
        echo -e "${CYAN}To stop the server, run:${NC} ${YELLOW}kill $PYTHON_PID${NC}"
        echo -e "${CYAN}Or run:${NC} ${YELLOW}fuser -k ${PORT}/tcp${NC}"
        
        # Disown the process so it continues after script exits
        disown $PYTHON_PID
        
        # Clear the trap so we don't kill the server on exit
        trap - SIGTERM SIGINT
        PYTHON_PID=""
    fi
else
    # Fallback to bash/nc approach
    echo -e "${YELLOW}Python3 not found, using netcat for HTTP server${NC}"
    
    # Check if nc is available
    if ! command -v nc &> /dev/null; then
        echo -e "${RED}Error: netcat is required but not installed.${NC}"
        echo "Install with: sudo apt install netcat-traditional"
        exit 1
    fi
    
    echo -e "${GREEN}Starting HTTP server on port $PORT (netcat)${NC}"
    echo ""
    echo -e "Access the dashboard at:"
    echo -e "  ${GREEN}Network:${NC}   ${NETWORK_URL}:${PORT}${NC}"
    echo -e "  ${GREEN}External:${NC}  ${EXTERNAL_URL}:${PORT}${NC}"
    echo -e "  ${GREEN}Local:${NC}     http://localhost:${PORT}${NC}"
    echo ""
    
    # Find a free port
    while nc -z localhost $PORT 2>/dev/null; do
        echo -e "${YELLOW}Port $PORT is busy, trying $((PORT+1))...${NC}"
        PORT=$((PORT + 1))
    done
    
    # Simple HTTP server using bash and nc  
    while true; do
        {
            read -r request
            read -r headers
            
            # Generate fresh HTML on each request
            local html_content=$(generate_html)
            
            # Save it to file
            echo "$html_content" > "$HTML_FILE"
            
            # Send HTTP response
            echo -ne "HTTP/1.1 200 OK\r\n"
            echo -ne "Content-Type: text/html; charset=utf-8\r\n"
            echo -ne "Content-Length: $(echo -n "$html_content" | wc -c)\r\n"
            echo -ne "Connection: close\r\n"
            echo -ne "\r\n"
            echo -n "$html_content"
            
        } | nc -l -p $PORT -q 1 2>/dev/null || true
    done
fi
