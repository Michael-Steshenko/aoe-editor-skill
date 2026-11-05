<#
.SYNOPSIS
    AoE Match Cutter Helper Script
.DESCRIPTION
    Automates extraction of Age of Empires game clips from full stream/recording sessions.
    Supports frame sampling for analysis, lossless segment cutting with ffmpeg, zoomed thumbnail extraction, and date folder derivation.
.NOTES
    This script never deletes, removes, overwrites, or moves raw source recording files.
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$Action = "help", # Action: 'date-folder', 'sample-frames', 'cut-game', 'batch-cut', 'thumbnail', 'mark-done'
    
    [Parameter(Mandatory=$false)]
    [string]$VideoPath,
    
    [Parameter(Mandatory=$false)]
    [string]$StartTime,
    
    [Parameter(Mandatory=$false)]
    [string]$EndTime,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath,
    
    [Parameter(Mandatory=$false)]
    [string]$BatchConfig, # Path to JSON file defining games list
    
    [Parameter(Mandatory=$false)]
    [int]$IntervalSeconds = 15,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputDir,

    [Parameter(Mandatory=$false)]
    [string]$Crop, # Explicit crop "W:H:X:Y", e.g. "1600:900:480:270"

    [Parameter(Mandatory=$false)]
    [double]$Zoom = 1.6, # Zoom factor (default 1.6x)

    [Parameter(Mandatory=$false)]
    [int]$FocusX = -1, # Focus center X coordinate (default: center of screen)

    [Parameter(Mandatory=$false)]
    [int]$FocusY = -1  # Focus center Y coordinate (default: center of screen)
)

function Get-AoEDateFolder([string]$filePath) {
    $filename = [System.IO.Path]::GetFileName($filePath)
    if ($filename -match '^(\d{4})-(\d{2})-(\d{2})') {
        $year = $Matches[1]
        $month = [int]$Matches[2]
        $day = [int]$Matches[3]
        $dateObj = Get-Date -Year $year -Month $month -Day $day
        $monthName = $dateObj.ToString("MMM", [System.Globalization.CultureInfo]::InvariantCulture)
        $shortYear = $year.Substring(2, 2)
        $folderName = "{0:D2}{1}{2}" -f $day, $monthName, $shortYear
        return $folderName
    }
    return (Get-Date -Format "ddMMMyy")
}

function Get-AoETargetDir([string]$filePath) {
    $dateFolder = Get-AoEDateFolder $filePath
    $base = Join-Path $env:USERPROFILE "Videos\aoe"
    return (Join-Path $base $dateFolder)
}

function Sample-Frames([string]$video, [string]$outDir, [int]$interval) {
    if (-not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    Write-Host "Sampling frames every $interval seconds from $video to $outDir..."
    $durationStr = ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$video"
    $duration = [double]$durationStr
    for ($s = 0; $s -le $duration; $s += $interval) {
        $idx = [int][math]::Floor($s / $interval) + 1
        $filename = "thumb_" + $idx.ToString("D4") + ".jpg"
        $outFile = Join-Path $outDir $filename
        $ts = [timespan]::FromSeconds($s).ToString("hh\:mm\:ss")
        & ffmpeg -hide_banner -loglevel error -ss $ts -i $video -vframes 1 -q:v 3 -vf "scale=1280:-1" -y $outFile
    }
    Write-Host "Frame sampling complete."
}

function Cut-Segment([string]$video, [string]$start, [string]$end, [string]$outputFile) {
    $parent = [System.IO.Path]::GetDirectoryName($outputFile)
    if ($parent -and (-not (Test-Path $parent))) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Write-Host "Cutting clip: $video [$start -> $end] to $outputFile"
    ffmpeg -hide_banner -loglevel warning -ss $start -to $end -i $video -c copy -avoid_negative_ts make_zero -y "$outputFile"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Successfully generated: $outputFile"
    } else {
        Write-Error "FFmpeg cut failed with exit code $LASTEXITCODE"
    }
}

