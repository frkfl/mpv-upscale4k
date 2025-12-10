#!/usr/bin/env bash
# Make a zip for release, removing pictures and editor stuff

set -euo pipefail

cd "$(dirname "$0")"

# Output zip name in your home directory
timestamp="$(date +%Y%m%d-%H%M%S)"
out="$HOME/mpv-config-$timestamp.zip"

echo "Creating $out ..."

# Find all regular files, excluding the ! below.
find . -type f \
  ! -iname "*.jpg" \
  ! -iname "*.jpeg" \
  ! -iname "draft.txt" \
  ! -path "*/.*" \
  -print | zip -@ "$out"

echo "Done."
echo "Created: $out"
