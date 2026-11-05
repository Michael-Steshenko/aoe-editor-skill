<#
.SYNOPSIS
    AoE Video Priority & Rescheduling Tool
.DESCRIPTION
    Manages AoE video priorities and YouTube publishing schedules using video_priority.json:
    - Registers newly cut clips with priorities (Default 5 for facecam, 0 for backlog, 6-10 promoted)
    - Verifies live YouTube release statuses and automatically prunes released (public) videos
    - Reorders pending scheduled releases on YouTube so prioritized videos claim prime-time slots and backlog videos are bumped back
    - Updates YouTube video publishAt dates
#>
param(
    [Parameter(Mandatory=$false)]
    [switch]$Apply = $false,

    [Parameter(Mandatory=$false)]
    [switch]$CleanOnly = $false, # Only prune released videos from video_priority.json without rescheduling

    [Parameter(Mandatory=$false)]
    [string]$StartDate = "", # First schedule slot date (YYYY-MM-DD). If omitted, auto-detected.

    [Parameter(Mandatory=$false)]
    [string]$HourUtc = "18:00:00Z", # Release time in UTC (18:00Z = 20:00 local UTC+2)

    [Parameter(Mandatory=$false)]
    [string]$RegisterVideo = "", # Path to newly cut .mp4 to register into priority index

    [Parameter(Mandatory=$false)]
    [string]$YTId = "", # YouTube video ID if registering

    [Parameter(Mandatory=$false)]
    [bool]$HasFacecam = $true, # Whether the registered video has facecam

    [Parameter(Mandatory=$false)]
    [int]$Priority = -1, # Explicit priority override (-1 = auto: 5 if facecam, 0 if no facecam)

    [Parameter(Mandatory=$false)]
    [string]$PriorityFile = "$env:USERPROFILE\Videos\yt-uploader\video_priority.json"
)

$ErrorActionPreference = "Stop"

# Ensure environment variables for yutu
Set-Location -Path "$env:USERPROFILE\Videos"
$env:YUTU_ROOT = "$env:USERPROFILE\Videos"
$env:YUTU_CREDENTIAL = "yt-uploader/client_secrets.json"
$env:YUTU_CACHE_TOKEN = "yt-uploader/youtube.token.json"

# Load or initialize JSON list
$items = @()
if (Test-Path $PriorityFile) {
    $raw = Get-Content -Raw $PriorityFile -Encoding UTF8
    if ($raw.Trim()) {
        $items = @($raw | ConvertFrom-Json | ForEach-Object { $_ })
    }
}

