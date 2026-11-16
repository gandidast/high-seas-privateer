<#
.SYNOPSIS
    Lokales Hosten & Teilen via Cloudflare Quick Tunnel (wss://) fuer High Seas Pixel Privateer.

.DESCRIPTION
    1) Startet den lokalen Godot Headless-Server auf Port 8080 (falls Port noch frei ist).
    2) Nutzt "cloudflared tunnel --url http://localhost:8080" (ohne Browser-Passwort!).
       Falls cloudflared nicht im PATH liegt, wird cloudflared-windows-amd64.exe
       automatisch nach tools\cloudflared.exe heruntergeladen.
    3) Wandelt die erzeugte https://....trycloudflare.com URL in wss://....trycloudflare.com um,
       speichert sie in %TEMP%\pirate_game_live_url.txt und kopiert sie in die Zwischenablage.
    4) Haelt das Fenster offen (Read-Host), bis der Nutzer es aktiv beendet, und stoppt
       anschliessend Server und Tunnel sauber.
#>
param(
    [int]$Port = 8080,
    [int]$Seed = 1337420,
    [string]$GodotBin = "",
    [switch]$NoInteractive
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$LocalCloudflared = Join-Path $ScriptDir "cloudflared.exe"
$LiveUrlFile = Join-Path $env:TEMP "pirate_game_live_url.txt"
$CloudflaredDownloadUrl = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"

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

function Resolve-GodotBinary {
    param([string]$RequestedPath)
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $candidates += $RequestedPath
    }
    $candidates += @(
        "C:\games187+\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe",
        "C:\games187+\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
    )
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
            return $candidate
        }
    }
    $godotCmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($godotCmd) {
        return $godotCmd.Source
    }
    if (Test-Path "C:\games187+") {
        $found = Get-ChildItem -Path "C:\games187+" -Filter "Godot*console.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            return $found.FullName
        }
    }
    throw "Godot-Binary nicht gefunden. Bitte -GodotBin <Pfad> angeben oder 'godot' in PATH legen."
}

function Resolve-CloudflaredBinary {
    $cmd = Get-Command cloudflared -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }
    if (Test-Path $LocalCloudflared) {
        return $LocalCloudflared
    }

    Write-Host "[Cloudflare] 'cloudflared' nicht gefunden. Lade cloudflared-windows-amd64.exe nach tools\cloudflared.exe..." -ForegroundColor Yellow
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $prevProgress = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"
    try {
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            & curl.exe -fsSL --retry 3 $CloudflaredDownloadUrl -o $LocalCloudflared
        } else {
            Invoke-WebRequest -Uri $CloudflaredDownloadUrl -OutFile $LocalCloudflared -UseBasicParsing
        }
    } finally {
        $ProgressPreference = $prevProgress
    }
    if (-not (Test-Path $LocalCloudflared)) {
        throw "Download von cloudflared fehlgeschlagen ($CloudflaredDownloadUrl)."
    }
    Write-Host "[Cloudflare] Download abgeschlossen: $LocalCloudflared" -ForegroundColor Green
    return $LocalCloudflared
}

function Save-LiveUrl {
    param([string]$Url)
    Set-Content -Path $LiveUrlFile -Value $Url -Encoding UTF8 -NoNewline
    if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) {
        try {
            Set-Clipboard -Value $Url
        } catch {}
    }
}

$serverProc = $null
$tunnelProc = $null
$outEvent = $null
$errEvent = $null

