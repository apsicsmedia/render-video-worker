#!/bin/bash
set -e
shopt -s nullglob

# === CONFIGURATION ===
DURATION=5
FPS=25
WIDTH=1280
HEIGHT=720
TOTAL_FRAMES=$((DURATION * FPS))

# === STEP 0: PAYLOAD ===
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

echo "📥 Loaded payload from: $PAYLOAD_FILE"

if [ ! -f "$PAYLOAD_FILE" ]; then echo "❌ Payload missing."; exit 1; fi
if ! command -v jq &> /dev/null; then echo "❌ jq is required."; exit 1; fi

# === STEP 1: DOWNLOAD IMAGES ===
IMAGE_COUNT=$(jq '.segments | length' "$PAYLOAD_FILE")
echo "🖼️ Downloading $IMAGE_COUNT images..."

for (( i=0; i<IMAGE_COUNT; i++ )); do
  URL=$(jq -r ".segments[$i].imageURL" "$PAYLOAD_FILE")
  OUTPUT="image$((i+1)).jpg"
  curl -s -L -o "$OUTPUT" "$URL"
done

# === STEP 2: CAPTIONS ===
jq -r '.captionsSRT' "$PAYLOAD_FILE" > captions.srt
CAPTIONS_EXIST=$(wc -l < captions.srt)

# === STEP 3: CREATE MOTION CLIPS ===
echo "🎞️ Creating motion clips..."
rm -rf motion_clips
mkdir motion_clips

for img in image*.jpg; do
  BASENAME=$(basename "$img" .jpg)
  ffmpeg -loglevel error -y -loop 1 -t $DURATION -i "$img" \
    -vf "zoompan=z='zoom+0.0005':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:fps=$FPS,scale=${WIDTH}:${HEIGHT},format=yuv420p" \
    -c:v libx264 -preset veryfast -t $DURATION "motion_clips/${BASENAME}.mp4"
done

# Validate output
if ! ls motion_clips/*.mp4 1> /dev/null 2>&1; then
  echo "❌ No motion clips generated."
  exit 1
fi

# === STEP 4: CONCAT CLIPS ===
echo "🧵 Concatenating clips..."
rm -f fileList.txt
for vid in motion_clips/*.mp4; do
  echo "file '$vid'" >> fileList.txt
done

ffmpeg -loglevel error -y -f concat -safe 0 -i fileList.txt -c copy slideshow.mp4

# === STEP 5: MERGE AUDIO ===
if [ -f voiceover.mp3 ]; then
  echo "🎙️ Adding voiceover..."
  ffmpeg -loglevel error -y -i slideshow.mp4 -i voiceover.mp3 -c:v copy -c:a aac -shortest temp_video.mp4
else
  echo "🎞️ No voiceover found, skipping audio."
  cp slideshow.mp4 temp_video.mp4
fi

# === STEP 6: SUBTITLES ===
if [ "$CAPTIONS_EXIST" -gt 0 ]; then
  echo "💬 Burning in subtitles..."
  ffmpeg -loglevel error -y -i temp_video.mp4 \
    -vf "subtitles=captions.srt:charenc=UTF-8:force_style='FontName=Roboto,FontSize=48,PrimaryColour=&H00FFFFFF,OutlineColour=&H40000000,BorderStyle=3,Alignment=2,MarginV=60',format=yuv420p,setpts=PTS-STARTPTS" \
    -af "asetpts=PTS-STARTPTS" \
    -c:v libx264 -preset medium -c:a aac -shortest final_video.mp4
else
  echo "🚫 No subtitles found, skipping..."
  ffmpeg -loglevel error -y -i temp_video.mp4 \
    -vf "format=yuv420p,setpts=PTS-STARTPTS" \
    -af "asetpts=PTS-STARTPTS" \
    -c:v libx264 -preset medium -c:a aac -shortest final_video.mp4
fi

# === STEP 7: CLEANUP (optional) ===
# rm -rf image*.jpg motion_clips temp_video.mp4 slideshow.mp4 captions.srt fileList.txt

echo "✅ SUCCESS: final_video.mp4 created"
