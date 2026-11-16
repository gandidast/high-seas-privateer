<#
.SYNOPSIS
    1-Klick Export-Skript fuer High Seas Pixel Privateer (Web & Windows Desktop).

.DESCRIPTION
    Exportiert das Projekt headless ueber Godot 4:
      - Preset "Web"             -> build/web/index.html (Single-Threaded, bereit fuer GitHub Pages & itch.io)
      - Preset "Windows Desktop" -> build/windows/HighSeasPixelPrivateer.exe

    Prueft automatisch auf Godot-Binary und installierte Export-Templates und gibt klare Statusmeldungen aus.
#>
param(
    [string]$GodotBin = "",
    [switch]$WebOnly,
    [switch]$WindowsOnly,
    [switch]$DebugBuild
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path

function Resolve-GodotBinary {
    param([string]$Requested)
    if (-not [string]::IsNullOrWhiteSpace($Requested)) {
        if (Test-Path $Requested) { return (Resolve-Path $Requested).Path }
        throw "Angegebene Godot-Binary nicht gefunden: $Requested"
    }

    $candidates = @(
        "C:\games187+\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe",
        "C:\games187+\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }

    foreach ($cmdName in @("godot4", "godot")) {
        $cmd = Get-Command $cmdName -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }

    throw "Keine Godot 4 Binary gefunden. Bitte Pfad via -GodotBin <Pfad> angeben."
}

function Get-TemplateVersionFolder {
    param([string]$RawVersion)
    $clean = $RawVersion.Trim()
    # Format e.g. "4.7.2.stable.official.ed1daf0bf" -> "4.7.2.stable"
    if ($clean -match "^(\d+\.\d+(?:\.\d+)?\.[a-zA-Z0-9_]+)") {
        return $Matches[1]
    }
    return $clean
}

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  HIGH SEAS PIXEL PRIVATEER - 1-KLICK EXPORT (WEB & WINDOWS)" -ForegroundColor Yellow
Write-Host "================================================================" -ForegroundColor Cyan

$godot = Resolve-GodotBinary -Requested $GodotBin
Write-Host "Projekt : $ProjectRoot"
Write-Host "Godot   : $godot"

$rawVersion = (& $godot --version 2>&1 | Select-Object -First 1).ToString().Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($rawVersion)) {
    throw "Konnte Godot-Version nicht abfragen."
}
$templateFolderName = Get-TemplateVersionFolder -RawVersion $rawVersion
$templatesBase = Join-Path $env:APPDATA "Godot\export_templates"
$templateDir = Join-Path $templatesBase $templateFolderName

Write-Host "Version : $rawVersion"
Write-Host "Templates: $templateDir"
Write-Host ""

if (-not (Test-Path $templateDir)) {
    Write-Host "[FEHLER] Export-Templates fuer '$templateFolderName' wurden nicht gefunden!" -ForegroundColor Red
    Write-Host "Erwarteter Pfad: $templateDir" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "So installierst du sie in 30 Sekunden:" -ForegroundColor White
    Write-Host "  1. Oeffne Godot -> Editor -> Export-Vorlagen verwalten -> Herunterladen und installieren" -ForegroundColor Gray
    Write-Host "  2. Oder lade 'Godot_v$($templateFolderName -replace '\.stable$', '-stable')_export_templates.tpz' von GitHub Releases" -ForegroundColor Gray
    Write-Host "     und entpacke den Inhalt von 'templates/' nach '$templateDir'." -ForegroundColor Gray
    exit 1
}

$exportFlag = if ($DebugBuild) { "--export-debug" } else { "--export-release" }
$exportedItems = @()

Push-Location $ProjectRoot
try {
    $presetsPath = Join-Path $ProjectRoot "export_presets.cfg"
    if (-not (Test-Path $presetsPath)) {
        throw "export_presets.cfg nicht gefunden unter $presetsPath"
    }

    if (-not $WindowsOnly) {
        $webTpl = Join-Path $templateDir "web_nothreads_release.zip"
        $webTplDebug = Join-Path $templateDir "web_nothreads_debug.zip"
        if (-not (Test-Path $webTpl) -and -not (Test-Path $webTplDebug)) {
            Write-Warning "Web Export-Template (web_nothreads_release.zip) in '$templateDir' nicht gefunden - Export koennte fehlschlagen."
        }
        $webDir = Join-Path $ProjectRoot "build\web"
        if (-not (Test-Path $webDir)) { New-Item -ItemType Directory -Path $webDir -Force | Out-Null }

        Write-Host "[1/2] Exportiere Preset 'Web' -> build/web/index.html ..." -ForegroundColor Green
        & $godot --headless --path $ProjectRoot $exportFlag "Web" "build/web/index.html"
        if ($LASTEXITCODE -ne 0) {
            throw "Web-Export fehlgeschlagen (ExitCode $LASTEXITCODE)."
        }
        $webOut = Join-Path $webDir "index.html"
        if (-not (Test-Path $webOut)) {
            throw "Web-Export abgeschlossen, aber build/web/index.html wurde nicht erzeugt."
        }
        $exportedItems += "Web            : $webOut"
    }

    if (-not $WebOnly) {
        $winTpl = Join-Path $templateDir "windows_release_x86_64.exe"
        if (-not $DebugBuild -and -not (Test-Path $winTpl)) {
            Write-Warning "Windows Export-Template (windows_release_x86_64.exe) in '$templateDir' nicht gefunden - Export koennte fehlschlagen."
        }
        $winDir = Join-Path $ProjectRoot "build\windows"
        if (-not (Test-Path $winDir)) { New-Item -ItemType Directory -Path $winDir -Force | Out-Null }

        Write-Host "[2/2] Exportiere Preset 'Windows Desktop' -> build/windows/HighSeasPixelPrivateer.exe ..." -ForegroundColor Green
        & $godot --headless --path $ProjectRoot $exportFlag "Windows Desktop" "build/windows/HighSeasPixelPrivateer.exe"
        if ($LASTEXITCODE -ne 0) {
            throw "Windows-Desktop-Export fehlgeschlagen (ExitCode $LASTEXITCODE)."
        }
        $winOut = Join-Path $winDir "HighSeasPixelPrivateer.exe"
        if (-not (Test-Path $winOut)) {
            throw "Windows-Export abgeschlossen, aber HighSeasPixelPrivateer.exe wurde nicht erzeugt."
        }
        $sizeMb = [math]::Round((Get-Item $winOut).Length / 1MB, 2)
        $exportedItems += "Windows Desktop: $winOut ($sizeMb MB)"
    }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  EXPORT ERFOLGREICH ABGESCHLOSSEN!" -ForegroundColor Yellow
foreach ($item in $exportedItems) {
    Write-Host "  $item" -ForegroundColor Cyan
}
Write-Host "================================================================" -ForegroundColor Green
Write-Host "Tipp: Push auf 'main' deployed build/web/ automatisch auf GitHub Pages!" -ForegroundColor Gray
