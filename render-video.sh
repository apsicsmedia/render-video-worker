#!/bin/bash
set -e
LOG=/app/render-worker.log

echo "🔄 Starting render at $(date)" >> "$LOG"

# 1) First argument is path to JSON payload
PAYLOAD="$1"
if [ ! -f "$PAYLOAD" ]; then
  echo "❌ Missing payload file: $PAYLOAD" >> "$LOG"
  exit 1
fi

echo "✅ Using payload: $PAYLOAD" >> "$LOG"

# 2) Extract image URLs and write captions.srt
mapfile -t IMAGE_URLS < <(jq -r '.segments[].imageURL' "$PAYLOAD")
jq -r '.captionsSRT' "$PAYLOAD" > /app/captions.srt

echo "📥 captions.srt written" >> "$LOG"

# 3) Download images
mkdir -p /app/images
for i in "${!IMAGE_URLS[@]}"; do
  idx=$((i+1))
  url="${IMAGE_URLS[i]}"
  out="/app/images/image${idx}.jpg"
  echo "📥 Downloading $url → $out" >> "$LOG"
  curl -sL "$url" -o "$out"
done

echo "✅ Images downloaded: ${#IMAGE_URLS[@]} files" >> "$LOG"

# 4) Render video with subtitles overlay
ffmpeg -y \
  -framerate 1/5 \
  -i /app/images/image%01d.jpg \
  -vf "subtitles=/app/captions.srt:force_style='FontName=DejaVuSans-Bold,FontSize=48,PrimaryColour=&HFFFFFF&,Outline=2,BorderStyle=3'" \
  -c:v libx264 -preset veryfast /app/final_video.mp4 >> "$LOG" 2>&1

echo "✅ Video created at /app/final_video.mp4" >> "$LOG"
