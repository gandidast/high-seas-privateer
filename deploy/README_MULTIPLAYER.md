# High Seas Pixel Privateer — Multiplayer & Oracle Cloud Setup

Dieses Projekt bietet drei sofort einsatzbereite Multiplayer-Wege — von **1-Klick lokal** über **sofortigen öffentlichen Browser-/Tunnel-Link** bis zum **dauerhaften 24/7 Oracle Cloud Always Free Server** mit automatischem `wss://` TLS-Zertifikat (ohne Domain-Kauf).

---

## 1. Sofortiger 1-Klick Multiplayer (Lokal & mehrere Fenster)

1. Spiel starten und im Startmenü auf **`One-World Beitreten`** klicken (`ws://localhost:8080`).
2. Wenn noch kein Server auf Port `8080` läuft, startet `NetworkManager` automatisch einen lokalen Godot-Headless-Server im Hintergrund und verbindet den Client nach ~0.8 Sekunden.
3. Jedes weitere geöffnete Spiel-Fenster verbindet sich direkt mit derselben laufenden One-World-Session.

---

## 2. Öffentlicher 1-Klick Internet- & Browser-Tunnel (`wss://`)

Im Startbildschirm auf **`Öffentlichen Server / Browser-Link starten`** klicken (oder in PowerShell ausführen):

```powershell
.\deploy\start_live_multiplayer.ps1
```

Was passiert automatisch:
- Prüft Port `8080` und startet bei Bedarf den Godot 4.7.2 Headless-Server.
- Startet automatisch `cloudflared` (falls installiert) oder `npx --yes localtunnel --port 8080`.
- Schreibt die erzeugte `wss://...`-Adresse in die Zwischenablage **und** übernimmt sie automatisch ins URL-Feld des Spiels.

---

## 3. Dauerhafter Oracle Cloud Always Free Server + Web-Client (ohne eigene Domain)

Mit Oracle Cloud Always Free (Ubuntu 22.04/24.04 — `x86_64` AMD Micro oder `aarch64` Ampere A1) läuft der Server 24/7 kostenlos mit echtem Let's-Encrypt-Zertifikat über `<VM_IP>.nip.io`.

### Schritt A: Ports in der Oracle Cloud Konsole freigeben
In der Oracle Cloud Console unter **Networking → Virtual Cloud Networks → Security Lists → Ingress Rules** hinzufügen:
- **Source CIDR:** `0.0.0.0/0`
- **IP Protocol:** `TCP`
- **Destination Port Range:** `80`, `443`, `8080`

### Schritt B: Mit einem einzigen Befehl auf Oracle Cloud deployen
Auf deinem Windows-PC (mit deiner Oracle VM-IP und deinem `.key` SSH-Schlüssel):

```powershell
.\deploy\start_live_multiplayer.ps1 -OracleIp <DEINE_VM_IP> -SshKey "C:\Pfad\zu\oracle_ssh.key"
```

Das Skript überträgt automatisch das Projekt auf die VM und führt `deploy/oracle_cloud_setup.sh` aus:
- Lädt Godot 4.7.2 Linux Headless passend zur CPU (`x86_64` oder `arm64`) herunter.
- Installiert **Caddy** als Reverse-Proxy mit automatischem HTTPS & `wss://<DEINE_VM_IP>.nip.io`.
- Öffnet die Linux-Firewall (`iptables` / `ufw` für Ports 80, 443, 8080).
- Richtet `pirate-server.service` (`systemd`) mit automatischem Neustart ein.

*(Optional: Eigene Domain per `-Domain play.meinedomain.de` übergeben.)*

---

## 4. HTML5 Web-Client & Linux Dedicated Server exportieren

In `export_presets.cfg` sind zwei Presets vorkonfiguriert:
1. **`Web`** → `build/web/index.html` (Single-Threaded, PWA-kompatibel; im Browser erkennt das Spiel die `wss://`-Domain automatisch).
2. **`Linux Dedicated Server`** → `build/linux/pirate_server.x86_64` (`dedicated_server=true`).

Wenn `build/web/index.html` vor dem Oracle-Deploy exportiert wird, liefert Caddy den spielbaren Browser-Client automatisch unter `https://<DEINE_VM_IP>.nip.io` aus!
