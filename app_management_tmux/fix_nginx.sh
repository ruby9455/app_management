#!/usr/bin/env bash
# Writes the unified nginx server block for all apps on 10.17.62.155,
# removes the now-redundant nd_shift_report site symlink, then reloads nginx.

set -euo pipefail

SITES_AVAILABLE="/etc/nginx/sites-available"
SITES_ENABLED="/etc/nginx/sites-enabled"

sudo tee "$SITES_AVAILABLE/app_dashboard" > /dev/null << 'EOF'
server {
    listen 80;
    server_name 10.17.62.155;

    # ── app_dashboard (port 1111) ─────────────────────────────────────────────
    location = /app_dashboard {
        return 301 /app_dashboard/;
    }

    location /app_dashboard/ {
        proxy_pass http://127.0.0.1:1111/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    # ── nurse_led_clinic (port 4544) ──────────────────────────────────────────
    location /nurse_led_clinic/ {
        proxy_pass http://127.0.0.1:4544/nurse_led_clinic/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }

    # ── nd-shift-report (port 3844) ───────────────────────────────────────────
    location = /nd_shift_report {
        return 301 /nd-shift-report/;
    }

    location /nd_shift_report/ {
        return 301 /nd-shift-report/;
    }

    location = /nd-shift-report {
        return 301 /nd-shift-report/;
    }

    location /nd-shift-report/ {
        proxy_pass http://127.0.0.1:3844/nd-shift-report/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }

    # ── yss (port 8250) ───────────────────────────────────────────────────────
    location /yss/ {
        proxy_pass http://127.0.0.1:8250/yss/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }

    # ── driving_assessment (port 5267) ────────────────────────────────────────
    location /driving_assessment/ {
        proxy_pass http://127.0.0.1:5267/driving_assessment/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }

    # ── long_covid (port 5139) ────────────────────────────────────────────────
    location /long_covid/ {
        proxy_pass http://127.0.0.1:5139/long_covid/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }

    # ── stroke_rehab (port 3985) ──────────────────────────────────────────────
    location /stroke_rehab/ {
        proxy_pass http://127.0.0.1:3985/stroke_rehab/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }

    # ── redcap_dashboard (port 3954) ─────────────────────────────────────────
    location /redcap_dashboard/ {
        proxy_pass http://127.0.0.1:3954/redcap_dashboard/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }
}
EOF

# Remove the standalone nd_shift_report site — its server block conflicts with app_dashboard
if [ -L "$SITES_ENABLED/nd_shift_report" ]; then
    sudo rm "$SITES_ENABLED/nd_shift_report"
    echo "Removed $SITES_ENABLED/nd_shift_report symlink."
fi

sudo nginx -t && sudo systemctl reload nginx
echo "Done. nginx reloaded successfully."
