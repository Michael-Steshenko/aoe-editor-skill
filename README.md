# aoe-editor

An autonomous video editing and YouTube publishing skill for AI coding agents, designed specifically for **Age of Empires II: Definitive Edition** (AoE2 DE) gameplay recordings.

I don't recommend you use it, it was vibe-coded and fits my own specific needs and tastes.
Here's the output:

| **1v1 Matches** | **Team Games** |
| :---: | :---: |
| [![1v1 Matches](https://img.youtube.com/vi/uYJPM7UKTHk/maxresdefault.jpg)](https://www.youtube.com/watch?v=uYJPM7UKTHk&list=PLVHBy9q6_Ft0) | [![Team Games](https://img.youtube.com/vi/r9vQlJZ0QYc/maxresdefault.jpg)](https://www.youtube.com/watch?v=r9vQlJZ0QYc&list=PLCB7WuHZdkkM) |
| [▶ Watch 1v1 Playlist](https://www.youtube.com/watch?v=uYJPM7UKTHk&list=PLVHBy9q6_Ft0) | [▶ Watch Team Games Playlist](https://www.youtube.com/watch?v=r9vQlJZ0QYc&list=PLCB7WuHZdkkM) |

---

## Overview

Processing multi-hour gameplay recordings into standalone YouTube matches is usually tedious: finding match start/end points, trimming matchmaking queues, cutting clips losslessly, designing thumbnails, generating timestamps, and scheduling uploads.

`aoe-editor` provides a declarative, production-tested specification and helper toolkit that enables an AI agent with terminal access to autonomously process raw session recordings into polished, standalone YouTube releases.

---

## Key Capabilities

### 1. Fast-Seek Match Detection & Lossless Cutting
- **Sub-Second Keyframe Seeking**: Never sequentially decodes 2–3 hour recordings. Uses fast input seeking (`-ss` before `-i`) to map an entire session in ~5–10 seconds.
- **Lossless Stream Copying**: Clips are extracted using FFmpeg stream copy (`-c copy -avoid_negative_ts make_zero`), ensuring zero quality loss and near-instant cut speeds.
- **Post-Game Analysis Retention**: Keeps post-game achievement screens (Summary, Military, Economy, Technology, Society) and replay reviews.
- **Queue & Idle Trimming**: Strips out matchmaking queues, civ draft countdowns, AFK breaks, and desktop browsing.

### 2. Intelligent Match Filtering
- **< 7 Minute Auto-Discard**: Automatically skips games under 7 minutes (early resignations, disconnects, failed starts) without slicing, while **preserving the chronological match numbering** (e.g., `Game 1`, `Game 3` if `Game 2` was discarded).
- **One-Sided Stomp Detection**: Detects heavily uncompetitive stomps and cuts the clip for local preservation, prompting the user for review before queueing for YouTube.

### 3. High-Contrast Custom Thumbnails
- **Bold Typography & Contrasting Colors**: Generates high-impact, mobile-optimized typography (heavy outlines, drop shadows, 2-tone colors like White + Vibrant Gold/Orange).
- **Negative-Space Placement**: Automatically locates empty/open terrain space to avoid covering unit combat.
- **Contextual Unit Memes**: Dynamic triumph/dominance edits (sunglasses, crowns, glowing auras) for carry units, or humorous expressions for flops.
- **Persistent Hook Memory**: Maintains a persistent `previous_hooks.txt` index to guarantee hook uniqueness across the entire channel history.
- **Webcam / Face Cam Quality Inspection**: Dedicated 1:1 inspection ensuring natural, energetic, or focused expressions without freeze-frame blink/speech artifacts.
- **Zero Resign Spoilers**: Ensures thumbnails never capture resignation chat messages or crossed-out player names.

### 4. Fluid Match Chapters & Milestones
- **Clean Baseline Age Transitions**: Accurately extracts `00:00 Dark Age`, `Feudal Age`, `Castle Age`, `Imperial Age`, and `GG & Post-Game Analysis`.
- **Dynamic In-Game Story Markers**: Weaves in fluid markers for memorable in-game moments, blunders, and tactical clashes (e.g., `Vil Lost to Boar`, `Hole in the Wall!`, `Forward Castle Drop`, `Decisive Push`).

### 5. Automated YouTube Publishing (`yutu`)
- **Dynamic Schedule Queue Inspection**: Directly queries YouTube Data API via `yutu` to inspect scheduled private videos and automatically attach new batches to the end of the queue with zero slot collisions.
- **Prime-Time Release Anchor**: Anchors regular uploads daily at **20:00 (8:00 PM local time)** with an 8-hour buffer and drought-prevention logic.
- **Automated Playlist Assignment**: Automatically routes uploaded videos to their respective public channel playlists:
  - `AOE2 1v1s` (for 1v1 matches)
  - `AOE2 team games` (for 2v2, 3v3, 4v4 matches)
- **Spoiler-Free Titles**: Strict naming conventions ensuring match outcomes and local session numbers are never leaked in YouTube titles.

### 6. Safety & Unattended Reliability
- **Source Recording Preservation**: Original recording files are **never deleted**. Once all matches are processed, the source file is safely marked as completed by appending ` - aoe-editor-done`.
- **Credential Protection**: Strict zero-inspection policy protecting OAuth tokens and secrets.
- **Native Windows Keep-Awake**: Uses Windows `SetThreadExecutionState` API (`0x80000001`) to guarantee continuous CPU, disk, and network execution during multi-hour uploads while allowing monitors to sleep naturally.

---

## Step-by-Step Setup Guide

If you are setting this up for the first time, follow this guide to install the required tools, configure Google OAuth for YouTube, and set up your channel IDs.

### Step 1: Install Required Tools

1. **PowerShell 5.1+ / PowerShell 7+** (built into Windows 10/11).
2. **FFmpeg & FFprobe**:
   ```powershell
   winget install Gyan.FFmpeg
   ```
   *Verify installation by opening a new terminal and running `ffmpeg -version` and `ffprobe -version`.*
3. **yutu CLI** (Fast Go-based YouTube Data API CLI):
   ```powershell
   winget install eat-pray-ai.yutu
   ```
   *Alternatively, download the prebuilt binary from [yutu releases](https://github.com/eat-pray-ai/yutu/releases) and place `yutu.exe` in your system `PATH`.*

---

### Step 2: Set Up Google Cloud & YouTube Data API (Google Auth)

To allow `yutu` to manage your uploads, scheduled publishing, and playlists, you need your own OAuth 2.0 desktop credentials from the Google Cloud Console.

1. **Create a Google Cloud Project**:
   - Open the [Google Cloud Console](https://console.cloud.google.com/).
   - Click the project dropdown at the top left > **New Project**.
   - Name it (e.g., `AoE2-Video-Publisher`) and click **Create**.

2. **Enable the YouTube Data API v3**:
   - In the navigation menu, select **APIs & Services** > **Library**.
   - Search for **YouTube Data API v3**.
   - Click it and click **Enable**.

3. **Configure the OAuth Consent Screen**:
   - Go to **APIs & Services** > **OAuth consent screen**.
   - Select **External** (standard for personal Google accounts) and click **Create**.
   - Fill in the required fields:
     - **App name**: `AoE Editor Publisher`
     - **User support email**: Your Google email
     - **Developer contact information**: Your Google email
   - Click **Save and Continue**.
   - **Scopes**: Click **Add or Remove Scopes**, select:
     - `https://www.googleapis.com/auth/youtube.upload` (Upload YouTube videos)
     - `https://www.googleapis.com/auth/youtube` (Manage YouTube account and playlists)
   - Click **Update** > **Save and Continue**.
   - **Test Users (Crucial)**:
     - While your project is in *Testing* status, only authorized test users can log in.
     - Click **+ ADD USERS** and enter the **Google email address associated with your YouTube channel**.
     - Click **Save and Continue**.

4. **Create OAuth 2.0 Client Credentials**:
   - Go to **APIs & Services** > **Credentials**.
   - Click **Create Credentials** > **OAuth client ID**.
   - **Application type**: Select **Desktop app**.
   - **Name**: `yutu-desktop-client`
   - Click **Create**.
   - In the popup, click **Download JSON**.
   - Rename the downloaded file to:
     ```text
     client_secrets.json
     ```

---

### Step 3: Initialize the Directory Structure

Create the required folders and place your `client_secrets.json` file inside:

```powershell
# Create the uploader and video directories
New-Item -ItemType Directory -Path "$env:USERPROFILE\Videos\yt-uploader" -Force
New-Item -ItemType Directory -Path "$env:USERPROFILE\Videos\aoe" -Force

# Initialize an empty previous_hooks.txt file (used for unique thumbnail text memory)
New-Item -ItemType File -Path "$env:USERPROFILE\Videos\yt-uploader\previous_hooks.txt" -Force
```

Move your downloaded `client_secrets.json` into:
```text
$env:USERPROFILE\Videos\yt-uploader\client_secrets.json
```

Your directory structure should look like this:
```text
$env:USERPROFILE\Videos\
├── yt-uploader\
│   ├── client_secrets.json       # Downloaded Google OAuth credentials
│   ├── youtube.token.json        # Auto-generated on first authentication
│   └── previous_hooks.txt        # Persistent thumbnail hook history
├── aoe\                          # Output folder where processed games will be saved
└── 2026-10-27 20-35-29.mp4       # Raw OBS / gameplay recordings
```

---

### Step 4: Perform First-Time Google Authentication

Run a simple command with `yutu` once to complete the OAuth browser flow and generate your cached session token (`youtube.token.json`):

```powershell
Set-Location -Path "$env:USERPROFILE\Videos"
$env:YUTU_ROOT = "$env:USERPROFILE\Videos"
$env:YUTU_CREDENTIAL = "yt-uploader/client_secrets.json"
$env:YUTU_CACHE_TOKEN = "yt-uploader/youtube.token.json"

# Trigger authentication
yutu channel list --for mine
```

1. A browser window will automatically open (or a link will be printed to your console).
2. Log in with the Google Account that owns your YouTube channel.
3. If Google displays an *"Unverified App"* screen, click **Advanced** > **Go to AoE Editor Publisher (unsafe)**.
4. Allow the requested permissions.
5. Once authorized, `yutu` will automatically save `youtube.token.json` in `$env:USERPROFILE\Videos\yt-uploader\`.

> [!NOTE]
> Once `youtube.token.json` is generated, authentication is completely autonomous. The AI agent will execute all scheduled uploads and playlist additions unattended without prompting you for credentials again.

---

### Step 5: Get Your Channel ID & Playlist IDs

1. **Channel ID**:
   - You can get your Channel ID from the output of the command you ran in Step 4:
     ```powershell
     yutu channel list --for mine
     ```
   - Alternatively, go to [YouTube Advanced Settings](https://www.youtube.com/account_advanced) and copy your **Channel ID** (starts with `UC...`, 24 characters).

2. **Playlist IDs**:
   - Go to [YouTube Studio](https://studio.youtube.com/) > **Content** > **Playlists**.
   - Create two public playlists if you haven't already:
     - `AOE2 1v1s`
     - `AOE2 team games`
   - Open each playlist. The Playlist ID is the characters following `list=` in the browser URL (e.g. `https://www.youtube.com/playlist?list=PL...`).

---

### Step 6: Create `config.json` for Channel & Playlist IDs

To keep your personal YouTube channel and playlist IDs completely separate from git version control, save them in `$env:USERPROFILE\Videos\yt-uploader\config.json`:

```json
{
  "channelId": "UC...",
  "playlist1v1": "PL...",
  "playlistTeam": "PL..."
}
```

The skill automatically reads this configuration file at runtime, keeping `SKILL.md` 100% clean and repository-ready.

---

## Installation into Your AI Agent

### Option A: Live Directory Junction (Recommended)
Creating an NTFS directory junction links your AI agent's skill directory directly to this repository without administrator rights. Any changes made by the AI or pulled from GitHub are immediately live in both places:

```powershell
# For Gemini CLI / Antigravity:
cmd /c mklink /J "$HOME\.gemini\config\skills\aoe-editor" "$PWD"

# For Claude Code:
cmd /c mklink /J "$HOME\.claude\skills\aoe-editor" "$PWD"
```

### Option B: Standard Copy
```powershell
# For Gemini CLI / Antigravity:
Copy-Item -Path "." -Destination "$HOME\.gemini\config\skills\aoe-editor" -Recurse

# For Claude Code:
Copy-Item -Path "." -Destination "$HOME\.claude\skills\aoe-editor" -Recurse
```

---

## How to Use

Once installed, simply invoke the skill in your agent prompt:

```text
/aoe-editor
```

The agent will autonomously:
1. Detect unprocessed session recordings in `$env:USERPROFILE\Videos\` (skipping those already marked `- aoe-editor-done`).
2. Scan footage using sub-second keyframe seeking to map match boundaries and extract fluid age transition chapters.
3. Discard games under 7 minutes while preserving chronological match numbering.
4. Extract lossless clips into `$env:USERPROFILE\Videos\aoe\<DateFolder>\`.
5. Capture decisive combat moments and render high-contrast, mobile-optimized custom thumbnails.
6. Query your YouTube queue via `yutu` and schedule uploads for daily 20:00 prime-time release slots.
7. Assign videos to their corresponding 1v1 or Team Game playlist.
8. Safely mark the source recording as completed by appending ` - aoe-editor-done`.


---

## License

This project is licensed under the [MIT License](LICENSE).
