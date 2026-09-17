# VLCKit

Run `sh Scripts/setup-vlckit.sh` from the project root. The script fetches the official VLCKit 3.7.3 macOS binary and verifies its pinned SHA-256. The downloaded XCFramework is ignored by Git and is linked and embedded by Xcode for both Apple Silicon and Intel.

Source: https://code.videolan.org/videolan/VLCKit (VLCKit revision `319ed2c0`, VLC revision `79128878`, as identified by the upstream archive).
Download: https://download.videolan.org/cocoapods/prod/VLCKit-3.7.3-319ed2c0-79128878.tar.xz

The upstream license is included in `VLCKit-COPYING.txt` and copied into the app resources. VLCKit and libVLC are dynamically linked; their source and build instructions are available from VideoLAN. No conversion utility or external player is used by the app.
