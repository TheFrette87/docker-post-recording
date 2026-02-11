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
exec 3>&1 1>>"${LOG_FILE}" 2>&1

echo "======================================="
echo "INPUT:  $INPUT"
echo "OUTPUT: $OUTPUT"
echo "DATE:   $DATE"
echo "======================================="

#----------------GPU DETECTION----------------
if command -v nvidia-smi >/dev/null 2>&1; then
    GPU_PRESENT=1
else
    GPU_PRESENT=0
fi
echo "GPU present: $GPU_PRESENT"

#----------------CODEC DETECTION----------------
codec_name=$(mediainfo --Inform="Video;%Format%" "$INPUT" | head -c 14)
echo "Detected codec (mediainfo): $codec_name"

#----------------SCALE FILTER (720p cap)----------------
# Only scale if height > 720
HEIGHT=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$INPUT")
echo "Detected height (ffprobe): $HEIGHT"

if [ -n "$HEIGHT" ] && [ "$HEIGHT" -gt 720 ]; then
    SCALE_EXPR="scale=-2:720"
    echo "Scaling enabled: YES (cap at 720p)"
else
    SCALE_EXPR=""
    echo "Scaling enabled: NO (<=720p)"
fi

#----------------NVENC OPTIONS----------------
# IMPORTANT: do NOT include -vf here; we apply scaling per-branch safely
NVENC_OPTIONS="-c:v hevc_nvenc -preset slow -rc:v vbr_hq -cq:v 26 -b:v 0 -rc-lookahead:v 32 -profile:v main -tier:v high -c:a aac -b:a 192k -ignore_unknown -map 0"

#----------------PROCESSING----------------
if [ "$GPU_PRESENT" -eq 1 ]; then
    echo "Running GPU accelerated encoding..."

    # AVC/H264 path (uses filter_complex, so scaling must be inside filter_complex)
    if [[ "$codec_name" == "AVC" || "$codec_name" == "h264" ]]; then
        if [ -n "$SCALE_EXPR" ]; then
            ffmpeg -hwaccel cuvid -c:v h264_cuvid -deint 2 -drop_second_field 1 -surfaces 10 -i "$INPUT" \
              -filter_complex "hwdownload,format=nv12,format=yuv420p,${SCALE_EXPR}" \
              $NVENC_OPTIONS "$OUTPUT"
        else
            ffmpeg -hwaccel cuvid -c:v h264_cuvid -deint 2 -drop_second_field 1 -surfaces 10 -i "$INPUT" \
              -filter_complex "hwdownload,format=nv12,format=yuv420p" \
              $NVENC_OPTIONS "$OUTPUT"
        fi

    # MPEG2 path (safe to use -vf)
    elif [[ "$codec_name" == "MPE" || "$codec_name" == "mpeg2video" ]]; then
        if [ -n "$SCALE_EXPR" ]; then
            ffmpeg -hwaccel cuvid -c:v mpeg2_cuvid -deint 2 -drop_second_field 1 -surfaces 10 -i "$INPUT" \
              -vf "$SCALE_EXPR" \
              $NVENC_OPTIONS "$OUTPUT"
        else
            ffmpeg -hwaccel cuvid -c:v mpeg2_cuvid -deint 2 -drop_second_field 1 -surfaces 10 -i "$INPUT" \
              $NVENC_OPTIONS "$OUTPUT"
        fi

    # Other codecs (nvdec decode; safe to use -vf)
    else
        if [ -n "$SCALE_EXPR" ]; then
            ffmpeg -hwaccel nvdec -i "$INPUT" \
              -vf "$SCALE_EXPR" \
              $NVENC_OPTIONS "$OUTPUT"
        else
            ffmpeg -hwaccel nvdec -i "$INPUT" \
              $NVENC_OPTIONS "$OUTPUT"
        fi
    fi

else
    echo "No GPU detected, using CPU encoding..."
    if [ -n "$SCALE_EXPR" ]; then
        ffmpeg -i "$INPUT" -hide_banner -loglevel info -max_muxing_queue_size 512 \
          -vf "$SCALE_EXPR" \
          -map 0 -ignore_unknown -c:v libx265 -preset slow -c:a aac -b:a 192k "$OUTPUT"
    else
        ffmpeg -i "$INPUT" -hide_banner -loglevel info -max_muxing_queue_size 512 \
          -map 0 -ignore_unknown -c:v libx265 -preset slow -c:a aac -b:a 192k "$OUTPUT"
    fi
fi

echo "Conversion finished!"
