#!/bin/bash
set -e
shopt -s nullglob

echo "🚀 Starting render-video.sh..."

# === CONFIG ===
DURATION=5
FPS=25
WIDTH=1280
HEIGHT=720
FONT_FILE="/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

echo "🔧 Config:"
echo "  Duration per image: $DURATION sec"
echo "  FPS: $FPS"
echo "  Resolution: ${WIDTH}x${HEIGHT}"
echo "  Font: $FONT_FILE"

# === PAYLOAD LOAD ===
echo "📦 Loading payload..."
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
echo "✅ Payload loaded: $PAYLOAD_FILE"

if ! command -v jq &> /dev/null; then echo "❌ jq is required."; exit 1; fi

# === DOWNLOAD IMAGES ===
echo "🖼️ Downloading images..."
IMAGE_COUNT=$(jq '.segments | length' "$PAYLOAD_FILE")
echo "📊 Total segments: $IMAGE_COUNT"

for (( i=0; i<IMAGE_COUNT; i++ )); do
  URL=$(jq -r ".segments[$i].imageURL" "$PAYLOAD_FILE")
  OUTPUT="image$((i+1)).jpg"
  echo "📥 [${i}] Downloading: $URL → $OUTPUT"
  curl -s -L -o "$OUTPUT" "$URL"
done

# === CREATE MOTION CLIPS W/ TEXT ===
echo "🎞️ Creating motion clips with captions..."
rm -rf motion_clips
mkdir motion_clips

for (( i=0; i<IMAGE_COUNT; i++ )); do
  IMG="image$((i+1)).jpg"
  BASENAME=$(basename "$IMG" .jpg)

  RAW_CAPTION=$(jq -r ".segments[$i].caption" "$PAYLOAD_FILE")
  RAW_CAPTION=$(echo "$RAW_CAPTION" | sed 's/:/ -/g; s/&/and/g; s/["'\'']//g' | xargs)
  CAPTION_FILE="caption$((i+1)).txt"
  echo "$RAW_CAPTION" > "$CAPTION_FILE"

  echo "📝 [${i}] Caption saved to $CAPTION_FILE: $RAW_CAPTION"

  ffmpeg -loglevel info -y -loop 1 -t $DURATION -i "$IMG" \
    -vf "zoompan=z='zoom+0.0005':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:fps=$FPS, \
         scale=${WIDTH}:${HEIGHT}, \
         drawtext=fontfile='$FONT_FILE':textfile='$CAPTION_FILE':fontsize=48:fontcolor=white:borderw=2:bordercolor=black:x=(w-text_w)/2:y=h-line_h-80, \
         format=yuv420p" \
    -c:v libx264 -preset veryfast -t $DURATION "motion_clips/${BASENAME}.mp4"

  echo "✅ Clip created: motion_clips/${BASENAME}.mp4"
done

# === CONCAT CLIPS ===
echo "🧵 Concatenating clips into slideshow..."
rm -f fileList.txt
for vid in motion_clips/*.mp4; do
  echo "file '$vid'" >> fileList.txt
done
cat fileList.txt

ffmpeg -loglevel info -y -f concat -safe 0 -i fileList.txt -c copy slideshow.mp4
echo "🎬 Slideshow created: slideshow.mp4"

# === VOICEOVER (optional) ===
if [ -f voiceover.mp3 ]; then
  echo "🎙️ Merging with voiceover..."
  ffmpeg -loglevel info -y -i slideshow.mp4 -i voiceover.mp3 -c:v copy -c:a aac -shortest final_video.mp4
  echo "🎧 Final video with audio: final_video.mp4"
else
  echo "🎞️ No voiceover found — using video only."
  cp slideshow.mp4 final_video.mp4
  echo "📽️ Final video: final_video.mp4"
fi

# === CLEANUP (optional) ===
rm -f caption*.txt

echo "✅ DONE: final_video.mp4 is ready"
