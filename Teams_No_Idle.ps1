Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Set console encoding to UTF-8 for proper character display
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Native Windows API interop
if (-not ("NativeKeepAlive" -as [type])) {
Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class NativeKeepAlive
{
    [StructLayout(LayoutKind.Sequential)]
    private struct LASTINPUTINFO
    {
        public uint cbSize;
        public uint dwTime;
    }

    [DllImport("user32.dll")]
    private static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, UIntPtr dwExtraInfo);

    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    private const uint MOUSEEVENTF_MOVE = 0x0001;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const int INPUT_DELAY_MS = 10;

    public static uint GetIdleMilliseconds()
    {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));

        if (!GetLastInputInfo(ref lii))
            return 0;

        unchecked
        {
            return (uint)Environment.TickCount - lii.dwTime;
        }
    }

    public static void MouseJiggle()
    {
        mouse_event(MOUSEEVENTF_MOVE, 1, 0, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(INPUT_DELAY_MS);
        mouse_event(MOUSEEVENTF_MOVE, -1, 0, 0, UIntPtr.Zero);
    }

    public static void PressF15()
    {
        const byte VK_F15 = 0x7E;
        keybd_event(VK_F15, 0, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(INPUT_DELAY_MS);
        keybd_event(VK_F15, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    }
}
"@
}

$cfg = [ordered]@{
    IntervalSeconds      = 20
    IdleThresholdSeconds = 50
    Action               = "MouseJiggle"
    MaxLogLines          = 500
    LogViewLines         = 15
    UseUnicodeChars      = $true
    UiWidth              = 76
    RenderIntervalMs     = 500
    LoopSleepMs          = 100
    ShutdownDelayMs      = 500
}

$state = [ordered]@{
    Running               = $false
    NextCheck             = (Get-Date).AddSeconds($cfg.IntervalSeconds)
    LastActionAt          = $null
    ActionCount           = 0
    CurrentRunStart       = $null
    AccumulatedRunSeconds = 0.0
    LastRendered          = ""
    NeedsRedraw           = $true
    QuitFlag              = $false
}

$log = New-Object System.Collections.Generic.List[string]

if ($cfg.UseUnicodeChars) {
    $box = @{
        TL  = [string][char]0x256D  # ╭
        TR  = [string][char]0x256E  # ╮
        BL  = [string][char]0x2570  # ╰
        BR  = [string][char]0x256F  # ╯
        H   = [string][char]0x2500  # ─
        V   = [string][char]0x2502  # │
        DH  = [string][char]0x2550  # ═
        DV  = [string][char]0x2551  # ║
        DTL = [string][char]0x2554  # ╔
        DTR = [string][char]0x2557  # ╗
        DBL = [string][char]0x255A  # ╚
        DBR = [string][char]0x255D  # ╝
        Dot = [string][char]0x25CF  # ●
        Circle = [string][char]0x25CB  # ○
    }
}
else {
    $box = @{
        TL  = "+"
        TR  = "+"
        BL  = "+"
        BR  = "+"
        H   = "-"
        V   = "|"
        DH  = "="
        DV  = "|"
        DTL = "+"
        DTR = "+"
        DBL = "+"
        DBR = "+"
        Dot = "*"
        Circle = "o"
    }
}

function Get-IdleSeconds {
    [Math]::Floor(([NativeKeepAlive]::GetIdleMilliseconds() / 1000.0))
}

function Add-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [string]$Level = "INFO"
    )

    $ts = (Get-Date).ToString("HH:mm:ss")
    $logLine = "[$ts] [$Level] $Message"
    $log.Add($logLine)

    if ($log.Count -gt $cfg.MaxLogLines) {
        $removeCount = $log.Count - $cfg.MaxLogLines
        $log.RemoveRange(0, $removeCount)
    }

    $state.NeedsRedraw = $true
}

