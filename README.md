# Multi-Camera Footage Merger

A bash script to merge video files from multiple cameras into a single folder, renamed so that sorting by filename gives you chronological order regardless of which camera or person filmed each clip.

## Background

Three of us went on a ski trip to Canmore and Banff in February 2026. We all had action cameras rolling throughout the trip:

- Phil had a DJI
- Eric had a GoPro
- Tom had a GoPro

Each camera has its own file naming convention. DJI bakes timestamps into filenames like `DJI_20260222125340_0001_D.MP4`, while GoPro just uses sequential numbers like `GX010459.MP4`. After the trip we had hundreds of clips across three folders with no easy way to watch everything in order.

On top of that, Tom's GoPro clock was set wrong. It thought it was January 2016 instead of February 2026, so all his file timestamps were off by over 10 years. You can't just sort by date and call it a day.

This script solves all of that by pulling timestamps from video metadata (or filesystem dates as a fallback), applying a date correction for cameras with bad clocks, and renaming everything into one folder with timestamps in the filename.

## How it works

The script:

1. Scans each camera folder for `.MP4` files
2. Tries to extract the creation timestamp from embedded video metadata via `ffprobe`
3. Falls back to filesystem modification time if there's no embedded metadata
4. Applies a configurable date offset for cameras with incorrect clocks
5. Moves all files into a single output folder named like:

```
YYYYMMDD_HHMMSS_CameraName_OriginalFilename.MP4
```

Since the timestamp is at the front, sorting by name in Finder (or any file browser) gives you true chronological order across all cameras.

## Requirements

- macOS (uses `date -j` and `stat -f` syntax)
- `ffprobe` (install with `brew install ffmpeg`)

## Configuration

Edit the variables at the top of `merge_footage.sh`:

```bash
# Base directory containing camera folders
BASE_DIR="/Volumes/WD BLACK/Canmore & Banff 2026"

# Output folder for merged files
OUTPUT_DIR="${BASE_DIR}/All_Merged"

# Camera folders - "Label:FolderName"
CAMERAS=("Eric:Eric" "Phil:Phil" "Tom:Tom")

# Date offset corrections for cameras with wrong clocks
# Format: "CameraLabel:OffsetInDays"
# Tom's GoPro was set to Jan 2016 instead of Feb 2026 (3705 days off)
DATE_OFFSETS=("Tom:3705")
```

### Figuring out the date offset

If one of your cameras had the wrong date, count the number of days between what the camera recorded and the actual date. Tom's first clip was stamped Jan 2, 2016 but was actually filmed Feb 23, 2026, which is 3,705 days apart.

## Usage

### Dry run (preview)

Always do a dry run first to make sure everything looks right:

```bash
bash merge_footage.sh
```

This prints a numbered list of every file with its new name, camera source, and corrected timestamp without actually moving anything.

### Execute

Once it looks good:

```bash
bash merge_footage.sh --execute
```

This moves (not copies) all files into the output folder so you don't need extra disk space.

**Heads up:** the move isn't reversible from within the script. If you want to be safe, back things up first.

## Example output

```
   #  New Filename                                            Camera   Timestamp
---------------------------------------------------------------------------------------------------------
   1  20260222_125400_Phil_DJI_20260222125340_0001_D.MP4      Phil     2026-02-22 12:54:00
   2  20260222_125723_Phil_DJI_20260222125713_0002_D.MP4      Phil     2026-02-22 12:57:23
   ...
  47  20260223_125004_Eric_GX010459.MP4                       Eric     2026-02-23 12:50:04
  48  20260223_125127_Phil_DJI_20260223124859_0083_D.MP4      Phil     2026-02-23 12:51:27
  49  20260223_125218_Eric_GX010460.MP4                       Eric     2026-02-23 12:52:18
  ...
 112  20260224_112528_Tom_GX010134.MP4                        Tom      2026-02-24 11:25:28
```

## License

MIT
