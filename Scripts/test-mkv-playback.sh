#!/bin/sh
set -eu
if [ "$#" -ne 1 ]; then
    echo 'Usage: sh Scripts/test-mkv-playback.sh /absolute/path/to/short-test.mkv' >&2
    exit 2
fi
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"
developer_root=${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}
compiler="$developer_root/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
sdk="$developer_root/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
framework_root="$project_root/Frameworks/VLCKit.xcframework/macos-arm64_x86_64"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/Contents/MacOS" "$work/Contents/Frameworks"
ln -s "$framework_root/VLCKit.framework" "$work/Contents/Frameworks/VLCKit.framework"
"$compiler" -sdk "$sdk" -module-cache-path "$work/modules" -F "$framework_root" -framework VLCKit \
    YouTubePlayer/StreamingProvider.swift YouTubePlayer/MKVPlayback.swift Tests/MKVPlaybackTests.swift \
    -o "$work/Contents/MacOS/mkv-tests"
"$work/Contents/MacOS/mkv-tests" "$1"
