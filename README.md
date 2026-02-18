# YAML Quick Look

A native macOS Quick Look extension for previewing YAML files. Provides the same clean, scrollable plain-text preview experience as built-in file types like `.txt` and `.plist`.

## Features

- Native plain-text Quick Look preview for `.yaml` and `.yml` files
- Scrollable content view for large files
- Thumbnail generation showing file content in Finder icons
- Dark mode support
- Lightweight container app with two system extensions

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15.0 or later (for building from source)

## Installation

### Option 1: Download Release

1. Download the latest `yamlQuickLook.zip` from [Releases](https://github.com/rodchristiansen/yaml-quicklook/releases)
2. Unzip and move `YamlQuickLook.app` to `/Applications`
3. Remove the quarantine attribute (required for unsigned apps):
   ```bash
   xattr -cr /Applications/YamlQuickLook.app
   ```
4. Open the app once to register the extension
5. Go to System Settings > Privacy and Security > Extensions > Quick Look
6. Enable "YAML Quick Look"
7. Restart Finder and Quick Look:
   ```bash
   killall Finder
   qlmanage -r && qlmanage -r cache
   ```

**Important:** The GitHub Actions release is **not code-signed or notarized**. macOS Sequoia and later require the `xattr` command above to run unsigned apps. See [Building with Code Signing](#signing-with-your-developer-id) for a properly signed build.

### Option 2: Build from Source

See [Building from Source](#building-from-source) below.

## Usage

1. Select any `.yaml` or `.yml` file in Finder
2. Press Space to preview with Quick Look
3. Or view in Finder's preview pane (right sidebar)

## Mac Admin Deployment

### MDM Considerations

- **Extension activation requires user interaction**: Users must enable the Quick Look extension in System Settings > Privacy & Security > Extensions > Quick Look. This step **cannot** be automated via MDM configuration profiles on macOS Sequoia and later.
- **Quarantine removal**: If deploying an unsigned build, include `xattr -cr` in your post-install script.
- **Recommended approach**: Build a signed and notarized version with your organization's Developer ID to avoid quarantine issues entirely.

### Munki

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>name</key>
    <string>YamlQuickLook</string>
    <key>display_name</key>
    <string>YAML Quick Look</string>
    <key>description</key>
    <string>Quick Look extension for previewing YAML files in Finder.</string>
    <key>category</key>
    <string>Utilities</string>
    <key>developer</key>
    <string>Rod Christiansen</string>
    <key>installer_type</key>
    <string>copy_from_dmg</string>
    <key>installs</key>
    <array>
        <dict>
            <key>CFBundleIdentifier</key>
            <string>com.github.rodchristiansen.YamlQuickLook</string>
            <key>path</key>
            <string>/Applications/YamlQuickLook.app</string>
            <key>type</key>
            <string>application</string>
        </dict>
    </array>
    <key>items_to_copy</key>
    <array>
        <dict>
            <key>destination_path</key>
            <string>/Applications</string>
            <key>source_item</key>
            <string>YamlQuickLook.app</string>
        </dict>
    </array>
    <key>postinstall_script</key>
    <string>#!/bin/bash
# Register Quick Look extensions
pluginkit -a /Applications/YamlQuickLook.app/Contents/PlugIns/YamlQuickLookExtension.appex || true
pluginkit -a /Applications/YamlQuickLook.app/Contents/PlugIns/YamlQuickLookThumbnailExtension.appex || true
qlmanage -r
qlmanage -r cache
    </string>
</dict>
</plist>
```

### Jamf Pro

1. Package `YamlQuickLook.app` into a `.pkg` installer
2. Upload to Jamf Pro and create a policy
3. Add a post-install script:
   ```bash
   #!/bin/bash
   pluginkit -a /Applications/YamlQuickLook.app/Contents/PlugIns/YamlQuickLookExtension.appex || true
   pluginkit -a /Applications/YamlQuickLook.app/Contents/PlugIns/YamlQuickLookThumbnailExtension.appex || true
   qlmanage -r
   qlmanage -r cache
   ```
4. Remind users to enable the extension in System Settings > Extensions > Quick Look.

## Building from Source

### Prerequisites

- macOS 14.0 or later
- Xcode 15.0 or later

### Basic Build

```bash
git clone https://github.com/rodchristiansen/yaml-quicklook.git
cd yaml-quicklook
xcodebuild -scheme YamlQuickLook -configuration Release build
```

### Install Locally

```bash
# Build
xcodebuild -scheme YamlQuickLook -configuration Release \
  -derivedDataPath build clean build

# Install
cp -R build/Build/Products/Release/YamlQuickLook.app /Applications/

# Register extensions
pluginkit -a /Applications/YamlQuickLook.app/Contents/PlugIns/YamlQuickLookExtension.appex
pluginkit -a /Applications/YamlQuickLook.app/Contents/PlugIns/YamlQuickLookThumbnailExtension.appex

# Reset Quick Look
qlmanage -r && qlmanage -r cache
```

### Signing with Your Developer ID

To distribute the app outside the Mac App Store, you need to sign and notarize it.

#### 1. Configure Signing in Xcode

Open `YAMLQuickLook.xcodeproj` in Xcode and configure signing for all three targets:

- **YamlQuickLook** (main app)
- **YamlQuickLookExtension** (Quick Look preview)
- **YamlQuickLookThumbnailExtension** (thumbnail generator)

For each target:
1. Select the target in the project navigator
2. Go to "Signing and Capabilities"
3. Select your Team
4. Choose "Developer ID Application" for distribution outside the App Store

#### 2. Build Signed Release

```bash
xcodebuild -scheme YamlQuickLook \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAM_ID)" \
  DEVELOPMENT_TEAM="TEAM_ID" \
  clean build
```

#### 3. Notarize the App

```bash
# Create a ZIP for notarization
cd build/Build/Products/Release
ditto -c -k --keepParent YamlQuickLook.app yamlQuickLook.zip

# Submit for notarization
xcrun notarytool submit yamlQuickLook.zip \
  --apple-id "your@email.com" \
  --team-id "TEAM_ID" \
  --password "app-specific-password" \
  --wait

# Staple the notarization ticket
xcrun stapler staple YamlQuickLook.app
```

#### 4. Create Distribution ZIP

```bash
# Re-zip with stapled ticket
VERSION=$(date -u +"%Y.%m.%d")
ditto -c -k --keepParent YamlQuickLook.app yamlQuickLook-${VERSION}.zip
```

## Project Structure

```
yaml-quicklook/
├── YamlQuickLook/                    # Main application (container)
│   ├── AppDelegate.swift
│   ├── ContentView.swift
│   └── yamlQuickLook.icon/
├── YamlQuickLookExtension/           # Quick Look preview extension
│   └── PreviewProvider.swift
├── YamlQuickLookThumbnailExtension/  # Thumbnail extension
│   └── ThumbnailProvider.swift
├── YAMLQuickLook.xcodeproj/
├── .github/workflows/
│   └── release.yml
├── Makefile
├── LICENSE
└── README.md
```

## Troubleshooting

### Extension not working

1. Ensure the app is in `/Applications`
2. Check System Settings > Privacy and Security > Extensions > Quick Look
3. Reset Quick Look: `qlmanage -r && qlmanage -r cache`
4. Restart Finder: `killall Finder`

### "App is damaged" error

Run: `xattr -cr /Applications/YamlQuickLook.app`

### Preview not updating after rebuild

```bash
pluginkit -a /Applications/YamlQuickLook.app/Contents/PlugIns/YamlQuickLookExtension.appex
qlmanage -r && qlmanage -r cache
killall Finder
```

### YAML files not previewing

1. Verify the file has a `.yaml` or `.yml` extension
2. Check that the file contains valid text (not binary data)
3. Files larger than 10 MB are truncated in the preview to prevent memory issues

### Build errors

1. Ensure you have Xcode 15.0 or later
2. Clean build folder (Cmd+Shift+K) and rebuild
3. Check that macOS deployment target is set to 14.0

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome. Please open an issue or submit a pull request.

```bash
xcodebuild -project YAMLQuickLook.xcodeproj -scheme YamlQuickLook -configuration Release
```