# --- Action: Register Video ---
if ($RegisterVideo) {
    if (-not (Test-Path $RegisterVideo)) {
        Write-Error "Video file not found: $RegisterVideo"
        exit 1
    }

    $fileItem = Get-Item $RegisterVideo
    $fileName = $fileItem.Name
    $hash = (Get-FileHash $fileItem.FullName -Algorithm SHA256).Hash.ToUpper()

    # Determine relative path relative to Videos\aoe or Videos
    $relPath = $fileItem.FullName
    $videosAoe = Join-Path $env:USERPROFILE "Videos\aoe"
    $videosRoot = Join-Path $env:USERPROFILE "Videos"
    if ($relPath.StartsWith($videosAoe, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relPath = $relPath.Substring($videosAoe.Length).TrimStart('\', '/')
    } elseif ($relPath.StartsWith($videosRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relPath = $relPath.Substring($videosRoot.Length).TrimStart('\', '/')
    }

    $session = if ($relPath.Contains('\')) { $relPath.Split('\')[0] } else { "" }
    $prio = if ($Priority -ge 0) { $Priority } elseif ($HasFacecam) { 5 } else { 0 }

    $existing = @($items | Where-Object { $_.Hash.ToUpper() -eq $hash -or $_.FileName -eq $fileName })
    if ($existing.Count -gt 0) {
        foreach ($e in $existing) {
            $e.Priority = $prio
            $e.Facecam = [bool]$HasFacecam
            if ($YTId) { $e.YTId = $YTId }
            $e.RelPath = $relPath
            $e.Session = $session
            Write-Host "Updated registered video: $fileName (Priority: $prio, YTId: $($e.YTId))" -ForegroundColor Cyan
        }
    } else {
        $newEntry = [PSCustomObject]@{
            Priority = $prio
            FileName = $fileName
            Session = $session
            YTId = $YTId
            Facecam = [bool]$HasFacecam
            Hash = $hash
            RelPath = $relPath
        }
        $items += $newEntry
        Write-Host "Registered new video: $fileName (Priority: $prio, YTId: $YTId)" -ForegroundColor Green
    }

    # Save to PriorityFile
    $items | ConvertTo-Json -Depth 4 | Set-Content -Path $PriorityFile -Encoding UTF8

    if (-not $Apply) {
        Write-Host "Video registered successfully in $PriorityFile. Run reorder-aoe-schedule.ps1 to review schedule or -Apply to update YouTube." -ForegroundColor Yellow
        return
    }
}

if ($items.Count -eq 0) {
    Write-Warning "No videos found in $PriorityFile."
    return
}

# --- Dynamic Schedule & Live YouTube Inspection ---
Write-Host "Inspecting live status of scheduled YouTube videos..." -ForegroundColor Cyan
$liveStatusMap = @{}
$allYTIds = @($items | Where-Object { $_.YTId } | ForEach-Object { $_.YTId })

if ($allYTIds.Count -gt 0) {
    # Query in batches of 50
    for ($i = 0; $i -lt $allYTIds.Count; $i += 50) {
        $batch = $allYTIds[$i..([Math]::Min($i + 49, $allYTIds.Count - 1))]
        $batchIds = $batch -join ","
        try {
            $jsonStr = & yutu video list --ids $batchIds --parts status --output json | Out-String
            if ($jsonStr.Trim()) {
                $ytVideos = $jsonStr | ConvertFrom-Json
                foreach ($v in $ytVideos) {
                    $liveStatusMap[$v.id] = $v.status
                }
            }
        } catch {
            Write-Warning "Failed to query live status for batch: $_"
        }
    }
}

# --- Check & Prune Released Videos from Priority Index (Verified on YouTube) ---
$releasedItems = @()
foreach ($item in $items) {
    if ($item.YTId -and $liveStatusMap.ContainsKey($item.YTId)) {
        $st = $liveStatusMap[$item.YTId]
        # Never assume: Only prune if confirmed public by YouTube API
        if ($st.privacyStatus -eq "public") {
            $releasedItems += $item
        }
    }
}

if ($releasedItems.Count -gt 0) {
    Write-Host "`nFound $($releasedItems.Count) video(s) already released (public) on YouTube. Cleaning up from $PriorityFile..." -ForegroundColor Cyan
    $releasedHashes = @($releasedItems | ForEach-Object { $_.Hash.ToUpper() })
    foreach ($rel in $releasedItems) {
        Write-Host "  - Pruned released video: $($rel.FileName) (YTId: $($rel.YTId)) [Live YouTube Status: Public]" -ForegroundColor Green
    }

    # Prune from $items and update PriorityFile
    $items = @($items | Where-Object { $releasedHashes -notcontains $_.Hash.ToUpper() })
    $items | ConvertTo-Json -Depth 4 | Set-Content -Path $PriorityFile -Encoding UTF8
    Write-Host "Priority index cleaned up: $($releasedItems.Count) released video(s) removed.`n" -ForegroundColor Green
} else {
    Write-Host "Live verification: All checked videos remain unreleased (private) on YouTube. Nothing to prune." -ForegroundColor Gray
}

if ($CleanOnly) {
    Write-Host "CleanOnly specified. Exiting without rescheduling." -ForegroundColor Yellow
    return
}

# --- Filter Only Pending Scheduled Videos ---
$nowUtc = [DateTime]::UtcNow
$pendingItems = @()

foreach ($item in $items) {
    if (-not $item.YTId) {
        $pendingItems += [PSCustomObject]@{
            Item = $item
            CurrentPublishAt = $null
            IsPending = $true
        }
        continue
    }

    if ($liveStatusMap.ContainsKey($item.YTId)) {
        $st = $liveStatusMap[$item.YTId]
        if ($st.privacyStatus -eq "public") {
            continue
        }
        if ($st.publishAt) {
            $pubDate = [DateTime]::Parse($st.publishAt).ToUniversalTime()
            if ($pubDate -lt $nowUtc) {
                continue
            }
            $pendingItems += [PSCustomObject]@{
                Item = $item
                CurrentPublishAt = $st.publishAt
                IsPending = $true
            }
            continue
        }
    }

    $pendingItems += [PSCustomObject]@{
        Item = $item
        CurrentPublishAt = $null
        IsPending = $true
    }
}

if ($pendingItems.Count -eq 0) {
    Write-Host "No pending scheduled videos found to reschedule." -ForegroundColor Green
    return
}

# --- Dynamic StartDate Detection ---
if (-not $StartDate) {
    $todaySlotUtc = [DateTime]::new($nowUtc.Year, $nowUtc.Month, $nowUtc.Day, 18, 0, 0, [DateTimeKind]::Utc)
    if ($nowUtc.AddMinutes(30) -ge $todaySlotUtc) {
        $StartDate = $nowUtc.AddDays(1).ToString("yyyy-MM-dd")
    } else {
        $StartDate = $nowUtc.ToString("yyyy-MM-dd")
    }
}

function Get-SortDate([string]$relPath) {
    if (-not $relPath) { return [DateTime]::MinValue }
    $folder = $relPath.Split('\')[0]
    try {
        return [DateTime]::ParseExact($folder, "ddMMMyy", [System.Globalization.CultureInfo]::InvariantCulture)
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
$sortedPending = $pendingItems | Sort-Object -Property @{Expression = { $_.Item.Priority }; Descending = $true}, `
                                                       @{Expression = { Get-SortDate $_.Item.RelPath }; Descending = $false}, `
                                                       @{Expression = { Get-GameNum $_.Item.RelPath }; Descending = $false}

# Compute new schedule dates starting from StartDate
$currentDate = [DateTime]::ParseExact($StartDate, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
$schedulePlan = @()

foreach ($p in $sortedPending) {
    $item = $p.Item
    $dateStr = $currentDate.ToString("yyyy-MM-dd")
    $newPublishAt = "${dateStr}T${HourUtc}"
    
    $status = "UNCHANGED"
    if (-not $p.CurrentPublishAt) {
        $status = "NEW"
    } elseif ($p.CurrentPublishAt -ne $newPublishAt) {
        $status = "MOVE"
    }

    $schedulePlan += [PSCustomObject]@{
        Priority = $item.Priority
        Facecam = if ($item.Priority -gt 0) { "YES" } else { "NO" }
        CurrentPublishAt = $p.CurrentPublishAt
        NewPublishAt = $newPublishAt
        Status = $status
        YTId = $item.YTId
        FileName = $item.FileName
        Session = if ($item.RelPath) { $item.RelPath.Split('\')[0] } else { "Unknown" }
    }
    $currentDate = $currentDate.AddDays(1)
}

Write-Host "`n=== Proposed Video Publishing Schedule ===" -ForegroundColor Cyan
$schedulePlan | Format-Table -Property Priority, Facecam, NewPublishAt, Status, YTId, Session, FileName -AutoSize

$moves = $schedulePlan | Where-Object { $_.Status -ne "UNCHANGED" -and $_.YTId }
$color = if ($moves.Count -gt 0) { "Yellow" } else { "Green" }
Write-Host "Total pending videos: $($schedulePlan.Count) | Updates needed: $($moves.Count)" -ForegroundColor $color

if (-not $Apply) {
    Write-Host "`n[DRY RUN] No changes were made to YouTube." -ForegroundColor Yellow
    Write-Host "Run with -Apply to update YouTube video publish dates." -ForegroundColor Yellow
    return
}

if ($moves.Count -eq 0) {
    Write-Host "`nAll videos are already scheduled with the correct dates! No YouTube updates required." -ForegroundColor Green
    return
}

Write-Host "`nApplying schedule changes to YouTube..." -ForegroundColor Green
if (-not ([System.Management.Automation.PSTypeName]'SystemSleep.PowerHelper').Type) {
    $sig = '[DllImport("kernel32.dll", SetLastError=true)] public static extern int SetThreadExecutionState(int esFlags);'
    Add-Type -MemberDefinition $sig -Name 'PowerHelper' -Namespace 'SystemSleep'
}
[SystemSleep.PowerHelper]::SetThreadExecutionState([int]0x80000001) | Out-Null

try {
    foreach ($entry in $moves) {
        Write-Host "Updating $($entry.YTId) ($($entry.FileName)) -> $($entry.NewPublishAt) [was $($entry.CurrentPublishAt)]"
        & yutu video update --id $entry.YTId --privacy private --publishAt $entry.NewPublishAt --yes
    }
    Write-Host "All schedule updates applied successfully!" -ForegroundColor Green
} finally {
    [SystemSleep.PowerHelper]::SetThreadExecutionState([int]0x80000000) | Out-Null
}
