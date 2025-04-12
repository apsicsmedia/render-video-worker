#!/bin/bash
# render-video.sh - Create a slideshow video from images, merge with voiceover, and add captions.
# This version checks if there’s piped input and writes it to 'payload.json'.

shopt -s nullglob

# Define the default payload file.
PAYLOAD_FILE="payload.json"

# Check if there is piped input (i.e. HTTP request body coming in).
if [ ! -t 0 ]; then
  # Read everything from STDIN and save it to payload.json.
  cat > "$PAYLOAD_FILE"
fi

# If a command-line argument is provided, use it.
if [ -n "$1" ]; then
  if [ -f "$1" ]; then
    PAYLOAD_FILE="$1"
  else
    echo "$1" > "$PAYLOAD_FILE"
  fi
fi

# Verify the payload file exists.
if [ ! -f "$PAYLOAD_FILE" ]; then
  echo "Payload file '$PAYLOAD_FILE' not found. Exiting." >&2
  exit 1
fi

echo "Using payload file: $PAYLOAD_FILE"

# -------------------------
# Step 0: Download images from the payload file
# -------------------------
echo "Downloading images from payload..."
IMAGE_COUNT=$(jq '.segments | length' "$PAYLOAD_FILE")
for (( i=0; i<IMAGE_COUNT; i++ )); do
  URL=$(jq -r ".segments[$i].imageURL" "$PAYLOAD_FILE")
  OUTPUT="image$((i+1)).jpg"
  echo "Downloading image from $URL to $OUTPUT"
  curl -s -o "$OUTPUT" "$URL"
done

# -------------------------
# Step 1: Create captions.srt from the payload file
# -------------------------
echo "Extracting captions SRT from payload..."
jq -r '.captionsSRT' "$PAYLOAD_FILE" > captions.srt

# -------------------------
# Create fileList.txt for FFmpeg
rm -f fileList.txt
for img in image*.jpg; do
  if [ -s "$img" ]; then
    echo "file '$img'" >> fileList.txt
    echo "duration 10" >> fileList.txt
  else
    echo "Warning: $img not found or is empty." >&2
  fi
done

LAST_IMG=$(ls image*.jpg 2>/dev/null | tail -n 1)
if [ -n "$LAST_IMG" ]; then
  echo "file '$LAST_IMG'" >> fileList.txt
else
  echo "No images found. Exiting."
  exit 1
fi

# -------------------------
# Step 2: Generate slideshow video from images
# -------------------------
echo "Creating slideshow video from images..."
ffmpeg -f concat -safe 0 -i fileList.txt -fps_mode vfr -pix_fmt yuv420p slideshow.mp4

# -------------------------
# Step 3: Merge audio (voiceover) if available.
# -------------------------
if [ -f voiceover.mp3 ]; then
  echo "Merging voiceover audio into video..."
  ffmpeg -i slideshow.mp4 -i voiceover.mp3 -c:v copy -c:a aac -shortest temp_video.mp4
else
  echo "Voiceover file (voiceover.mp3) not found, skipping audio merge."
  cp slideshow.mp4 temp_video.mp4
fi

# -------------------------
# Step 4: Add captions/subtitles if an SRT file is available.
# -------------------------
if [ -f captions.srt ]; then
  echo "Adding captions from captions.srt..."
  ffmpeg -i temp_video.mp4 -vf "subtitles=captions.srt" final_video.mp4
else
  echo "Captions file (captions.srt) not found, skipping caption overlay."
  cp temp_video.mp4 final_video.mp4
fi

echo "Final video created: final_video.mp4"
