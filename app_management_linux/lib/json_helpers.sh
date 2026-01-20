#!/usr/bin/env bash
#
# lib/json_helpers.sh - JSON manipulation helpers for apps.json
#
# Source this file to use the functions:
#   source "$(dirname "${BASH_SOURCE[0]}")/json_helpers.sh"
#

# Get apps.json file path (global for the session)
APPS_JSON_FILE=""

# Initialize the apps JSON file path
# Usage: init_apps_json_file "/path/to/script/dir"
init_apps_json_file() {
    local script_dir="$1"
    APPS_JSON_FILE="$script_dir/apps.json"
}

# Add a new app to apps.json
# Usage: add_app_to_json "$json_file" "$app_json"
add_app_to_json() {
    local json_file="$1"
    local app_json="$2"
    
    if [[ ! -f "$json_file" ]]; then
        echo "[$app_json]" > "$json_file"
    else
        # Add to existing array
        local existing=$(cat "$json_file")
        echo "$existing" | jq ". + [$app_json]" > "$json_file"
    fi
}

# Update an app in apps.json by name
# Usage: update_app_in_json "$json_file" "$app_name" "$new_app_json"
update_app_in_json() {
    local json_file="$1"
    local app_name="$2"
    local new_app_json="$3"
    
    local existing=$(cat "$json_file")
    echo "$existing" | jq --arg name "$app_name" --argjson newapp "$new_app_json" \
        'map(if (.Name | ascii_downcase) == ($name | ascii_downcase) then $newapp else . end)' > "$json_file"
}

# Remove an app from apps.json by name
# Usage: remove_app_from_json "$json_file" "$app_name"
remove_app_from_json() {
    local json_file="$1"
    local app_name="$2"
    
    local existing=$(cat "$json_file")
    echo "$existing" | jq --arg name "$app_name" \
        'map(select((.Name | ascii_downcase) != ($name | ascii_downcase)))' > "$json_file"
}

# Check if an app name already exists
# Usage: app_name_exists "$json_file" "$app_name"
app_name_exists() {
    local json_file="$1"
    local app_name="$2"
    
    if [[ ! -f "$json_file" ]]; then
        return 1
    fi
    
    local count=$(cat "$json_file" | jq --arg name "$app_name" \
        '[.[] | select((.Name | ascii_downcase) == ($name | ascii_downcase))] | length')
    
    [[ "$count" -gt 0 ]]
}

# Detect app type from project directory
# Usage: detect_app_type "/path/to/project"
detect_app_type() {
    local project_dir="$1"
    
    # Check pyproject.toml first
    if [[ -f "$project_dir/pyproject.toml" ]]; then
        local content=$(cat "$project_dir/pyproject.toml")
        if echo "$content" | grep -qi "streamlit"; then echo "Streamlit"; return; fi
        if echo "$content" | grep -qi "django"; then echo "Django"; return; fi
        if echo "$content" | grep -qi "flask"; then echo "Flask"; return; fi
        if echo "$content" | grep -qi "dash"; then echo "Dash"; return; fi
    fi
    
    # Check requirements.txt
    local req_file=$(find "$project_dir" -maxdepth 2 -name "requirements.txt" -type f 2>/dev/null | head -1)
    if [[ -n "$req_file" ]]; then
        local content=$(cat "$req_file")
        if echo "$content" | grep -qi "streamlit"; then echo "Streamlit"; return; fi
        if echo "$content" | grep -qi "django"; then echo "Django"; return; fi
        if echo "$content" | grep -qi "flask"; then echo "Flask"; return; fi
        if echo "$content" | grep -qi "dash"; then echo "Dash"; return; fi
    fi
    
    echo "Unknown"
}

# Find all Python files in a project (excluding venv)
# Usage: find_python_files "/path/to/project"
find_python_files() {
    local project_dir="$1"
    
    # Exclude common venv directories
    find "$project_dir" -name "*.py" -type f \
        ! -path "*/venv/*" \
        ! -path "*/.venv/*" \
        ! -path "*/env/*" \
        ! -path "*/.env/*" \
        ! -path "*/__pycache__/*" \
        ! -path "*/site-packages/*" \
        2>/dev/null | sort
}

# Interactive: Select index/main Python file
# Usage: select_index_file "/path/to/project"
select_index_file() {
    local project_dir="$1"
    
    local files=($(find_python_files "$project_dir"))
    
    if [[ ${#files[@]} -eq 0 ]]; then
        echo ""
        return 1
    fi
    
    echo -e "${CYAN}Found Python files:${NC}" >&2
    local i=1
    for file in "${files[@]}"; do
        local rel_path=$(realpath --relative-to="$project_dir" "$file" 2>/dev/null || echo "$file")
        echo "  $i) $rel_path" >&2
        ((i++))
    done
    
    local selection
    read -r -p "Select index file (number or path): " selection
    
    if [[ "$selection" =~ ^[0-9]+$ ]]; then
        local idx=$((selection - 1))
        if [[ $idx -ge 0 && $idx -lt ${#files[@]} ]]; then
            realpath --relative-to="$project_dir" "${files[$idx]}" 2>/dev/null || echo "${files[$idx]}"
            return 0
        fi
    fi
    
    # Treat as path
    echo "$selection"
}

# Generate a random available port
# Usage: get_random_port
get_random_port() {
    local port
    local max_attempts=50
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        port=$((RANDOM % 6000 + 3000))  # Range: 3000-8999
        
        if ! is_port_in_use "$port" 2>/dev/null; then
            echo "$port"
            return 0
        fi
        ((attempt++))
    done
    
    # Fallback
    echo $((RANDOM % 6000 + 3000))
}

# Interactive: Get port number
# Usage: get_port_number
get_port_number() {
    local response
    read -r -p "Assign a random port? [Y/n]: " response
    
    if [[ -z "$response" || "${response,,}" =~ ^(y|yes)$ ]]; then
        local port=$(get_random_port)
        echo -e "${GREEN}Assigned port: $port${NC}" >&2
        echo "$port"
    else
        local port
        read -r -p "Enter port number: " port
        
        if [[ ! "$port" =~ ^[0-9]+$ ]]; then
            echo -e "${YELLOW}Invalid port, generating random...${NC}" >&2
            port=$(get_random_port)
            echo -e "${GREEN}Assigned port: $port${NC}" >&2
        fi
        
        echo "$port"
    fi
}

# Build app JSON object from parameters
# Usage: build_app_json "name" "type" "port" "app_path" "index_path" "venv_path" "pkg_manager"
build_app_json() {
    local name="$1"
    local app_type="$2"
    local port="$3"
    local app_path="$4"
    local index_path="${5:-}"
    local venv_path="${6:-}"
    local pkg_manager="${7:-}"
    
    local json=$(jq -n \
        --arg name "$name" \
        --arg type "$app_type" \
        --argjson port "$port" \
        --arg appPath "$app_path" \
        '{Name: $name, Type: $type, Port: $port, AppPath: $appPath}')
    
    # Add optional fields if present
    if [[ -n "$index_path" ]]; then
        json=$(echo "$json" | jq --arg val "$index_path" '. + {IndexPath: $val}')
    fi
    
    if [[ -n "$venv_path" ]]; then
        json=$(echo "$json" | jq --arg val "$venv_path" '. + {VenvPath: $val}')
    fi
    
    if [[ -n "$pkg_manager" ]]; then
        json=$(echo "$json" | jq --arg val "$pkg_manager" '. + {PackageManager: $val}')
    fi
    
    echo "$json"
}
