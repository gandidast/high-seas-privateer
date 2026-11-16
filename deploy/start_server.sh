#!/usr/bin/env bash
# ==============================================================================
# Oracle Cloud Linux Headless Server Launcher for High Seas Pixel Privateer
# Runs Godot 4 in pure headless mode on port 8080 behind Caddy (wss://)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PORT="${PORT:-8080}"
SEED="${WORLD_SEED:-1337420}"

# Auto-detect Godot binary if GODOT_BIN is not explicitly provided
GODOT_BIN="${GODOT_BIN:-}"
if [[ -z "${GODOT_BIN}" ]]; then
	if command -v godot >/dev/null 2>&1; then
		GODOT_BIN="$(command -v godot)"
	elif [[ -x "/usr/local/bin/godot" ]]; then
		GODOT_BIN="/usr/local/bin/godot"
	elif [[ -x "${PROJECT_ROOT}/godot" ]]; then
		GODOT_BIN="${PROJECT_ROOT}/godot"
	fi
fi

# Fallback to exported dedicated Linux server binary if present
EXPORTED_SRV="${PROJECT_ROOT}/build/linux/pirate_server.x86_64"
if [[ -z "${GODOT_BIN}" && -x "${EXPORTED_SRV}" ]]; then
	echo "[High Seas Server] Starting exported Linux Dedicated Server..."
	exec "${EXPORTED_SRV}" --headless -- --server --port="${PORT}" --seed="${SEED}"
fi

if [[ -z "${GODOT_BIN}" ]]; then
	echo "[High Seas Server] ERROR: Neither Godot binary nor ${EXPORTED_SRV} found." >&2
	exit 1
fi

echo "[High Seas Server] Starting Godot 4 Headless Server..."
echo "[High Seas Server] Binary       : ${GODOT_BIN}"
echo "[High Seas Server] Project Root : ${PROJECT_ROOT}"
echo "[High Seas Server] Listen Port  : ${PORT}"
echo "[High Seas Server] World Seed   : ${SEED}"

exec "${GODOT_BIN}" \
	--headless \
	--path "${PROJECT_ROOT}" \
	-- \
	--server \
	--port="${PORT}" \
	--seed="${SEED}"
