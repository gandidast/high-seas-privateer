#!/usr/bin/env bash
# ==============================================================================
# Update-Skript fuer den Oracle Cloud Server (/opt/pixel-privateer)
# Zieht die neueste Git-Version, startet pixel-privateer neu & zeigt den Status.
# ==============================================================================
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/pixel-privateer}"
SERVICE_NAME="pixel-privateer"

if [[ ! -d "${APP_DIR}" ]]; then
	echo "FEHLER: ${APP_DIR} existiert nicht." >&2
	exit 1
fi

echo "=== [1/3] Aktualisiere Repository in ${APP_DIR} ==="
cd "${APP_DIR}"
if [[ -d "${APP_DIR}/.git" ]]; then
	git pull --ff-only
else
	echo "WARNUNG: Kein .git-Verzeichnis in ${APP_DIR} gefunden – ueberspringe git pull."
fi

if [[ -d "${APP_DIR}/deploy" ]]; then
	chmod +x "${APP_DIR}/deploy/"*.sh || true
fi

echo "=== [2/3] Starte systemd-Service ${SERVICE_NAME} neu ==="
sudo systemctl restart "${SERVICE_NAME}"

echo "=== [3/3] Service-Status ==="
sudo systemctl status "${SERVICE_NAME}" --no-pager
