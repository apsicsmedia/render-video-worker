#!/bin/bash
# This script creates a slideshow video from images using FFmpeg.
# It assumes that your images are named in a sequential pattern: image0.jpg, image1.jpg, etc.

# Remove any existing fileList.txt to start fresh
rm -f fileList.txt

# Define the duration for each image (in seconds)
DURATION=5

# Loop through all JPEG images starting with "image"
for img in image*.jpg; do
  echo "file '$img'" >> fileList.txt
  echo "duration $DURATION" >> fileList.txt
done

# FFmpeg concat demuxer requires the last image to be repeated without a duration line.
LAST_IMG=$(ls image*.jpg | tail -n 1)
echo "file '$LAST_IMG'" >> fileList.txt

# Use FFmpeg to create a slideshow video
ffmpeg -f concat -safe 0 -i fileList.txt -vsync vfr -pix_fmt yuv420p slideshow.mp4

echo "Video slideshow created: slideshow.mp4"
