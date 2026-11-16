# Oracle Cloud 24/7 Server Setup (`wss://` mit Caddy & `sslip.io`)

Kurzanleitung für den kostenlosen **Oracle Cloud Always Free** 24/7 Dedicated Server inklusive automatischem Let's-Encrypt-Zertifikat (`wss://<DEINE-IP>.sslip.io`) ohne eigene Domain.

---

## 1. Oracle Cloud Always Free VM & VCN Firewall einrichten

1. Im **Oracle Cloud Dashboard** eine neue **Compute Instance** erstellen:
   - **Image:** Ubuntu (`22.04` oder `24.04` Minimal/Standard)
   - **Shape:** `VM.Standard.A1.Flex` (Always Free ARM64, z. B. 1–4 OCPUs, 6–24 GB RAM) oder `VM.Standard.E2.1.Micro` (`x86_64`)
   - **SSH Key:** Eigenen Public Key hinterlegen bzw. generierten Private Key herunterladen.
2. **Ports 80 & 443 in der VCN Security List freigeben** (zwingend für Let's Encrypt & `wss://`!):
   - Navigiere zu **Networking → Virtual Cloud Networks → dein VCN → Subnets → Default Security List**.
   - Klicke auf **Add Ingress Rules** und füge hinzu:
     - **Source CIDR:** `0.0.0.0/0` | **IP Protocol:** `TCP` | **Destination Port Range:** `80`
     - **Source CIDR:** `0.0.0.0/0` | **IP Protocol:** `TCP` | **Destination Port Range:** `443`
     - *(Optional für direktes `ws://`-Testing)* **Destination Port Range:** `8080`

---

## 2. 1-Befehl-Installation auf der VM

Per SSH auf die VM verbinden (`ssh -i <DEIN-KEY>.key ubuntu@<DEINE-IP>`), das Repository klonen (oder hochladen) und das Setup-Skript ausführen:

```bash
git clone <DEIN-REPO-URL> /opt/pixel-privateer
cd /opt/pixel-privateer
sudo bash deploy/setup_oracle.sh
```

**Was `deploy/setup_oracle.sh` vollautomatisch erledigt:**
- Öffnet Ports `80`, `443` und `8080` in `iptables` (`netfilter-persistent save`) und `ufw`.
- Erkennt die CPU-Architektur (`aarch64`/`arm64` für `VM.Standard.A1.Flex` oder `x86_64`) und installiert die passende offizielle Godot 4 Headless-Binary nach `/usr/local/bin/godot`.
- Installiert **Caddy** und richtet `/etc/caddy/Caddyfile` für `<PUBLIC_IP>.sslip.io` → `reverse_proxy localhost:8080` mit WebSocket- & CORS-Support sowie automatischem HTTPS/`wss://`-Zertifikat ein.
- Erstellt und aktiviert `/etc/systemd/system/pixel-privateer.service` (`Restart=always`, `RestartSec=3`) für den 24/7-Betrieb.

Am Ende gibt das Skript deine fertige Server-URL aus, z. B.:
`wss://129.159.xx.xx.sslip.io`

---

## 3. Server-URL im Spiel oder Web-Link eintragen

Du hast zwei Möglichkeiten, deinen Server mit Spielern zu teilen:

1. **Fest im Projekt hinterlegen (`res://net/server_config.gd`):**
   Trage deine ausgegebene Adresse in `DEFAULT_SERVER_URL` ein:
   ```gdscript
   const DEFAULT_SERVER_URL := "wss://<DEINE-IP>.sslip.io"
   ```
2. **Per URL-Parameter an den GitHub Pages Web-Link anhängen (ohne Rebuild):**
   ```text
   https://<DEIN-USER>.github.io/<DEIN-REPO>/?server=wss://<DEINE-IP>.sslip.io
   ```
   *(Der HTML5-Client liest `?server=...` automatisch beim Start aus.)*

---

## 4. Server updaten

Um neue Änderungen aus Git auf der Oracle-VM einzuspielen und den Server sauber neu zu starten:

```bash
bash /opt/pixel-privateer/deploy/update_server.sh
```

Live-Logs kannst du jederzeit mit folgendem Befehl prüfen:

```bash
sudo journalctl -u pixel-privateer -f
```
