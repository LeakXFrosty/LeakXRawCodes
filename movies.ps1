<#
.SYNOPSIS
    MovieBox-TUI Installer - LeakX Edition
.DESCRIPTION
    Windows PowerShell installer for MovieBox-TUI with LeakX watermark and animated UI.
#>

param(
    [string]$Version = "",
    [string]$InstallDir = "",
    [switch]$Force,
    [switch]$DryRun,
    [switch]$NoModifyPath,
    [switch]$Uninstall,
    [switch]$Help
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {}
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls13
} catch {}
Set-StrictMode -Version Latest

# ============================================================
#  CONFIGURATION
# ============================================================
$AppName      = "MovieBox-Tui"
$BinName      = "moviebox-tui.exe"
$Repo         = "mesamirh/MovieBox-Tui"
$Watermark    = "LeakX"
$DefaultInstallDir = Join-Path $env:LOCALAPPDATA "Programs\MovieBox-Tui\bin"

# ============================================================
#  COLOR / THEME (Black Theme)
# ============================================================
$Theme = @{
    Background  = "Black"
    Primary     = "Magenta"
    Secondary   = "Cyan"
    Accent      = "DarkMagenta"
    Success     = "Green"
    Warning     = "Yellow"
    Error       = "Red"
    Dim         = "DarkGray"
    White       = "White"
    Watermark   = "DarkRed"
}

# ============================================================
#  HELP
# ============================================================
if ($Help) {
    Clear-Host
    Write-Host ""
    Write-Host "  ██╗     ███████╗ █████╗ ██╗  ██╗██╗  ██╗" -ForegroundColor $Theme.Watermark
    Write-Host "  ██║     ██╔════╝██╔══██╗██║ ██╔╝╚██╗██╔╝" -ForegroundColor $Theme.Watermark
    Write-Host "  ██║     █████╗  ███████║█████╔╝  ╚███╔╝ " -ForegroundColor $Theme.Watermark
    Write-Host "  ██║     ██╔══╝  ██╔══██║██╔═██╗  ██╔██╗ " -ForegroundColor $Theme.Watermark
    Write-Host "  ███████╗███████╗██║  ██║██║  ██╗██╔╝ ██╗" -ForegroundColor $Theme.Watermark
    Write-Host "  ╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝" -ForegroundColor $Theme.Watermark
    Write-Host ""
    Write-Host "  MovieBox-TUI Installer (Windows PowerShell)" -ForegroundColor $Theme.Secondary
    Write-Host "  ─────────────────────────────────────────────" -ForegroundColor $Theme.Dim
    Write-Host ""
    Write-Host "  USAGE:" -ForegroundColor $Theme.White
    Write-Host "      irm https://raw.githubusercontent.com/mesamirh/MovieBox-Tui/main/install.ps1 | iex" -ForegroundColor $Theme.Dim
    Write-Host "      .\install.ps1 [OPTIONS]" -ForegroundColor $Theme.Dim
    Write-Host ""
    Write-Host "  OPTIONS:" -ForegroundColor $Theme.White
    Write-Host "      -Version <tag>       Install a specific version (e.g. v0.1.14)" -ForegroundColor $Theme.Dim
    Write-Host "      -InstallDir <path>   Install binary to a custom directory" -ForegroundColor $Theme.Dim
    Write-Host "      -Force               Reinstall even if already at the latest version" -ForegroundColor $Theme.Dim
    Write-Host "      -DryRun              Perform preflight checks without writing files" -ForegroundColor $Theme.Dim
    Write-Host "      -NoModifyPath        Do not modify User PATH environment variable" -ForegroundColor $Theme.Dim
    Write-Host "      -Uninstall           Uninstall MovieBox-TUI from your system" -ForegroundColor $Theme.Dim
    Write-Host "      -Help                Show this help message" -ForegroundColor $Theme.Dim
    Write-Host ""
    Write-Host "  ─────────────────────────────────────────────" -ForegroundColor $Theme.Dim
    Write-Host "  Watermark: " -NoNewline -ForegroundColor $Theme.Dim
    Write-Host "$Watermark" -ForegroundColor $Theme.Watermark
    Write-Host ""
    return
}

