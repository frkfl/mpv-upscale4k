#!/usr/bin/env bash

# Usage:
#   vhs_restore.sh INPUT [OUTPUT] [MPV_PROFILE_CONF]
#
# INPUT  = source video (e.g. VHS capture)
# OUTPUT = encoded 4K HEVC file
#          default: "<input basename>_restored.mkv" in the same directory
# MPV_PROFILE_CONF (optional) = mpv profile file containing glsl-shaders-append lines
#
# Requirement
# - Linux
# - Nvidia GPU
# - ffmpeg and mpv installed
#
# But you can change the script to CPU encoding, run it on WSL, and enjoy a 3 hours break

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

# Build shader list from glsl-shaders-append lines.
# ffmpeg's libplacebo custom_shader_path only accepts a single file.
# Multiple shaders are handled by concatenating them into one temp file —
# libplacebo parses multiple !HOOK sections from a single file the same way
# it processes multiple files in mpv.
SHADER_LIST=()

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
        *)  path="$MPV_ROOT/$path" ;;
      esac

      # Shaders using //!STORAGE (imageLoad/imageStore compute) fail on this GPU setup.
      # ssim_downscale_remaster fails PARAM parsing in ffmpeg libplacebo.
      case "$path" in
        *nlmeans_parameter*|\
        *temporal_luma_grain*|\
        *temporal_luma_grain2*|\
        *temporal_motion_blur*|\
        *temporal_motion_blur2*|\
        *temporal_sharpen*|\
        *temporal_stabilizer*|\
        *static_smooth*|\
        *skin_temporal_grain*|\
        *dnr_residue_clean*)
          echo "Skipping (incompatible): $(basename "$path")" >&2 ;;
        *) SHADER_LIST+=("$path") ;;
      esac
      ;;
  esac
done < "$MPV_CONF"

if [[ ${#SHADER_LIST[@]} -eq 0 ]]; then
  echo "No glsl-shaders-append lines found in $MPV_CONF" >&2
  exit 1
fi

# Concatenate all shaders into a single temp file.
# Strip leading non-//! lines from each file: libplacebo parses from the first
# //! directive; anything before it is documentation. Leaving those comment
# blocks in place causes the parser to treat them as the body of the preceding
# shader's //!STORAGE texture and fail with "not a valid hexadecimal sequence".
TEMP_SHADER=$(mktemp --suffix=.glsl)

for shader_path in "${SHADER_LIST[@]}"; do
  sed -n '/^\/\/!/,$p' "$shader_path"
  echo; echo  # blank line between shaders so //!STORAGE isn't directly followed by //!PARAM
done > "$TEMP_SHADER"

# Detect deinterlace=auto in the profile
VF_PREFIX="format=yuv420p,"
if grep -q '^deinterlace=auto' "$MPV_CONF"; then
  VF_PREFIX+="bwdif=mode=send_frame:parity=auto:deint=all,"
fi

# Full libplacebo block:
# - keep 4:3 AR, upscale to 2160p (w=-1:h=2160)
# - upscaler defaults to spline36, matching mpv.conf scale=spline36 — no override needed
# - disable_builtin=true lets RAVU/SSimSuperRes hook shaders own upscaling
# - dithering=none because bayer_dither.glsl handles it
# - color metadata auto-detected from stream; no explicit colorspace/range needed
# - apply all shaders in mpv order from the concatenated file
VF_LIBPLACEBO="${VF_PREFIX}libplacebo=w=-1:h=2160:disable_builtin=true:dithering=none:custom_shader_path=${TEMP_SHADER},format=p010le"

# Try to reuse mpv's af= line if present in this profile
AF_FILTER=""
AF_LINE="$(grep -m1 '^af=' "$MPV_CONF" 2>/dev/null || true)"
if [[ -n "$AF_LINE" ]]; then
  AF_FILTER="${AF_LINE#af=}"
fi

# Pick encoder: prefer NVENC, fall back to libx265
if ffmpeg -f lavfi -i nullsrc -t 0 -c:v hevc_nvenc -f null - &>/dev/null; then
  VIDEO_CODEC=( -c:v hevc_nvenc -profile:v main10 -pix_fmt p010le
                -preset p5 -tune hq -rc vbr -cq 16 -b:v 0
                -spatial_aq 1 -temporal_aq 1 -aq-strength 10 -multipass fullres )
  echo "Encoder: hevc_nvenc"
else
  VIDEO_CODEC=( -c:v libx265 -profile:v main10 -pix_fmt yuv420p10le
                -preset medium -crf 18 -x265-params "aq-mode=3" )
  echo "Encoder: libx265 (nvenc unavailable)"
fi

FFMPEG_CMD=(
  ffmpeg
  -i "$IN"
  -vf "$VF_LIBPLACEBO"
  "${VIDEO_CODEC[@]}"
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
printf '  %s\n' "${SHADER_LIST[@]}"
echo
echo "Running ffmpeg..."
printf '  %q ' "${FFMPEG_CMD[@]}"
echo
echo

exec "${FFMPEG_CMD[@]}"
