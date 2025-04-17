#!/bin/bash

# Log the start of the render worker
echo "🔄 Render worker is starting..." >> /app/render-worker.log
echo "Start time: $(date)" >> /app/render-worker.log

# Create the directory to store logs and images (if it doesn't exist)
mkdir -p /app/logs /app/images

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
CAPTIONS=$(jq -r '.segments[].captionsSRT' /app/request_payload.json)

# Download the images
echo "📥 Downloading images..." >> /app/render-worker.log
INDEX=0
for IMAGE_URL in $IMAGE_URLS; do
    IMAGE_FILE="/app/images/image$((INDEX+1)).jpg"
    echo "📥 Downloading image $((INDEX+1)) from $IMAGE_URL to $IMAGE_FILE" >> /app/render-worker.log
    curl -s -L -o "$IMAGE_FILE" "$IMAGE_URL"

    # Check if the image was downloaded successfully
    if [ ! -f "$IMAGE_FILE" ]; then
        echo "❌ Error: Image $((INDEX+1)) not downloaded!" >> /app/render-worker.log
        exit 1
    else
        echo "✅ Image $((INDEX+1)) downloaded: $IMAGE_FILE" >> /app/render-worker.log
    fi

    INDEX=$((INDEX+1))
done

# Use FFmpeg to create a video from the images with captions
echo "🎞️ Creating video from images with captions..." >> /app/render-worker.log

# Generate video using FFmpeg: loop through images and add captions
ffmpeg_command="ffmpeg -y"
for (( i=0; i<$INDEX; i++ )); do
    IMAGE_FILE="/app/images/image$((i+1)).jpg"
    CAPTION=$(echo "$CAPTIONS" | jq -r ".[$i]")

    # Escape any special characters in the caption to prevent errors with FFmpeg
    ESCAPED_CAPTION=$(printf "%q" "$CAPTION")

    # Build the FFmpeg command to apply the caption
    ffmpeg_command="$ffmpeg_command -loop 1 -t 5 -i $IMAGE_FILE \
        -vf \"drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='$ESCAPED_CAPTION':fontsize=48:fontcolor=white:borderw=2:bordercolor=black:x=(w-text_w)/2:y=h-line_h-80\" \
        -c:v libx264 -preset veryfast"
done

# Final video output file
OUTPUT_FILE="/app/final_video.mp4"
ffmpeg_command="$ffmpeg_command $OUTPUT_FILE"

# Run the FFmpeg command to generate the video
echo "Running FFmpeg command: $ffmpeg_command" >> /app/render-worker.log
eval $ffmpeg_command

# Check if the final video is created
if [ ! -f "$OUTPUT_FILE" ]; then
    echo "❌ Error: Final video not created!" >> /app/render-worker.log
    exit 1
else
    echo "✅ Final video created: $OUTPUT_FILE" >> /app/render-worker.log
fi

# Respond with success message
echo "✅ Render job completed successfully!" >> /app/render-worker.log
echo "Render job started successfully!"