function Extract-ZoomedThumbnail(
    [string]$video,
    [string]$timestamp,
    [string]$outputFile,
    [string]$cropFilter = "",
    [double]$zoomFactor = 1.6,
    [int]$fx = -1,
    [int]$fy = -1
) {
    $parent = [System.IO.Path]::GetDirectoryName($outputFile)
    if ($parent -and (-not (Test-Path $parent))) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    # Probe source resolution
    $dimStr = ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$video"
    $srcW = 2560
    $srcH = 1440
    if ($dimStr -match '^(\d+)x(\d+)') {
        $srcW = [int]$Matches[1]
        $srcH = [int]$Matches[2]
    }

    $vf = ""
    if ($cropFilter) {
        $vf = "crop=$cropFilter,scale=${srcW}:${srcH}:flags=lanczos,eq=saturation=1.20:contrast=1.08"
    } else {
        $z = if ($zoomFactor -gt 1.0) { $zoomFactor } else { 1.6 }
        $cropW = [int][Math]::Round($srcW / $z)
        $cropH = [int][Math]::Round($srcH / $z)
        if ($cropW % 2 -ne 0) { $cropW-- }
        if ($cropH % 2 -ne 0) { $cropH-- }

        $centerX = if ($fx -ge 0) { $fx } else { [int]($srcW / 2) }
        $centerY = if ($fy -ge 0) { $fy } else { [int]($srcH / 2) }

        $x = [int][Math]::Round($centerX - ($cropW / 2))
        $y = [int][Math]::Round($centerY - ($cropH / 2))

        # Clamp within video boundaries
        if ($x -lt 0) { $x = 0 }
        if ($y -lt 0) { $y = 0 }
        if ($x + $cropW -gt $srcW) { $x = $srcW - $cropW }
        if ($y + $cropH -gt $srcH) { $y = $srcH - $cropH }

        # Avoid facecam overlay (typically left side x <= 390, y >= 890 at 1440p)
        if ($srcW -eq 2560 -and $srcH -eq 1440) {
            if ($x -lt 400 -and ($y + $cropH) -gt 880) {
                $x = 400
            }
            # Avoid score panel (typically lower right x >= 2100, y >= 1000 at 1440p)
            if (($x + $cropW) -gt 2100 -and ($y + $cropH) -gt 1000) {
                $x = [Math]::Max(0, 2100 - $cropW)
            }
        }

        $vf = "crop=${cropW}:${cropH}:${x}:${y},scale=${srcW}:${srcH}:flags=lanczos,eq=saturation=1.20:contrast=1.08"
    }

    Write-Host "Extracting zoomed thumbnail ($timestamp): $outputFile with vf='$vf'"
    & ffmpeg -hide_banner -loglevel warning -ss $timestamp -i "$video" -vframes 1 -update 1 -vf "$vf" -y "$outputFile"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Thumbnail saved successfully: $outputFile"
    } else {
        Write-Error "FFmpeg thumbnail extraction failed with exit code $LASTEXITCODE"
    }
}

function Mark-Completed([string]$filePath) {
    if (-not (Test-Path $filePath)) {
        Write-Error "File not found: $filePath"
        return
    }
    $item = Get-Item $filePath
    if ($item.BaseName -like "*- aoe-editor-done") {
        Write-Host "File is already marked as completed: $($item.Name)"
        return $item.FullName
    }
    $newName = "$($item.BaseName) - aoe-editor-done$($item.Extension)"
    $renamed = Rename-Item -Path $item.FullName -NewName $newName -PassThru
    Write-Host "Marked source recording as completed: $($renamed.FullName)"
    return $renamed.FullName
}

switch ($Action.ToLower()) {
    "date-folder" {
        Get-AoEDateFolder $VideoPath
    }
    "target-dir" {
        Get-AoETargetDir $VideoPath
    }
    "sample-frames" {
        Sample-Frames $VideoPath $OutputDir $IntervalSeconds
    }
    "cut-game" {
        Cut-Segment $VideoPath $StartTime $EndTime $OutputPath
    }
    "thumbnail" {
        Extract-ZoomedThumbnail -video $VideoPath -timestamp $StartTime -outputFile $OutputPath -cropFilter $Crop -zoomFactor $Zoom -fx $FocusX -fy $FocusY
    }
    "mark-done" {
        Mark-Completed $VideoPath
    }
    "batch-cut" {
        if (-not (Test-Path $BatchConfig)) {
            Write-Error "Batch config file not found: $BatchConfig"
            exit 1
        }
        $config = Get-Content -Raw $BatchConfig | ConvertFrom-Json
        foreach ($game in $config.games) {
            Cut-Segment $config.videoPath $game.start $game.end $game.outputPath
            if ($game.thumbnailTimestamp) {
                $thumbPath = if ($game.thumbnailPath) { $game.thumbnailPath } else { [System.IO.Path]::ChangeExtension($game.outputPath, ".png") }
                $gameZoom = if ($game.zoom) { [double]$game.zoom } else { 1.6 }
                $gameCrop = if ($game.crop) { $game.crop } else { "" }
                $gameFx = if ($game.focusX) { [int]$game.focusX } else { -1 }
                $gameFy = if ($game.focusY) { [int]$game.focusY } else { -1 }
                Extract-ZoomedThumbnail -video $config.videoPath -timestamp $game.thumbnailTimestamp -outputFile $thumbPath -cropFilter $gameCrop -zoomFactor $gameZoom -fx $gameFx -fy $gameFy
            }
        }
    }
    default {
        Write-Host "AoE Match Cutter Script"
        Write-Host "Actions: date-folder, target-dir, sample-frames, cut-game, batch-cut, thumbnail, mark-done"
    }
}
