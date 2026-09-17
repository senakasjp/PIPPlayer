#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
framework="$project_root/Frameworks/VLCKit.xcframework"
if [ -d "$framework" ]; then
    echo 'VLCKit is already available.'
    exit 0
fi
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
archive="$scratch/VLCKit.tar.xz"
curl --fail --location --retry 3 \
    'https://download.videolan.org/cocoapods/prod/VLCKit-3.7.3-319ed2c0-79128878.tar.xz' \
    --output "$archive"
printf '%s  %s\n' '019afdae4e2e2d0f3ac325fac8f7ba0af25dca70b9d157df7d60db88e0be8e5d' "$archive" | shasum -a 256 --check
mkdir -p "$scratch/extracted" "$project_root/Frameworks"
tar -xf "$archive" -C "$scratch/extracted"
mv "$scratch/extracted/VLCKit - binary package/VLCKit.xcframework" "$framework"
echo 'VLCKit 3.7.3 is ready. Build YouTubePlayer.xcodeproj normally.'
