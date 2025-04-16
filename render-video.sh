#!/bin/bash
echo "DEBUG: render-video.sh script started!"
shopt -s nullglob

# Payload setup
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
if [ ! -f "$PAYLOAD_FILE" ]; then echo "Payload missing"; exit 1; fi

# jq check
if ! command -v jq &> /dev/null; then echo "jq not found"; exit 1; fi

# Step 0: Download images
IMAGE_COUNT=$(jq '.segments | length' "$PAYLOAD_FILE")
for (( i=0; i<IMAGE_COUNT; i++ )); do
  URL=$(jq -r ".segments[$i].imageURL" "$PAYLOAD_FILE")
  OUTPUT="image$((i+1)).jpg"
  curl -s -L -o "$OUTPUT" "$URL"
done

# Step 1: Create captions.srt
jq -r '.captionsSRT' "$PAYLOAD_FILE" > captions.srt
echo "DEBUG: Contents of captions.srt:"
cat captions.srt

# Step 2: Create fileList.txt
rm -f fileList.txt
for img in image*.jpg; do
  echo "file '$img'" >> fileList.txt
  echo "duration 10" >> fileList.txt
done
LAST_IMG=$(ls image*.jpg | tail -n 1)
echo "file '$LAST_IMG'" >> fileList.txt

# Step 3: Create slideshow with range fix
ffmpeg -y -f concat -safe 0 -i fileList.txt \
  -vf "fps=30,scale=in_range=full:out_range=tv,format=yuv420p" \
  -c:v libx264 -preset medium slideshow.mp4

# Step 4: Merge voiceover
if [ -f voiceover.mp3 ]; then
  ffmpeg -y -i slideshow.mp4 -i voiceover.mp3 -c:v copy -c:a aac -shortest temp_video.mp4
else
  cp slideshow.mp4 temp_video.mp4
fi

# Step 5: Burn subtitles + re-encode clean start + format fix
if [ -s captions.srt ]; then
  ffmpeg -y -i temp_video.mp4 \
    -vf "subtitles=captions.srt:charenc=UTF-8,setpts=PTS-STARTPTS,format=yuv420p" \
    -af "asetpts=PTS-STARTPTS" \
    -c:v libx264 -preset medium -c:a aac -shortest final_video.mp4
else
  ffmpeg -y -i temp_video.mp4 \
    -vf "setpts=PTS-STARTPTS,format=yuv420p" \
    -af "asetpts=PTS-STARTPTS" \
    -c:v libx264 -preset medium -c:a aac -shortest final_video.mp4
fi

echo "SUCCESS: final_video.mp4 created"
