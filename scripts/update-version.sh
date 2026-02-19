#!/bin/bash

# Update version to YYYY.MM.DD.HHMM format at build time
VERSION=$(TZ=America/Vancouver date +'%Y.%m.%d.%H%M')

echo "Updating version to: $VERSION"

# Update CFBundleShortVersionString and CFBundleVersion in all Info.plist files
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"

echo "Version updated successfully"
