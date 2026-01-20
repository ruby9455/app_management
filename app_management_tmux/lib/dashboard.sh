#!/usr/bin/env bash
#
# lib/dashboard.sh - Dashboard HTML generation functions
#
# Source this file to use the functions:
#   source "$(dirname "${BASH_SOURCE[0]}")/dashboard.sh"
#

# Generate the full dashboard HTML
# Usage: generate_dashboard_html "$apps_json" "$network_url" "$external_url" "$generic_url"
generate_dashboard_html() {
    local apps_json="$1"
    local network_url="${2:-http://localhost}"
    local external_url="${3:-http://localhost}"
    local generic_url="${4:-http://localhost}"
    
    # Filter apps with valid ports
    local apps_with_ports=$(echo "$apps_json" | jq '[.[] | select(.Port != null and .Port > 0)]')
    local app_count=$(echo "$apps_with_ports" | jq 'length')
    
    cat << 'HEADER_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>App Management Dashboard</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 15px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        .header h1 {
            margin: 0;
            font-size: 2.5em;
            font-weight: 300;
        }
        .header p {
            margin: 10px 0 0 0;
            opacity: 0.9;
            font-size: 1.1em;
        }
        .apps-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
            gap: 20px;
            padding: 30px;
        }
        .app-card {
            background: #f8f9fa;
            border-radius: 10px;
            padding: 20px;
            border-left: 4px solid #11998e;
            transition: transform 0.2s, box-shadow 0.2s;
        }
        .app-card:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 25px rgba(0,0,0,0.1);
        }
        .app-name {
            font-size: 1.3em;
            font-weight: 600;
            color: #2c3e50;
            margin-bottom: 10px;
        }
        .app-type {
            background: #e3f2fd;
            color: #1976d2;
            padding: 4px 8px;
            border-radius: 15px;
            font-size: 0.8em;
            display: inline-block;
            margin-bottom: 15px;
        }
        .app-type.streamlit { background: #ffebee; color: #c62828; }
        .app-type.django { background: #e8f5e9; color: #2e7d32; }
        .app-type.flask { background: #fff3e0; color: #ef6c00; }
        .app-type.dash { background: #e3f2fd; color: #1565c0; }
        .url-section { margin-bottom: 15px; }
        .url-label { font-weight: 600; color: #555; margin-bottom: 5px; font-size: 0.9em; }
        .url-container { display: flex; align-items: center; gap: 8px; margin-bottom: 5px; }
        .url-link {
            flex: 1;
            background: white;
            border: 1px solid #ddd;
            border-radius: 5px;
            padding: 8px 12px;
            text-decoration: none;
            color: #2c3e50;
            transition: background-color 0.2s;
            word-break: break-all;
            display: block;
        }
        .url-link:hover { background: #f0f8ff; border-color: #11998e; }
        .copy-btn {
            background: #667eea;
            color: white;
            border: none;
            padding: 6px 12px;
            border-radius: 4px;
            cursor: pointer;
            font-size: 0.85em;
            transition: background 0.2s;
            white-space: nowrap;
        }
        .copy-btn:hover { background: #5568d3; }
        .copy-btn.copied { background: #2ecc71; }
        .footer {
            background: #f8f9fa;
            padding: 20px;
            text-align: center;
            color: #666;
            border-top: 1px solid #eee;
        }
        .refresh-btn {
            background: #11998e;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 5px;
            cursor: pointer;
            font-size: 1em;
            margin-bottom: 20px;
        }
        .refresh-btn:hover { background: #0e7a6f; }
        .status-indicator {
            display: inline-block;
            width: 10px;
            height: 10px;
            border-radius: 50%;
            margin-right: 8px;
        }
        .status-running { background: #2ecc71; }
        .status-stopped { background: #e74c3c; }
    </style>
    <script>
        function copyToClipboard(url, button) {
            navigator.clipboard.writeText(url).then(() => {
                const originalText = button.textContent;
                button.textContent = '✓ Copied!';
                button.classList.add('copied');
                setTimeout(() => {
                    button.textContent = originalText;
                    button.classList.remove('copied');
                }, 2000);
            });
        }
    </script>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🐧 App Management Dashboard</h1>
            <p>Linux Server with tmux</p>
        </div>
        <div style="text-align: center; padding-top: 20px;">
            <button class="refresh-btn" onclick="location.reload()">🔄 Refresh</button>
        </div>
        <div class="apps-grid">
HEADER_HTML

    # Generate app cards
    echo "$apps_with_ports" | jq -c '.[]' | while IFS= read -r app; do
        local name=$(echo "$app" | jq -r '.Name // "Unknown"')
        local app_type=$(echo "$app" | jq -r '.Type // "Unknown"')
        local port=$(echo "$app" | jq -r '.Port')
        local base_path=$(echo "$app" | jq -r '.BasePath // ""')
        
        local type_class=$(echo "$app_type" | tr '[:upper:]' '[:lower:]')
        
        # Build URLs
        local path_suffix=""
        [[ -n "$base_path" ]] && path_suffix="/${base_path#/}"
        
        local localhost_url="http://localhost:${port}${path_suffix}"
        local network_app_url="${network_url}:${port}${path_suffix}"
        local external_app_url="${external_url}:${port}${path_suffix}"
        
        cat << EOF
            <div class="app-card">
                <div class="app-name">$name</div>
                <span class="app-type $type_class">$app_type</span>
                <div class="url-section">
                    <div class="url-label">🏠 Localhost:</div>
                    <div class="url-container">
                        <a href="$localhost_url" target="_blank" class="url-link">$localhost_url</a>
                        <button class="copy-btn" onclick="copyToClipboard('$localhost_url', this)">📋 Copy</button>
                    </div>
                </div>
                <div class="url-section">
                    <div class="url-label">🌐 Network:</div>
                    <div class="url-container">
                        <a href="$network_app_url" target="_blank" class="url-link">$network_app_url</a>
                        <button class="copy-btn" onclick="copyToClipboard('$network_app_url', this)">📋 Copy</button>
                    </div>
                </div>
                <div class="url-section">
                    <div class="url-label">🌍 External:</div>
                    <div class="url-container">
                        <a href="$external_app_url" target="_blank" class="url-link">$external_app_url</a>
                        <button class="copy-btn" onclick="copyToClipboard('$external_app_url', this)">📋 Copy</button>
                    </div>
                </div>
            </div>
EOF
    done

    cat << 'FOOTER_HTML'
        </div>
        <div class="footer">
            <p>Generated by App Management Linux • Powered by tmux</p>
        </div>
    </div>
</body>
</html>
FOOTER_HTML
}

# Save dashboard to file
# Usage: save_dashboard "$apps_json" "$output_file" "$network_url" "$external_url" "$generic_url"
save_dashboard() {
    local apps_json="$1"
    local output_file="$2"
    local network_url="${3:-http://localhost}"
    local external_url="${4:-http://localhost}"
    local generic_url="${5:-http://localhost}"
    
    generate_dashboard_html "$apps_json" "$network_url" "$external_url" "$generic_url" > "$output_file"
    echo -e "${GREEN}Dashboard saved to: $output_file${NC}"
}
