<#
.SYNOPSIS
    AoE Video Priority & Rescheduling Tool
.DESCRIPTION
    Reads video priorities from yt-uploader/video_priority.txt (or video_priority_meta.json),
    sorts scheduled videos by priority (10 = Facecam first, 0 = Backlog last), and updates
    their publishAt dates on YouTube.
#>
param(
    [Parameter(Mandatory=$false)]
    [switch]$Apply = $false,

    [Parameter(Mandatory=$false)]
    [string]$StartDate = "2026-11-05", # First schedule slot date (YYYY-MM-DD)

    [Parameter(Mandatory=$false)]
    [string]$HourUtc = "18:00:00Z", # Release time in UTC (18:00Z = 20:00 local UTC+2)

    [Parameter(Mandatory=$false)]
    [string]$PriorityFile = "$env:USERPROFILE\Videos\yt-uploader\video_priority.txt",

    [Parameter(Mandatory=$false)]
    [string]$MetaFile = "$env:USERPROFILE\Videos\yt-uploader\video_priority_meta.json"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $MetaFile)) {
    Write-Error "Priority metadata file not found: $MetaFile"
    exit 1
}

# Load metadata
$items = Get-Content -Raw $MetaFile | ConvertFrom-Json

# If priority.txt exists, sync any user-modified priorities from text file
if (Test-Path $PriorityFile) {
    $lines = Get-Content $PriorityFile
    foreach ($line in $lines) {
        $line = $line.Trim()
        if (-not $line -or $line.StartsWith("#")) { continue }
        if ($line -match '^(?<file>.+)\s+(?<hash>[a-fA-F0-9]{64})\s+(?<prio>\d+)$') {
            $h = $Matches['hash'].ToUpper()
            $p = [int]$Matches['prio']
            $matched = $items | Where-Object { $_.Hash.ToUpper() -eq $h }
            if ($matched) {
                $matched.Priority = $p
            }
        }
    }
}

function Get-SortDate([string]$relPath) {
    # RelPath like "31Oct26\Game 2..." or "04Nov26\Game 2..."
    $folder = $relPath.Split('\')[0]
    try {
        $d = [DateTime]::ParseExact($folder, "ddMMMyy", [System.Globalization.CultureInfo]::InvariantCulture)
        return $d
    } catch {
        return [DateTime]::MinValue
    }
}

function Get-GameNum([string]$relPath) {
    if ($relPath -match 'Game\s+(\d+)') {
        return [int]$Matches[1]
    }
    return 999
}

# Sort items:
# 1. Priority descending (10 down to 1, then 0 last)
# 2. Chronological date of session
# 3. Game number
$sorted = $items | Sort-Object -Property @{Expression = "Priority"; Descending = $true}, `
                                         @{Expression = { Get-SortDate $_.RelPath }; Descending = $false}, `
                                         @{Expression = { Get-GameNum $_.RelPath }; Descending = $false}

# Compute new schedule dates starting from StartDate
$currentDate = [DateTime]::ParseExact($StartDate, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
$schedulePlan = @()

foreach ($item in $sorted) {
    $dateStr = $currentDate.ToString("yyyy-MM-dd")
    $newPublishAt = "${dateStr}T${HourUtc}"
    $schedulePlan += [PSCustomObject]@{
        Priority = $item.Priority
        Facecam = if ($item.Priority -gt 0) { "YES" } else { "NO" }
        NewPublishAt = $newPublishAt
        YTId = $item.YTId
        FileName = $item.FileName
        Session = $item.RelPath.Split('\')[0]
    }
    $currentDate = $currentDate.AddDays(1)
}

Write-Host "=== Proposed Video Publishing Schedule ===" -ForegroundColor Cyan
$schedulePlan | Format-Table -Property Priority, Facecam, NewPublishAt, YTId, Session, FileName -AutoSize

if (-not $Apply) {
    Write-Host "`n[DRY RUN] No changes were made to YouTube." -ForegroundColor Yellow
    Write-Host "Run with -Apply to update YouTube video publish dates." -ForegroundColor Yellow
    return
}

Write-Host "`nApplying schedule changes to YouTube..." -ForegroundColor Green
$sig = '[DllImport("kernel32.dll", SetLastError=true)] public static extern int SetThreadExecutionState(int esFlags);'
$power = Add-Type -MemberDefinition $sig -Name 'PowerHelper' -Namespace 'SystemSleep' -PassThru
$power::SetThreadExecutionState([int]0x80000001) | Out-Null

try {
    Set-Location -Path "$env:USERPROFILE\Videos"
    $env:YUTU_ROOT = "$env:USERPROFILE\Videos"
    $env:YUTU_CREDENTIAL = "yt-uploader/client_secrets.json"
    $env:YUTU_CACHE_TOKEN = "yt-uploader/youtube.token.json"

    foreach ($entry in $schedulePlan) {
        Write-Host "Updating $($entry.YTId) ($($entry.FileName)) -> $($entry.NewPublishAt)"
        & yutu video update --id $entry.YTId --privacy private --publishAt $entry.NewPublishAt --yes
    }
    Write-Host "All scheduled dates updated successfully!" -ForegroundColor Green
} finally {
    $power::SetThreadExecutionState([int]0x80000000) | Out-Null
}
