---
name: aoe-editor
description: Full end-to-end Age of Empires video editing and publishing workflow. Detects and cuts session recordings into individual game clips in date subfolders, extracts age transition chapters, keeps post-game analysis, trims queues/idle, discards games under 7 minutes while maintaining original numbering, flags one-sided games for review, generates authentic custom YouTube thumbnails matching each video's filename with optional unit meme edits, dynamically inspects YouTube schedule queues, assigns videos to 1v1 and Team Game playlists, preserves source files, and marks completed session recordings by appending ' - aoe-editor-done' before the file extension.
---

# AoE Editor

Use this skill to process long Age of Empires (AoE) gameplay recording sessions into clean, standalone match clips, generate authentic YouTube thumbnails, and manage scheduled YouTube uploads.

## Strict Safety & Security Guardrails

### 1. Source Recording Preservation & Completion Marking
> [!IMPORTANT] **NEVER DELETE SOURCE RECORDINGS — MARK COMPLETED FILES WITH `- aoe-editor-done`**
> Under NO circumstances should the agent ever delete, remove, or overwrite the original source recording files (e.g. in `$env:USERPROFILE\Videos\`).
> - **Source Remains Untouched During Processing**: Even after clips are successfully extracted, reviewed, or uploaded to YouTube, original session footage must **never be deleted**.
> - **Renaming Upon Completion (` - aoe-editor-done`)**: Once all games from a source recording have finished being edited, sliced, verified, and saved to the target date folder, the source file **MUST be renamed by appending ` - aoe-editor-done` before its extension**:
>   - *Example (`.mp4`)*: `2026-10-27 20-35-29.mp4` -> `2026-10-27 20-35-29 - aoe-editor-done.mp4`
>   - *Example (any extension)*: `<filename>.<ext>` -> `<filename> - aoe-editor-done.<ext>`
>   - *PowerShell command*:
>     ```powershell
>     $item = Get-Item "<SourcePath>"
>     Rename-Item -Path $item.FullName -NewName "$($item.BaseName) - aoe-editor-done$($item.Extension)"
>     ```
> - **Skip Already Completed Files**: When scanning or identifying session recordings to process, always ignore and skip any file that already has `- aoe-editor-done` before its extension.
> - **Discarded Games**: For games that are skipped or discarded (e.g., duration < 7 minutes), simply skip extracting that segment. Never cut, truncate, or delete anything from the source video.
> - **Temporary Cleanup Only**: Only temporary scratch files (such as sample frame JPEGs in a temporary/scratch folder) may be cleaned up. Never delete source video files.

### 2. Strict Security & Credential Protection
> [!CAUTION] **NEVER READ CREDENTIALS OR TOKEN FILES**
> Under NO circumstances should the agent ever read, view, display, or inspect the contents of any credential files, secrets, or tokens.
> - **Zero Inspection**: Specifically, NEVER read, inspect, cat, print, or output any files inside `$env:USERPROFILE\Videos\yt-uploader\` (such as `request.token`, `youtube.token.json`, `client_secrets.json`, or any `*.token` / `*.json` credential files).
> - **Execution Only**: When executing `yutu`, only invoke it with environment variables (`YUTU_CREDENTIAL`, `YUTU_CACHE_TOKEN`) and command line flags. Never inspect or output the tokens or secrets it reads.

### 3. Sleep Prevention During Unattended Processing (Native Keep-Awake)
To allow the workflow to run completely unattended (detecting, cutting clips, rendering thumbnails, or uploading batches to YouTube) while letting the user's display turn off or sleep naturally:
- **Default Method (Native Windows API - Screen Can Sleep)**: Use Windows `SetThreadExecutionState` with `ES_CONTINUOUS | ES_SYSTEM_REQUIRED` (`0x80000001`). This informs Windows that background processing/uploading is active, guaranteeing the CPU, disk, and network **never go to sleep**, while allowing monitors to turn off or sleep per normal Windows power settings:
  ```powershell
  $sig = '[DllImport("kernel32.dll", SetLastError=true)] public static extern int SetThreadExecutionState(int esFlags);'
  $power = Add-Type -MemberDefinition $sig -Name 'PowerHelper' -Namespace 'SystemSleep' -PassThru
  # Prevent system sleep (allows display to sleep)
  $power::SetThreadExecutionState([int]0x80000001)
  ```
- **Releasing the Sleep Lock**: Once all batch tasks or uploads are completed, reset execution state back to default continuous mode:
  ```powershell
  $power::SetThreadExecutionState([int]0x80000000)
  ```
- **Alternative (Caffeine)**: Caffeine is installed at `caffeine64.exe`. Because Caffeine simulates keyboard input every 59s, it will prevent display sleep unless the monitor is physically turned off. Use the native method above as the standard.
- **Recommended Durations / Usage**:
  - Keep active for the duration of the batch job (especially uploads, which can take 1–3 hours for 6–8 GB of video), and release immediately upon completion.

---

## Destination Folder Structure

All processed games and thumbnails are saved under the `aoe` directory inside a date-formatted subfolder derived from the recording filename:

```text
$env:USERPROFILE\Videos\aoe\<DDMmmYY>\
  ├── Game 1 - <MyCiv> vs <OpponentCiv> (<Map> - <Result>).mp4
  ├── Game 1 - <MyCiv> vs <OpponentCiv> (<Map> - <Result>).png       # Thumbnail matching video name exactly
  ├── Game 3 - <MyTeamCivs> vs <OpponentCivs> (<Map> - <Result>).mp4 # (e.g. Game 2 was <7m discarded)
  ├── Game 3 - <MyTeamCivs> vs <OpponentCivs> (<Map> - <Result>).png
  └── ...
```

### Date Folder Rule
- Date is parsed from the video filename: `YYYY-MM-DD ...`
  - Example: `2026-10-27 20-35-29.mp4` -> `27Oct26`
  - Example: `2026-10-29 19-46-42.mp4` -> `29Oct26`
  - Format: `<Day><3-letter Month><2-digit Year>` (e.g., `13Oct26`, `27Oct26`, `29Oct26`).

---

## Game Filtering & Duration Rules

1. **Short Games Under 7 Minutes (Auto-Discard / Skip Export)**:
   - Any game with an in-game duration **under 7 minutes** (e.g., early resign, disconnect, failed start) must be **skipped from export** (not extracted or saved as an output clip). Do NOT delete, truncate, or modify any part of the original source video.
   - **Chronological Numbering Preservation**: Discarded games **still consume their chronological number** from the recording session.
     - *Example*: If Game 1 is 18m, Game 2 is 2m (discarded), and Game 3 is 25m, the resulting output files will be `Game 1 - ...` followed by `Game 3 - ...`. Game 2 is skipped in the file list so the numbers accurately reflect the original match sequence.

2. **One-Sided / Boring Games (Cut & User Review)**:
   - If a game appears heavily one-sided or boring (e.g., massive early score runaway, minimal resistance/engagements, uncompetitive stomp):
     - **Cut and save the game** to the date folder as normal so local footage is preserved.
     - **Prompt the user**: Notify the user with the clip details, timestamp, and why it felt one-sided/boring. Ask the user to review the clip before deciding if it should be queued for YouTube upload.

---

## Game Detection & Trimming Rules

1. **Clip Start Point**:
   - Begin right when the loading screen transitions to the game start (town center and starting units appear).

2. **Clip End Point & Post-Game Analysis**:
   - **Keep Post-Game Analysis**: If the player reviews the post-game achievements screens (Summary, Military, Economy, Technology, Society) or watches a replay analysis, keep this in the game video clip.
   - The clip ends when the player leaves the post-game screen / replay back to the main menu or queue.

3. **What to Cut Out**:
   - Matchmaking queue times.
   - Lobby waiting and civ drafting countdown screens.
   - Any idle time, desktop browsing, or away-from-keyboard (AFK) segments.

---

## Strict Naming Conventions

### 1. Local Video & Thumbnail Filenames (`.mp4` / `.png`)
Local files on disk are named for local tracking, archiving, and match chronology:
- **Game Number**: The chronological match index from the session (`Game 1`, `Game 2`, etc.), preserving skipped numbers for <7m discarded matches.
- **Civilizations**:
  - 1v1: `Game <N> - <MyCiv> vs <OpponentCiv> (<Map> - <Result/Notes>).mp4`
    - Example: `Game 1 - Ethiopians vs Franks (Arabia - Win).mp4`
  - Team: `Game <N> - <MyTeamCivs> vs <OpponentCivs> (<Map> - <Result/Notes>).mp4`
    - Example: `Game 3 - Khmer and Franks vs Persians and Bohemians (Arena - Win).mp4`
- **Thumbnail Filename**: Must match the `.mp4` filename character-for-character, swapping `.mp4` to `.png`.

### 2. YouTube Video Titles (Uploaded to YouTube via `-title` / `-metaJSON`)
> [!IMPORTANT] **YOUTUBE TITLES: NO WIN/LOSS SPOILERS & NO GAME NUMBERS**
> Titles published to YouTube must NEVER spoil the match outcome and must NEVER include session game numbers:
> - **DO NOT include `Win` or `Loss`**: Never spoil the match outcome for the audience.
> - **DO NOT include `Game 1`, `Game 2`, etc.**: Viewers on YouTube browse standalone matches, not raw session indices.
> - **Standard YouTube Title Syntax**:
>   `<MyTeamCivs> vs <OpponentCivs> AOE2 <MatchFormat> <Map>`
>   - **1v1 Format**:
>     `<MyCiv> vs <OpponentCiv> AOE2 1v1 <Map>`
>     - *Example*: `Khmer vs Bohemians AOE2 1v1 Arena`
>     - *Example*: `Dravidians vs Tatars AOE2 1v1 Arabian Desert`
>     - *Example*: `Ethiopians vs Franks AOE2 1v1 Arabian Desert`
>   - **2v2 Format**:
>     `<Civ1> & <Civ2> vs <Civ3> & <Civ4> AOE2 2v2 <Map>`
>     - *Example*: `Khmer & Franks vs Persians & Bohemians AOE2 2v2 Arena`
>     - *Example*: `Khmer & Bengalis vs Malians & Mongols AOE2 2v2 Arena`
>   - **3v3 Format**:
>     `<Civ1>, <Civ2> & <Civ3> vs <Civ4>, <Civ5> & <Civ6> AOE2 3v3 <Map>`
>     - *Example*: `Khmer, Bohemians & Goths vs Ethiopians, Romans & Celts AOE2 3v3 Arena`
>   - **4v4 Format**:
>     `<Civ1>, <Civ2>, <Civ3> & <Civ4> vs <Civ5>, <Civ6>, <Civ7> & <Civ8> AOE2 4v4 <Map>`
>     - *Example*: `Ethiopians, Franks, Britons & Mayans vs Mongols, Tatars, Turks & Persians AOE2 4v4 Black Forest`

---

## Authentic Thumbnail & Dynamic Meme Guidelines (<VideoName>.png)

> [!IMPORTANT] **THUMBNAIL FILENAME MUST MATCH VIDEO FILENAME**
> The thumbnail filename for each video must **match the video filename exactly** (swapping the extension to `.png`):
> - Video: `Game 1 - Ethiopians vs Franks (Arabia - Win).mp4`
> - Thumbnail: `Game 1 - Ethiopians vs Franks (Arabia - Win).png`
> - Video: `Game 3 - Khmer and Franks vs Persians and Bohemians (Arena - Win).mp4`
> - Thumbnail: `Game 3 - Khmer and Franks vs Persians and Bohemians (Arena - Win).png`

Avoid deceptive clickbait or repetitive single-meme tropes. Ground the thumbnail in what actually happened, keeping meme edits varied, organic, and fitting to the match story:

### 1. High-Impact Thumbnail Styling & Typography
Design bold, high-contrast typography optimized for mobile feed legibility:
- **Large & Punchy Text**: Font size must be large and immediately legible on mobile feeds (`fontsize=140` to `160` for 1440p, scaled for other resolutions). Never use small, low-contrast text (<100).
- **Thick Outlines & Drop Shadows**: Use a heavy black border (`borderw=8` to `12`) and shadow (`shadowx=4:shadowy=4:shadowcolor=black`) so text pops against any background.
- **Two-Tone & Multi-Color Text Styling**: Do not default to plain single white text. Use contrasting, vibrant colors across words/lines:
  - Top word in White (`#FFFFFF`), Bottom/Punchline word in Vibrant Gold/Yellow (`#FFD700` or `#FFE500`) or Orange (`#FF8C00`).
  - Example two-tone layouts:
    - `"LETS STEAL" (White) / "SOME GOLD!" (Yellow)`
    - `"OUTPOST" (White) / "REVENGE!" (Orange)`
    - `"CASTLE" (White) / "MELTERS" (Yellow)`
    - `"WHY MAKE" (White) / "THESE?!" (Orange)`
    - `"SCORPION" (White) / "DEATHBALL" (Yellow)`
    - `"CELT SIEGE" (Yellow) / "UNSTOPPABLE" (White)`
- **Dynamic & Flexible Text Placement (Strict Subject Clearance)**:
  - > [!IMPORTANT] **TEXT MUST NEVER COVER FOCAL UNITS OR SUBJECTS**
  - The text overlay must **NEVER cover, occlude, or sit on top of the focal units, buildings, or tactical event** named in the hook (e.g. if the hook says `"SIEGE ELEPHANT BREACH"`, the siege elephants must remain 100% visible and unobstructed by the text).
  - Place text strictly where it does NOT cover the action (in open negative space, fog of war, or empty terrain).
  - Check where units and fighting are situated on screen and dynamically position text across top-center, top-left, top-right, or bottom-center so the focal action and subject units remain completely unblocked.

### 2. Action Frame Selection & Visual-Text Substantiation
- **Zero Idle Base Frames**: NEVER select a frame where the camera is panned back over peaceful home farms, town centers, or economic queues while action occurs elsewhere.
- **Active Combat & Attacking in Progress (NEVER Post-Fight Aftermath or Empty Ruins)**:
  - The frame MUST capture **live, active fighting or an attack in progress**: units actively clashing in melee, shooting arrows, firing siege projectiles, raiding an eco, or assaulting an enemy base/castle.
  - **NO Empty Static Ruins**: NEVER pick a frame of broken walls or battered buildings where **no enemy units are actively attacking or present**. Broken walls with no active troops look abandoned, static, and uninteresting.
  - **NO Post-Fight Aftermath (Bodies on Floor)**: NEVER pick a frame taken after the fight has already concluded, showing only dead corpses/bodies on the floor with remaining units standing idle. Capture the action **during the fight**, not after.
- **NO Outcome Leaks or Score Spoilers**:
  - The thumbnail must **NEVER reveal the match outcome**:
    - NEVER capture frames showing `"Player X resigned"` in chat or crossed-out player names in the score box.
    - **NO Score Disparity / Overrun Base Leaks**: NEVER choose a frame where the lower-right score box displays a massive score deficit (e.g. player at 70–75% of opponent's score) while the player's base is in ruins/being raided. This blatantly leaks a loss to the viewer and ruins suspense. Keep the score and board state ambiguous or cropped/clean.
  - All thumbnail frames MUST be captured during **active, tense, competitive gameplay**.
- **Face Cam Expression Quality Guardrail**:
  - If the recording features a webcam / face cam overlay:
    - **Inspect Face Cam Carefully**: Never choose a frame where the creator has an awkward, weird, or unflattering expression (e.g. mid-blink, eyes half-closed, mouth awkwardly open mid-word, yawning, looking away).
    - Ensure the face cam displays a clean, focused, hyped, laughing, or naturally engaged expression.
- **Hook Uniqueness Across All Past Videos (`previous_hooks.txt`)**:
  - Always read and check `$env:USERPROFILE\Videos\yt-uploader\previous_hooks.txt` before selecting or rendering a thumbnail hook.
  - This persistent text file is the **sole memory of all previous hooks**, allowing past video clips to be deleted from disk without losing hook history.
  - **Never duplicate an existing hook phrase** from `previous_hooks.txt`.
  - **Always append new hooks** to `$env:USERPROFILE\Videos\yt-uploader\previous_hooks.txt` whenever new thumbnails are finalized.
- **Visual Must Substantiate the Text Hook**:
  - The visual frame must **directly show what the hook claims**. Never make a claim in the text that isn't prominently visible in the frame:
    - If the hook is `"CASTLE DENIED!"`: The denied/failing castle foundation, dead builders, or defensive towers/units shutting it down **MUST be clearly visible on screen**.
    - If the hook is `"WHY IS THERE A HOLE?!"` or `"WALL BREACHED!"`: The actual gap in the wall with enemy units running through **MUST be clearly visible on screen**.
    - If a specific unit is referenced (e.g. `"STEPPE LANCERS"`, `"ELEPHANT ARCHER"`): Those exact units must be actively visible on screen in combat without text covering them.
- **Frontline Engagements & Active Combat**:
  - Avoid wide empty landscapes with buildings in fog/distance and no units clashing.
  - Always locate the actual combat / tactical focal point (clashing army deathballs, raids actively slicing into eco, forward castles under active assault).

### 3. Match Story, Core Strategy & Tactical Specificity
- **Accurate Unit Naming (NO Nonsensical Civ Adjectives)**:
  - Civilization adjectives apply **ONLY to real unique units or unique technologies** (e.g., Italians have *Genoese Crossbowmen*; trebuchets are a generic Imperial Age siege weapon, so calling them *"Genoese Trebuchets"* makes no sense).
  - Never attach civ names as adjectives to generic units unless grammatically and factually accurate to the game.
- **Avoid Mundane / Routine Siege — Highlight High-Stakes Dramatic Events**:
  - Routine occurrences (such as 4 standard trebuchets firing at a castle) are ordinary AoE2 gameplay and are not special or unique.
  - Center thumbnails on truly memorable, catastrophic, or distinct turns:
    - Teammate losing their entire base / getting flattened / overrun (`"TEAMMATE BASE / WIPED OUT!"`, `"TEAMMATE / OVERRUN!"`).
    - Catastrophic base collapses, massive forward castle rushes, dramatic multi-front reversals, or game-deciding economy wipes.
- **Highlight the Defining Match Dynamic & Proactive Strategy**:
  - Identify what made the match truly unique or what core strategy the player committed to:
    - **Protracted Feudal Wars**: If a game is an extended, 20-minute Feudal Age bloodbath on Steppe/Arabia, focus on that defining dynamic (`"ENDLESS FEUDAL / WAR!"`, `"FEUDAL AGE / FOREVER?!"`).
    - **Core Offensive Strategy vs Endgame Collapse**: If the player committed to an all-in strategy like a Donjon rush with massed Serjeants, highlight the proactive game plan (`"ALL IN / DONJONS!"`, `"DONJON / SPAM!"`), rather than a brief defensive collapse during the final moments of the game.
    - Always represent the core identity and strategic drive of the match.
- **Authentic AoE2 Community Terminology vs Unremarkable Labels**:
  - Do NOT label standard generic buildings with a civ name as if they are unique (e.g., "Chinese Castle" is unremarkable—a castle is just a standard castle regardless of civ skin).
  - Use authentic AoE2 community terminology when describing tactical situations:
    - `"TREB WAR"`: Trebuchets duel-firing against castles or each other from opposite sides.
    - `"CASTLE DROP"`, `"TRUSH"`, `"FAST IMP"`, `"SMUSH"`, `"CROSSFIRE"`, `"DOUCHING"`, `"RELIC HEIST"`.
    - Prioritize truly unique match dynamics first; fall back to common tactical tropes like a "Treb War" only if no more defining story occurred in the match.
- **Avoid Generic Map Features (Focus on Distinct Match Narrative)**:
  - Do NOT frame hooks around ordinary or baseline map expectations (e.g., framing a Black Forest game around "Chokepoint Lockdown" or "Walling", which is standard for that map).
  - Center hooks on the unique tactical or human story that made the game memorable (e.g., `"THEY GANGED UP / ON MY TEAMMATE!"`, `"HE WENT / TOO ALL IN!"`, `"CLUTCH CONVERSION!"`).
  - Distinguish genuine playstyles: Do not label standard defensive towers or early aggressive rushes as "Tower Defense" unless the strategy was an actual dedicated tower defense / trush build.
- **Precise Unit Naming (No Ambiguous Terms)**:
  - Be specific with unit variants. Do NOT use generic terms when specific variants are being used:
    - In AoE II, generic "Elephant" implies melee Battle Elephants. When Elephant Archers are carrying, explicitly specify `"ELEPHANT ARCHER"` (e.g. `"ELEPHANT ARCHER RAMPAGE!"`). Similarly distinguish Ballista Elephants, Armored Elephants, and Siege Elephants.
- **Early Abandons vs Tactical Defeats**:
  - Frame hooks around teammate abandons only when an ally prematurely resigns or disconnects without mutual agreement while the match is still contested.
  - When the team mutually concedes with 'gg', frame the hook around the tactical defeat (e.g. `"FORWARD CASTLE!"`, `"SIEGE OVERRUN!"`, `"CASTLE DROP!"`).

### 4. Contextual Unit Highlight & Dynamic Meme Edits
- **When a unit carries the game**: Give it a humorous, varied triumph/dominance meme treatment (sunglasses, crown, glowing aura, "carrying the team" framing, arrows). Rotate styles dynamically across games.
- **When a unit flops or fails**: Apply a fitting disappointed/humorous meme edit (facepalm energy, sad unit expressions, clown vibes, "this is fine").
- **Natural & Balanced**: If a clean, intense civ clash or forward siege communicates the story best, rely on the raw gameplay frame with bold two-tone typography without sticker edits.

### 5. Visual Polish & Vibrance Boost
- Boost saturation (+18-25%) and contrast (+5-10%) so player colors (blue, red, yellow, green) stand out brightly on mobile.
- Clean 16:9 1440p (2560x1440) or 1080p resolution.

---

## YouTube Video Descriptions, Chapters & Game Title

### 1. YouTube Video Description & Fluid Gameplay Chapters
Every uploaded video must include the standard gameplay description followed by fluid, timestamped chapters marking baseline age transitions alongside notable match highlights, tactical turning points, and memorable blunders (relative to the cut game start, starting with `00:00`):

- **Baseline Age Transitions (Clean & Standard)**:
  - `00:00 Dark Age`
  - `<MM:SS> Feudal Age`
  - `<MM:SS> Castle Age`
  - `<MM:SS> Imperial Age` (if reached)
  - `<MM:SS> GG & Post-Game Analysis` (achievements & stats screens)

- **Fluid Event & Story Markers (Insert Notable Moments as They Occur)**:
  - Weave in markers whenever something noteworthy, funny, or decisive happens:
    - **Blunders & Memes**: `Vil Lost to Boar`, `Accidental TC Delete`, `Scout Trapped`, `Loom Forgotten`, `Bad Mangonel Shot`
    - **Tactical Turning Points**: `Hole in the Wall!`, `Forward Castle Drop`, `Castle Denied!`, `Castle Age Push`, `Monk Relic Heist`, `Deathball Engagement`, `Flank Overrun`, `Last Stand`
  - *Keep markers chronological, minimum 10 seconds apart per YouTube chapter requirements.*

- **Example Description with Fluid Chapters**:
```text
Age of Empires II: Definitive Edition gameplay.

Chapters:
00:00 Dark Age
03:45 Vil Lost to Boar
10:15 Feudal Age
13:30 Hole in the Wall!
21:10 Castle Age
24:50 Forward Castle Drop
31:40 Imperial Age
34:15 Decisive Push
37:50 GG & Post-Game Analysis
```

### 2. YouTube Game Title & Category
For all uploaded videos:
- **Category**: Gaming (`categoryId: 20`)
- **Game Title**: `Age of Empires II: Definitive Edition`
Always ensure the Game Title metadata in YouTube (under the Gaming category in YouTube Studio / upload metadata) is set to `Age of Empires II: Definitive Edition`.

---

## YouTube Playlist Assignment (1v1s & Team Games)

All uploaded videos must be immediately assigned to their dedicated playlist based on match format:
- **1v1 Matches**: Add to `AOE2 1v1s`
  - **Playlist ID**: `<Your1v1PlaylistID>`
- **Team Game Matches (2v2, 3v3, 4v4)**: Add to `AOE2 team games`
  - **Playlist ID**: `<YourTeamPlaylistID>`
- **Channel ID**: `<YourChannelID>`

### Playlist Insertion Command (`yutu`):
```powershell
& "yutu" playlistItem insert `
  --kind video `
  --playlistId "<PlaylistID>" `
  --channelId "<YourChannelID>" `
  --kVideoId "<VideoID>" `
  --yes
```

---

## YouTube Upload Scheduling & Dynamic Queue Inspection

### 1. Dynamic Schedule Queue Inspection (Live YouTube API)
> [!IMPORTANT] **ALWAYS INSPECT LIVE SCHEDULE QUEUE BEFORE COMPUTING SLOTS**
> Before computing upload times (`publishAt`), always query YouTube via `yutu` to inspect existing scheduled private videos:
```powershell
Set-Location -Path "$env:USERPROFILE\Videos"
$env:YUTU_ROOT = "$env:USERPROFILE\Videos"
$env:YUTU_CREDENTIAL = "yt-uploader/client_secrets.json"
$env:YUTU_CACHE_TOKEN = "yt-uploader/youtube.token.json"
$yutuExe = "yutu"

$search = & $yutuExe search list --for mine --types video --maxResults 50 --output json | Out-String | ConvertFrom-Json
$aoeVideos = $search | Where-Object { $_.snippet.title -match "AOE|vs|Definitive Edition" }
$ids = ($aoeVideos | ForEach-Object { $_.id.videoId }) -join ","
$details = & $yutuExe video list --ids $ids --parts snippet,status --output json | Out-String | ConvertFrom-Json
$scheduled = $details | Where-Object { $_.status.privacyStatus -eq "private" -and $_.status.publishAt } | Sort-Object { [DateTime]$_.status.publishAt } -Descending
```
- **If scheduled videos exist**: The queue is already active! Find the highest/latest scheduled `publishAt` date. The new batch starts publishing sequentially starting from **`LastScheduledDate + 1 day` at 20:00 local time**, continuing with `+1 day` per video.
- **If NO scheduled videos exist**: Follow the 24-Hour Drought vs 8-Hour Buffer Logic below.

### 2. Prime-Time Anchor Slot & Cadence Rules
When no pending queue exists, maintain the daily prime-time anchor slot at **20:00 (8:00 PM)** with a minimum **8-hour buffer**:
- **Daily at 20:00 (8:00 PM local time)** is the target publishing time for all regular releases.
- **Drought Prevention vs 8-Hour Buffer Logic (when queue is empty)**:
  - **If no video uploaded in the last 24 hours**:
    - **Window A: Current time is 20:00 to 12:00 (Night to Noon, >= 8h until 20:00)**:
      - **Game 1**: Upload immediately (`Public` now).
      - **Game 2**: Schedule for **20:00 today** (satisfies the >= 8-hour gap).
    - **Window B: Current time is 12:01 to 19:59 (Afternoon, < 8h until 20:00)**:
      - Rather than dropping an awkward mid-afternoon video right before prime time, wait for the prime-time anchor:
      - **Game 1**: Schedule for **20:00 today**.
      - **Game 2**: Schedule for **20:00 tomorrow**.
  - **If a video was already uploaded in the last 24 hours**:
    - **Game 1**: Schedule for the next open **20:00** slot tomorrow.
  - **Subsequent Games (Queue Drip-Feed)**:
    - All further games in the batch are scheduled sequentially at **20:00, +1 day each** (`Day + 1`, `Day + 2`, `Day + 3`, etc.).

### 3. Scheduled Upload Format
Scheduled videos use `"privacyStatus": "private"` with `"publishAt": "<ISO_Timestamp>"` (e.g. `2026-11-16T18:00:00Z` or `2026-11-16T20:00:00+02:00`).

---

## Step-by-Step Execution Workflow

1. **Inspect and Locate Match Timestamps & Age Transitions (Fast-Seek ONLY)**:
   - Check input file: If the file already contains `- aoe-editor-done`, it has already been processed; skip it.
   - > [!WARNING] **NEVER SEQUENTIALLY DECODE LONG RECORDINGS**
     > **NEVER** use full-video sequential decoding filters such as `-i "<InputFile>" -vf "fps=..."`. In 2-3 hour 1440p 60fps recordings, sequential CPU decode tries to decode 500,000+ frames and will freeze or take hours.
     > **ALWAYS use fast keyframe input seeking** by putting `-ss` **BEFORE** `-i`:
     > ```powershell
     > ffmpeg -hide_banner -loglevel error -ss <HH:MM:SS> -i "<InputFile>" -vframes 1 -update 1 -y "<ScratchDir>\frame.jpg"
     > ```
     > Each seek executes in under 200ms. To map an entire session, run a fast-seeking loop (e.g. stepping every 120-180 seconds across the duration) which completes in ~5-10 seconds.
   - Identify civilizations, map, game duration, score trajectory, and exact `start_time` and `end_time`.
   - **Extract Fluid Chapter Timestamps**: Note baseline age transitions (`Dark Age` at `00:00`, `Feudal Age`, `Castle Age`, `Imperial Age`) along with any memorable match moments, blunders, or key engagements (e.g. `Vil Lost to Boar`, `Hole in the Wall!`, `Castle Drop`, `Decisive Push`, `GG & Post-Game Analysis`), offset to `00:00` relative to game start.
   - Check duration: If `< 7 minutes`, log it as discarded and increment the game counter without exporting.
   - Check competitiveness: If heavily one-sided, flag for user confirmation before any upload step.

2. **Create Target Folder**:
   ```powershell
   New-Item -ItemType Directory -Path "$env:USERPROFILE\Videos\aoe\<DDMmmYY>" -Force
   ```

3. **Extract Game Clips Losslessly**:
   Use FFmpeg stream copy (`-c copy`) for fast, zero-quality-loss extraction:
   ```powershell
   ffmpeg -hide_banner -loglevel warning -ss <StartTime> -to <EndTime> -i "<InputFile>" -c copy -avoid_negative_ts make_zero -y "<OutputFile>"
   ```

4. **Generate Varied, Authentic Thumbnail (Matching Video Filename)**:
   - Pick the key turning point frame during **live, active combat or an attack in progress** (NEVER post-fight aftermath with bodies on the floor, NEVER empty broken walls with no enemy units).
   - If there is a webcam/face cam overlay, inspect the face expression carefully: ensure the creator looks focused, hyped, laughing, or naturally engaged, and NEVER weird, mid-blink, or with an awkward mouth expression.
   - Position large two-tone typography in negative space, ensuring the text overlay **NEVER covers, occludes, or sits on top of the focal units, buildings, or subject named in the hook**.
   - Frame the hook around the defining match dynamic or proactive core strategy (e.g., protracted Feudal war, teammate base collapse, all-in donjons) using authentic AoE2 community terminology (e.g. `TREB WAR`).
   - Avoid nonsensical civ adjectives on generic units (e.g., no "Genoese Trebuchets") or unremarkable labels (e.g., no "Chinese Castle").
   - NEVER leak the match outcome via score disparities (e.g. player at 75% score with raided base).
   - Check and append new hooks to `previous_hooks.txt`.
   - If there is a natural carry or flop unit narrative, apply a contextual, varied meme or spotlight edit without overusing any single meme format.
   - Save the thumbnail using the **exact same name as the video file**, replacing the extension with `.png`:
     `$env:USERPROFILE\Videos\aoe\<DDMmmYY>\<MatchingVideoName>.png`

5. **Prompt User on Flagged Games & Verify Output**:
   - Present generated files and ask about any one-sided matches flagged during analysis.

6. **Execute Scheduled YouTube Uploads, Metadata, & Playlists (`yutu`)**:
   - Activate Native Keep-Awake (`SetThreadExecutionState` with `0x80000001`) so the PC and uploads stay active while allowing the monitor to sleep.
   - **Inspect Queue**: Run dynamic schedule queue inspection to identify latest scheduled date on YouTube.
   - Compute each video's upload/publish timestamp.
   - Format YouTube title per standard: `<MyCiv(s)> vs <OpponentCiv(s)> AOE2 <MatchFormat> <Map>` (strictly NO Win/Loss spoilers, NO Game 1/Game 2).
   - Format description including **Age Transition Chapters**.
   - Set Game Title (Gaming Category 20): `Age of Empires II: Definitive Edition`.
   - **CLI Tool (`yutu`)**: Located at `yutu` (or direct binary at `$env:LOCALAPPDATA\Microsoft\WinGet\Packages\eat-pray-ai.yutu_Microsoft.Winget.Source_8wekyb3d8bbwe\yutu.exe`).
     - > [!IMPORTANT] **`YUTU_ROOT` & RELATIVE FORWARD-SLASH PATHS REQUIREMENT**
       > `yutu` is built with Go and resolves all filesystem paths using `os.DirFS($env:YUTU_ROOT)`.
       > Passing Windows absolute paths (e.g., `C:\Users\Michael\...` with drive letters or backslashes) to credentials, `--file`, or `--thumbnail` will cause Go's filesystem validator to throw:
       > `path escapes from parent` or `failed to parse client secret: illegal base64 data at input byte 1`.
       > **Always set working directory and `YUTU_ROOT` to `$env:USERPROFILE\Videos` and pass forward-slash relative paths**:
       > ```powershell
       > Set-Location -Path "$env:USERPROFILE\Videos"
       > $env:YUTU_ROOT = "$env:USERPROFILE\Videos"
       > $env:YUTU_CREDENTIAL = "yt-uploader/client_secrets.json"
       > $env:YUTU_CACHE_TOKEN = "yt-uploader/youtube.token.json"
       > ```
     - **Upload**:
       ```powershell
       & "yutu" video insert `
         --file "aoe/<DDMmmYY>/<VideoName>.mp4" `
         --thumbnail "aoe/<DDMmmYY>/<MatchingThumbName>.png" `
         --title "<StandardTitle>" `
         --description "<DescriptionWithChapters>" `
         --privacy private `
         --publishAt "<PublishAt_ISO8601>" `
         --tags "Age of Empires II,AoE2,AoE2 DE,Age of Empires,Gameplay" `
         --categoryId 20 `
         --yes
       ```
     - **Assign to Playlist**:
       ```powershell
       # Target Playlist: <Your1v1PlaylistID> (1v1) or <YourTeamPlaylistID> (Team Games)
       & "yutu" playlistItem insert `
         --kind video `
         --playlistId "<PlaylistID>" `
         --channelId "<YourChannelID>" `
         --kVideoId "<VideoID>" `
         --yes
       ```
     - **Update Metadata (Post-Upload if needed)**:
       ```powershell
       & "yutu" video update `
         --id <VideoID> `
         --title "<StandardTitle>" `
         --description "<DescriptionWithChapters>" `
         --yes
       ```
     - **Update Thumbnail (Post-Upload)**:
       ```powershell
       & "yutu" thumbnail set `
         --videoId <VideoID> `
         --file "aoe/<DDMmmYY>/<MatchingThumbName>.png" `
         --yes
       ```
   - Release the Keep-Awake lock (`0x80000000`) once all operations conclude.
   - **Strict Rule**: Never read, inspect, cat, or output token or secret files.

7. **Mark Source Recording as Completed (` - aoe-editor-done`)**:
   - The source recording file must **never be deleted**.
   - Once all games from the session recording have finished being edited, sliced, verified, and saved to the target folder, rename the source recording file by appending ` - aoe-editor-done` before the file extension:
     ```powershell
     $item = Get-Item "<InputFile>"
     Rename-Item -Path $item.FullName -NewName "$($item.BaseName) - aoe-editor-done$($item.Extension)"
     ```
   - Only remove temporary analysis scratch frames if created; leave all other footage intact.
