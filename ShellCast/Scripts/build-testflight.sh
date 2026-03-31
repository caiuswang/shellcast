#!/bin/bash
set -euo pipefail

# ShellCast — Archive & Upload to TestFlight
#
# Prerequisites:
#   1. Set DEVELOPMENT_TEAM in project.yml to your Apple Team ID
#   2. Run `xcodegen generate` after changing project.yml
#   3. Ensure you're signed into App Store Connect: `xcrun notarytool store-credentials`
#   4. Create the App ID in App Store Connect (com.shellcast.app)
#
# Usage:
#   ./Scripts/build-testflight.sh              # Archive only
#   ./Scripts/build-testflight.sh --upload     # Archive + upload to TestFlight

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/ShellCast.xcarchive"
EXPORT_PATH="${BUILD_DIR}/export"
SCHEME="ShellCast"
PROJECT="${PROJECT_DIR}/ShellCast.xcodeproj"

UPLOAD=false
if [[ "${1:-}" == "--upload" ]]; then
    UPLOAD=true
fi

echo "=== ShellCast TestFlight Build ==="
echo "Project: ${PROJECT}"
echo "Scheme:  ${SCHEME}"
echo ""

# Check DEVELOPMENT_TEAM is set
TEAM_ID=$(grep 'DEVELOPMENT_TEAM:' "${PROJECT_DIR}/project.yml" | sed 's/.*: *"\(.*\)"/\1/')
if [[ -z "$TEAM_ID" ]]; then
    echo "ERROR: DEVELOPMENT_TEAM is empty in project.yml"
    echo "Set it to your Apple Team ID (e.g., ABC123XYZ9)"
    exit 1
fi
echo "Team ID: ${TEAM_ID}"

# Regenerate project
echo ""
echo "--- Regenerating Xcode project ---"
cd "$PROJECT_DIR"
xcodegen generate

# Resolve SPM packages
echo ""
echo "--- Resolving Swift packages ---"
xcodebuild -resolvePackageDependencies -project "$PROJECT" -scheme "$SCHEME"

# Increment build number (timestamp-based for uniqueness)
BUILD_NUMBER=$(date +%Y%m%d%H%M)
echo ""
echo "--- Build number: ${BUILD_NUMBER} ---"
# Update build number in project.yml
sed -i '' "s/CURRENT_PROJECT_VERSION: .*/CURRENT_PROJECT_VERSION: ${BUILD_NUMBER}/" "${PROJECT_DIR}/project.yml"
xcodegen generate >/dev/null 2>&1

# Archive
echo ""
echo "--- Archiving ---"
mkdir -p "$BUILD_DIR"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    | tail -5

if [[ ! -d "$ARCHIVE_PATH" ]]; then
    echo "ERROR: Archive failed — ${ARCHIVE_PATH} not found"
    exit 1
fi
echo "Archive: ${ARCHIVE_PATH}"

# Export IPA
echo ""
echo "--- Exporting IPA ---"
EXPORT_OPTIONS="${SCRIPT_DIR}/ExportOptions.plist"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -allowProvisioningUpdates \
    | tail -5

IPA_PATH="${EXPORT_PATH}/ShellCast.ipa"
if [[ ! -f "$IPA_PATH" ]]; then
    echo "ERROR: Export failed — IPA not found"
    exit 1
fi
echo "IPA: ${IPA_PATH}"

# Upload to TestFlight
if $UPLOAD; then
    echo ""
    echo "--- Uploading to TestFlight ---"
    xcrun altool --upload-app \
        --type ios \
        --file "$IPA_PATH" \
        --apiKey "${APP_STORE_API_KEY:-}" \
        --apiIssuer "${APP_STORE_API_ISSUER:-}" \
        2>&1 || {
        echo ""
        echo "If API key upload fails, try manual upload:"
        echo "  xcrun altool --upload-app -t ios -f '${IPA_PATH}' -u YOUR_APPLE_ID -p @keychain:AC_PASSWORD"
        echo "  or use Transporter.app"
    }
fi

echo ""
echo "=== Done ==="
echo "Archive: ${ARCHIVE_PATH}"
echo "IPA:     ${IPA_PATH}"
