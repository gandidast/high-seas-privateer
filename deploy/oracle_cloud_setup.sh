#!/usr/bin/env bash
# ==============================================================================
# Oracle Cloud Always Free (Ubuntu 22.04/24.04 x86_64 & ARM64) Auto-Provisioning
# Installs Godot 4.7.2 Headless, Caddy (Auto-TLS via <PUBLIC_IP>.nip.io),
# Linux Firewall Rules (80, 443, 8080), and systemd service pirate-server.
# ==============================================================================
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
	echo "Please run as root: sudo bash $0" >&2
	exit 1
fi

GODOT_VERSION="${GODOT_VERSION:-4.7.2-stable}"
APP_DIR="${APP_DIR:-/opt/pirate_game}"
WEB_DIR="/var/www/pirate_game_web"
PORT="${PORT:-8080}"
WORLD_SEED="${WORLD_SEED:-1337420}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== [1/6] Installing base dependencies ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
	curl unzip ca-certificates gnupg debian-keyring \
	debian-archive-keyring apt-transport-https ufw iptables-persistent

echo "=== [2/6] Installing Godot ${GODOT_VERSION} Linux Headless ==="
ARCH="$(uname -m)"
case "${ARCH}" in
	x86_64|amd64)
		GODOT_ARCH="linux.x86_64"
		;;
	aarch64|arm64)
		GODOT_ARCH="linux.arm64"
		;;
	*)
		echo "Unsupported architecture: ${ARCH}" >&2
		exit 1
		;;
esac

GODOT_BIN_NAME="Godot_v${GODOT_VERSION}_${GODOT_ARCH}"
GODOT_ZIP="${GODOT_BIN_NAME}.zip"
GODOT_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${GODOT_ZIP}"

if [[ ! -x /usr/local/bin/godot ]]; then
	echo "Downloading ${GODOT_URL}..."
	curl -fsSL "${GODOT_URL}" -o "/tmp/${GODOT_ZIP}"
	unzip -o -q "/tmp/${GODOT_ZIP}" -d /tmp/godot_extract
	mv "/tmp/godot_extract/${GODOT_BIN_NAME}" /usr/local/bin/godot
	chmod +x /usr/local/bin/godot
	rm -rf "/tmp/${GODOT_ZIP}" /tmp/godot_extract
else
	echo "Godot already installed at /usr/local/bin/godot"
fi
/usr/local/bin/godot --version || true

echo "=== [3/6] Installing Caddy Reverse Proxy (HTTPS / WSS) ==="
if ! command -v caddy >/dev/null 2>&1; then
	curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
		| gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
	curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
		> /etc/apt/sources.list.d/caddy-stable.list
	apt-get update -y
	apt-get install -y caddy
fi

echo "=== [4/6] Syncing project to ${APP_DIR} & configuring domain ==="
if [[ "${SOURCE_DIR}" != "${APP_DIR}" ]]; then
	mkdir -p "${APP_DIR}"
	cp -a "${SOURCE_DIR}/." "${APP_DIR}/"
fi
chmod +x "${APP_DIR}/deploy/"*.sh

PUBLIC_IP="$(curl -4 -fsSL https://api.ipify.org || curl -4 -fsSL https://ifconfig.me || curl -4 -fsSL https://icanhazip.com || true)"
PUBLIC_IP="$(echo "${PUBLIC_IP}" | tr -d '[:space:]')"
if [[ -z "${PUBLIC_IP}" ]]; then
	echo "ERROR: Could not detect public IP address. Set GAME_DOMAIN manually." >&2
	exit 1
fi

GAME_DOMAIN="${GAME_DOMAIN:-${PUBLIC_IP}.nip.io}"
echo "Public IP   : ${PUBLIC_IP}"
echo "Game Domain : ${GAME_DOMAIN}"

mkdir -p "${WEB_DIR}"
if [[ -f "${APP_DIR}/build/web/index.html" ]]; then
	echo "Deploying exported HTML5 Web client to ${WEB_DIR}..."
	cp -a "${APP_DIR}/build/web/." "${WEB_DIR}/"