function Invoke-KeepAliveAction {
    $idle = Get-IdleSeconds

    if ($idle -lt $cfg.IdleThresholdSeconds) {
        return
    }

    try {
        if ($cfg.Action -eq "MouseJiggle") {
            [NativeKeepAlive]::MouseJiggle()
            Add-Log "Idle ${idle}s >= $($cfg.IdleThresholdSeconds)s -> Mouse jiggle (+/-1px)" "ACTION"
        }
        elseif ($cfg.Action -eq "F15") {
            [NativeKeepAlive]::PressF15()
            Add-Log "Idle ${idle}s >= $($cfg.IdleThresholdSeconds)s -> F15 key press" "ACTION"
        }
        else {
            Add-Log "Unknown action '$($cfg.Action)' - skipped" "WARN"
            return
        }

        $state.LastActionAt = Get-Date
        $state.ActionCount++
        $state.NeedsRedraw = $true
    }
    catch {
        Add-Log "Action failed: $($_.Exception.Message)" "ERROR"
    }
}

function Format-Uptime {
    param([object]$StartTime = $null)

    if ($null -eq $StartTime) {
        return "-"
    }

    $span = (Get-Date) - ([DateTime]$StartTime)
    if ($span.TotalHours -ge 1) {
        return "{0:D2}h {1:D2}m {2:D2}s" -f [int][Math]::Floor($span.TotalHours), $span.Minutes, $span.Seconds
    }
    elseif ($span.TotalMinutes -ge 1) {
        return "{0:D2}m {1:D2}s" -f $span.Minutes, $span.Seconds
    }
    else {
        return "{0}s" -f $span.Seconds
    }
}

function Format-DurationSeconds {
    param([double]$TotalSeconds = 0)

    if ($TotalSeconds -lt 0) {
        $TotalSeconds = 0
    }

    $span = [TimeSpan]::FromSeconds([Math]::Floor($TotalSeconds))
    if ($span.TotalHours -ge 1) {
        return "{0:D2}h {1:D2}m {2:D2}s" -f [int][Math]::Floor($span.TotalHours), $span.Minutes, $span.Seconds
    }
    elseif ($span.TotalMinutes -ge 1) {
        return "{0:D2}m {1:D2}s" -f $span.Minutes, $span.Seconds
    }
    else {
        return "{0}s" -f $span.Seconds
    }
}

function Get-TotalRuntimeSeconds {
    $total = [double]$state.AccumulatedRunSeconds
    if ($null -ne $state.CurrentRunStart) {
        $total += ((Get-Date) - ([DateTime]$state.CurrentRunStart)).TotalSeconds
    }
    return [Math]::Max(0, $total)
}

function Test-ConfigInt {
    param(
        [Nullable[int]]$Value,
        [int]$Min,
        [int]$Max
    )

    if ($null -eq $Value) {
        return $false
    }

    return ($Value -ge $Min -and $Value -le $Max)
}

function Get-StatusBar {
    $now = Get-Date
    $idle = Get-IdleSeconds

    if ($state.Running) {
        $statusIcon = $box.Dot
        $statusText = "RUNNING"
        $statusColor = "Green"
    }
    else {
        $statusIcon = $box.Circle
        $statusText = "STOPPED"
        $statusColor = "Gray"
    }

    return @{
        Icon  = $statusIcon
        Text  = $statusText
        Color = $statusColor
        Idle  = $idle
        Time  = $now.ToString("yyyy-MM-dd HH:mm:ss")
    }
}

function New-SectionHeader {
    param(
        [string]$Title,
        [string]$Left,
        [string]$Right,
        [string]$Fill,
        [int]$InnerWidth
    )
    $label = "$Fill $Title "
    $remaining = $InnerWidth - $label.Length
    if ($remaining -lt 0) { $remaining = 0 }
    return "$Left$label$($Fill * $remaining)$Right"
}

function New-ContentLine {
    param(
        [string]$Text,
        [int]$InnerWidth
    )
    $padded = " $Text"
    if ($padded.Length -gt $InnerWidth) {
        $padded = $padded.Substring(0, $InnerWidth - 3) + "..."
    }
    return "$($box.V)$($padded.PadRight($InnerWidth))$($box.V)"
}

function New-BottomBorder {
    param([int]$InnerWidth)
    return "$($box.BL)$($box.H * $InnerWidth)$($box.BR)"
}

