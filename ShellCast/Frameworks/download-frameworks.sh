#!/bin/bash
# Download pre-built Mosh and Protobuf xcframeworks for iOS
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Downloading mosh.xcframework..."
gh release download v1.4.0+blink-18.4.5 -R blinksh/mosh-apple -p "mosh.xcframework.zip" --clobber
unzip -o mosh.xcframework.zip
rm mosh.xcframework.zip

# Strip non-iOS platforms
for dir in mosh.xcframework/macos-* mosh.xcframework/tvos-* mosh.xcframework/watchos-* mosh.xcframework/ios-*-maccatalyst; do
    [ -d "$dir" ] && rm -rf "$dir"
done

echo "Downloading Protobuf_C_.xcframework..."
gh release download v3.21.1 -R blinksh/protobuf-apple -p "Protobuf_C_-static.xcframework.zip" --clobber
unzip -o Protobuf_C_-static.xcframework.zip
rm Protobuf_C_-static.xcframework.zip

# Strip non-iOS platforms and sanitize metadata for the remaining iOS slices
for dir in Protobuf_C_.xcframework/macos-* Protobuf_C_.xcframework/tvos-* Protobuf_C_.xcframework/watchos-* Protobuf_C_.xcframework/ios-*-maccatalyst; do
    [ -d "$dir" ] && rm -rf "$dir"
done
find Protobuf_C_.xcframework -name "dSYMs" -type d -exec rm -rf {} + 2>/dev/null || true

python3 - <<'PY'
import plistlib
from pathlib import Path

xcframework = Path("Protobuf_C_.xcframework")
info_path = xcframework / "Info.plist"

with info_path.open("rb") as fh:
    info = plistlib.load(fh)

libraries = []
for library in info.get("AvailableLibraries", []):
    identifier = library.get("LibraryIdentifier")
    if not identifier:
        continue

    library_dir = xcframework / identifier
    if not library_dir.exists():
        continue

    debug_symbols_path = library.get("DebugSymbolsPath")
    if debug_symbols_path and not (library_dir / debug_symbols_path).exists():
        library = dict(library)
        library.pop("DebugSymbolsPath", None)

    libraries.append(library)

info["AvailableLibraries"] = libraries

with info_path.open("wb") as fh:
    plistlib.dump(info, fh)
PY

echo "Done. Frameworks ready in $SCRIPT_DIR"
