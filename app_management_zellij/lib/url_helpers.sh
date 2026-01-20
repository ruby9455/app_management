#!/usr/bin/env bash
#
# lib/url_helpers.sh - URL prefix detection utilities for Linux
#
# Source this file to use the functions:
#   source "$(dirname "${BASH_SOURCE[0]}")/url_helpers.sh"
#

# Get the primary local IPv4 address
# Usage: get_network_url_prefix
# Returns: URL like "http://192.168.1.10"
get_network_url_prefix() {
    local ip=""
    
    # Try to get IP from default route interface
    if command -v ip &>/dev/null; then
        local default_iface=$(ip route | grep default | awk '{print $5}' | head -1)
        if [[ -n "$default_iface" ]]; then
            ip=$(ip -4 addr show "$default_iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        fi
    fi
    
    # Fallback: get any non-loopback IPv4
    if [[ -z "$ip" ]]; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    
    # Fallback to loopback
    if [[ -z "$ip" ]]; then
        ip="127.0.0.1"
    fi
    
    echo "http://$ip"
}

# Get external/public IP address
# Usage: get_external_url_prefix [timeout_sec]
# Returns: URL like "http://203.1.252.70"
get_external_url_prefix() {
    local timeout="${1:-5}"
    local services=(
        "https://api.ipify.org?format=text"
        "https://ifconfig.me/ip"
        "https://icanhazip.com"
    )
    
    for service in "${services[@]}"; do
        local ip
        if command -v curl &>/dev/null; then
            ip=$(curl -s --connect-timeout "$timeout" "$service" 2>/dev/null)
        elif command -v wget &>/dev/null; then
            ip=$(wget -qO- --timeout="$timeout" "$service" 2>/dev/null)
        fi
        
        # Validate it looks like an IP
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "http://$ip"
            return 0
        fi
    done
    
    # Fallback to network URL
    get_network_url_prefix
}

# Get generic URL prefix (localhost)
# Usage: get_generic_url_prefix
get_generic_url_prefix() {
    echo "http://localhost"
}

# Build full URL for an app
# Usage: build_app_url "$base_url" "$port" "$base_path"
build_app_url() {
    local base_url="$1"
    local port="$2"
    local base_path="${3:-}"
    
    local url="${base_url}:${port}"
    
    if [[ -n "$base_path" ]]; then
        # Remove leading slash if present, then add it
        base_path="${base_path#/}"
        url="${url}/${base_path}"
    fi
    
    echo "$url"
}
