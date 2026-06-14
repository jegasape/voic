#!/usr/bin/env bash
# voic.sh
# Re-encodes video file(s) stripping all personal metadata
# and assigns a random UUID as the output filename.
# Accepts either a single file or a directory (batch mode).
# Also stamps the output file with a random date within the past year.

set -uo pipefail   # not -e: we want batch mode to continue past failures

# --- Check dependencies ---
for cmd in ffmpeg ffprobe; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: '$cmd' is not installed." >&2
        exit 1
    fi
done

# --- Ask for input ---
read -e -p "Input file or directory: " INPUT

# Strip surrounding quotes if the user dragged something in
INPUT="${INPUT%\"}"
INPUT="${INPUT#\"}"
INPUT="${INPUT%\'}"
INPUT="${INPUT#\'}"
INPUT="${INPUT%/}"

if [[ ! -e "$INPUT" ]]; then
    echo "Error: '$INPUT' does not exist." >&2
    exit 1
fi

# --- Parameters with defaults ---
read -p "CRF (quality, 18-28, default 23): " CRF
CRF="${CRF:-23}"
if ! [[ "$CRF" =~ ^[0-9]+$ ]] || (( CRF < 0 || CRF > 51 )); then
    echo "Error: CRF must be an integer 0-51." >&2
    exit 1
fi

read -p "Preset (ultrafast..veryslow, default medium): " PRESET
PRESET="${PRESET:-medium}"
case "$PRESET" in
    ultrafast|superfast|veryfast|faster|fast|medium|slow|slower|veryslow|placebo) ;;
    *) echo "Error: invalid preset '$PRESET'." >&2; exit 1 ;;
esac

read -p "Audio bitrate (default 128k): " ABR
ABR="${ABR:-128k}"

# --- Helper: random epoch within the past 365 days ---
random_past_year_epoch() {
    local now seconds_per_year rand_bytes offset
    now="$(date +%s)"
    seconds_per_year=31536000
    rand_bytes=$(od -An -N4 -tu4 < /dev/urandom | tr -d ' ')
    offset=$(( rand_bytes % seconds_per_year ))
    echo $(( now - offset ))
}

# --- Function: sanitize a single file ---
sanitize_file() {
    local input="$1"
    local outdir output
    outdir="$(dirname "$input")"
    output="$outdir/$(cat /proc/sys/kernel/random/uuid).mp4"

    echo
    echo "Processing: $input"
    echo "  -> $output"

    # -map 0:v? / 0:a? — keep video and audio streams if they exist;
    #   the '?' makes the mapping optional so audio-less or video-less
    #   inputs don't abort.
    # -map_metadata:s -1 strips per-stream metadata on ALL streams,
    #   not just s:v:0 / s:a:0 (covers multi-audio / multi-video files).
    # -metadata:s handler_name="" / vendor_id="" applies to every stream.
    if ! ffmpeg -hide_banner -loglevel warning -stats \
        -i "$input" \
        -map 0:v? -map 0:a? \
        -c:v libx264 -preset "$PRESET" -crf "$CRF" \
        -c:a aac -b:a "$ABR" \
        -map_metadata -1 \
        -map_metadata:s -1 \
        -metadata:s handler_name="" \
        -metadata:s vendor_id="" \
        -fflags +bitexact -flags:v +bitexact -flags:a +bitexact \
        "$output"; then
        echo "FAILED: $input" >&2
        rm -f "$output"
        return 1
    fi

    # Stamp the output with a random date in the past year
    local rand_epoch
    rand_epoch="$(random_past_year_epoch)"
    touch -d "@$rand_epoch" "$output"

    echo "Done: $output"
    echo "       timestamp set to $(date -d "@$rand_epoch" '+%Y-%m-%d %H:%M:%S %z')"

    # --- Verification: flag only truly identifying tags ---
    # The MP4 format requires handler_name (defaults: VideoHandler/SoundHandler)
    # and vendor_id (cleared state: [0][0][0][0]). Those are NOT personal info.
    # We only warn when something identifying actually survived.
    echo "       verification:"
    local probe issues
    probe="$(ffprobe -hide_banner "$output" 2>&1)"
    issues="$(echo "$probe" | grep -iE "creation_time|^[[:space:]]*location|make[[:space:]]*:|model[[:space:]]*:|software|title[[:space:]]*:|artist|comment|copyright|album|composer|description|gps" || true)"
    # Flag non-default vendor_id (anything other than [0][0][0][0] or empty)
    local bad_vendor
    bad_vendor="$(echo "$probe" | grep "vendor_id" | grep -viE '\[0\]\[0\]\[0\]\[0\]|:[[:space:]]*$' || true)"
    # Flag encoder with a version number (e.g. Lavf60.16.100) — bitexact should strip these
    local bad_encoder
    bad_encoder="$(echo "$probe" | grep -iE "encoder.*[0-9]+\.[0-9]+" || true)"

    if [[ -z "$issues" && -z "$bad_vendor" && -z "$bad_encoder" ]]; then
        echo "         clean (no identifying tags found)"
    else
        echo "         WARNING: identifying tags detected:"
        [[ -n "$issues" ]]      && echo "$issues"      | sed 's/^/           /'
        [[ -n "$bad_vendor" ]]  && echo "$bad_vendor"  | sed 's/^/           /'
        [[ -n "$bad_encoder" ]] && echo "$bad_encoder" | sed 's/^/           /'
    fi
    return 0
}

# --- Decide: file or directory? ---
if [[ -f "$INPUT" ]]; then
    sanitize_file "$INPUT" || exit 1

elif [[ -d "$INPUT" ]]; then
    shopt -s nullglob nocaseglob
    FILES=("$INPUT"/*.mp4 "$INPUT"/*.mov "$INPUT"/*.mkv "$INPUT"/*.webm "$INPUT"/*.avi)
    shopt -u nullglob nocaseglob

    if [[ ${#FILES[@]} -eq 0 ]]; then
        echo "No video files found in '$INPUT'." >&2
        exit 1
    fi

    echo
    echo "Found ${#FILES[@]} file(s) in '$INPUT':"
    for f in "${FILES[@]}"; do
        echo "  - $(basename "$f")"
    done
    echo
    read -p "Continue? [y/N]: " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi

    OK=0
    FAILED=0
    for f in "${FILES[@]}"; do
        if sanitize_file "$f"; then
            OK=$((OK + 1))
        else
            FAILED=$((FAILED + 1))
        fi
    done

    echo
    echo "Summary: $OK succeeded, $FAILED failed (of ${#FILES[@]} total)."
    [[ $FAILED -eq 0 ]] || exit 1
else
    echo "Error: '$INPUT' is neither a regular file nor a directory." >&2
    exit 1
fi
