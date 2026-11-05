<#
.SYNOPSIS
    AoE Video Priority & Rescheduling Tool
.DESCRIPTION
    Manages AoE video priorities and YouTube publishing schedules:
    - Automatically registers newly cut videos into video_priority.txt and video_priority_meta.json
    - Automatically checks live YouTube scheduled release queue
    - Sorts pending scheduled videos by priority (10 = Facecam first, 0 = Backlog last), session recording date, and game number
    - Automatically bumps/pushes backlog videos back when new facecam videos are added
    - Updates YouTube video publishAt dates
#>
param(
    [Parameter(Mandatory=$false)]
    [switch]$Apply = $false,

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
    [int]$Priority = -1, # Explicit priority override (-1 = auto: 10 if facecam, 0 if no facecam)

    [Parameter(Mandatory=$false)]
    [string]$PriorityFile = "$env:USERPROFILE\Videos\yt-uploader\video_priority.txt",

    [Parameter(Mandatory=$false)]
    [string]$MetaFile = "$env:USERPROFILE\Videos\yt-uploader\video_priority_meta.json"
)

$ErrorActionPreference = "Stop"

# Ensure environment variables for yutu
Set-Location -Path "$env:USERPROFILE\Videos"
$env:YUTU_ROOT = "$env:USERPROFILE\Videos"
$env:YUTU_CREDENTIAL = "yt-uploader/client_secrets.json"
$env:YUTU_CACHE_TOKEN = "yt-uploader/youtube.token.json"

# Load or initialize metadata
$items = @()
if (Test-Path $MetaFile) {
    $items = @(Get-Content -Raw $MetaFile | ConvertFrom-Json | ForEach-Object { $_ })
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

    $prio = if ($Priority -ge 0) { $Priority } elseif ($HasFacecam) { 10 } else { 0 }

    $existing = @($items | Where-Object { $_.Hash.ToUpper() -eq $hash -or $_.FileName -eq $fileName })
    if ($existing.Count -gt 0) {
        foreach ($e in $existing) {
            $e.Priority = $prio
            $e.Facecam = [bool]$HasFacecam
            if ($YTId) { $e.YTId = $YTId }
            $e.RelPath = $relPath
            Write-Host "Updated registered video: $fileName (Priority: $prio, YTId: $($e.YTId))" -ForegroundColor Cyan
        }
    } else {
        $newEntry = [PSCustomObject]@{
            FileName = $fileName
            RelPath = $relPath
            Hash = $hash
            Priority = $prio
            Facecam = [bool]$HasFacecam
            YTId = $YTId
        }
        $items += $newEntry
        Write-Host "Registered new video: $fileName (Priority: $prio, YTId: $YTId)" -ForegroundColor Green
    }

    # Save to MetaFile
    $items | ConvertTo-Json -Depth 4 | Set-Content -Path $MetaFile -Encoding UTF8

    # Sync into PriorityFile text format
    if (Test-Path $PriorityFile) {
        $content = Get-Content $PriorityFile
        $found = $false
        $newContent = @()
        foreach ($line in $content) {
            if ($line -match "^.+$hash\s+\d+") {
                $newContent += "$fileName $hash $prio"
                $found = $true
            } else {
                $newContent += $line
            }
        }
        if (-not $found) {
            $newContent += "$fileName $hash $prio"
        }
        $newContent | Set-Content -Path $PriorityFile -Encoding UTF8
    }

    if (-not $Apply) {
        Write-Host "Video registered successfully. Run reorder-aoe-schedule.ps1 to review schedule or -Apply to update YouTube." -ForegroundColor Yellow
        return
    }
}

if ($items.Count -eq 0) {
    Write-Warning "No videos found in $MetaFile."
    return
}

# Sync any hand-edited priorities from text file
if (Test-Path $PriorityFile) {
    $lines = Get-Content $PriorityFile
    foreach ($line in $lines) {
        $line = $line.Trim()
        if (-not $line -or $line.StartsWith("#")) { continue }
        if ($line -match '^(?<file>.+)\s+(?<hash>[a-fA-F0-9]{64})\s+(?<prio>\d+)$') {
            $h = $Matches['hash'].ToUpper()
            $p = [int]$Matches['prio']
            $matched = @($items | Where-Object { $_.Hash.ToUpper() -eq $h })
            foreach ($m in $matched) {
                $m.Priority = $p
            }
        }
    }
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

# Filter only pending scheduled videos:
# A video is pending if:
# 1. It is private on YouTube with a publishAt timestamp, OR
# 2. It is newly registered with a YTId and not yet published
$nowUtc = [DateTime]::UtcNow
$pendingItems = @()

foreach ($item in $items) {
    if (-not $item.YTId) {
        # Un-uploaded video
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
            # Already published! Skip reordering
            continue
        }
        if ($st.publishAt) {
            $pubDate = [DateTime]::Parse($st.publishAt).ToUniversalTime()
            if ($pubDate -lt $nowUtc) {
                # In the past / published
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

    # If status unknown or newly uploaded private
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
    # 18:00 UTC = 20:00 local time UTC+2
    $todaySlotUtc = [DateTime]::new($nowUtc.Year, $nowUtc.Month, $nowUtc.Day, 18, 0, 0, [DateTimeKind]::Utc)
    if ($nowUtc.AddMinutes(30) -ge $todaySlotUtc) {
        # Less than 30 mins to today's slot or already past; start from tomorrow
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