try {
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  HIGH SEAS PIXEL PRIVATEER - LOKALER SERVER + CLOUDFLARE WSS" -ForegroundColor Yellow
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "Projekt : $ProjectRoot"
    Write-Host "Port    : $Port | Seed: $Seed"
    Write-Host ""

    if (Test-LocalPortOpen -CheckPort $Port) {
        Write-Host "[1/2] Godot Headless-Server laeuft bereits auf Port $Port (wird mitgenutzt)." -ForegroundColor Green
    } else {
        $resolvedGodot = Resolve-GodotBinary -RequestedPath $GodotBin
        Write-Host "[1/2] Starte Godot Headless-Server ($resolvedGodot)..." -ForegroundColor Green
        $godotArgs = @(
            "--headless",
            "--path", "`"$ProjectRoot`"",
            "--",
            "--server",
            "--port=$Port",
            "--seed=$Seed"
        )
        $serverProc = Start-Process -FilePath $resolvedGodot -ArgumentList $godotArgs -PassThru -WindowStyle Hidden

        $ready = $false
        for ($i = 0; $i -lt 40; $i++) {
            Start-Sleep -Milliseconds 250
            if (Test-LocalPortOpen -CheckPort $Port) {
                $ready = $true
                break
            }
            if ($serverProc.HasExited) {
                throw "Godot Headless-Server wurde unerwartet beendet (ExitCode $($serverProc.ExitCode))."
            }
        }
        if (-not $ready) {
            throw "Godot Headless-Server antwortet nach 10s nicht auf Port $Port."
        }
        Write-Host "      -> Lokaler Server bereit: ws://localhost:$Port" -ForegroundColor Cyan
    }

    $cloudflaredExe = Resolve-CloudflaredBinary
    Write-Host "[2/2] Starte cloudflared tunnel --url http://127.0.0.1:$Port ..." -ForegroundColor Green

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $cloudflaredExe
    $psi.Arguments = "tunnel --url http://127.0.0.1:$Port --no-autoupdate"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $tunnelProc = New-Object System.Diagnostics.Process
    $tunnelProc.StartInfo = $psi

    $lineQueue = New-Object "System.Collections.Concurrent.ConcurrentQueue[string]"
    $lineHandler = {
        if ($Event.SourceEventArgs.Data) {
            $Event.MessageData.Enqueue($Event.SourceEventArgs.Data)
        }
    }
    $outEvent = Register-ObjectEvent -InputObject $tunnelProc -EventName OutputDataReceived -MessageData $lineQueue -Action $lineHandler
    $errEvent = Register-ObjectEvent -InputObject $tunnelProc -EventName ErrorDataReceived -MessageData $lineQueue -Action $lineHandler

    [void]$tunnelProc.Start()
    $tunnelProc.BeginOutputReadLine()
    $tunnelProc.BeginErrorReadLine()

    $wssUrl = ""
    $deadline = (Get-Date).AddSeconds(45)
    while ((Get-Date) -lt $deadline) {
        $line = $null
        while ($lineQueue.TryDequeue([ref]$line)) {
            Write-Host "  [cloudflared] $line" -ForegroundColor DarkGray
            if ($line -match "https://[a-zA-Z0-9\-]+\.trycloudflare\.com") {
                $httpsUrl = $Matches[0]
                $wssUrl = $httpsUrl -replace "^https://", "wss://"
                break
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($wssUrl)) {
            break
        }
        if ($tunnelProc.HasExited -and $lineQueue.IsEmpty) {
            break
        }
        Start-Sleep -Milliseconds 120
    }

    if ([string]::IsNullOrWhiteSpace($wssUrl)) {
        Write-Warning "Keine trycloudflare.com URL erkannt. Pruefe die [cloudflared]-Ausgabe oben."
    } else {
        Save-LiveUrl -Url $wssUrl
        Write-Host ""
        Write-Host "================================================================" -ForegroundColor Green
        Write-Host "  CLOUDFLARE WSS-TUNNEL AKTIV!" -ForegroundColor Yellow
        Write-Host "  WSS-URL (in Zwischenablage & $LiveUrlFile):" -ForegroundColor White
        Write-Host "    $wssUrl" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Web-Client Parameter:" -ForegroundColor White
        Write-Host "    ?server=$wssUrl" -ForegroundColor Gray
        Write-Host "  Lokal (gleicher PC):" -ForegroundColor White
        Write-Host "    ws://localhost:$Port" -ForegroundColor Gray
        Write-Host "================================================================" -ForegroundColor Green
        Write-Host ""
    }

    if ($NoInteractive) {
        Write-Host "Laeuft im Hintergrund-Modus (-NoInteractive)..." -ForegroundColor Yellow
        while ($tunnelProc -and -not $tunnelProc.HasExited) {
            Start-Sleep -Seconds 2
        }
    } else {
        [void](Read-Host "Dieses Fenster offen lassen! Druecke [ENTER], um Server & Tunnel sauber zu beenden")
    }
} finally {
    if ($outEvent) { Unregister-Event -SourceIdentifier $outEvent.Name -ErrorAction SilentlyContinue }
    if ($errEvent) { Unregister-Event -SourceIdentifier $errEvent.Name -ErrorAction SilentlyContinue }
    Get-EventSubscriber | Where-Object { $_.SourceObject -eq $tunnelProc } | Unregister-Event -ErrorAction SilentlyContinue

    if ($tunnelProc -and -not $tunnelProc.HasExited) {
        Write-Host "Beende cloudflared Tunnel (PID $($tunnelProc.Id))..." -ForegroundColor Yellow
        try { $tunnelProc.Kill() } catch {}
        try { $tunnelProc.WaitForExit(2000) | Out-Null } catch {}
    }
    if ($serverProc -and -not $serverProc.HasExited) {
        Write-Host "Beende lokalen Godot Headless-Server (PID $($serverProc.Id))..." -ForegroundColor Yellow
        try { $serverProc.Kill() } catch {}
        try { $serverProc.WaitForExit(2000) | Out-Null } catch {}
    }
    Write-Host "Server und Tunnel wurden beendet." -ForegroundColor Gray
}
