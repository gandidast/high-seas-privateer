#!/usr/bin/env bash
# ==============================================================================
# Oracle Cloud Always Free (Ubuntu ARM64 VM.Standard.A1.Flex & x86_64) Setup
# - Opens ports 80, 443, 8080 in iptables (netfilter-persistent) & ufw
# - Installs Godot 4 Headless matching CPU architecture (arm64 / x86_64)
# - Installs project to /opt/pixel-privateer/
# - Installs Caddy & configures <PUBLIC_IP>.sslip.io -> localhost:8080 (Auto wss://)
# - Registers & starts systemd service pixel-privateer.service (24/7 auto-restart)
# ==============================================================================
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
	echo "Bitte als root ausfuehren: sudo bash $0" >&2
	exit 1
fi

GODOT_VERSION="${GODOT_VERSION:-4.7.2-stable}"
APP_DIR="${APP_DIR:-/opt/pixel-privateer}"
PORT="${PORT:-8080}"
WORLD_SEED="${WORLD_SEED:-1337420}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== [1/6] Systempakete & Firewall-Tools installieren ==="
export DEBIAN_FRONTEND=noninteractive
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections

apt-get update -y
apt-get install -y --no-install-recommends \
	curl unzip ca-certificates gnupg debian-keyring \
	debian-archive-keyring apt-transport-https git iptables-persistent \
	libfontconfig1 libfreetype6

echo "=== [2/6] Firewall oeffnen (Ports 80, 443, ${PORT} in iptables & ufw) ==="
# Oracle Cloud Ubuntu images often ship with a default iptables REJECT rule.
# Insert ACCEPT rules at the top of INPUT and persist via netfilter-persistent.
for p in 22 80 443 "${PORT}"; do
	if ! iptables -C INPUT -p tcp --dport "${p}" -j ACCEPT 2>/dev/null; then
		iptables -I INPUT 1 -p tcp --dport "${p}" -j ACCEPT
	fi
done
netfilter-persistent save || true

if command -v ufw >/dev/null 2>&1; then
	ufw allow 22/tcp >/dev/null 2>&1 || true
	ufw allow 80/tcp >/dev/null 2>&1 || true
	ufw allow 443/tcp >/dev/null 2>&1 || true
	ufw allow "${PORT}/tcp" >/dev/null 2>&1 || true
	if ufw status 2>/dev/null | grep -q "Status: active"; then
		ufw reload || true
	fi
fi

echo "=== [3/6] CPU-Architektur erkennen & Godot ${GODOT_VERSION} Headless installieren ==="
ARCH="$(uname -m)"
case "${ARCH}" in
	aarch64|arm64)
		GODOT_ARCH="linux.arm64"
		;;
	x86_64|amd64)
		GODOT_ARCH="linux.x86_64"
		;;
	*)
		echo "Nicht unterstuetzte CPU-Architektur: ${ARCH}" >&2
		exit 1
		;;
esac

GODOT_BIN_NAME="Godot_v${GODOT_VERSION}_${GODOT_ARCH}"
GODOT_ZIP="${GODOT_BIN_NAME}.zip"
GODOT_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${GODOT_ZIP}"

if [[ ! -x /usr/local/bin/godot ]]; then
	echo "Lade ${GODOT_URL} herunter (${ARCH})..."
	curl -fSL --retry 3 "${GODOT_URL}" -o "/tmp/${GODOT_ZIP}" \
		|| curl -fSL --retry 3 "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}/${GODOT_ZIP}" -o "/tmp/${GODOT_ZIP}"
	rm -rf /tmp/godot_extract
	unzip -o -q "/tmp/${GODOT_ZIP}" -d /tmp/godot_extract
	EXTRACTED_BIN="$(find /tmp/godot_extract -maxdepth 2 -type f -name "Godot_v*" | head -n 1)"
	if [[ -z "${EXTRACTED_BIN}" ]]; then
		echo "Godot-Binary im Archiv ${GODOT_ZIP} nicht gefunden." >&2
		exit 1
	fi
	mv "${EXTRACTED_BIN}" /usr/local/bin/godot
	chmod +x /usr/local/bin/godot
	rm -rf "/tmp/${GODOT_ZIP}" /tmp/godot_extract
else
	echo "Godot bereits unter /usr/local/bin/godot vorhanden."
fi
/usr/local/bin/godot --version || true

echo "=== [4/6] Projekt nach ${APP_DIR} installieren ==="
mkdir -p "${APP_DIR}"
if [[ "${SOURCE_DIR}" != "${APP_DIR}" ]] && [[ -f "${SOURCE_DIR}/project.godot" ]]; then
	cp -a "${SOURCE_DIR}/." "${APP_DIR}/"
