#!/usr/bin/env bash
#
# lib/app_helpers.sh - App management helper functions
#
# Source this file to use the functions:
#   source "$(dirname "${BASH_SOURCE[0]}")/app_helpers.sh"
#

# Check if a virtual environment exists
# Usage: venv_exists "/path/to/venv"
venv_exists() {
    local venv_path="$1"
    [[ -f "$venv_path/bin/activate" ]]
}

# Find virtual environment in a directory
# Usage: find_venv "/path/to/project"
find_venv() {
    local project_dir="$1"
    local venv_dirs=(".venv" "venv" "env" ".env")
    
    for venv_name in "${venv_dirs[@]}"; do
        local venv_path="$project_dir/$venv_name"
        if venv_exists "$venv_path"; then
            echo "$venv_path"
            return 0
        fi
    done
    
    # Search for any directory with bin/activate
    local found=$(find "$project_dir" -maxdepth 3 -type f -name "activate" -path "*/bin/activate" 2>/dev/null | head -1)
    if [[ -n "$found" ]]; then
        echo "$(dirname "$(dirname "$found")")"
        return 0
    fi
    
    return 1
}

# Detect package manager (uv or pip)
# Usage: detect_package_manager "/path/to/project"
detect_package_manager() {
    local project_dir="$1"
    
    # Check for pyproject.toml (usually indicates uv or poetry)
    if [[ -f "$project_dir/pyproject.toml" ]]; then
        # Check if uv is available
        if command -v uv &>/dev/null; then
            echo "uv"
            return 0
        fi
    fi
    
    echo "pip"
}

# Find manage.py for Django projects
# Usage: find_manage_py "/path/to/project"
find_manage_py() {
    local project_dir="$1"
    
    # Check direct path first
    if [[ -f "$project_dir/manage.py" ]]; then
        echo "manage.py"
        return 0
    fi
    
    # Search recursively
    local found=$(find "$project_dir" -maxdepth 3 -name "manage.py" -type f 2>/dev/null | head -1)
    if [[ -n "$found" ]]; then
        # Return relative path
        realpath --relative-to="$project_dir" "$found"
        return 0
    fi
    
    return 1
}

# Get requirements.txt path
# Usage: find_requirements "/path/to/project"
find_requirements() {
    local project_dir="$1"
    
    # Check root first
    if [[ -f "$project_dir/requirements.txt" ]]; then
        echo "$project_dir/requirements.txt"
        return 0
    fi
    
    # Search recursively
    find "$project_dir" -maxdepth 2 -name "requirements.txt" -type f 2>/dev/null | head -1
}

# Build the activation command prefix for venv
# Usage: get_venv_activate_prefix "/path/to/venv"
get_venv_activate_prefix() {
    local venv_path="$1"
    
    if [[ -n "$venv_path" && -f "$venv_path/bin/activate" ]]; then
        echo "source '$venv_path/bin/activate' && "
    fi
}

