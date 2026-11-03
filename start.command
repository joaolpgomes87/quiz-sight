#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="$PWD/QuizSight.app"
BUILD_LOG="$PWD/quizlens-build.log"
VERSION="3.6"

# macOS associates screen recording permission with the app signature.
# Ad-hoc signatures change on rebuild, so do not rebuild during normal startup.
if [[ -x "$APP/Contents/MacOS/QuizLens" && "${1:-}" != "--rebuild" ]]; then
    CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || true)
    if [[ "$CURRENT_VERSION" == "$VERSION" ]]; then
        echo 'Opening the existing QuizSight app without rebuilding or changing its signature…'
        open "$APP"
        exit 0
    fi
    echo 'An older version was found; building the current version.'
fi

if [[ "${1:-}" == "--rebuild" ]]; then
    echo 'Warning: rebuilding may require Screen Recording permission again.'
    echo 'Quit QuizSight before continuing.'
fi

if ! command -v xcrun >/dev/null 2>&1 || ! xcrun --find swiftc >/dev/null 2>&1; then
    echo 'Swift compiler unavailable. Install or repair the Apple Command Line Tools.'
    echo 'xcode-select --install'
    exit 1
fi

TEMP_APP="$PWD/.QuizLens-build-$$.app"
trap 'rm -rf "$TEMP_APP"' EXIT
mkdir -p "$TEMP_APP/Contents/MacOS" "$TEMP_APP/Contents/Resources"
cp Info.plist "$TEMP_APP/Contents/Info.plist"
cp QuizSight.icns "$TEMP_APP/Contents/Resources/QuizSight.icns"
cp QuizSightMenuBarColor.png "$TEMP_APP/Contents/Resources/QuizSightMenuBarColor.png"
cp QuizSight-Icon.png "$TEMP_APP/Contents/Resources/QuizSight-Icon.png"

echo 'Building QuizSight v3.6 (only on first install or with --rebuild)…'
if ! xcrun --sdk macosx swiftc -O QuizModels.swift main.swift \
    -o "$TEMP_APP/Contents/MacOS/QuizLens" -framework AppKit -framework Foundation -framework Security \
    2> "$BUILD_LOG"; then
    echo ''
    echo 'Build failed. First error messages:'
    sed -n '1,35p' "$BUILD_LOG"
    echo ''
    echo "Full log: $BUILD_LOG"
    exit 1
fi
chmod +x "$TEMP_APP/Contents/MacOS/QuizLens"
if command -v codesign >/dev/null 2>&1; then
    if ! codesign --force --sign - "$TEMP_APP"; then
        echo 'Warning: ad-hoc signing failed; permission may not persist.'
    fi
fi
rm -f "$BUILD_LOG"

# The app will not be rebuilt on the next launch.
if [[ -d "$APP" ]]; then rm -rf "$APP"; fi
mv "$TEMP_APP" "$APP"
trap - EXIT

echo 'QuizSight installed. Run start.command or open QuizSight.app for subsequent launches.'
echo 'If permission prompts repeat, quit QuizSight and check its permission and identity in Privacy & Security.'
open "$APP"
