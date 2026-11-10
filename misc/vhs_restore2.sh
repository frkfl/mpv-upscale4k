#!/usr/bin/env bash
# vhs_restore_final.sh INPUT [OUTPUT]

set -u

IN="$1"
OUT="${2:-${IN%.*}_restored.mkv}"
TEMP="${IN%.*}_temp_prores.mov"

echo "=== Step 1: mpv rendering full shader chain to lossless ProRes"
echo "Input:  $IN"
echo "Temp:   $TEMP"
echo

mpv "$IN" \
  --no-audio \
  --o="$TEMP"

echo
echo "=== Step 2: ffmpeg encoding to HEVC (your final 4K file)"
echo "Output: $OUT"
echo

ffmpeg -i "$TEMP" \
  -c:v hevc_nvenc \
  -profile:v main10 \
  -preset p5 \
  -tune hq \
  -rc vbr \
  -cq 16 \
  -spatial_aq 1 \
  -temporal_aq 1 \
  -aq-strength 10 \
  -multipass fullres \
  -c:a aac -b:a 192k \
  -y "$OUT"

rm -f "$TEMP"   # delete temp file (comment out if you want to keep it)

echo "✅ Done → $OUT"