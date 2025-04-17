#!/bin/bash

# Log the start of the render worker
echo "🔄 Render worker is starting..." >> /app/render-worker.log
echo "Start time: $(date)" >> /app/render-worker.log

# Create the directory to store logs (if it doesn't exist)
mkdir -p /app/logs

# Capture the incoming request
echo "Received request at $(date)" >> /app/render-worker.log
echo "Request Body: $@" >> /app/render-worker.log

# If the request includes specific arguments (e.g., $1 is the payload), 
# you can store it in a file to further process it
echo "Saving request body to /app/request_payload.json" >> /app/render-worker.log
echo "$@" > /app/request_payload.json

# Check if the request was received (for debugging purposes)
if [ -f /app/request_payload.json ]; then
    echo "✅ Request payload saved to /app/request_payload.json" >> /app/render-worker.log
else
    echo "❌ Failed to save request payload" >> /app/render-worker.log
    exit 1
fi

# Extract video data (e.g., image URLs, captions, etc.)
IMAGE_URLS=$(jq -r '.segments[].imageURL' /app/request_payload.json)
CAPTIONS=$(jq -r '.segments[].caption' /app/request_payload.json)

# Create the motion clips
echo "🎞️ Creating motion clips..." >> /app/render-worker.log
mkdir -p /app/motion_clips

INDEX=0
for IMAGE_URL in $IMAGE_URLS; do
    CAPTION=$(echo $CAPTIONS | jq -r ".[$INDEX]")

    # Download the image
    IMAGE_FILE="/app/motion_clips/image$((INDEX+1)).jpg"
    echo "📥 Downloading image $((INDEX+1)) from $IMAGE_URL to $IMAGE_FILE" >> /app/render-worker.log
    curl -s -L -o "$IMAGE_FILE" "$IMAGE_URL"

    # Check if the image was downloaded successfully
    if [ ! -f "$IMAGE_FILE" ]; then
        echo "❌ Error: Image $((INDEX+1)) not downloaded!" >> /app/render-worker.log
        exit 1
    fi

    # Create a video clip from the image
    CLIP_FILE="/app/motion_clips/clip$((INDEX+1)).mp4"
    ffmpeg -loglevel info -y -loop 1 -t 5 -i "$IMAGE_FILE" \
      -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='$CAPTION':fontsize=48:fontcolor=white:borderw=2:bordercolor=black:x=(w-text_w)/2:y=h-line_h-80" \
      -c:v libx264 -preset veryfast "$CLIP_FILE"

    # Check if the clip was created
    if [ ! -f "$CLIP_FILE" ]; then
        echo "❌ Error: Video clip $((INDEX+1)) not created!" >> /app/render-worker.log
        exit 1
    fi

    echo "✅ Clip $((INDEX+1)) created: $CLIP_FILE" >> /app/render-worker.log
    INDEX=$((INDEX+1))
done

# Concatenate the clips into a single video
echo "🧵 Concatenating clips into final video..." >> /app/render-worker.log
echo "file '/app/motion_clips/clip1.mp4'" > /app/motion_clips/fileList.txt
for i in $(seq 2 $INDEX); do
    echo "file '/app/motion_clips/clip$i.mp4'" >> /app/motion_clips/fileList.txt
done

ffmpeg -loglevel info -y -f concat -safe 0 -i /app/motion_clips/fileList.txt -c copy /app/final_video.mp4

# Check if the final video is created
if [ ! -f "/app/final_video.mp4" ]; then
    echo "❌ Error: Final video not created!" >> /app/render-worker.log
    exit 1
else
    echo "✅ Final video created: /app/final_video.mp4" >> /app/render-worker.log
fi

# Optionally, if you have a voiceover to merge, do it here (ensure voiceover.mp3 exists)
if [ -f /app/voiceover.mp3 ]; then
    echo "🎙️ Merging voiceover..." >> /app/render-worker.log
    ffmpeg -loglevel info -y -i /app/final_video.mp4 -i /app/voiceover.mp3 -c:v copy -c:a aac -shortest /app/final_video_with_audio.mp4
    echo "✅ Final video with audio created: /app/final_video_with_audio.mp4" >> /app/render-worker.log
else
    echo "🎞️ No voiceover provided." >> /app/render-worker.log
fi

# Respond with success message
echo "✅ Render job completed successfully!" >> /app/render-worker.log
echo "Render job started successfully!"
