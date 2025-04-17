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

# Build file list
rm -f fileList.txt
for img in image*.jpg; do
  echo "file '$img'" >> fileList.txt
  echo "duration 10" >> fileList.txt
done
LAST_IMG=$(ls image*.jpg | tail -n 1)
echo "file '$LAST_IMG'" >> fileList.txt

# Create slideshow
ffmpeg -loglevel error -y -f concat -safe 0 -i fileList.txt \
  -vf "fps=30,scale=in_range=full:out_range=tv,format=yuv420p" \
  -c:v libx264 -preset medium slideshow.mp4

# Merge voiceover
if [ -f voiceover.mp3 ]; then
  ffmpeg -loglevel error -y -i slideshow.mp4 -i voiceover.mp3 -c:v copy -c:a aac -shortest temp_video.mp4
else
  cp slideshow.mp4 temp_video.mp4
fi

# Burn subtitles
if [ -s captions.srt ]; then
  ffmpeg -loglevel error -y -i temp_video.mp4 \
    -vf "subtitles=captions.srt:charenc=UTF-8:force_style='FontName=Impact,FontSize=42,PrimaryColour=&H00FFFF00&,OutlineColour=&H00000000&,BackColour=&H64000000&,BorderStyle=1,Outline=3,Shadow=0,Alignment=2,MarginV=50',setpts=PTS-STARTPTS,format=yuv420p" \
    -af "asetpts=PTS-STARTPTS" \
    -c:v libx264 -preset medium -c:a aac -shortest final_video.mp4
else
  ffmpeg -loglevel error -y -i temp_video.mp4 \
    -vf "setpts=PTS-STARTPTS,format=yuv420p" \
    -af "asetpts=PTS-STARTPTS" \
    -c:v libx264 -preset medium -c:a aac -shortest final_video.mp4
fi

echo "SUCCESS: final_video.mp4 created"
