<#
.SYNOPSIS
    AoE Match Cutter Helper Script
.DESCRIPTION
    Automates extraction of Age of Empires game clips from full stream/recording sessions.
    Supports frame sampling for analysis, lossless segment cutting with ffmpeg, and date folder derivation.
.NOTES
    This script never deletes, removes, overwrites, or moves raw source recording files.
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$Action = "help", # Action: 'date-folder', 'sample-frames', 'cut-game', 'batch-cut', 'mark-done'
    
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
    [string]$OutputDir
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
    "sample-frames" {
        Sample-Frames $VideoPath $OutputDir $IntervalSeconds
    }
    "cut-game" {
        Cut-Segment $VideoPath $StartTime $EndTime $OutputPath
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
                Write-Host "Generating thumbnail: $thumbPath"
                ffmpeg -hide_banner -loglevel warning -ss $game.thumbnailTimestamp -i $config.videoPath -vframes 1 -q:v 2 -y "$thumbPath"
            }
        }
    }
    default {
        Write-Host "AoE Match Cutter Script"
        Write-Host "Actions: date-folder, sample-frames, cut-game, batch-cut, mark-done"
    }
}