function Build-TuiContent {
    $status = Get-StatusBar

    if ($state.Running) {
        $nextCheckText = $state.NextCheck.ToString("HH:mm:ss")
    }
    else {
        $nextCheckText = "-"
    }

    if ($null -ne $state.LastActionAt) {
        $lastActionText = $state.LastActionAt.ToString("HH:mm:ss")
    }
    else {
        $lastActionText = "-"
    }

    $uptimeText = Format-Uptime $state.CurrentRunStart

    $sb = New-Object System.Text.StringBuilder
    $width = $cfg.UiWidth  # total width including border chars
    $inner = $width - 2  # inner width between border characters

    [void]$sb.AppendLine("$($box.DTL)$($box.DH * $inner)$($box.DTR)")
    $title = "Stay Green Monitor"
    $pad = [Math]::Max(0, $inner - $title.Length)
    $leftPad = [int][Math]::Floor($pad / 2)
    $rightPad = $pad - $leftPad
    [void]$sb.AppendLine("$($box.DV)$(' ' * $leftPad)$title$(' ' * $rightPad)$($box.DV)")
    [void]$sb.AppendLine("$($box.DBL)$($box.DH * $inner)$($box.DBR)")
    [void]$sb.AppendLine("")

    [void]$sb.AppendLine((New-SectionHeader -Title "Status" -Left $box.TL -Right $box.TR -Fill $box.H -InnerWidth $inner))
    [void]$sb.AppendLine((New-ContentLine -Text "Time:   $($status.Time)" -InnerWidth $inner))
    [void]$sb.AppendLine((New-ContentLine -Text "State:  $($status.Icon) $($status.Text)" -InnerWidth $inner))
    [void]$sb.AppendLine((New-ContentLine -Text "Uptime: $uptimeText" -InnerWidth $inner))
    [void]$sb.AppendLine((New-BottomBorder -InnerWidth $inner))
    [void]$sb.AppendLine("")

    [void]$sb.AppendLine((New-SectionHeader -Title "Metrics" -Left $box.TL -Right $box.TR -Fill $box.H -InnerWidth $inner))
    
    if ($status.Idle -ge $cfg.IdleThresholdSeconds) {
        $idleStatus = "(>= threshold)"
    }
    else {
        $idleStatus = ""
    }
    
    [void]$sb.AppendLine((New-ContentLine -Text ("Current idle time:    {0,4}s  {1}" -f $status.Idle, $idleStatus) -InnerWidth $inner))
    [void]$sb.AppendLine((New-ContentLine -Text ("Check interval:       {0,4}s" -f $cfg.IntervalSeconds) -InnerWidth $inner))
    [void]$sb.AppendLine((New-ContentLine -Text ("Idle threshold:       {0,4}s" -f $cfg.IdleThresholdSeconds) -InnerWidth $inner))
    [void]$sb.AppendLine((New-ContentLine -Text ("Action type:          {0}" -f $cfg.Action) -InnerWidth $inner))
    [void]$sb.AppendLine((New-ContentLine -Text ("Next check at:        {0}" -f $nextCheckText) -InnerWidth $inner))
    [void]$sb.AppendLine((New-ContentLine -Text ("Last action at:       {0}" -f $lastActionText) -InnerWidth $inner))
    [void]$sb.AppendLine((New-ContentLine -Text ("Actions performed:    {0}" -f $state.ActionCount) -InnerWidth $inner))
    [void]$sb.AppendLine((New-BottomBorder -InnerWidth $inner))
    [void]$sb.AppendLine("")

    [void]$sb.AppendLine((New-SectionHeader -Title "Controls" -Left $box.TL -Right $box.TR -Fill $box.H -InnerWidth $inner))
    [void]$sb.AppendLine((New-ContentLine -Text "[S] Start/Stop   [I] Interval   [T] Threshold   [A] Action" -InnerWidth $inner))
    [void]$sb.AppendLine((New-ContentLine -Text "[C] Clear Log    [Q] Quit" -InnerWidth $inner))
    [void]$sb.AppendLine((New-BottomBorder -InnerWidth $inner))
    [void]$sb.AppendLine("")

    [void]$sb.AppendLine((New-SectionHeader -Title "Activity Log" -Left $box.TL -Right $box.TR -Fill $box.H -InnerWidth $inner))

    $count = $log.Count
    $take = [Math]::Min($cfg.LogViewLines, $count)
    $start = [Math]::Max(0, $count - $take)

    if ($count -eq 0) {
        [void]$sb.AppendLine((New-ContentLine -Text "(No activity yet)" -InnerWidth $inner))
        $take = 1
    }
    else {
        for ($i = $start; $i -lt $count; $i++) {
            [void]$sb.AppendLine((New-ContentLine -Text $log[$i] -InnerWidth $inner))
        }
    }

    $emptyLine = "$($box.V)$(' ' * $inner)$($box.V)"
    $linesToPad = $cfg.LogViewLines - $take
    for ($i = 0; $i -lt $linesToPad; $i++) {
        [void]$sb.AppendLine($emptyLine)
    }

    [void]$sb.AppendLine((New-BottomBorder -InnerWidth $inner))

    return $sb.ToString()
}

