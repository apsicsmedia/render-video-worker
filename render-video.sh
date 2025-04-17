#!/bin/bash
set -e
shopt -s nullglob

# === CONFIG ===
DURATION=5
FPS=25
WIDTH=1280
HEIGHT=720
FONT="Roboto"  # fallback to Arial if Roboto isn’t installed

# === PAYLOAD LOAD ===
if [ -n "$1" ]; then
  if [ -f "$1" ]; then
    PAYLOAD_FILE="$1"
  else
    echo "$1" > payload.json
    PAYLOAD_FILE="payload.json"
  fi
else
  PAYLOAD_FILE="payload.json"
  if [ ! -t 0 ]; then cat > "$PAYLOAD_FILE"; fi
fi

if [ ! -f "$PAYLOAD_FILE" ]; then echo "❌ Payload missing"; exit 1; fi
if ! command -v jq &> /dev/null; then echo "❌ jq is required."; exit 1; fi

# === DOWNLOAD IMAGES ===
echo "🖼️ Downloading images..."
IMAGE_COUNT=$(jq '.segments | length' "$PAYLOAD_FILE")

for (( i=0; i<IMAGE_COUNT; i++ )); do
  URL=$(jq -r ".segments[$i].imageURL" "$PAYLOAD_FILE")
  OUTPUT="image$((i+1)).jpg"
  curl -s -L -o "$OUTPUT" "$URL"
done

# === CREATE MOTION CLIPS W/ TEXT ===
echo "🎞️ Creating motion clips with captions..."
rm -rf motion_clips
mkdir motion_clips

for (( i=0; i<IMAGE_COUNT; i++ )); do
  IMG="image$((i+1)).jpg"
  BASENAME=$(basename "$IMG" .jpg)
  
  # Get raw caption and escape it for ffmpeg
  RAW_CAPTION=$(jq -r ".segments[$i].caption" "$PAYLOAD_FILE")
  ESCAPED_CAPTION=$(echo "$RAW_CAPTION" | sed "s/'/\\\\'/g")

  ffmpeg -loglevel error -y -loop 1 -t $DURATION -i "$IMG" \
    -vf "zoompan=z='zoom+0.0005':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:fps=$FPS, \
         scale=${WIDTH}:${HEIGHT}, \
         drawtext=font='$FONT':text='$ESCAPED_CAPTION':fontsize=42:fontcolor=white:borderw=1:bordercolor=black:x=(w-text_w)/2:y=h-80, \
         format=yuv420p" \
    -c:v libx264 -preset veryfast -t $DURATION "motion_clips/${BASENAME}.mp4"
done

# === CONCAT CLIPS ===
echo "🧵 Concatenating clips..."
rm -f fileList.txt
for vid in motion_clips/*.mp4; do
  echo "file '$vid'" >> fileList.txt
done

ffmpeg -loglevel error -y -f concat -safe 0 -i fileList.txt -c copy slideshow.mp4

# === VOICEOVER (optional) ===
if [ -f voiceover.mp3 ]; then
  echo "🎙️ Merging voiceover..."
  ffmpeg -loglevel error -y -i slideshow.mp4 -i voiceover.mp3 -c:v copy -c:a aac -shortest final_video.mp4
else
  echo "🎞️ No voiceover found, exporting video only..."
  cp slideshow.mp4 final_video.mp4
fi

echo "✅ SUCCESS: final_video.mp4 created"
