#!/bin/bash

#----------------CONFIG----------------
INPUT="$1"
OUTPUT="$2"
INPUTSRT="$3"

CONFIG_DIR="/config"
LOG_DIR="${CONFIG_DIR}/log/ffmpeg"
mkdir -p "$LOG_DIR"

DATE=$(date +"%d-%m-%Y-%H%M")
LOG_FILE="${LOG_DIR}/$(basename "$INPUT" | sed 's/\.[^.]*$//').$DATE.log"

# Redirect stdout/stderr to log
exec 3>&1 1>>${LOG_FILE} 2>&1

#----------------GPU DETECTION----------------
if command -v nvidia-smi >/dev/null 2>&1; then
    GPU_PRESENT=1
else
    GPU_PRESENT=0
fi
echo "GPU present: $GPU_PRESENT"

#----------------CHAPTER EXTRACTION----------------
# Extract codec_name for proper GPU handling
codec_name=$(mediainfo --Inform="Video;%Format%" "$INPUT" | head -c 14)
echo "Detected codec: $codec_name"

#----------------SCALE FILTER (720p cap)----------------
# Only scale if height > 720
HEIGHT=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$INPUT")
if [ "$HEIGHT" -gt 720 ]; then
    SCALE_FILTER="-vf scale=-2:720"
else
    SCALE_FILTER=""
fi

#----------------NVENC OPTIONS----------------
NVENC_OPTIONS="-c:v hevc_nvenc -preset slow -rc:v vbr_hq -cq:v 26 -b:v 0 -rc-lookahead:v 32 -profile:v main -tier:v high -c:a aac -b:a 192k -ignore_unknown -map 0 $SCALE_FILTER"

#----------------PROCESSING----------------
if [ $GPU_PRESENT -eq 1 ]; then
    echo "Running GPU accelerated encoding..."
    if [[ "$codec_name" == "AVC" || "$codec_name" == "h264" ]]; then
        ffmpeg -hwaccel cuvid -c:v h264_cuvid -deint 2 -drop_second_field 1 -surfaces 10 -i "$INPUT" -filter_complex "hwdownload,format=nv12,format=yuv420p" $NVENC_OPTIONS "$OUTPUT"
    elif [[ "$codec_name" == "MPE" || "$codec_name" == "mpeg2video" ]]; then
        ffmpeg -hwaccel cuvid -c:v mpeg2_cuvid -deint 2 -drop_second_field 1 -surfaces 10 -i "$INPUT" $NVENC_OPTIONS "$OUTPUT"
    else
        ffmpeg -hwaccel nvdec -i "$INPUT" $NVENC_OPTIONS "$OUTPUT"
    fi
else
    echo "No GPU detected, using CPU encoding..."
    ffmpeg -i "$INPUT" -hide_banner -loglevel info -max_muxing_queue_size 512 $SCALE_FILTER -map 0 -ignore_unknown -c:v libx265 -preset slow -c:a aac -b:a 192k "$OUTPUT"
fi

echo "Conversion finished!"