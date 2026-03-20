Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

[Console]::Title = "Stay Green Monitor"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ---------------------------------------------------------------------------
# Log file — same directory as script, fallback to cwd
# ---------------------------------------------------------------------------
$script:logFilePath = if ($PSScriptRoot) {
    Join-Path $PSScriptRoot "StayGreen.log"
} else {
    Join-Path (Get-Location).Path "StayGreen.log"
}

# ---------------------------------------------------------------------------
# Native Windows API
# ---------------------------------------------------------------------------
if (-not ("NativeKeepAlive" -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class NativeKeepAlive
{
    [StructLayout(LayoutKind.Sequential)]
    private struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }

    [DllImport("user32.dll")] private static extern bool GetLastInputInfo(ref LASTINPUTINFO p);
    [DllImport("user32.dll")] public  static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
    [DllImport("user32.dll")] public  static extern void keybd_event(byte vk, byte sc, uint f, UIntPtr e);

    private const uint MOUSEEVENTF_MOVE = 0x0001;
    private const uint KEYEVENTF_KEYUP  = 0x0002;
    private const int  DELAY_MS         = 10;

    public static uint GetIdleMilliseconds() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf(typeof(LASTINPUTINFO));
        if (!GetLastInputInfo(ref lii)) return 0;
        unchecked { return (uint)Environment.TickCount - lii.dwTime; }
    }

    public static void MouseJiggle() {
        mouse_event(MOUSEEVENTF_MOVE,  1, 0, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(DELAY_MS);
        mouse_event(MOUSEEVENTF_MOVE, -1, 0, 0, UIntPtr.Zero);
    }

    public static void PressF15() {
        const byte VK_F15 = 0x7E;
        keybd_event(VK_F15, 0, 0,               UIntPtr.Zero);
        System.Threading.Thread.Sleep(DELAY_MS);
        keybd_event(VK_F15, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    }
}
"@
}

# ---------------------------------------------------------------------------
# Window sizing
# ---------------------------------------------------------------------------
try {
    if ([Console]::WindowWidth -lt 110) { [Console]::WindowWidth = 110 }
    if ([Console]::BufferWidth -lt [Console]::WindowWidth) {
        [Console]::BufferWidth = [Console]::WindowWidth
    }
} catch {}

# ---------------------------------------------------------------------------
# Config
# OPT: plain hashtable — marginally faster key lookup than [ordered] for
#      hot-path reads since ordered uses an ArrayList for key ordering
# ---------------------------------------------------------------------------
$script:cfg = @{
    IntervalSeconds      = 20
    IdleThresholdSeconds = 50
    Action               = "MouseJiggle"
    MaxLogLines          = 200        # 200 is plenty; less than original 500
    UseUnicodeChars      = $true
    RenderIntervalMs     = 500
    LoopSleepMs          = 100
    ShutdownDelayMs      = 500
    EyeIntervalMs        = 750
}

# ---------------------------------------------------------------------------
# Eye animation — fixed-length array, no heap growth ever
# Sequence: center -> left -> center -> right -> center -> blink
# ---------------------------------------------------------------------------
$script:eyeFrames = [string[]]@(
    "(  o o  )"   # 0  center
    "( o o   )"   # 1  left
    "(  o o  )"   # 2  center
    "(   o o )"   # 3  right
    "(  o o  )"   # 4  center
    "(  - -  )"   # 5  blink
)
$script:EYE_FRAME_COUNT = $script:eyeFrames.Length

# ---------------------------------------------------------------------------
# Box characters — resolved once; stored as bare variables, not a hashtable
# OPT: removes one hashtable key-lookup per character reference in render loop
# ---------------------------------------------------------------------------
if ($script:cfg.UseUnicodeChars) {
    $script:bV      = [char]0x2502        # │  (char for IndexOf)
    $script:bVS     = [string][char]0x2502  # │  (string for Write)
    $script:bH      = [string][char]0x2500  # ─
    $script:bTL     = [string][char]0x256D  # ╭
    $script:bTR     = [string][char]0x256E  # ╮
    $script:bBL     = [string][char]0x2570  # ╰
    $script:bBR     = [string][char]0x256F  # ╯
    $script:bTTop   = [string][char]0x252C  # ┬
    $script:bTBot   = [string][char]0x2534  # ┴
    $script:bDot    = [string][char]0x25CF  # ●
    $script:bCircle = [string][char]0x25CB  # ○
} else {
    $script:bV      = [char]'|'
    $script:bVS     = "|"
    $script:bH      = "-"
    $script:bTL     = "+"  ;  $script:bTR = "+"
    $script:bBL     = "+"  ;  $script:bBR = "+"
    $script:bTTop   = "+"  ;  $script:bTBot = "+"
    $script:bDot    = "*"  ;  $script:bCircle = "o"
}

# ---------------------------------------------------------------------------
# Layout constants
# ---------------------------------------------------------------------------
$script:COL1_WIDTH = 42
$script:LEFT_ROWS  = 17   # left column always has exactly 17 rows

# ---------------------------------------------------------------------------
# Border / static-string cache
# OPT: strings are rebuilt only when the console window width changes,
#      not on every render call (~500 ms interval)
# ---------------------------------------------------------------------------
$script:cacheWinWidth   = -1
$script:cacheCol2Width  = 0
$script:cacheTopBorder  = ""
$script:cacheBotBorder  = ""
$script:cacheBlankLine  = ""
$script:cacheStatusHdr  = ""
$script:cacheMetricsHdr = ""
$script:cacheCtrlHdr    = ""
$script:cacheLogHdr     = ""
# Control rows pre-padded to COL1_WIDTH so PadRight is skipped at render time
$script:cacheCtrl1      = ""
$script:cacheCtrl2      = ""
$script:cacheCtrl3      = ""

function Update-BorderCache {
    $w = [Console]::WindowWidth
    if ($w -lt 80) { $w = 80 }
    if ($w -eq $script:cacheWinWidth) { return }   # width unchanged — nothing to do

    $c1 = $script:COL1_WIDTH
    $c2 = [Math]::Max(20, $w - $c1 - 4)
    $H  = $script:bH

    $script:cacheWinWidth   = $w
    $script:cacheCol2Width  = $c2
    $script:cacheTopBorder  = "$($script:bTL)$($H * $c1)$($script:bTTop)$($H * $c2)$($script:bTR)"
    $script:cacheBotBorder  = "$($script:bBL)$($H * $c1)$($script:bTBot)$($H * $c2)$($script:bBR)"
    $script:cacheBlankLine  = ' ' * $w

    # Helper: build a column header with trailing dashes to fill $width chars
    $mkHdr = {
        param([string]$title, [int]$width)
        $d = $width - $title.Length - 1
        if ($d -lt 0) { $d = 0 }
        return "$title $($script:bH * $d)"
    }
    $script:cacheStatusHdr  = & $mkHdr " STATUS"       $c1
    $script:cacheMetricsHdr = & $mkHdr " METRICS"      $c1
    $script:cacheCtrlHdr    = & $mkHdr " CONTROLS"     $c1
    $script:cacheLogHdr     = & $mkHdr " ACTIVITY LOG" $c2

    # Pre-pad static control rows so the render loop skips PadRight for them
    $script:cacheCtrl1 = " [S] Start/Stop   [C] Clear Log".PadRight($c1)
    $script:cacheCtrl2 = " [I] Interval     [Q] Quit".PadRight($c1)
    $script:cacheCtrl3 = " [T] Threshold    [A] Action".PadRight($c1)
}

# ---------------------------------------------------------------------------
# State
# OPT: EyeLastUpdateTick uses Environment.TickCount (Int32 read, zero alloc)
#      instead of DateTime.Now which allocates a new DateTime struct each call
# ---------------------------------------------------------------------------
$script:state = @{
    Running               = $true
    NextCheck             = [DateTime]::MinValue   # set after first init log
    LastActionAt          = $null
    ActionCount           = 0
    CurrentRunStart       = [DateTime]::Now
    AccumulatedRunSeconds = 0.0
    NeedsRedraw           = $true
    QuitFlag              = $false
    EyeFrameIndex         = 0
    EyeLastUpdateTick     = [Environment]::TickCount
}

# ---------------------------------------------------------------------------
# Circular log buffer
# OPT: Queue[string] — O(1) Enqueue at tail + O(1) Dequeue from head
#      The previous List[string].RemoveRange(0, n) was O(n) because it shifts
#      every remaining element in the backing array forward after each trim
# ---------------------------------------------------------------------------
$script:logQ = New-Object 'System.Collections.Generic.Queue[string]' ($script:cfg.MaxLogLines + 1)

# ---------------------------------------------------------------------------
# Persistent StreamWriter for file logging
# OPT: one open file handle for the entire session instead of Add-Content
#      which opens, seeks-to-end, writes, flushes, and closes on every call
# ---------------------------------------------------------------------------
$script:logWriter = $null
try {
    $script:logWriter = [System.IO.StreamWriter]::new(
        $script:logFilePath, $true, [System.Text.Encoding]::UTF8
    )
    $script:logWriter.AutoFlush = $true
} catch {}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Get-IdleSeconds {
    # OPT: pure integer math, no DateTime object created
    [int][Math]::Floor([NativeKeepAlive]::GetIdleMilliseconds() / 1000.0)
}

function Get-OrdinalSuffix([int]$Day) {
    if ($Day -in 11, 12, 13) { return "th" }
    switch ($Day % 10) {
        1 { return "st" }  2 { return "nd" }  3 { return "rd" }  default { return "th" }
    }
}

function Format-DisplayDate([DateTime]$Now) {
    # OPT: caller passes $Now so no second [DateTime]::Now is needed here
    # Output: "Feb 26th 2026 10:20:13"
    $sfx = Get-OrdinalSuffix $Now.Day
    return $Now.ToString("MMM ") + $Now.Day + $sfx + $Now.ToString(" yyyy HH:mm:ss")
}

function Format-Uptime([object]$StartTime, [DateTime]$Now) {
    # OPT: caller passes $Now — reuses the single timestamp from the render call
    if ($null -eq $StartTime) { return "-" }
    $span = $Now - [DateTime]$StartTime
    if ($span.TotalHours   -ge 1) { return "{0:D2}h {1:D2}m {2:D2}s" -f [int][Math]::Floor($span.TotalHours), $span.Minutes, $span.Seconds }
    if ($span.TotalMinutes -ge 1) { return "{0:D2}m {1:D2}s"          -f $span.Minutes, $span.Seconds }
    return "{0}s" -f $span.Seconds
}

function Format-DurationSeconds([double]$TotalSeconds) {
    if ($TotalSeconds -lt 0) { $TotalSeconds = 0 }
    $span = [TimeSpan]::FromSeconds([Math]::Floor($TotalSeconds))
    return "{0:D2}h {1:D2}m {2:D2}s" -f [int][Math]::Floor($span.TotalHours), $span.Minutes, $span.Seconds
}

function Get-TotalRuntimeSeconds {
    $total = [double]$script:state.AccumulatedRunSeconds
    if ($null -ne $script:state.CurrentRunStart) {
        $total += ([DateTime]::Now - [DateTime]$script:state.CurrentRunStart).TotalSeconds
    }
    return [Math]::Max(0.0, $total)
}

function Test-ConfigInt([object]$Value, [int]$Min, [int]$Max) {
    if ($null -eq $Value) { return $false }
    $v = 0
    if (-not [int]::TryParse($Value.ToString(), [ref]$v)) { return $false }
    return ($v -ge $Min -and $v -le $Max)
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

function Add-Log([string]$Message, [string]$Level = "INFO") {
    $line = "[{0}] [{1}] {2}" -f [DateTime]::Now.ToString("HH:mm:ss"), $Level, $Message

    $script:logQ.Enqueue($line)
    # OPT: Dequeue is O(1) — no element shifting like List.RemoveRange
    if ($script:logQ.Count -gt $script:cfg.MaxLogLines) {
        [void]$script:logQ.Dequeue()
    }

    if ($null -ne $script:logWriter) {
        try { $script:logWriter.WriteLine($line) } catch {}
    }

    $script:state.NeedsRedraw = $true
}

function Invoke-KeepAliveAction {
    $idle = Get-IdleSeconds
    if ($idle -lt $script:cfg.IdleThresholdSeconds) { return }

    try {
        if ($script:cfg.Action -eq "MouseJiggle") {
            [NativeKeepAlive]::MouseJiggle()
            Add-Log "Idle ${idle}s >= $($script:cfg.IdleThresholdSeconds)s -> Mouse jiggle" "ACTION"
        } elseif ($script:cfg.Action -eq "F15") {
            [NativeKeepAlive]::PressF15()
            Add-Log "Idle ${idle}s >= $($script:cfg.IdleThresholdSeconds)s -> F15 key press" "ACTION"
        } else {
            Add-Log "Unknown action '$($script:cfg.Action)' - skipped" "WARN"
            return
        }
        $script:state.LastActionAt = [DateTime]::Now
        $script:state.ActionCount++
        $script:state.NeedsRedraw = $true
    } catch {
        Add-Log "Action failed: $($_.Exception.Message)" "ERROR"
    }
}

# ---------------------------------------------------------------------------
# Rendering
#
# Optimisation summary:
#   [Console]::Out  — write directly to the TextWriter; skips Write-Host's
#                     PowerShell pipeline, format-string parser, and object
#                     unwrapping (~10x faster per line of output)
#   ForegroundColor — set via property assignment, not a cmdlet
#   .Contains()     — O(n) scan with no regex engine; replaces -match
#   [string[]]::new — fixed-size array allocated once; no List resizing
#   Cached strings  — borders, headers, control rows rebuilt only on resize
#   LINQ Skip       — snapshots only the visible log window (≤16 entries)
#                     instead of the full 200-entry Queue backing store
#   [DateTime]::Now — one call per render, passed to sub-functions
#   No intermediate full-TUI string — render line-by-line directly
# ---------------------------------------------------------------------------

function Get-LogLineColor([string]$Line) {
    # OPT: .Contains() avoids regex engine startup cost on every log row
    if ($Line.Contains("[ERROR]"))  { return [ConsoleColor]::Red }
    if ($Line.Contains("[WARN]"))   { return [ConsoleColor]::Yellow }
    if ($Line.Contains("[ACTION]")) { return [ConsoleColor]::Cyan }
    return $null
}

function Render-Tui {
    Update-BorderCache

    $now     = [DateTime]::Now         # single allocation reused throughout
    $c1      = $script:COL1_WIDTH
    $c2      = $script:cacheCol2Width
    $ww      = $script:cacheWinWidth
    $vStr    = $script:bVS             # │ string — cached to avoid repeated field lookups
    $out     = [Console]::Out          # TextWriter ref — avoids property lookup in tight loop
    $running = $script:state.Running

    # ---- Build left column as a fixed-size string array (17 rows) ----
    $left       = [string[]]::new($script:LEFT_ROWS)
    $idle       = Get-IdleSeconds
    $stateIcon  = if ($running) { $script:bDot } else { $script:bCircle }
    $stateWord  = if ($running) { "RUNNING" }    else { "STOPPED" }
    $stateColor = if ($running) { [ConsoleColor]::Green } else { [ConsoleColor]::Yellow }
    $idleFlag   = if ($idle -ge $script:cfg.IdleThresholdSeconds) { " (>= cfg)" } else { "" }
    $nextStr    = if ($running) { $script:state.NextCheck.ToString("HH:mm:ss") } else { "-" }
    $lastActStr = if ($null -ne $script:state.LastActionAt) { $script:state.LastActionAt.ToString("HH:mm:ss") } else { "-" }

    $left[0]  = $script:cacheStatusHdr
    $left[1]  = " State:  $stateIcon $stateWord"       # left cell coloured in render loop
    $left[2]  = " Time:   $(Format-DisplayDate $now)"
    $left[3]  = " Uptime: $(Format-Uptime $script:state.CurrentRunStart $now)"
    $left[4]  = " " + $script:eyeFrames[$script:state.EyeFrameIndex]   # flush-left, no leading space
    $left[5]  = ""
    $left[6]  = $script:cacheMetricsHdr
    $left[7]  = " Idle:   {0,-4} / {1,-4}{2}" -f "${idle}s", "$($script:cfg.IdleThresholdSeconds)s", $idleFlag
    $left[8]  = " Check:  $($script:cfg.IntervalSeconds)s"
    $left[9]  = " Action: $($script:cfg.Action)"
    $left[10] = " Next:   $nextStr"
    $left[11] = " Acts:   $($script:state.ActionCount) ($lastActStr)"
    $left[12] = ""
    $left[13] = $script:cacheCtrlHdr
    $left[14] = $script:cacheCtrl1    # already padded to $c1 in cache
    $left[15] = $script:cacheCtrl2
    $left[16] = $script:cacheCtrl3

    # ---- Snapshot only the visible log window from the Queue ----
    # OPT: LINQ Skip avoids allocating a full 200-element array via ToArray();
    #      we allocate at most LEFT_ROWS-1 = 16 strings
    $logSlots = $script:LEFT_ROWS - 1   # row 0 of right column is the header
    $logTotal = $script:logQ.Count
    $logShow  = [Math]::Min($logSlots, $logTotal)
    $logSkip  = $logTotal - $logShow
    $logSnap  = if ($logShow -gt 0) {
        [string[]][System.Linq.Enumerable]::ToArray(
            [System.Linq.Enumerable]::Skip(
                [System.Collections.Generic.IEnumerable[string]]$script:logQ,
                $logSkip
            )
        )
    } else { [string[]]@() }

    # ---- Output ----
    [Console]::SetCursorPosition(0, 0)
    $defColor = [Console]::ForegroundColor

    $out.WriteLine($script:cacheTopBorder)

    for ($i = 0; $i -lt $script:LEFT_ROWS; $i++) {

        # Left cell — rows 14-16 were pre-padded in the cache; all others need PadRight
        $lText = if ($i -ge 14) { $left[$i] } else { $left[$i].PadRight($c1) }

        # Right cell
        if ($i -eq 0) {
            $rText  = $script:cacheLogHdr.PadRight($c2)
            $rColor = $null
        } elseif ($logShow -eq 0 -and $i -eq 1) {
            $rText  = " (No activity yet)".PadRight($c2)
            $rColor = $null
        } else {
            $li = $i - 1   # log index: left row 1 -> log entry 0
            if ($li -lt $logShow) {
                $msg    = $logSnap[$li]
                if ($msg.Length -gt $c2) { $msg = $msg.Substring(0, $c2 - 3) + "..." }
                $rText  = $msg.PadRight($c2)
                $rColor = Get-LogLineColor $msg
            } else {
                $rText  = "".PadRight($c2)
                $rColor = $null
            }
        }

        # Write: │  [coloured left cell]  │  [coloured right cell]  │
        if ($i -eq 1) {
            # State row — colour the left cell only
            $out.Write($vStr)
            [Console]::ForegroundColor = $stateColor
            $out.Write($lText)
            [Console]::ForegroundColor = $defColor
        } else {
            $out.Write($vStr)
            $out.Write($lText)
        }

        $out.Write($vStr)
        if ($null -ne $rColor) {
            [Console]::ForegroundColor = $rColor
            $out.Write($rText)
            [Console]::ForegroundColor = $defColor
        } else {
            $out.Write($rText)
        }
        $out.WriteLine($vStr)
    }

    $out.WriteLine($script:cacheBotBorder)

    # Clear rows below the TUI so stale content from a taller prior render doesn't bleed
    $curY = [Console]::CursorTop
    $winH = [Console]::WindowHeight
    while ($curY -lt ($winH - 1)) {
        $out.WriteLine($script:cacheBlankLine)
        $curY++
    }

    $script:state.NeedsRedraw = $false
}

# ---------------------------------------------------------------------------
# Input helper
# ---------------------------------------------------------------------------

function Read-IntOrNull([string]$Prompt) {
    [Console]::CursorVisible = $true
    [Console]::Out.WriteLine("")
    [Console]::ForegroundColor = [ConsoleColor]::Yellow
    [Console]::Out.Write($Prompt)
    [Console]::ResetColor()
    $raw = Read-Host
    [Console]::CursorVisible = $false
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $v = 0
    if ([int]::TryParse($raw, [ref]$v)) { return $v }
    return $null
}

# ---------------------------------------------------------------------------
# Main Execution
# ---------------------------------------------------------------------------

[Console]::CursorVisible = $false
[Console]::Clear()

# Write session header directly to log file (bypasses Add-Log to avoid
# putting the header lines in the in-memory queue)
if ($null -ne $script:logWriter) {
    $sep = "=" * 60
    $script:logWriter.WriteLine("")
    $script:logWriter.WriteLine($sep)
    $script:logWriter.WriteLine("  Stay Green Session Started: $(Format-DisplayDate ([DateTime]::Now))")
    $script:logWriter.WriteLine("  Log file: $script:logFilePath")
    $script:logWriter.WriteLine($sep)
}

Add-Log "Stay Green initialized" "INFO"
Add-Log "Int=$($script:cfg.IntervalSeconds)s  Thr=$($script:cfg.IdleThresholdSeconds)s  Action=$($script:cfg.Action)" "INFO"
Add-Log "Log: $script:logFilePath" "INFO"

$script:state.NextCheck = [DateTime]::Now.AddSeconds($script:cfg.IntervalSeconds)

# OPT: render timing tracked with Environment.TickCount — Int32 field read,
#      zero allocation, wraps safely after ~49 days
$renderLastTick = [Environment]::TickCount

try {
    while (-not $script:state.QuitFlag) {

        $tickNow = [Environment]::TickCount   # cheap Int32 read

        # ---- Eye animation tick ----
        # OPT: [int] cast ensures unchecked subtraction — handles TickCount
        #      rollover at ~49 days without any extra logic
        if ([int]($tickNow - $script:state.EyeLastUpdateTick) -ge $script:cfg.EyeIntervalMs) {
            $script:state.EyeFrameIndex     = ($script:state.EyeFrameIndex + 1) % $script:EYE_FRAME_COUNT
            $script:state.EyeLastUpdateTick = $tickNow
            $script:state.NeedsRedraw       = $true
        }

        # ---- Render ----
        if ($script:state.NeedsRedraw -or
            [int]($tickNow - $renderLastTick) -ge $script:cfg.RenderIntervalMs) {
            Render-Tui
            $renderLastTick = $tickNow
        }

        # ---- Keyboard input ----
        if ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)

            switch ($k.Key) {
                "S" {
                    $script:state.Running = -not $script:state.Running
                    if ($script:state.Running) {
                        $script:state.NextCheck       = [DateTime]::Now.AddSeconds(1)
                        $script:state.CurrentRunStart = [DateTime]::Now
                        Add-Log "Keep-alive started" "INFO"
                    } else {
                        if ($null -ne $script:state.CurrentRunStart) {
                            $script:state.AccumulatedRunSeconds += ([DateTime]::Now - [DateTime]$script:state.CurrentRunStart).TotalSeconds
                            $script:state.CurrentRunStart = $null
                        }
                        Add-Log "Keep-alive stopped" "INFO"
                    }
                }
                "I" {
                    $v = Read-IntOrNull "Enter interval seconds (1-3600, current $($script:cfg.IntervalSeconds)): "
                    if (Test-ConfigInt $v 1 3600) {
                        $script:cfg.IntervalSeconds = $v
                        Add-Log "Interval -> ${v}s" "INFO"
                    }
                    [Console]::Clear()
                    $script:state.NeedsRedraw = $true
                    Render-Tui
                }
                "T" {
                    $v = Read-IntOrNull "Enter idle threshold seconds (5-7200, current $($script:cfg.IdleThresholdSeconds)): "
                    if (Test-ConfigInt $v 5 7200) {
                        $script:cfg.IdleThresholdSeconds = $v
                        Add-Log "Idle threshold -> ${v}s" "INFO"
                    }
                    [Console]::Clear()
                    $script:state.NeedsRedraw = $true
                    Render-Tui
                }
                "A" {
                    $old = $script:cfg.Action
                    $script:cfg.Action = if ($script:cfg.Action -eq "MouseJiggle") { "F15" } else { "MouseJiggle" }
                    Add-Log "Action: $old -> $($script:cfg.Action)" "INFO"
                }
                "C" {
                    $script:logQ.Clear()
                    Add-Log "Log cleared" "INFO"
                }
                "Q" {
                    Add-Log "Shutting down..." "INFO"
                    Render-Tui
                    # OPT: direct BCL call — skips Start-Sleep cmdlet pipeline overhead
                    [Threading.Thread]::Sleep($script:cfg.ShutdownDelayMs)
                    $script:state.QuitFlag = $true
                }
            }
        }

        # ---- Keep-alive check ----
        # OPT: DateTime.Now only allocated here when actually needed for the
        #      NextCheck comparison, not at the top of every loop iteration
        $now = [DateTime]::Now
        if ($script:state.Running -and $now -ge $script:state.NextCheck) {
            Invoke-KeepAliveAction
            $script:state.NextCheck = $now.AddSeconds($script:cfg.IntervalSeconds)
        }

        # OPT: Thread.Sleep is a direct BCL call vs Start-Sleep which routes
        #      through the PowerShell cmdlet pipeline on every iteration
        [Threading.Thread]::Sleep($script:cfg.LoopSleepMs)
    }
}
finally {
    [Console]::CursorVisible = $true
    [Console]::ResetColor()
    [Console]::Clear()

    $runtime = Format-DurationSeconds (Get-TotalRuntimeSeconds)

    # Flush and close the StreamWriter cleanly
    if ($null -ne $script:logWriter) {
        try {
            $script:logWriter.WriteLine("  Session ended. Total runtime: $runtime")
            $script:logWriter.WriteLine("=" * 60)
            $script:logWriter.Close()
            $script:logWriter.Dispose()
        } catch {}
    }

    $out = [Console]::Out
    [Console]::ForegroundColor = [ConsoleColor]::Green
    $out.WriteLine("Stay Green stopped.")
    [Console]::ForegroundColor = [ConsoleColor]::Cyan
    $out.WriteLine("Total runtime: $runtime")
    [Console]::ForegroundColor = [ConsoleColor]::DarkGray
    $out.WriteLine("Log saved to:  $script:logFilePath")
    [Console]::ResetColor()
}