function Show-Tui {
    param([switch]$Force)

    $content = Build-TuiContent

    if ($Force -or $state.NeedsRedraw -or $content -ne $state.LastRendered) {
        [Console]::SetCursorPosition(0, 0)

        $trimmed = $content.TrimEnd([char]13, [char]10)
        $lines = $trimmed -split "`r?`n"

        $consoleWidth = [Console]::WindowWidth
        if ($consoleWidth -lt 1) { $consoleWidth = 80 }

        foreach ($line in $lines) {
            if ($line.Length -ge $consoleWidth) {
                $padded = $line.Substring(0, $consoleWidth)
            }
            else {
                $padded = $line.PadRight($consoleWidth)
            }

            $lineColor = Get-LineColor -Line $line
            if ($null -ne $lineColor) {
                Write-ColoredContentLine -Line $padded -Color $lineColor
            }
            else {
                Write-Host $padded
            }
        }

        $blankLine = " " * $consoleWidth
        $currentY = [Console]::CursorTop
        $windowHeight = [Console]::WindowHeight
        $remaining = $windowHeight - $currentY - 1
        for ($i = 0; $i -lt $remaining; $i++) {
            Write-Host $blankLine
        }

        $state.LastRendered = $content
        $state.NeedsRedraw = $false
    }
}

function Get-LineColor {
    param([string]$Line)

    if ($Line -match "RUNNING") { return "Green" }
    if ($Line -match "STOPPED") { return "Gray" }
    if ($Line -match "\[ACTION\]") { return "Cyan" }
    if ($Line -match "\[WARN\]") { return "Yellow" }
    if ($Line -match "\[ERROR\]") { return "Red" }
    if ($Line -match "Stay Green Monitor") { return "Cyan" }
    if ($Line -match "Status|Metrics|Controls|Activity Log") { return "DarkCyan" }
    return $null
}

function Write-ColoredContentLine {
    param(
        [string]$Line,
        [string]$Color
    )

    $prefix = ""
    $suffix = ""
    $core = $Line

    if ($core.Length -gt 0 -and $core[0] -eq $box.V) {
        $prefix = $box.V
        $core = $core.Substring(1)
    }

    if ($core.Length -gt 0 -and $core[-1] -eq $box.V) {
        $suffix = $box.V
        $core = $core.Substring(0, $core.Length - 1)
    }

    if ($prefix -ne "") {
        Write-Host $prefix -NoNewline
    }

    if ($core -ne "") {
        Write-Host $core -NoNewline -ForegroundColor $Color
    }
    else {
        Write-Host -NoNewline ""
    }

    if ($suffix -ne "") {
        Write-Host $suffix
    }
    else {
        Write-Host ""
    }
}

function Read-IntOrNull {
    param([string]$Prompt)

    [Console]::CursorVisible = $true
    Write-Host ""
    Write-Host $Prompt -NoNewline -ForegroundColor Yellow

    $raw = Read-Host
    [Console]::CursorVisible = $false

    if ([string]::IsNullOrWhiteSpace($raw)) { 
        return $null 
    }

    $val = 0
    if ([int]::TryParse($raw, [ref]$val)) { 
        return $val 
    }
    return $null
}

