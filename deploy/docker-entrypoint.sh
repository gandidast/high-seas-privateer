#!/usr/bin/env bash
set -euo pipefail

PUBLIC_PORT="${PORT:-7860}"
GODOT_PORT="${GODOT_INTERNAL_PORT:-18080}"

echo "[Entrypoint] Starting Godot headless server on 127.0.0.1:${GODOT_PORT} (public port ${PUBLIC_PORT})..."
godot --headless --path /app -- --server --port="${GODOT_PORT}" &
GODOT_PID=$!

cleanup() {
    echo "[Entrypoint] Shutting down..."
    kill "${GODOT_PID}" 2>/dev/null || true
    if [ -n "${NGINX_PID:-}" ]; then
        kill "${NGINX_PID}" 2>/dev/null || true
    fi
}
trap cleanup TERM INT EXIT

# Wait briefly for Godot WebSocket server to bind
sleep 1

cat > /tmp/nginx.conf <<EOF
worker_processes 1;
pid /tmp/nginx.pid;
error_log /dev/stderr warn;

events {
    worker_connections 1024;
}

http {
    access_log /dev/stdout;
    client_body_temp_path /tmp/nginx_body;
    proxy_temp_path /tmp/nginx_proxy;
    fastcgi_temp_path /tmp/nginx_fastcgi;
    uwsgi_temp_path /tmp/nginx_uwsgi;
    scgi_temp_path /tmp/nginx_scgi;

    map \$http_upgrade \$connection_upgrade {
        default upgrade;
        '' close;
    }

    server {
        listen 0.0.0.0:${PUBLIC_PORT} default_server;
        server_name _;

        tcp_nodelay on;

        location / {
            error_page 418 = @ws;
            if (\$http_upgrade ~* "websocket") {
                return 418;
            }
            default_type text/html;
            return 200 '<!DOCTYPE html><html><head><meta charset="utf-8"><title>High Seas Pixel Privateer Server</title></head><body style="background:#0c1322;color:#f5e6c4;font-family:sans-serif;text-align:center;padding:48px"><h1>High Seas Pixel Privateer - One-World Server</h1><p>Status: <strong>ONLINE</strong> (Godot 4.7.2 WebSocket Server)</p><p>WebSocket Endpoint: <code id="ws"></code></p><script>document.getElementById("ws").textContent = location.origin.replace(/^http/, "ws");</script><p><a href="https://gandidast.github.io/high-seas-privateer/" style="color:#f5c84b;font-size:18px">Play in Browser (GitHub Pages)</a></p></body></html>';
        }

        location @ws {
            proxy_pass http://127.0.0.1:${GODOT_PORT};
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_buffering off;
            proxy_read_timeout 86400s;
            proxy_send_timeout 86400s;
        }
    }
}
EOF

echo "[Entrypoint] Starting nginx WebSocket + HTTP health proxy on 0.0.0.0:${PUBLIC_PORT}..."
nginx -c /tmp/nginx.conf -g "daemon off;" &
NGINX_PID=$!

# Keep container alive as long as both Godot and nginx are running
while kill -0 "${GODOT_PID}" 2>/dev/null && kill -0 "${NGINX_PID}" 2>/dev/null; do
    sleep 2
done

echo "[Entrypoint] A core process exited; stopping container."
exit 1
