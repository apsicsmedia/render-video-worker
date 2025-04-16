#!/bin/bash
shopt -s nullglob

# Payload
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

sleep 1
if [ ! -f "$PAYLOAD_FILE" ]; then exit 1; fi

# Check jq
if ! command -v jq &> /dev/null; then exit 1; fi

# Download images
IMAGE_COUNT=$(jq '.segments | length' "$PAYLOAD_FILE")
for (( i=0; i<IMAGE_COUNT; i++ )); do
  URL=$(jq -r ".segments[$i].imageURL" "$PAYLOAD_FILE")
  OUTPUT="image$((i+1)).jpg"
  curl -s -L -o "$OUTPUT" "$URL"
done

# Create captions.srt
jq -r '.captionsSRT' "$PAYLOAD_FILE" > captions.srt

# Create motion clips from each image
rm -rf motion_clips
mkdir motion_clips

DURATION=10
FPS=30
RES=1920x1080
TOTAL_FRAMES=$((DURATION * FPS))

for img in image*.jpg; do
  BASENAME=$(basename "$img" .jpg)
  ffmpeg -loglevel error -y -loop 1 -t $DURATION -i "$img" \
    -filter_complex "
      [0:v]scale=2400:1350,
      zoompan=z='1.002':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=$TOTAL_FRAMES,
      scale=$RES:force_original_aspect_ratio=decrease,
      pad=$RES:(ow-iw)/2:(oh-ih)/2,
      format=yuv420p
    " \
    -c:v libx264 -t $DURATION -preset veryfast "motion_clips/${BASENAME}.mp4"
done

# Build file list
rm -f fileList.txt
for vid in motion_clips/*.mp4; do
  echo "file '$vid'" >> fileList.txt
done

# Concatenate all clips into slideshow
ffmpeg -loglevel error -y -f concat -safe 0 -i fileList.txt -c copy slideshow.mp4

# Merge voiceover
if [ -f voiceover.mp3 ]; then
  ffmpeg -loglevel error -y -i slideshow.mp4 -i voiceover.mp3 -c:v copy -c:a aac -shortest temp_video.mp4
else
  cp slideshow.mp4 temp_video.mp4
fi

# Burn styled subtitles (Roboto, white, black background, 75% opacity)
if [ -s captions.srt ]; then
  ffmpeg -loglevel error -y -i temp_video.mp4 \
    -vf "subtitles=captions.srt:charenc=UTF-8:force_style='FontName=Roboto,FontSize=48,PrimaryColour=&H00FFFFFF,OutlineColour=&H40000000,BorderStyle=3,Alignment=2,MarginV=60',setpts=PTS-STARTPTS,format=yuv420p" \
    -af "asetpts=PTS-STARTPTS" \
    -c:v libx264 -preset medium -c:a aac -shortest final_video.mp4
else
  ffmpeg -loglevel error -y -i temp_video.mp4 \
    -vf "setpts=PTS-STARTPTS,format=yuv420p" \
    -af "asetpts=PTS-STARTPTS" \
    -c:v libx264 -preset medium -c:a aac -shortest final_video.mp4
fi

echo "✅ SUCCESS: final_video.mp4 created"