[Console]::CursorVisible = $false
[Console]::Clear()

Add-Log "Stay Green initialized" "INFO"
Add-Log "Default: Interval=$($cfg.IntervalSeconds)s, Threshold=$($cfg.IdleThresholdSeconds)s, Action=$($cfg.Action)" "INFO"
if (-not $cfg.UseUnicodeChars) {
    Add-Log "Using ASCII-only mode (Unicode disabled)" "INFO"
}

$lastRender = Get-Date

try {
    while (-not $state.QuitFlag) {
        $now = Get-Date

        $timeSinceRender = ($now - $lastRender).TotalMilliseconds
        if ($state.NeedsRedraw -or $timeSinceRender -ge $cfg.RenderIntervalMs) {
            Show-Tui
            $lastRender = $now
        }

        if ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)

            switch ($k.Key) {
                "S" {
                    $state.Running = -not $state.Running
                    if ($state.Running) {
                        $state.NextCheck = (Get-Date).AddSeconds(1)
                        $state.CurrentRunStart = Get-Date
                        Add-Log "Keep-alive started" "INFO"
                    }
                    else {
                        if ($null -ne $state.CurrentRunStart) {
                            $state.AccumulatedRunSeconds += ((Get-Date) - ([DateTime]$state.CurrentRunStart)).TotalSeconds
                            $state.CurrentRunStart = $null
                        }
                        Add-Log "Keep-alive stopped" "INFO"
                    }
                }
                "I" {
                    $v = Read-IntOrNull "Enter interval seconds (1-3600, current $($cfg.IntervalSeconds)): "

                    if (Test-ConfigInt -Value $v -Min 1 -Max 3600) {
                        $cfg.IntervalSeconds = $v
                        Add-Log "Interval changed to $v seconds" "INFO"
                    }
                    else {
                        Add-Log "Interval unchanged (invalid input)" "WARN"
                    }
                    [Console]::Clear()
                    $state.NeedsRedraw = $true
                    Show-Tui -Force
                }
                "T" {
                    $v = Read-IntOrNull "Enter idle threshold seconds (5-7200, current $($cfg.IdleThresholdSeconds)): "

                    if (Test-ConfigInt -Value $v -Min 5 -Max 7200) {
                        $cfg.IdleThresholdSeconds = $v
                        Add-Log "Idle threshold changed to $v seconds" "INFO"
                    }
                    else {
                        Add-Log "Threshold unchanged (invalid input)" "WARN"
                    }
                    [Console]::Clear()
                    $state.NeedsRedraw = $true
                    Show-Tui -Force
                }
                "A" {
                    $oldAction = $cfg.Action
                    if ($cfg.Action -eq "MouseJiggle") {
                        $cfg.Action = "F15"
                    }
                    else {
                        $cfg.Action = "MouseJiggle"
                    }
                    Add-Log "Action changed: $oldAction -> $($cfg.Action)" "INFO"
                }
                "C" {
                    $log.Clear()
                    Add-Log "Log cleared" "INFO"
                }
                "Q" {
                    Add-Log "Shutting down..." "INFO"
                    Show-Tui -Force
                    Start-Sleep -Milliseconds $cfg.ShutdownDelayMs
                    $state.QuitFlag = $true
                }
            }
        }

        # Perform keep-alive check
        if ($state.Running -and $now -ge $state.NextCheck) {
            Invoke-KeepAliveAction
            $state.NextCheck = (Get-Date).AddSeconds($cfg.IntervalSeconds)
        }

        # Small sleep to reduce CPU usage
        Start-Sleep -Milliseconds $cfg.LoopSleepMs
    }
}
finally {
    [Console]::CursorVisible = $true
    [Console]::Clear()
    Write-Host "Stay Green stopped." -ForegroundColor Green
    Write-Host "Total actions performed: $($state.ActionCount)" -ForegroundColor Cyan

    $totalRuntime = Format-DurationSeconds (Get-TotalRuntimeSeconds)
    Write-Host "Total runtime: $totalRuntime" -ForegroundColor Cyan
}