# ============================================================
#  WRITE HELPERS
# ============================================================
function Write-Step    { param([string]$Message) Write-Host "  > " -ForegroundColor $Theme.Secondary -NoNewline; Write-Host $Message -ForegroundColor $Theme.White }
function Write-Success { param([string]$Message) Write-Host "  + " -ForegroundColor $Theme.Success -NoNewline; Write-Host $Message -ForegroundColor $Theme.White }
function Write-Warn    { param([string]$Message) Write-Host "  ! " -ForegroundColor $Theme.Warning -NoNewline; Write-Host $Message -ForegroundColor $Theme.White }
function Write-Err     { param([string]$Message) Write-Host "  x " -ForegroundColor $Theme.Error -NoNewline; Write-Host $Message -ForegroundColor $Theme.White }

# ============================================================
#  VERSION NORMALIZATION
# ============================================================
if ($Version -and $Version[0] -ne "v") {
    $Version = "v$Version"
}

# ============================================================
#  REGISTRY PATH HELPERS
# ============================================================
function Get-UserPathRaw {
    param([ref]$Kind)
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment")
    if (-not $key) { return "" }
    try {
        $raw = $key.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        try { $Kind.Value = $key.GetValueKind("Path") } catch { $Kind.Value = [Microsoft.Win32.RegistryValueKind]::ExpandString }
        return [string]$raw
    } finally {
        $key.Close()
    }
}

function Set-UserPathRaw {
    param([string]$NewPath, [Microsoft.Win32.RegistryValueKind]$ValueKind)
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $true)
    if (-not $key) { return }
    try { $key.SetValue("Path", $NewPath, $ValueKind) } finally { $key.Close() }
}