fi

if [[ -d "${APP_DIR}/deploy" ]]; then
	chmod +x "${APP_DIR}/deploy/"*.sh || true
fi

if [[ -f "${APP_DIR}/project.godot" ]]; then
	echo "Erzeuge Godot Klassen-Cache (--import)..."
	/usr/local/bin/godot --headless --path "${APP_DIR}" --import || true
fi

if [[ ! -f "${APP_DIR}/project.godot" ]] && [[ ! -x "${APP_DIR}/build/linux/pirate_server.x86_64" ]] && [[ ! -f "${APP_DIR}/server.pck" ]]; then
	echo "WARNUNG: Weder project.godot noch Server-Binary/PCK in ${APP_DIR} gefunden." >&2
fi

echo "=== [5/6] Oeffentliche IP ermitteln & Caddy (wss://<IP>.sslip.io) konfigurieren ==="
PUBLIC_IP="$(curl -4 -fsSL https://ifconfig.me || curl -4 -fsSL https://api.ipify.org || curl -4 -fsSL https://icanhazip.com || true)"
PUBLIC_IP="$(echo "${PUBLIC_IP}" | tr -d '[:space:]')"
if [[ -z "${PUBLIC_IP}" ]]; then
	echo "FEHLER: Oeffentliche IP konnte nicht ermittelt werden. Bitte GAME_DOMAIN setzen." >&2
	exit 1
fi

GAME_DOMAIN="${GAME_DOMAIN:-${PUBLIC_IP}.sslip.io}"
echo "Oeffentliche IP : ${PUBLIC_IP}"
echo "Caddy-Domain    : ${GAME_DOMAIN}"

if ! command -v caddy >/dev/null 2>&1; then
	curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
		| gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
	curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
		> /etc/apt/sources.list.d/caddy-stable.list
	apt-get update -y
	apt-get install -y caddy
fi

cat > /etc/caddy/Caddyfile <<EOF
${GAME_DOMAIN} {
	encode zstd gzip

	header {
		Access-Control-Allow-Origin *
		Access-Control-Allow-Methods "GET, POST, OPTIONS"
		Access-Control-Allow-Headers "*"
	}

	@websocket {
		header Connection *Upgrade*
		header Upgrade websocket
	}
	reverse_proxy @websocket localhost:${PORT}

	handle /ws* {
		reverse_proxy localhost:${PORT}
	}

	reverse_proxy localhost:${PORT}
}
EOF

caddy validate --config /etc/caddy/Caddyfile

echo "=== [6/6] systemd-Service pixel-privateer.service & Caddy aktivieren ==="
EXEC_CMD="/usr/local/bin/godot --headless --path ${APP_DIR} -- --server --port=${PORT} --seed=${WORLD_SEED}"
if [[ ! -f "${APP_DIR}/project.godot" ]] && [[ -f "${APP_DIR}/server.pck" ]]; then
	EXEC_CMD="/usr/local/bin/godot --headless --main-pack ${APP_DIR}/server.pck -- --server --port=${PORT} --seed=${WORLD_SEED}"
elif [[ ! -f "${APP_DIR}/project.godot" ]] && [[ -x "${APP_DIR}/build/linux/pirate_server.x86_64" ]]; then
	EXEC_CMD="${APP_DIR}/build/linux/pirate_server.x86_64 --headless -- --server --port=${PORT} --seed=${WORLD_SEED}"
fi

cat > /etc/systemd/system/pixel-privateer.service <<EOF
[Unit]
Description=High Seas Pixel Privateer Headless Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${APP_DIR}
Environment="PORT=${PORT}"
Environment="HOME=/tmp"
ExecStart=${EXEC_CMD}
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable pixel-privateer.service
systemctl restart pixel-privateer.service
systemctl enable caddy.service
systemctl restart caddy.service

echo ""
echo "=================================================================="
echo "  ORACLE CLOUD 24/7 SERVER & WSS:// PROXY BEREIT!"
echo "=================================================================="
echo "  WSS-URL (fuer res://net/server_config.gd):"
echo "    wss://${GAME_DOMAIN}"
echo ""
echo "  GitHub Pages Web-Link Parameter:"
echo "    ?server=wss://${GAME_DOMAIN}"
echo ""
echo "  WICHTIG in der Oracle Cloud Console:"
echo "    VCN -> Security Lists -> Add Ingress Rules:"
echo "    Source CIDR: 0.0.0.0/0 | IP Protocol: TCP | Ports: 80, 443"
echo ""
echo "  Service-Status : sudo systemctl status pixel-privateer --no-pager"
echo "  Live-Logs      : sudo journalctl -u pixel-privateer -f"
echo "=================================================================="
