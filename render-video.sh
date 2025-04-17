#!/bin/bash
shopt -s nullglob

# Load payload
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

# Require jq
if ! command -v jq &> /dev/null; then exit 1; fi

# Download images
IMAGE_COUNT=$(jq '.segments | length' "$PAYLOAD_FILE")
for (( i=0; i<IMAGE_COUNT; i++ )); do
  URL=$(jq -r ".segments[$i].imageURL" "$PAYLOAD_FILE")
  OUTPUT="image$((i+1)).jpg"
  curl -s -L -o "$OUTPUT" "$URL"
done

# Write captions.srt
jq -r '.captionsSRT' "$PAYLOAD_FILE" > captions.srt

# Constants
DURATION=10
WIDTH=1920
HEIGHT=1080

rm -rf motion_clips
mkdir motion_clips

# Create simple motion clips using scale and crop
for img in image*.jpg; do
  BASENAME=$(basename "$img" .jpg)
  ffmpeg -loglevel error -y -loop 1 -t $DURATION -i "$img" \
    -vf "
      scale=2200:1238, 
      crop=w='iw-2*t':h='ih-2*t':x='t':y='t', 
      fps=30,format=yuv420p
    " \
    -c:v libx264 -preset veryfast -t $DURATION "motion_clips/${BASENAME}.mp4"
done

# Create file list
rm -f fileList.txt
for vid in motion_clips/*.mp4; do
  echo "file '$vid'" >> fileList.txt
done

# Concatenate motion clips
ffmpeg -loglevel error -y -f concat -safe 0 -i fileList.txt -c copy slideshow.mp4

# Merge voiceover if it exists
if [ -f voiceover.mp3 ]; then
  ffmpeg -loglevel error -y -i slideshow.mp4 -i voiceover.mp3 -c:v copy -c:a aac -shortest temp_video.mp4
else
  cp slideshow.mp4 temp_video.mp4
fi

# Burn subtitles
if [ -s captions.srt ]; then
  ffmpeg -loglevel error -y -i temp_video.mp4 \
    -vf "subtitles=captions.srt:charenc=UTF-8:force_style='FontName=Roboto,FontSize=48,PrimaryColour=&H00FFFFFF,OutlineColour=&H40000000,BorderStyle=3,Alignment=2,MarginV=60',format=yuv420p,setpts=PTS-STARTPTS" \
    -af "asetpts=PTS-STARTPTS" \
    -c:v libx264 -preset medium -c:a aac -shortest final_video.mp4
else
  ffmpeg -loglevel error -y -i temp_video.mp4 \
    -vf "format=yuv420p,setpts=PTS-STARTPTS" \
    -af "asetpts=PTS-STARTPTS" \
    -c:v libx264 -preset medium -c:a aac -shortest final_video.mp4
fi

echo "✅ SUCCESS: final_video.mp4 created"
