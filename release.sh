#!/bin/sh
# Cuts a release: builds the app, zips it, publishes a GitHub release and updates the Homebrew cask.
# Usage: ./release.sh 0.1.2        (the version must already be in Resources/Info.plist)
# Needs: gh (logged in) and a checkout of the tap at ~/Projects/homebrew-tap (or $TAP).
set -e
cd "$(dirname "$0")"
V="$1"; [ -n "$V" ] || { echo "usage: $0 <version>"; exit 1; }
PLIST_V=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
[ "$PLIST_V" = "$V" ] || { echo "Resources/Info.plist says $PLIST_V, not $V"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "commit your changes first"; exit 1; }

./build.sh
ZIP="NotchControl-$V.zip"
rm -f "build/$ZIP" "build/$ZIP.sha256"
ditto -c -k --keepParent build/NotchControl.app "build/$ZIP"
(cd build && shasum -a 256 "$ZIP" > "$ZIP.sha256")

git tag -f "v$V"
git push origin main "v$V"
gh release create "v$V" "build/$ZIP" "build/$ZIP.sha256" --title "v$V" --generate-notes

TAP="${TAP:-$HOME/Projects/homebrew-tap}"
if [ -d "$TAP" ]; then
    (cd "$TAP" && ./update-cask.sh "$V" && git commit -qam "notchcontrol $V" && git push -q)
    echo "Cask updated: brew update && brew upgrade notchcontrol"
else
    echo "Tap not found at $TAP; run update-cask.sh $V there by hand."
fi
