#!/usr/bin/env bash

# Usage:
#   vhs_restore.sh INPUT [OUTPUT] [MPV_PROFILE_CONF]
#
# INPUT  = source video (e.g. VHS capture)
# OUTPUT = encoded 4K HEVC file
#          default: "<input basename>_restored.mkv" in the same directory
# MPV_PROFILE_CONF (optional) = mpv profile file containing glsl-shaders-append lines

set -u

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 INPUT [OUTPUT] [MPV_PROFILE_CONF]" >&2
  exit 1
fi

IN="$1"

# If OUTPUT not given, derive it from INPUT: strip extension, add _restored.mkv
if [[ $# -ge 2 && -n "${2:-}" ]]; then
  OUT="$2"
else
  # Keep directory, strip only the last extension
  in_dir=$(dirname -- "$IN")
  in_base=$(basename -- "$IN")
  base_no_ext="${in_base%.*}"
  OUT="${in_dir}/${base_no_ext}_restored.mkv"
fi

# Default mpv profile, can be overridden by $3
MPV_CONF="${3:-$HOME/.config/mpv/profiles/480p.conf}"

if [[ ! -f "$MPV_CONF" ]]; then
  echo "mpv profile not found: $MPV_CONF" >&2
  exit 1
fi

MPV_ROOT="${MPV_ROOT:-$HOME/.config/mpv}"

# Build shader chain from glsl-shaders-append lines
SHADER_CHAIN=""

while IFS= read -r line; do
  # Strip leading/trailing spaces
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"

  case "$line" in
    glsl-shaders-append*=*)
      # Extract the path between the first and last double-quote
      path=${line#*\"}
      path=${path%\"*}

      # Expand mpv's ~~/
      if [[ "$path" == "~~/"* ]]; then
        path="$MPV_ROOT/${path#"~~/"}"
      fi

      # Make it absolute if it isn't already
      case "$path" in
        /*) ;;  # already absolute
        *)
          path="$MPV_ROOT/$path"
          ;;
      esac

      SHADER_CHAIN+="custom_shader_path=${path}:"
      ;;
  esac
done < "$MPV_CONF"

if [[ -z "$SHADER_CHAIN" ]]; then
  echo "No glsl-shaders-append lines found in $MPV_CONF" >&2
  exit 1
fi

# Detect deinterlace=auto in the profile
VF_PREFIX="format=yuv420p,"
if grep -q '^deinterlace=auto' "$MPV_CONF"; then
  VF_PREFIX+="bwdif=mode=send_frame:parity=auto:deint=all,"
fi

# Full libplacebo block:
# - keep 4:3 AR, upscale to 2160p (w=-1:h=2160)
# - apply all shaders in mpv order
VF_LIBPLACEBO="${VF_PREFIX}libplacebo=w=-1:h=2160:${SHADER_CHAIN}disable_builtin=1,format=p010le"

# Try to reuse mpv's af= line if present in this profile
AF_FILTER=""
AF_LINE="$(grep -m1 '^af=' "$MPV_CONF" 2>/dev/null || true)"
if [[ -n "$AF_LINE" ]]; then
  AF_FILTER="${AF_LINE#af=}"
fi

# Build ffmpeg command
# Video: HEVC NVENC, 10-bit, quality-oriented settings
FFMPEG_CMD=(
  ffmpeg
  -i "$IN"
  -vf "$VF_LIBPLACEBO"
  -c:v hevc_nvenc
  -profile:v main10
  -pix_fmt p010le
  -preset p5
  -tune hq
  -rc vbr
  -cq 16
  -b:v 0
  -spatial_aq 1
  -temporal_aq 1
  -aq-strength 10
  -multipass fullres
)

# Audio
if [[ -n "$AF_FILTER" ]]; then
  FFMPEG_CMD+=( -af "$AF_FILTER" )
fi
FFMPEG_CMD+=( -c:a aac -b:a 192k )

# Output
FFMPEG_CMD+=( -y "$OUT" )

echo "Using mpv profile: $MPV_CONF"
echo "Shaders:"
printf '  %s\n' ${SHADER_CHAIN//custom_shader_path=/}
echo
echo "Running ffmpeg..."
printf '  %q ' "${FFMPEG_CMD[@]}"
echo
echo

exec "${FFMPEG_CMD[@]}"
