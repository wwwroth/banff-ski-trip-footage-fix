#!/usr/bin/env bash
# =============================================================================
# merge_footage.sh
#
# Merge video files from multiple camera folders into a single folder,
# renaming them so that sorting by filename gives chronological order.
#
# Uses ffprobe to try embedded metadata first, falls back to filesystem
# modification time. Supports a date offset correction for cameras with
# incorrect clocks.
#
# Usage:
#     bash merge_footage.sh              # Dry run (preview only)
#     bash merge_footage.sh --execute    # Actually move and rename files
# =============================================================================

set -eo pipefail

# =============================================================================
# CONFIGURATION — Edit these to match your setup
# =============================================================================

BASE_DIR="/Volumes/WD BLACK/Canmore & Banff 2026"
OUTPUT_DIR="${BASE_DIR}/All_Merged"

# Camera folders: "Label:FolderName"
CAMERAS=("Eric:Eric" "Phil:Phil" "Tom:Tom")

# Date offset corrections for cameras with wrong clocks.
# Format: "CameraLabel:OffsetInDays"
# Tom's GoPro was set to Jan 2016 instead of Feb 2026 (3705 days off).
# Leave empty if no corrections needed.
DATE_OFFSETS=("Tom:3705")

# =============================================================================
# END CONFIGURATION
# =============================================================================

DRY_RUN=true
if [[ "${1:-}" == "--execute" ]]; then
    DRY_RUN=false
fi

# Build an associative array for offsets
declare -A OFFSET_MAP
for entry in "${DATE_OFFSETS[@]}"; do
    cam="${entry%%:*}"
    days="${entry##*:}"
    OFFSET_MAP["$cam"]=$((days * 86400))
done

# Temp file to collect all entries for sorting
TMPFILE=$(mktemp /tmp/merge_footage.XXXXXX)
trap "rm -f '$TMPFILE'" EXIT

# ---- Helper: get creation timestamp via ffprobe ----
get_creation_time() {
    local filepath="$1"
    local ts
    ts=$(ffprobe -v quiet -print_format json -show_format "$filepath" 2>/dev/null \
        | grep -i '"creation_time"' \
        | head -1 \
        | sed 's/.*: *"//;s/".*//')

    if [[ -z "$ts" ]]; then
        echo ""
        return
    fi

    # Try to parse ISO timestamp to YYYYMMDD_HHMMSS using macOS date
    # Handle: 2026-02-22T12:53:40.000000Z, 2026-02-22T12:53:40Z, etc.
    local clean="${ts%%.*}"        # Strip fractional seconds
    clean="${clean%%Z}"            # Strip trailing Z
    clean="${clean%%+*}"           # Strip timezone offset

    # Try parsing with macOS date
    local formatted
    formatted=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$clean" "+%Y%m%d_%H%M%S" 2>/dev/null) || true

    if [[ -n "$formatted" ]]; then
        echo "$formatted"
    fi
}

# ---- Helper: get file modification time as YYYYMMDD_HHMMSS ----
get_mod_time() {
    stat -f '%Sm' -t '%Y%m%d_%H%M%S' "$1"
}

# ---- Helper: apply date offset and return corrected timestamp ----
apply_offset() {
    local ts_str="$1"      # YYYYMMDD_HHMMSS
    local offset_secs="$2"

    local digits="${ts_str:0:8}${ts_str:9:6}"
    local epoch
    epoch=$(date -j -f "%Y%m%d%H%M%S" "$digits" +%s)
    epoch=$((epoch + offset_secs))
    date -r "$epoch" +%Y%m%d_%H%M%S
}

# =============================================================================
# Main
# =============================================================================

if $DRY_RUN; then
    echo "======================================================================"
    echo "  DRY RUN MODE — No files will be moved."
    echo "  Run with --execute to actually perform the merge."
    echo "======================================================================"
else
    echo "======================================================================"
    echo "  EXECUTE MODE — Files will be MOVED to the output folder."
    echo "  ⚠️  This is not reversible. Make sure you ran the dry run first."
    echo "======================================================================"
fi
echo ""

# Step 1: Scan each camera folder
for cam_entry in "${CAMERAS[@]}"; do
    camera="${cam_entry%%:*}"
    folder_name="${cam_entry##*:}"
    folder="${BASE_DIR}/${folder_name}"

    if [[ ! -d "$folder" ]]; then
        echo "⚠ Folder not found: $folder"
        continue
    fi

    count=0
    fallback_count=0
    corrected_count=0
    echo "📁 Scanning ${camera} (${folder})..."

    for filepath in "$folder"/*.MP4 "$folder"/*.mp4; do
        [[ -e "$filepath" ]] || continue
        filename=$(basename "$filepath")

        # Try ffprobe first
        ts=$(get_creation_time "$filepath")

        if [[ -z "$ts" ]]; then
            # Fallback to file modification time
            ts=$(get_mod_time "$filepath")
            fallback_count=$((fallback_count + 1))
        fi

        # Apply date offset if configured for this camera
        if [[ -n "${OFFSET_MAP[$camera]:-}" ]]; then
            ts=$(apply_offset "$ts" "${OFFSET_MAP[$camera]}")
            corrected_count=$((corrected_count + 1))
        fi

        # Write to temp file: timestamp|camera|filepath|filename
        echo "${ts}|${camera}|${filepath}|${filename}" >> "$TMPFILE"
        count=$((count + 1))
    done

    echo "   Found ${count} files"
    [[ $fallback_count -gt 0 ]] && echo "   ⚠ ${fallback_count} used filesystem mod time (no embedded metadata)"
    [[ $corrected_count -gt 0 ]] && echo "   🔧 ${corrected_count} had date offset correction applied"
    echo ""
done

total=$(wc -l < "$TMPFILE" | tr -d ' ')
echo "📋 Total files: ${total}"
echo "📂 Output folder: ${OUTPUT_DIR}"
echo ""

if [[ "$total" -eq 0 ]]; then
    echo "No files found. Check your CAMERAS configuration."
    exit 1
fi

if ! $DRY_RUN; then
    mkdir -p "$OUTPUT_DIR"
fi

# Step 2: Sort and rename
sort -t'|' -k1,1 -k2,2 "$TMPFILE" | {
    i=0
    printf "%4s  %-60s %-8s %s\n" "#" "New Filename" "Camera" "Timestamp"
    printf '%0.s-' {1..105}
    echo ""

    while IFS='|' read -r ts camera filepath filename; do
        i=$((i + 1))
        new_name="${ts}_${camera}_${filename}"

        # Display
        ts_display="${ts:0:4}-${ts:4:2}-${ts:6:2} ${ts:9:2}:${ts:11:2}:${ts:13:2}"
        printf "%4d  %-60s %-8s %s\n" "$i" "$new_name" "$camera" "$ts_display"

        if ! $DRY_RUN; then
            mv "$filepath" "${OUTPUT_DIR}/${new_name}"
        fi
    done

    echo ""
    if $DRY_RUN; then
        echo "✅ Dry run complete. ${i} files would be moved."
        echo "   Run with --execute to perform the actual merge."
    else
        echo "✅ Done! ${i} files moved to ${OUTPUT_DIR}"
    fi
}
