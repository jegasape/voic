voic.sh

re-encodes video files to strip personal metadata, gives them a random uuid filename, and stamps them with a random filesystem date from the past year. useful before sharing videos online when you don't want to leak identifying information.

What it does

For every video you pass in, the script:

1. Re-encodes the video to H.264 + AAC (so any encoder-specific artifacts of the original are replaced).
2. Strips metadata at the container level and at the stream level (creation dates, GPS, camera make/model, software, vendor ID, etc.).
3. Drops non-video/audio streams (chapters, QuickTime metadata tracks, subtitles).
4. Removes the encoder version tag (-fflags +bitexact).
5. Renames the output to a random UUID like 3e3eeee7-b819-43fe-be8f-1986c01e8a06.mp4.
6. Randomizes the filesystem timestamp to a random point in the last 365 days.
7. Verifies the result and tells you whether any identifying tags survived.

The original file is left untouched.

Requirements

- bash
- ffmpeg and ffprobe
- Linux (the script reads /proc/sys/kernel/random/uuid and /dev/urandom)

Install ffmpeg on Debian/Ubuntu:

sudo apt install ffmpeg

Installation

Download voic.sh, then:

chmod +x voic.sh

Optional — make it available system-wide:

mkdir -p ~/.local/bin
mv voic.sh ~/.local/bin/voic

Usage

Run it and answer the prompts:

./voic.sh

It will ask for:

Prompt              Default   Notes
Input file or dir   —         Path to a single video, or a folder for batch mode. Tab autocomplete works.
CRF                 23        Quality: lower = better, larger files. Range 0–51. 18–28 is typical.
Preset              medium    Encoding speed vs. compression. ultrafast…veryslow.
Audio bitrate       128k      E.g. 96k, 192k, 320k.

Press Enter on any prompt to accept the default.

Examples

Single file:

$ ./voic.sh
Input file or directory: my_clip.mp4
CRF (quality, 18-28, default 23):
Preset (ultrafast..veryslow, default medium):
Audio bitrate (default 128k):

Processing: my_clip.mp4
  -> ./3e3eeee7-b819-43fe-be8f-1986c01e8a06.mp4
Done: ./3e3eeee7-b819-43fe-be8f-1986c01e8a06.mp4
       timestamp set to 2025-08-17 20:28:51 +0000
       verification:
         clean (no identifying tags found)

Whole folder (batch mode):

$ ./voic.sh
Input file or directory: ~/Videos

Found 3 file(s) in '/home/user/Videos':
  - vacation.mp4
  - meeting.mov
  - clip.mkv

Continue? [y/N]: y
...
Summary: 3 succeeded, 0 failed (of 3 total).

Supported extensions in batch mode: .mp4, .mov, .mkv, .webm, .avi (case-insensitive). Subfolders are not processed.

How to verify manually

After running the script you can double-check with:

exiftool output.mp4
ffprobe -hide_banner output.mp4

Look for these tags — if any of them appear with personal-looking values, something leaked:

- creation_time, Create Date, Modify Date (anything other than zeroes)
- location, GPS*
- make, model, software
- title, artist, comment, copyright
- vendor_id (should be [0][0][0][0])
- encoder with a version number like Lavf60.16.100

It's normal and harmless for the output to still contain:

- handler_name: VideoHandler / SoundHandler — generic MP4 defaults
- vendor_id: [0][0][0][0] — empty/zeroed vendor (this is the cleared state)
- major_brand, minor_version, compatible_brands — MP4 format identifiers
- encoder: Lavc libx264 (no version) — codec name embedded in the bitstream

What this script does NOT do

- It does not remove visual or audio content from the video. If your face, a license plate, or a voice is in the frame, it stays. Use a video editor for that.
- It does not anonymize you when uploading. The hosting service still sees your IP, browser, and connection metadata. Combine with a VPN or Tor if that matters.
- It does not encrypt the file. Anyone who has the link/file can watch it.
- It does not process subfolders. Only the top level of the directory you point at.
- It does not delete the original. That's intentional — review the output before discarding the source.

Notes

- Re-encoding takes time and introduces a small quality loss. CRF 23 is visually near-transparent for most footage. If you want to preserve quality at the cost of a larger file, use CRF 18–20.
- The randomized filesystem timestamp only matters if you share the file directly (USB, attachment, file-sharing app that preserves mtime). When you upload to a web service, the server assigns its own timestamps.
- Filenames are random UUIDs, so the original filename does not leak. Keep a separate note if you need to remember which UUID corresponds to which source.

License

Public domain / do whatever you want.
