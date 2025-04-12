#!/bin/bash
# render-video.sh - Create a slideshow video from images, merge with voiceover, and add captions.

# Check if payload.json exists
if [ -f payload.json ]; then
  echo "Downloading images from payload..."
  # Extract each image URL from the payload (assumes 'segments' is an array in the JSON)
  IMAGE_COUNT=$(jq '.segments | length' payload.json)
  for (( i=0; i<IMAGE_COUNT; i++ )); do
    # Get image URL and set the output filename: image1.jpg, image2.jpg, etc.
    URL=$(jq -r ".segments[$i].imageURL" payload.json)
    OUTPUT="image$((i+1)).jpg"
    echo "Downloading image from $URL to $OUTPUT"
    curl -s -o "$OUTPUT" "$URL"
  done
else
  echo "payload.json not found. Please ensure the payload file is available." >&2
  exit 1
fi

# Set image display duration (in seconds)
DURATION=10

# Remove any existing file list
rm -f fileList.txt

# Create fileList.txt from all images matching image*.jpg
for img in image*.jpg; do
  # Check if file exists and is non-empty
  if [ -s "$img" ]; then
    echo "file '$img'" >> fileList.txt
    echo "duration $DURATION" >> fileList.txt
  else
    echo "Warning: $img not found or is empty." >&2
  fi
done

# FFmpeg requires the last image to be repeated without a duration line.
LAST_IMG=$(ls image*.jpg | tail -n 1)
if [ -n "$LAST_IMG" ]; then
  echo "file '$LAST_IMG'" >> fileList.txt
else
  echo "No images found. Exiting."
  exit 1
fi

# Step 1: Generate slideshow video from images
echo "Creating slideshow video from images..."
ffmpeg -f concat -safe 0 -i fileList.txt -fps_mode vfr -pix_fmt yuv420p slideshow.mp4

# Step 2: Merge audio (voiceover) if available.
if [ -f voiceover.mp3 ]; then
  echo "Merging voiceover audio into video..."
  ffmpeg -i slideshow.mp4 -i voiceover.mp3 -c:v copy -c:a aac -shortest temp_video.mp4
else
  echo "Voiceover file (voiceover.mp3) not found, skipping audio merge."
  cp slideshow.mp4 temp_video.mp4
fi

# Step 3: Add captions/subtitles if an SRT file is available.
if [ -f captions.srt ]; then
  echo "Adding captions from captions.srt..."
  ffmpeg -i temp_video.mp4 -vf "subtitles=captions.srt" final_video.mp4
else
  echo "Captions file (captions.srt) not found, skipping caption overlay."
  cp temp_video.mp4 final_video.mp4
fi

echo "Final video created: final_video.mp4"
