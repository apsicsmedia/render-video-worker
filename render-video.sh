#!/bin/bash
echo "DEBUG: render-video.sh script started!"

shopt -s nullglob

# Determine payload file
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
# Step 1: Create captions.srt
# -------------------------
echo "DEBUG: Starting Step 1: Create captions.srt..."
jq -r '.captionsSRT' "$PAYLOAD_FILE" > captions.srt
if [ ! -s captions.srt ]; then
  echo "DEBUG: WARNING - captions.srt file is empty or not created." >&2
fi
echo "DEBUG: Finished Step 1."

echo "DEBUG: Contents of captions.srt:"
cat captions.srt

# -------------------------
# Step 2: Create fileList.txt for FFmpeg
# -------------------------
echo "DEBUG: Creating fileList.txt..."
rm -f fileList.txt
for img in image*.jpg; do
  if [ -s "$img" ]; then
    echo "file '$img'" >> fileList.txt
    echo "duration 10" >> fileList.txt
  else
    echo "DEBUG: Warning: $img not found or is empty." >&2
  fi
done

LAST_IMG=$(ls image*.jpg 2>/dev/null | tail -n 1)
if [ -n "$LAST_IMG" ]; then
  # Repeat the last image to avoid abrupt ending
  echo "file '$LAST_IMG'" >> fileList.txt
else
  echo "DEBUG: No valid images found. Exiting." >&2
  exit 1
fi
echo "DEBUG: Finished creating fileList.txt."

# -------------------------
# Step 3: Generate slideshow video
# -------------------------
echo "DEBUG: Starting Step 3: Generate slideshow..."
ffmpeg -f concat -safe 0 -i fileList.txt -vf "fps=30,format=yuv420p" -c:v libx264 -preset medium slideshow.mp4
if [ $? -ne 0 ]; then
  echo "DEBUG: ERROR generating slideshow (ffmpeg concat)." >&2
  exit 1
fi
echo "DEBUG: Finished Step 3."

# -------------------------
# Step 4: Merge audio (voiceover) if available -> temp_video.mp4
# -------------------------
echo "DEBUG: Starting Step 4: Merge audio if voiceover.mp3 exists..."
if [ -f voiceover.mp3 ]; then
  echo "DEBUG: voiceover.mp3 found. Merging..."
  ffmpeg -i slideshow.mp4 -i voiceover.mp3 -c:v copy -c:a aac -shortest temp_video.mp4
  if [ $? -ne 0 ]; then
    echo "DEBUG: ERROR merging audio." >&2
    exit 1
  fi
else
  echo "DEBUG: No voiceover found. Copying slideshow.mp4 to temp_video.mp4."
  cp slideshow.mp4 temp_video.mp4
fi
echo "DEBUG: Finished Step 4."

# -------------------------
# Step 5: Re-encode so final starts at 0s & optionally burn subtitles
# -------------------------
echo "DEBUG: Starting Step 5: Force final to 0s and handle subtitles..."

if [ -f captions.srt ] && [ -s captions.srt ]; then
  echo "DEBUG: SRT found, burning subtitles with setpts/asetpts re-encode..."
  ffmpeg -i temp_video.mp4 \
    -vf "subtitles=captions.srt,setpts=PTS-STARTPTS" \
    -af "asetpts=PTS-STARTPTS" \
    -c:v libx264 -preset medium \
    -c:a aac -shortest \
    final_video.mp4
  if [ $? -ne 0 ]; then
    echo "DEBUG: ERROR during subtitle burn-in re-encode." >&2
    exit 1
  fi
else
  echo "DEBUG: No valid SRT. We'll still re-encode to ensure 0s start."
  ffmpeg -i temp_video.mp4 \
    -vf "setpts=PTS-STARTPTS" \
    -af "asetpts=PTS-STARTPTS" \
    -c:v libx264 -preset medium \
    -c:a aac -shortest \
    final_video.mp4
fi

if [ $? -ne 0 ]; then
  echo "DEBUG: ERROR re-encoding final video." >&2
  exit 1
fi

echo "DEBUG: Finished Step 5."

echo "DEBUG: Final video created: final_video.mp4"
echo "Final video created: final_video.mp4"

# Optional: Clean up intermediate files (uncomment to enable)
# rm -f image*.jpg fileList.txt slideshow.mp4 temp_video.mp4 captions.srt payload.json
