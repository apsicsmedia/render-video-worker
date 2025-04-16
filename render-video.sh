#!/bin/bash
echo "DEBUG: render-video.sh script started!"

shopt -s nullglob

# Determine payload file: if a command-line argument is provided, use it; otherwise, default to payload.json.
if [ -n "$1" ]; then
  if [ -f "$1" ]; then
    PAYLOAD_FILE="$1"
    echo "DEBUG: Payload file provided as argument exists: $PAYLOAD_FILE"
  else
    echo "$1" > payload.json
    PAYLOAD_FILE="payload.json"
    echo "DEBUG: Payload argument provided, but file not found. Written to payload.json"
  fi
else
  PAYLOAD_FILE="payload.json"
  # Only read from STDIN if no argument is provided.
  echo "DEBUG: No payload argument provided. Checking for piped input..."
  if [ ! -t 0 ]; then
    echo "DEBUG: Piped input detected. Reading stdin to $PAYLOAD_FILE..."
    cat > "$PAYLOAD_FILE"
    echo "DEBUG: Finished reading stdin. Payload size: $(wc -c < "$PAYLOAD_FILE") bytes."
  else
    echo "DEBUG: No piped input detected (stdin is a TTY)."
  fi
fi

# Add a small delay to ensure logs flush
sleep 1
echo "DEBUG: Verifying payload file existence..."
if [ ! -f "$PAYLOAD_FILE" ]; then
  echo "DEBUG: Payload file '$PAYLOAD_FILE' not found. Exiting." >&2
  exit 1
fi
echo "DEBUG: Payload file $PAYLOAD_FILE exists."
echo "Using payload file: $PAYLOAD_FILE"

echo "DEBUG: Checking jq command..."
if ! command -v jq &> /dev/null; then
    echo "DEBUG: jq command could not be found. Exiting." >&2
    exit 1
fi
echo "DEBUG: jq seems available."

# -------------------------
# Step 0: Download images from the payload file
# -------------------------
echo "DEBUG: Starting Step 0: Download images..."
IMAGE_COUNT=$(jq '.segments | length' "$PAYLOAD_FILE")
echo "DEBUG: Found $IMAGE_COUNT segments in payload."

for (( i=0; i<IMAGE_COUNT; i++ )); do
  URL=$(jq -r ".segments[$i].imageURL" "$PAYLOAD_FILE")
  OUTPUT="image$((i+1)).jpg"
  echo "DEBUG: Downloading image $((i+1)) from $URL to $OUTPUT"
  curl -s -L -o "$OUTPUT" "$URL"
  if [ ! -s "$OUTPUT" ]; then
    echo "DEBUG: WARNING - Failed to download or image $((i+1)) is empty: $URL" >&2
  fi
done

echo "DEBUG: Finished Step 0."

# -------------------------
# Step 1: Create captions.srt from the payload file
# -------------------------
echo "DEBUG: Starting Step 1: Create captions.srt..."
jq -r '.captionsSRT' "$PAYLOAD_FILE" > captions.srt
if [ ! -s captions.srt ]; then
  echo "DEBUG: WARNING - captions.srt file is empty or not created." >&2
fi
echo "DEBUG: Finished Step 1."

# Log the contents of captions.srt for verification.
echo "DEBUG: Contents of captions.srt:"
cat captions.srt

# -------------------------
# Create fileList.txt for FFmpeg
# -------------------------
echo "DEBUG: Creating fileList.txt..."
rm -f fileList.txt
for img in image*.jpg; do
  if [ -s "$img" ]; then
    echo "file '$img'" >> fileList.txt
    echo "duration 10" >> fileList.txt
  else
    echo "DEBUG: Warning: $img not found or is empty when creating fileList." >&2
  fi
done

# Duplicate the last image so the concat demuxer doesn't end abruptly
LAST_IMG=$(ls image*.jpg 2>/dev/null | tail -n 1)
if [ -n "$LAST_IMG" ]; then
  echo "file '$LAST_IMG'" >> fileList.txt
