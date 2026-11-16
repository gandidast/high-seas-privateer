<#
.SYNOPSIS
    1-Klick Live-Multiplayer & Oracle Cloud Deploy fuer High Seas Pixel Privateer.

.DESCRIPTION
    Ohne -OracleIp:
      1) Startet (falls noch nicht aktiv) den Godot 4.7.2 Headless-Server auf Port 8080.
      2) Startet einen oeffentlichen HTTPS/WSS-Tunnel (cloudflared oder npx localtunnel),
         sodass Mitspieler sofort per Internet oder Browser ueber wss://... beitreten koennen.

    Mit -OracleIp <VM-IP> [-SshKey <Pfad>]:
      Laedt das Projekt vollautomatisch per scp/ssh auf eine Oracle Cloud Always Free
      Ubuntu-VM hoch und richtet Godot Headless + Caddy (Auto-TLS via <IP>.nip.io) + systemd ein.
#>
param(
    [int]$Port = 8080,
    [int]$Seed = 1337420,
    [string]$GodotBin = "C:\games187+\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe",
    [string]$OracleIp = "",
    [string]$SshKey = "",
    [string]$SshUser = "ubuntu",
    [string]$Domain = "",
    [switch]$NoTunnel
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$LiveUrlFile = Join-Path $env:TEMP "pirate_game_live_url.txt"

function Test-LocalPortOpen {
    param([int]$CheckPort)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect("127.0.0.1", $CheckPort, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(350, $false)
        if ($ok -and $client.Connected) {
            $client.EndConnect($iar)
            return $true
        }
        return $false
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Save-LiveUrl {
    param([string]$Url)
    try {
        Set-Content -Path $LiveUrlFile -Value $Url -Encoding UTF8 -NoNewline
    } catch {}
    try {
        if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) {
            Set-Clipboard -Value $Url
        }
    } catch {}
}

# ==============================================================================
# MODUS A: VOLLAUTOMATISCHES ORACLE CLOUD DEPLOYMENT
# ==============================================================================
if (-not [string]::IsNullOrWhiteSpace($OracleIp)) {
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  HIGH SEAS PIXEL PRIVATEER - ORACLE CLOUD AUTO-DEPLOY" -ForegroundColor Yellow
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "Ziel-VM : $SshUser@$OracleIp"

    $sshCmd = Get-Command ssh -ErrorAction SilentlyContinue
    $scpCmd = Get-Command scp -ErrorAction SilentlyContinue
    if (-not $sshCmd -or -not $scpCmd) {
        throw "OpenSSH (ssh/scp) nicht gefunden. Bitte Windows OpenSSH-Client aktivieren."
    }

    $sshOpts = @("-o", "StrictHostKeyChecking=accept-new")
    if (-not [string]::IsNullOrWhiteSpace($SshKey)) {
        if (-not (Test-Path $SshKey)) {
            throw "SSH-Key nicht gefunden: $SshKey"
        }
        $sshOpts += @("-i", $SshKey)
    }

    $archivePath = Join-Path $env:TEMP "pirate_game_deploy.tar.gz"
    if (Test-Path $archivePath) { Remove-Item $archivePath -Force }

    Write-Host "[1/3] Verpacke Projekt ($ProjectRoot)..." -ForegroundColor Green
    $tarCmd = Get-Command tar -ErrorAction SilentlyContinue
    if (-not $tarCmd) {
        throw "'tar' nicht gefunden. Bitte Windows 10/11 tar.exe im PATH bereitstellen."
    }
    Push-Location $ProjectRoot
    try {
        & tar -czf $archivePath --exclude=".git" --exclude=".godot" --exclude="build" --exclude="*.tmp" .
        if ($LASTEXITCODE -ne 0) { throw "tar Verpackung fehlgeschlagen." }
    } finally {
        Pop-Location
    }

    Write-Host "[2/3] Lade Projekt auf Oracle Cloud VM hoch..." -ForegroundColor Green
    $remoteTarget = "${SshUser}@${OracleIp}:/tmp/pirate_game_deploy.tar.gz"
    & scp @sshOpts $archivePath $remoteTarget
    if ($LASTEXITCODE -ne 0) { throw "scp Upload fehlgeschlagen." }

    $domainEnv = ""
    if (-not [string]::IsNullOrWhiteSpace($Domain)) {
        $domainEnv = "GAME_DOMAIN='$Domain' "
    }
    $remoteCmd = "sudo mkdir -p /opt/pirate_game && " +
                 "sudo tar -xzf /tmp/pirate_game_deploy.tar.gz -C /opt/pirate_game && " +
                 "sudo rm -f /tmp/pirate_game_deploy.tar.gz && " +
                 "sudo sed -i 's/\r`$//' /opt/pirate_game/deploy/*.sh /opt/pirate_game/deploy/Caddyfile && " +
                 "sudo ${domainEnv}PORT=$Port WORLD_SEED=$Seed bash /opt/pirate_game/deploy/oracle_cloud_setup.sh"

    Write-Host "[3/3] Provisioniere Godot 4.7.2 + Caddy wss:// + systemd auf VM..." -ForegroundColor Green
    & ssh @sshOpts "$SshUser@$OracleIp" $remoteCmd
    if ($LASTEXITCODE -ne 0) { throw "Remote-Provisionierung fehlgeschlagen." }

    $effectiveDomain = if ([string]::IsNullOrWhiteSpace($Domain)) { "$OracleIp.nip.io" } else { $Domain }
    $liveWss = "wss://$effectiveDomain"
    Save-LiveUrl -Url $liveWss

    Write-Host ""
    Write-Host "FERTIG! Oeffentliche WSS-URL (in Zwischenablage): $liveWss" -ForegroundColor Green
    Write-Host "Web / HTTPS Status-Seite: https://$effectiveDomain" -ForegroundColor Cyan
    exit 0
}

# ==============================================================================
# MODUS B: LOKALER 1-KLICK SERVER + OEFFENTLICHER INTERNET-TUNNEL (WSS://)
# ==============================================================================
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  HIGH SEAS PIXEL PRIVATEER - 1-KLICK LIVE MULTIPLAYER" -ForegroundColor Yellow
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "Projekt : $ProjectRoot"
Write-Host "Port    : $Port | Seed: $Seed"
Write-Host ""

$serverProc = $null
$tunnelProc = $null

try {
    if (Test-LocalPortOpen -CheckPort $Port) {
        Write-Host "[1/2] Godot Headless-Server laeuft bereits auf Port $Port (wird weiterverwendet)." -ForegroundColor Green
    } else {
        if (-not (Test-Path $GodotBin)) {
            $godotInPath = Get-Command godot -ErrorAction SilentlyContinue
            if ($godotInPath) {
                $GodotBin = $godotInPath.Source
            } else {
                throw "Godot Binary nicht gefunden: $GodotBin"
            }
        }
        Write-Host "[1/2] Starte Godot Headless-Server auf Port $Port..." -ForegroundColor Green
        $godotArgs = @(
            "--headless",
            "--path", "`"$ProjectRoot`"",
            "--",
            "--server",
            "--port=$Port",
            "--seed=$Seed"
        )
        $serverProc = Start-Process -FilePath $GodotBin -ArgumentList $godotArgs -PassThru -WindowStyle Hidden

        $ready = $false
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Milliseconds 250
            if (Test-LocalPortOpen -CheckPort $Port) {
                $ready = $true
                break
            }
            if ($serverProc.HasExited) {
                throw "Godot Headless-Server hat sich unerwartet beendet (ExitCode $($serverProc.ExitCode))."
            }
        }
        if (-not $ready) {
            throw "Godot Headless-Server antwortet nach 7.5s nicht auf Port $Port."
        }
        Write-Host "      -> Lokaler Server bereit: ws://localhost:$Port" -ForegroundColor Cyan
    }

    if ($NoTunnel) {
        Save-LiveUrl -Url "ws://localhost:$Port"
        Write-Host "[2/2] Tunnel uebersprungen (-NoTunnel). Druecke Strg+C zum Beenden." -ForegroundColor Yellow
        while ($true) { Start-Sleep -Seconds 2 }
    }

    $cloudflared = Get-Command cloudflared -ErrorAction SilentlyContinue
    $npx = Get-Command npx -ErrorAction SilentlyContinue

    $tunnelExe = ""
    $tunnelArgs = ""
    $tunnelKind = ""

    if ($cloudflared) {
        $tunnelExe = $cloudflared.Source
        $tunnelArgs = "tunnel --url http://localhost:$Port --no-autoupdate"
        $tunnelKind = "cloudflared"
        Write-Host "[2/2] Starte Cloudflare Quick Tunnel (wss:// ohne Passwort-Hinweis)..." -ForegroundColor Green
    } elseif ($npx) {
        $tunnelExe = "cmd.exe"
        $tunnelArgs = "/c npx --yes localtunnel --port $Port"
        $tunnelKind = "localtunnel"
        Write-Host "[2/2] Starte Localtunnel via npx (wss://)..." -ForegroundColor Green
    } else {
        Save-LiveUrl -Url "ws://localhost:$Port"
        Write-Warning "Weder 'cloudflared' noch 'npx' gefunden. Server laeuft lokal auf ws://localhost:$Port."
        while ($true) { Start-Sleep -Seconds 2 }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $tunnelExe
    $psi.Arguments = $tunnelArgs
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $tunnelProc = New-Object System.Diagnostics.Process
    $tunnelProc.StartInfo = $psi

    $lineQueue = New-Object "System.Collections.Concurrent.ConcurrentQueue[string]"
    $outHandler = {
        if ($Event.SourceEventArgs.Data) {
            $Event.MessageData.Enqueue($Event.SourceEventArgs.Data)
        }
    }
    $outEvent = Register-ObjectEvent -InputObject $tunnelProc -EventName OutputDataReceived -MessageData $lineQueue -Action $outHandler
    $errEvent = Register-ObjectEvent -InputObject $tunnelProc -EventName ErrorDataReceived -MessageData $lineQueue -Action $outHandler

    [void]$tunnelProc.Start()
    $tunnelProc.BeginOutputReadLine()
    $tunnelProc.BeginErrorReadLine()

    $urlAnnounced = $false
    $pattern = if ($tunnelKind -eq "cloudflared") { "https://[a-zA-Z0-9\-]+\.trycloudflare\.com" } else { "https://[a-zA-Z0-9\-]+\.loca\.lt" }

    $publicIpHint = ""
    if ($tunnelKind -eq "localtunnel") {
        try {
            $publicIpHint = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 3).ToString().Trim()
        } catch {}
    }

    while (-not $tunnelProc.HasExited -or -not $lineQueue.IsEmpty) {
        $line = $null
        while ($lineQueue.TryDequeue([ref]$line)) {
            Write-Host "  [Tunnel] $line" -ForegroundColor DarkGray
            if (-not $urlAnnounced -and $line -match $pattern) {
                $httpsUrl = $Matches[0]
                $wssUrl = $httpsUrl -replace "^https://", "wss://"
                Save-LiveUrl -Url $wssUrl
                $urlAnnounced = $true
                Write-Host ""
                Write-Host "================================================================" -ForegroundColor Green
                Write-Host "  OEFFENTLICHER ONE-WORLD SERVER AKTIV!" -ForegroundColor Yellow
                Write-Host "  Teile diese URL (wurde in die Zwischenablage kopiert):" -ForegroundColor White
                Write-Host "    $wssUrl" -ForegroundColor Cyan
                Write-Host "  Lokal (gleicher PC): ws://localhost:$Port" -ForegroundColor Gray
                if ($publicIpHint) {
                    Write-Host "  Localtunnel-Passwort (falls im Browser gefragt): $publicIpHint" -ForegroundColor DarkYellow
                }
                Write-Host "  Dieses Fenster offen lassen, solange der Server laufen soll." -ForegroundColor Gray
                Write-Host "================================================================" -ForegroundColor Green
                Write-Host ""
            }
        }
        Start-Sleep -Milliseconds 120
    }
} finally {
    Get-EventSubscriber | Where-Object { $_.SourceObject -eq $tunnelProc } | Unregister-Event -ErrorAction SilentlyContinue
    if ($tunnelProc -and -not $tunnelProc.HasExited) {
        try { $tunnelProc.Kill() } catch {}
    }
    if ($serverProc -and -not $serverProc.HasExited) {
        Write-Host "Beende gestarteten lokalen Server (PID $($serverProc.Id))..." -ForegroundColor Yellow
        try { $serverProc.Kill() } catch {}
    }
}
