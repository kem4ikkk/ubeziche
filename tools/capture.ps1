# =====================================================================
#  capture.ps1 - progon (test run) of "Ubezhishche" with auto-screenshot.
#  Used by the AI assistant to self-check changes after editing code.
#
#  NOTE: this file is intentionally ASCII-only. Windows PowerShell 5.1 reads
#  a BOM-less .ps1 as ANSI, and Cyrillic (even in comments) gets mangled into
#  stray quotes that break parsing. The game's own Russian output comes from
#  Godot through the pipe and prints fine.
#
#  What it does:
#    1) (with -Import, or if .godot/imported is missing) imports assets
#       (--import) - needed after new images/scenes/class_name.
#    2) runs the game in progon mode (-- --capture <Seconds>):
#       scripts/debug_capture.gd plays the test scenario, saves
#       debug/last_run.png and terminates the process.
#    3) parses output: PASS/FAIL, screenshot path, detected errors.
#    4) on a flaky engine crash (no screenshot AND no SCRIPT ERROR - the known
#       Label3D/segfault race on exit) auto-retries up to -Retries times.
#
#  Usage (from project root):
#    powershell -ExecutionPolicy Bypass -File tools/capture.ps1
#    powershell -ExecutionPolicy Bypass -File tools/capture.ps1 -Seconds 4 -Import
#
#  Exit code: 0 = clean run; 1 = error / no clean run.
#  Do NOT rely on Godot's exit code: the progon ends via OS.kill.
# =====================================================================
param(
    [double]$Seconds = 3,
    [switch]$Import,
    [int]$Retries = 3
)

$ErrorActionPreference = "Stop"

# UTF-8 console so the game's Russian output is not garbled.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# Project root = parent of the tools/ folder where this script lives.
$Root  = Split-Path -Parent $PSScriptRoot
$Godot = "D:/Godot/Godot_v4.6.3-stable_win64_console.exe"

if (-not (Test-Path $Godot)) {
    Write-Host "ERROR: Godot not found: $Godot" -ForegroundColor Red
    Write-Host "Fix the path in tools/capture.ps1 (variable `$Godot)."
    exit 1
}

# 1) Import assets if needed.
$importedDir = Join-Path $Root ".godot/imported"
if ($Import -or -not (Test-Path $importedDir)) {
    Write-Host "== Import assets (--import) ==" -ForegroundColor Cyan
    & $Godot --headless --path $Root --import 2>&1 | Out-Host
}

$shot = Join-Path $Root "debug/last_run.png"

# 2-4) Run with auto-retry on flaky crash.
for ($attempt = 1; $attempt -le $Retries; $attempt++) {
    Write-Host ""
    Write-Host "== Run + screenshot (--capture $Seconds), attempt $attempt/$Retries ==" -ForegroundColor Cyan

    $gameArgs = @("--path", $Root, "--", "--capture", "$Seconds")
    $log  = & $Godot @gameArgs 2>&1
    $log | Out-Host

    $text     = ($log | Out-String)
    $hasShot  = ($text -match "CLAUDE_SCREENSHOT:") -and (Test-Path $shot)
    $hasError = ($text -match "SCRIPT ERROR") -or ($text -match "Parse Error") -or ($text -match "Parser Error")

    Write-Host ""
    Write-Host "----- RUN RESULT (attempt $attempt) -----"

    if ($hasError) {
        Write-Host "FAIL: SCRIPT/Parse ERROR in output - a real code error, fix it." -ForegroundColor Red
        exit 1
    }
    if ($hasShot) {
        Write-Host "PASS: run clean, screenshot saved." -ForegroundColor Green
        Write-Host "Screenshot: $shot"
        exit 0
    }

    # No screenshot and no script error => flaky engine crash, retry.
    Write-Host "FLAKY: no screenshot and no SCRIPT ERROR (engine crash on exit). Retrying..." -ForegroundColor Yellow
    Start-Sleep -Milliseconds 500
}

Write-Host ""
Write-Host "FAIL: no clean run after $Retries attempts." -ForegroundColor Red
exit 1