function Broadcast-EnvironmentChange {
    try {
        if (-not ([System.Management.Automation.PSTypeName]'Win32.NativeMethods'.Type)) {
            Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@ -ErrorAction SilentlyContinue
        }
        [UIntPtr]$result = [UIntPtr]::Zero
        [Win32.NativeMethods]::SendMessageTimeout(
            [IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, "Environment", 2, 5000, [ref]$result) | Out-Null
    } catch {}
}

function Add-ToUserPath {
    param([string]$Directory)
    $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
    $raw = Get-UserPathRaw -Kind ([ref]$kind)
    $segments = @($raw -split ";" | Where-Object { $_ })
    if ($segments -notcontains $Directory.TrimEnd("\")) {
        $joined = if ($raw.Trim()) { "$raw;$Directory" } else { $Directory }
        Set-UserPathRaw -NewPath $joined -ValueKind $kind
        Broadcast-EnvironmentChange
        return $true
    }
    return $false
}

function Remove-FromUserPath {
    param([string[]]$Directories)
    $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
    $raw = Get-UserPathRaw -Kind ([ref]$kind)
    if (-not $raw) { return $false }
    $normalized = @($Directories | ForEach-Object { $_.TrimEnd("\").ToLowerInvariant() })
    $kept = @($raw -split ";" | Where-Object { $_ -and ($normalized -notcontains $_.TrimEnd("\").ToLowerInvariant()) })
    if ($kept.Count -eq @($raw -split ";" | Where-Object { $_ }).Count) { return $false }
    Set-UserPathRaw -NewPath ($kept -join ";") -ValueKind $kind
    Broadcast-EnvironmentChange
    return $true
}

# ============================================================
#  TERMINAL SIZE
# ============================================================
function Get-TerminalCols {
    $Cols = 80
    try {
        if ($Host.UI.RawUI.WindowSize.Width -gt 0) {
            $Cols = $Host.UI.RawUI.WindowSize.Width
        }
    } catch {
        $Cols = 80
    }
    return $Cols
}

# ============================================================
#  LEAKX WATERMARK
# ============================================================
function Write-Watermark {
    param([string]$Position = "bottom")
    $Cols = Get-TerminalCols
    $Text = "LEAKX"
    $Pad  = [Math]::Max(0, [int][Math]::Floor(($Cols - $Text.Length) / 2))
    Write-Host ""
    Write-Host ((" " * $Pad) + "░▒▓█ " + $Text + " █▓▒░") -ForegroundColor $Theme.Watermark
}

function Write-WatermarkInline {
    Write-Host "  [" -NoNewline -ForegroundColor $Theme.Dim
    Write-Host "LEAKX" -NoNewline -ForegroundColor $Theme.Watermark
    Write-Host "]" -NoNewline -ForegroundColor $Theme.Dim
}

# ============================================================
#  ANIMATED ASCII BANNER (Black Theme)
# ============================================================
function Print-Header {
    Clear-Host
    $Cols = Get-TerminalCols

    # ---- ASCII Art (LeakX custom) ----
    $LeakXLines = @(
        ' /$$                           /$$             /$$   /$$',
        '| $$                          | $$            | $$  / $$',
        '| $$        /$$$$$$   /$$$$$$ | $$   /$$      |  $$/ $$/',
        '| $$       /$$__  $$ |____  $$| $$  /$$/       \  $$$$/ ',
        '| $$      | $$$$$$$$  /$$$$$$$| $$$$$$/         >$$  $$ ',
        '| $$      | $$_____/ /$$__  $$| $$_  $$        /$$/\  $$',
        '| $$$$$$$$|  $$$$$$$|  $$$$$$$| $$ \  $$      | $$  \ $$',
        '|________/ \_______/ \_______/|__/  \__/      |__/  |__/',
        '                                                        ',
        '                                                        ',
        '                                                        '
    )

    # ---- Animated reveal (typewriter effect) ----
    $RevealDelay = 40  # ms per line
    foreach ($Line in $LeakXLines) {
        $Pad = [Math]::Max(0, [int][Math]::Floor(($Cols - $Line.Length) / 2))
        if ($Pad -gt 0) {
            Write-Host ((" " * $Pad) + $Line) -ForegroundColor $Theme.Primary
        } else {
            Write-Host $Line -ForegroundColor $Theme.Primary
        }
        Start-Sleep -Milliseconds $RevealDelay
    }

    # ---- Subtitle with pulse effect ----
    $Sub = "Official Installer  •  LeakX Edition"
    $SubPad = [Math]::Max(0, [int][Math]::Floor(($Cols - $Sub.Length) / 2))
    if ($SubPad -gt 0) {
        Write-Host ""
        Write-Host ((" " * $SubPad) + $Sub) -ForegroundColor $Theme.Secondary
    } else {
        Write-Host ""
        Write-Host $Sub -ForegroundColor $Theme.Secondary
    }

    # ---- Watermark line ----
    Write-Watermark

    # ---- Divider ----
    $Divider = "─" * [Math]::Min($Cols, 60)
    $DivPad = [Math]::Max(0, [int][Math]::Floor(($Cols - $Divider.Length) / 2))
    if ($DivPad -gt 0) {
        Write-Host ((" " * $DivPad) + $Divider) -ForegroundColor $Theme.Accent
    } else {
        Write-Host $Divider -ForegroundColor $Theme.Accent
    }
    Write-Host ""
}

# ============================================================
#  ANIMATED SPINNER
# ============================================================
function Show-Spinner {
    param(
        [string]$Text = "Working",
        [int]$DurationMs = 1200
    )
    $Frames = @("⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏")
    $End = (Get-Date).AddMilliseconds($DurationMs)
    $i = 0
    while ((Get-Date) -lt $End) {
        $Frame = $Frames[$i % $Frames.Count]
        Write-Host "`r  $Frame $Text..." -NoNewline -ForegroundColor $Theme.Secondary
        Start-Sleep -Milliseconds 80
        $i++
    }
    Write-Host "`r  + $Text... done!   " -ForegroundColor $Theme.Success
}

# ============================================================
#  UNINSTALL
# ============================================================
function Do-Uninstall {
    Print-Header
    Write-Step "Uninstalling $AppName..."
    Show-Spinner -Text "Removing files" -DurationMs 800

    $Found = $false
    $TargetDirs = @(
        $DefaultInstallDir,
        "$env:LOCALAPPDATA\MovieBox-Tui"
    )

    foreach ($Dir in $TargetDirs) {
        $Exe = Join-Path $Dir $BinName
        if (Test-Path $Exe) {
            try {
                $RunningProcesses = Get-Process -Name "moviebox-tui" -ErrorAction SilentlyContinue
                if ($RunningProcesses) {
                    $RunningProcesses | Stop-Process -Force
                    Start-Sleep -Seconds 1
                }
                Remove-Item -Path $Exe -Force -ErrorAction SilentlyContinue
                Write-Success "Removed $Exe"
                $Found = $true
            } catch {
                Write-Warn "Could not remove $Exe"
            }
        }
    }

    if ($Found) {
        $Removed = Remove-FromUserPath -Directories @($DefaultInstallDir, "$env:LOCALAPPDATA\MovieBox-Tui\bin")
        Write-Success "$AppName was successfully uninstalled."
        if ($Removed) {
            Write-Success "Removed stale entry from User PATH."
        }
    } else {
        Write-Warn "No installed binary of $BinName was found."
    }
    Write-Watermark
    return
}

if ($Uninstall) {
    Do-Uninstall
    return
}

# ============================================================
#  MAIN FLOW
# ============================================================
Print-Header

$Architecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
if ($Architecture -eq "ARM64") {
    $ArchiveName = "MovieBox_Windows_arm64.zip"
    $PlatformName = "Windows (arm64)"
} elseif ($Architecture -eq "AMD64") {
    $ArchiveName = "MovieBox_Windows_x64.zip"
    $PlatformName = "Windows (x64)"
} else {
    Write-Err "Unsupported Windows architecture: $Architecture"
    Write-Watermark
    return
}

Write-Step "[1/4] Checking environment & resolving version..."
Show-Spinner -Text "Resolving latest release" -DurationMs 900

$TargetVersion = $Version
if (-not $TargetVersion) {
    try {
        $Request = [System.Net.WebRequest]::Create("https://github.com/$Repo/releases/latest")
        $Request.AllowAutoRedirect = $false
        $Response = $Request.GetResponse()
        $Location = $Response.Headers["Location"]
        if ($Location) {
            $TargetVersion = $Location.Split("/")[-1].Trim()
        }
        $Response.Close()
    } catch {
        try {
            $ReleaseJson = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ "User-Agent" = "MovieBox-Installer" } -UseBasicParsing
            $TargetVersion = $ReleaseJson.tag_name.Trim()
        } catch {
            Write-Err "Failed to contact GitHub for latest release. Please check your internet connection."
            Write-Watermark
            return
        }
    }
}

if (-not $TargetVersion) {
    Write-Err "Could not resolve latest release version from GitHub."
    Write-Watermark
    return
}

Write-Success "[1/4] Environment ready ($PlatformName - $TargetVersion)"

$EffectiveInstallDir = if ($InstallDir) { $InstallDir } else { $DefaultInstallDir }
$ExePath = Join-Path $EffectiveInstallDir $BinName

if (Test-Path $ExePath) {
    if (-not $Force) {
        $IsInteractive = [Environment]::UserInteractive -and (-not [Console]::IsInputRedirected)
        if ($IsInteractive) {
            Write-Host ""
            Write-Warn "$AppName is already installed at $ExePath"
            Write-Host "  What would you like to do?" -ForegroundColor $Theme.White
            Write-Host "    1) Reinstall / Update to latest version" -ForegroundColor $Theme.Dim
            Write-Host "    2) Uninstall" -ForegroundColor $Theme.Dim
            Write-Host "    3) Cancel" -ForegroundColor $Theme.Dim
            Write-Host ""
            $Choice = Read-Host "  Enter choice [1-3] (default 1)"
            if ($Choice -eq "2") {
                Do-Uninstall
                return
            } elseif ($Choice -eq "3") {
                Write-Success "No changes made. Exiting."
                Write-Watermark
                return
            }
        } else {
            try {
                $CurrentVerOutput = (& $ExePath --version 2>&1 | Out-String)
                if ($CurrentVerOutput -match "moviebox-tui\s+([\d\.]+)") {
                    $CurrentVer = "v" + $matches[1]
                    if ($CurrentVer -eq $TargetVersion) {
                        Write-Success "MovieBox-TUI $TargetVersion is already installed at $ExePath. Use -Force to reinstall."
                        Write-Watermark
                        return
                    }
                }
            } catch {}
        }
    }
}

if ($DryRun) {
    Write-Success "[Dry Run] Target package: $ArchiveName"
    Write-Success "[Dry Run] Target install directory: $ExePath"
    Write-Success "[Dry Run] All preflight checks passed."
    Write-Watermark
    return
}

$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("moviebox-tui-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

$ZipFile      = Join-Path $TempDir $ArchiveName
$ChecksumFile = Join-Path $TempDir "SHA256SUMS"
$BaseUrl      = "https://github.com/$Repo/releases/download/$TargetVersion"
$Url          = "$BaseUrl/$ArchiveName"

try {
    Write-Step "[2/4] Downloading $ArchiveName..."
    Show-Spinner -Text "Downloading package" -DurationMs 1000
    Invoke-WebRequest -Uri $Url -OutFile $ZipFile -UseBasicParsing
    Invoke-WebRequest -Uri "$BaseUrl/SHA256SUMS" -OutFile $ChecksumFile -UseBasicParsing
    try { Unblock-File -Path $ZipFile -ErrorAction SilentlyContinue } catch {}
    Write-Success "[2/4] Downloaded $ArchiveName"

    Write-Step "[3/4] Verifying SHA256 checksum..."
    Show-Spinner -Text "Verifying integrity" -DurationMs 800
    $ChecksumLine = Get-Content $ChecksumFile | Where-Object { $_ -match "\s+$([regex]::Escape($ArchiveName))$" } | Select-Object -First 1
    if (-not $ChecksumLine) {
        throw "Release checksum is missing for $ArchiveName."
    }
    $ExpectedHash = ($ChecksumLine -split "\s+")[0].Trim().ToUpper()
    $ActualHash   = (Get-FileHash -Path $ZipFile -Algorithm SHA256).Hash.Trim().ToUpper()
    if ($ActualHash -ne $ExpectedHash) {
        throw "Checksum verification failed."
    }
    Write-Success "[3/4] Cryptographic checksum verified"

    Write-Step "[4/4] Installing binary to $EffectiveInstallDir..."
    Show-Spinner -Text "Installing binary" -DurationMs 900
    if (-not (Test-Path $EffectiveInstallDir)) {
        New-Item -ItemType Directory -Force -Path $EffectiveInstallDir | Out-Null
    }

    $RunningProcesses = Get-Process -Name "moviebox-tui" -ErrorAction SilentlyContinue
    if ($RunningProcesses) {
        $RunningProcesses | Stop-Process -Force
        Start-Sleep -Seconds 1
    }

    Expand-Archive -Path $ZipFile -DestinationPath $TempDir -Force
    $ExtractedExe = Join-Path $TempDir $BinName
    if (-not (Test-Path $ExtractedExe)) {
        throw "Binary not found in archive."
    }

    try { Unblock-File -Path $ExtractedExe -ErrorAction SilentlyContinue } catch {}
    Move-Item -Path $ExtractedExe -Destination $ExePath -Force
    try { Unblock-File -Path $ExePath -ErrorAction SilentlyContinue } catch {}
    try {
        $SmokeOutput = (& $ExePath --version 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Verification note: $SmokeOutput"
        }
    } catch {
        Write-Warn "Verification note: $_"
    }
    Write-Success "[4/4] Binary installed to $ExePath"
} catch {
    Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Err "Installation failed: $_"
    Write-Watermark
    return
} finally {
    Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================
#  PATH UPDATE
# ============================================================
$PathModified = $false
if (-not $NoModifyPath) {
    if (Add-ToUserPath -Directory $EffectiveInstallDir) {
        $PathModified = $true
    }
    if (@($env:PATH -split ";") -notcontains $EffectiveInstallDir.TrimEnd("\")) {
        $env:PATH = "$env:PATH;$EffectiveInstallDir"
    }
}

# ============================================================
#  MEDIA PLAYER DETECTION
# ============================================================
$PlayerDetected = ""
if ((Get-Command "mpv" -ErrorAction SilentlyContinue) -or (Test-Path "C:\Program Files\mpv\mpv.exe") -or (Test-Path "C:\Program Files\MPV Player\mpv.exe") -or (Test-Path "C:\mpv\mpv.exe") -or (Test-Path "$env:LOCALAPPDATA\Programs\mpv\mpv.exe")) {
    $PlayerDetected = "mpv"
} elseif ((Get-Command "vlc" -ErrorAction SilentlyContinue) -or (Test-Path "C:\Program Files\VideoLAN\VLC\vlc.exe") -or (Test-Path "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe") -or (Test-Path "$env:LOCALAPPDATA\Programs\VLC\vlc.exe")) {
    $PlayerDetected = "VLC"
}

# ============================================================
#  FINAL SUMMARY (Black Theme + Watermark)
# ============================================================
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor $Theme.Accent
Write-Host "  ║                                                          ║" -ForegroundColor $Theme.Accent
Write-Host "  ║   " -NoNewline -ForegroundColor $Theme.Accent
Write-Host "+ MovieBox-Tui $TargetVersion successfully installed!" -NoNewline -ForegroundColor $Theme.Success
Write-Host "   ║" -ForegroundColor $Theme.Accent
Write-Host "  ║                                                          ║" -ForegroundColor $Theme.Accent
Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor $Theme.Accent
Write-Host ""

Write-Host "  - Binary:  " -ForegroundColor $Theme.Dim -NoNewline
Write-Host $ExePath -ForegroundColor $Theme.White

if ($PlayerDetected) {
    Write-Host "  - Player:  " -ForegroundColor $Theme.Dim -NoNewline
    Write-Host "$PlayerDetected (ready)" -ForegroundColor $Theme.Success
} else {
    Write-Host "  - Player:  " -ForegroundColor $Theme.Dim -NoNewline
    Write-Host "None detected (mpv or VLC recommended)" -ForegroundColor $Theme.Secondary
}

if ($PathModified) {
    Write-Host "  - Shell:   " -ForegroundColor $Theme.Dim -NoNewline
    Write-Host "PATH updated in User Environment" -ForegroundColor $Theme.Primary
}

Write-Host ""
Write-Host "  To start streaming:" -ForegroundColor $Theme.White
Write-Host "    moviebox-tui" -ForegroundColor $Theme.Success
Write-Host ""

if (-not $PlayerDetected) {
    Write-Host "  [i] Note: A media player (mpv or VLC) is recommended for video playback." -ForegroundColor $Theme.Secondary
    Write-Host ""
}

if ($PathModified) {
    Write-Host "  [i] In existing terminal windows, restart the window or run:" -ForegroundColor $Theme.Secondary
    Write-Host "      & `"$ExePath`"" -ForegroundColor $Theme.White
    Write-Host ""
}

# ---- Final Watermark ----
Write-Watermark
Write-Host ""
Write-Host "  Powered by " -NoNewline -ForegroundColor $Theme.Dim
Write-Host "LeakX" -NoNewline -ForegroundColor $Theme.Watermark
Write-Host "  •  Enjoy!" -ForegroundColor $Theme.Dim
Write-Host ""
