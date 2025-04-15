#!/bin/bash
echo "DEBUG: render-video.sh script started!" # <-- Added

shopt -s nullglob
PAYLOAD_FILE="payload.json"

echo "DEBUG: Checking for piped input..." # <-- Added
if [ ! -t 0 ]; then
  echo "DEBUG: Piped input detected. Reading stdin to $PAYLOAD_FILE..." # <-- Added
  cat > "$PAYLOAD_FILE"
  echo "DEBUG: Finished reading stdin. Payload size: $(wc -c < $PAYLOAD_FILE) bytes." # <-- Added
else
  echo "DEBUG: No piped input detected (stdin is a TTY)." # <-- Added
fi

# Add a small delay just in case logs need time to flush
sleep 1
echo "DEBUG: Verifying payload file existence..." # <-- Added
if [ ! -f "$PAYLOAD_FILE" ]; then
  echo "DEBUG: Payload file '$PAYLOAD_FILE' not found. Exiting." >&2
  exit 1
fi
echo "DEBUG: Payload file $PAYLOAD_FILE exists." # <-- Added confirmation
echo "Using payload file: $PAYLOAD_FILE"

echo "DEBUG: Checking jq command..." # <-- Added
if ! command -v jq &> /dev/null; then
    echo "DEBUG: jq command could not be found. Exiting." >&2
    exit 1
fi
echo "DEBUG: jq seems available." # <-- Added

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
  curl -s -L -o "$OUTPUT" "$URL"  # Added -L to follow redirects
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
ffmpeg -f concat -safe 0 -i fileList.txt -vf "fps=30,format=yuv420p" -c:v libx264 -preset fast slideshow.mp4
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
# Step 4: Add captions/subtitles if an SRT file is available.
# -------------------------
echo "DEBUG: Starting Step 4: Check for captions..."
if [ -f captions.srt ] && [ -s captions.srt ]; then
  echo "DEBUG: captions.srt found. Adding captions (FFmpeg subtitles)..."
  ffmpeg -i temp_video.mp4 -vf "subtitles=captions.srt:force_style='Fontsize=18,PrimaryColour=&H00FFFFFF,BorderStyle=3,Outline=1,Shadow=0'" final_video.mp4
  if [ $? -ne 0 ]; then 
    echo "DEBUG: ERROR during caption overlay (ffmpeg)." >&2
    exit 1
  fi
else
  echo "DEBUG: Captions file (captions.srt) not found or empty, copying temp_video.mp4 to final_video.mp4."
  cp temp_video.mp4 final_video.mp4
fi
echo "DEBUG: Finished Step 4."

echo "DEBUG: Final video created: final_video.mp4"
echo "Final video created: final_video.mp4"

# Optional: Clean up intermediate files
# echo "DEBUG: Cleaning up temporary files..."
# rm -f image*.jpg captions.srt fileList.txt slideshow.mp4 temp_video.mp4 payload.json
# echo "DEBUG: Cleanup complete."