else
  echo "DEBUG: No valid images found for fileList.txt. Exiting." >&2
  exit 1
fi
echo "DEBUG: Finished creating fileList.txt."

# -------------------------
# Step 2: Generate slideshow video from images
# -------------------------
echo "DEBUG: Starting Step 2: Generate slideshow (FFmpeg concat)..."
ffmpeg -f concat -safe 0 -i fileList.txt -vf "fps=30,format=yuv420p" -c:v libx264 -preset medium slideshow.mp4
if [ $? -ne 0 ]; then
  echo "DEBUG: ERROR during slideshow generation (ffmpeg concat)." >&2
  exit 1
fi
echo "DEBUG: Finished Step 2."

# -------------------------
# Step 3: Merge audio (voiceover) if available.
# -------------------------
echo "DEBUG: Starting Step 3: Check for audio..."
if [ -f voiceover.mp3 ]; then
  echo "DEBUG: voiceover.mp3 found. Merging audio (FFmpeg merge)..."
  ffmpeg -i slideshow.mp4 -i voiceover.mp3 -c:v copy -c:a aac -shortest temp_video.mp4
  if [ $? -ne 0 ]; then
    echo "DEBUG: ERROR during audio merge (ffmpeg)." >&2
    exit 1
  fi
else
  echo "DEBUG: Voiceover file (voiceover.mp3) not found, copying slideshow.mp4 to temp_video.mp4."
  cp slideshow.mp4 temp_video.mp4
fi
echo "DEBUG: Finished Step 3."

# -------------------------
# Step 3.5: Remove container offset (Method #2 remux)
# -------------------------
echo "DEBUG: Step 3.5: Removing offset from temp_video.mp4 via TS remux..."
ffmpeg -y -i temp_video.mp4 -c copy -bsf:v h264_mp4toannexb -f mpegts intermediate.ts
if [ $? -ne 0 ]; then
  echo "DEBUG: ERROR during .ts creation." >&2
  exit 1
fi

ffmpeg -y -i intermediate.ts -c copy offset_fixed.mp4
if [ $? -ne 0 ]; then
  echo "DEBUG: ERROR remuxing back to offset_fixed.mp4." >&2
  exit 1
fi
echo "DEBUG: offset_fixed.mp4 should now start at 0s."
echo "DEBUG: Finished Step 3.5."

# -------------------------
# Step 4: Burn subtitles if an SRT file is available
# -------------------------
echo "DEBUG: Starting Step 4: Check for captions..."
if [ -f captions.srt ] && [ -s captions.srt ]; then
  echo "DEBUG: captions.srt found. Burning subtitles..."
  ffmpeg -i offset_fixed.mp4 \
    -vf "subtitles=captions.srt:force_style='FontName=Arial,FontSize=24,PrimaryColour=&H00FFFFFF,BorderStyle=4,OutlineColour=&H000000FF,Shadow=0,BackColour=&H80000000,Bold=1'" \
    -c:a aac -shortest \
    final_video.mp4
  if [ $? -ne 0 ]; then
    echo "DEBUG: ERROR during subtitle burn-in (ffmpeg)." >&2
    exit 1
  fi
else
  echo "DEBUG: Captions file (captions.srt) not found or empty. Copying offset_fixed.mp4 to final_video.mp4."
  ffmpeg -i offset_fixed.mp4 -c copy final_video.mp4
fi
echo "DEBUG: Finished Step 4."

echo "DEBUG: Final video created: final_video.mp4"
echo "Final video created: final_video.mp4"

# Optional: Clean up intermediate files (uncomment if desired)
# echo "DEBUG: Cleaning up temporary files..."
# rm -f image*.jpg captions.srt fileList.txt slideshow.mp4 temp_video.mp4 intermediate.ts offset_fixed.mp4 payload.json
# echo "DEBUG: Cleanup complete."
