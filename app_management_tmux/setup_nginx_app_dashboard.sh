#!/usr/bin/env bash
# Sets up nginx reverse proxy for app_dashboard at http://<server-ip>/app_dashboard/

set -euo pipefail

NGINX_CONF="/etc/nginx/sites-available/app_dashboard"
NGINX_LINK="/etc/nginx/sites-enabled/app_dashboard"

cat > "$NGINX_CONF" << 'CONF'
server {
    listen 80;
    server_name localhost ~^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$;

    location = /app_dashboard {
        return 301 /app_dashboard/;
    }

    location /app_dashboard/ {
        proxy_pass http://127.0.0.1:1111/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
CONF

if [ ! -L "$NGINX_LINK" ]; then
    ln -s "$NGINX_CONF" "$NGINX_LINK"
fi

nginx -t && systemctl reload nginx

echo "Done. Access the dashboard at http://<server-ip>/app_dashboard/"