# Build the run command for an app
# Usage: build_app_run_command "$app_json" "$working_dir"
build_app_run_command() {
    local app_json="$1"
    local working_dir="$2"
    
    # Parse app fields
    local app_type=$(echo "$app_json" | jq -r '.Type // empty')
    local port=$(echo "$app_json" | jq -r '.Port // empty')
    local index_path=$(echo "$app_json" | jq -r '.IndexPath // empty')
    local base_path=$(echo "$app_json" | jq -r '.BasePath // empty')
    local venv_path=$(echo "$app_json" | jq -r '.VenvPath // empty')
    local pkg_manager=$(echo "$app_json" | jq -r '.PackageManager // empty')
    local custom_command=$(echo "$app_json" | jq -r '.CustomCommand // empty')
    
    # Auto-detect package manager if not specified
    if [[ -z "$pkg_manager" ]]; then
        pkg_manager=$(detect_package_manager "$working_dir")
    fi
    
    # Find venv if not specified
    if [[ -z "$venv_path" && "$pkg_manager" == "pip" ]]; then
        venv_path=$(find_venv "$working_dir" 2>/dev/null || true)
    fi
    
    local activate_prefix=""
    local run_cmd=""
    
    if [[ "$pkg_manager" == "pip" ]]; then
        activate_prefix=$(get_venv_activate_prefix "$venv_path")
    fi
    
    case "$app_type" in
        Streamlit)
            local port_arg=""
            local basepath_arg=""
            [[ -n "$port" ]] && port_arg=" --server.port $port"
            [[ -n "$base_path" ]] && basepath_arg=" --server.baseUrlPath '$base_path'"
            
            if [[ "$pkg_manager" == "uv" ]]; then
                run_cmd="uv run streamlit run '$index_path'$port_arg$basepath_arg"
            else
                run_cmd="${activate_prefix}streamlit run '$index_path'$port_arg$basepath_arg"
            fi
            ;;
            
        Django)
            local manage_py=$(find_manage_py "$working_dir")
            local runserver_arg=""
            [[ -n "$port" ]] && runserver_arg=" 0.0.0.0:$port"
            
            # Handle custom Django commands
            if [[ -n "$custom_command" ]]; then
                if [[ "$pkg_manager" == "uv" ]]; then
                    run_cmd="uv run python '$manage_py' $custom_command"
                else
                    run_cmd="${activate_prefix}python '$manage_py' $custom_command"
                fi
            else
                if [[ "$pkg_manager" == "uv" ]]; then
                    run_cmd="uv run python '$manage_py' runserver$runserver_arg"
                else
                    run_cmd="${activate_prefix}python '$manage_py' runserver$runserver_arg"
                fi
            fi
            ;;
            
        Dash)
            local port_arg=""
            [[ -n "$port" ]] && port_arg=" --server.port $port"
            
            if [[ "$pkg_manager" == "uv" ]]; then
                run_cmd="uv run python '$index_path'$port_arg"
            else
                run_cmd="${activate_prefix}python '$index_path'$port_arg"
            fi
            ;;
            
        Flask)
            local host_port_arg=""
            [[ -n "$port" ]] && host_port_arg=" --host=0.0.0.0 --port $port"
            local flask_env="export FLASK_APP='$index_path' FLASK_ENV='development'; "
            
            if [[ "$pkg_manager" == "uv" ]]; then
                run_cmd="${flask_env}uv run flask run$host_port_arg"
            else
                run_cmd="${flask_env}${activate_prefix}flask run$host_port_arg"
            fi
            ;;
            
        *)
            # Type-agnostic CustomCommand support (no Type required)
            if [[ -n "$custom_command" ]]; then
                local manage_py=$(find_manage_py "$working_dir")
                if [[ -n "$manage_py" ]]; then
                    # Django-style management command
                    if [[ "$pkg_manager" == "uv" ]]; then
                        run_cmd="uv run python '$manage_py' $custom_command"
                    else
                        run_cmd="${activate_prefix}python '$manage_py' $custom_command"
                    fi
                else
                    # Fallback: run as raw command
                    if [[ "$pkg_manager" == "uv" ]]; then
                        run_cmd="uv run $custom_command"
                    else
                        run_cmd="${activate_prefix}$custom_command"
                    fi
                fi
            else
                echo "Error: Unsupported app type: $app_type" >&2
                return 1
            fi
            ;;
    esac
    
    echo "$run_cmd"
}

# Check if a port is in use
# Usage: is_port_in_use 8000
is_port_in_use() {
    local port="$1"
    
    if command -v ss &>/dev/null; then
        ss -tuln 2>/dev/null | grep -q ":${port}\b"
    elif command -v netstat &>/dev/null; then
        netstat -tuln 2>/dev/null | grep -q ":${port}\b"
    elif command -v lsof &>/dev/null; then
        lsof -i ":$port" &>/dev/null
    else
        # If no tools available, assume port is free
        return 1
    fi
}

# Get process IDs using a port
# Usage: get_pids_on_port 8000
get_pids_on_port() {
    local port="$1"
    
    if command -v lsof &>/dev/null; then
        lsof -ti ":$port" 2>/dev/null
    elif command -v ss &>/dev/null; then
        ss -tulnp 2>/dev/null | grep ":${port}\b" | grep -oP '(?<=pid=)\d+'
    elif command -v fuser &>/dev/null; then
        fuser "$port/tcp" 2>/dev/null | tr -s ' ' '\n'
    fi
}

# Kill process on a port
# Usage: kill_port 8000
kill_port() {
    local port="$1"
    local pids=$(get_pids_on_port "$port")
    
    if [[ -n "$pids" ]]; then
        echo "Killing processes on port $port: $pids"
        echo "$pids" | xargs -r kill 2>/dev/null
        sleep 1
        # Force kill if still running
        echo "$pids" | xargs -r kill -9 2>/dev/null
        return 0
    fi
    return 1
}

# Wait for port to be free
# Usage: wait_for_port_free 8000 10
wait_for_port_free() {
    local port="$1"
    local timeout="${2:-10}"
    local elapsed=0
    
    while is_port_in_use "$port" && [[ $elapsed -lt $timeout ]]; do
        sleep 1
        ((elapsed++))
    done
    
    ! is_port_in_use "$port"
}