else
	cat > "${WEB_DIR}/index.html" <<EOF
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="utf-8" />
  <title>High Seas Pixel Privateer — One-World Server</title>
  <style>
    body { font-family: system-ui, sans-serif; background: #0d1321; color: #f5ebd6; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; }
    .card { background: #161b2e; border: 2px solid #d8a94b; border-radius: 8px; padding: 28px 32px; max-width: 560px; box-shadow: 0 12px 32px rgba(0,0,0,.5); }
    h1 { color: #f6c945; margin-top: 0; font-size: 22px; }
    code { background: #0a0e18; border: 1px solid #5c4928; padding: 4px 8px; border-radius: 4px; color: #73e2d3; }
    .ok { color: #7ae582; font-weight: 600; }
  </style>
</head>
<body>
  <div class="card">
    <h1>High Seas Pixel Privateer — One-World Server</h1>
    <p class="ok">WebSocket-Server aktiv auf Oracle Cloud!</p>
    <p>Verbinde dich im Spiel unter <b>One-World Multiplayer</b> mit:</p>
    <p><code>wss://${GAME_DOMAIN}</code></p>
    <p style="font-size:13px;color:#b8b2a2;">Tipp: Exportiere das Godot-Preset <b>"Web"</b> nach <code>build/web/index.html</code> und lade es erneut hoch, um direkt hier im Browser zu spielen.</p>
  </div>
</body>
</html>
EOF
fi

cat > /etc/caddy/Caddyfile <<EOF
${GAME_DOMAIN} {
	encode zstd gzip

	@websocket {
		header Connection *Upgrade*
		header Upgrade websocket
	}
	reverse_proxy @websocket 127.0.0.1:${PORT}

	handle_path /ws* {
		reverse_proxy 127.0.0.1:${PORT}
	}

	root * ${WEB_DIR}
	try_files {path} /index.html
	file_server

	header {
		Cross-Origin-Opener-Policy "same-origin"
		Cross-Origin-Embedder-Policy "require-corp"
		X-Content-Type-Options "nosniff"
	}
}
EOF

echo "=== [5/6] Configuring Firewall (Ports 80, 443, ${PORT}) ==="
for p in 22 80 443 "${PORT}"; do
	if ! iptables -C INPUT -p tcp --dport "${p}" -j ACCEPT 2>/dev/null; then
		iptables -I INPUT 1 -p tcp --dport "${p}" -j ACCEPT
	fi
done
netfilter-persistent save || true

if ufw status 2>/dev/null | grep -q "Status: active"; then
	ufw allow 22/tcp || true
	ufw allow 80/tcp || true
	ufw allow 443/tcp || true
	ufw allow "${PORT}"/tcp || true
fi

echo "=== [6/6] Enabling systemd service pirate-server.service & Caddy ==="
mkdir -p /var/lib/pirate_game
cat > /etc/systemd/system/pirate-server.service <<EOF
[Unit]
Description=High Seas Pixel Privateer Headless Dedicated Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${APP_DIR}
Environment="GODOT_BIN=/usr/local/bin/godot"
Environment="PORT=${PORT}"
Environment="WORLD_SEED=${WORLD_SEED}"
Environment="PIRATE_DATA_DIR=/var/lib/pirate_game"
ExecStart=${APP_DIR}/deploy/start_server.sh
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable pirate-server.service
systemctl restart pirate-server.service
systemctl enable caddy.service
systemctl restart caddy.service

echo ""
echo "=================================================================="
echo "  ORACLE CLOUD MULTIPLAYER BEREIT!"
echo "=================================================================="
echo "  Oeffentliche WSS-URL : wss://${GAME_DOMAIN}"
echo "  Browser / HTTPS URL  : https://${GAME_DOMAIN}"
echo "  Direkte WS-URL       : ws://${PUBLIC_IP}:${PORT}"
echo ""
echo "  WICHTIG in Oracle Cloud Console:"
echo "  -> Networking -> VCN -> Security Lists -> Add Ingress Rules:"
echo "     Source CIDR: 0.0.0.0/0 | IP Protocol: TCP | Ports: 80, 443, ${PORT}"
echo ""
echo "  Logs ansehen : sudo journalctl -u pirate-server -f"
echo "=================================================================="
