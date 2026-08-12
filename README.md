# Tarn — A native macOS SQLite GUI

[![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-lightgrey.svg)](https://www.apple.com/macos)

Tarn is a focused, native SQLite GUI for Mac. It opens local SQLite database files directly — no server, no connection credentials, no data leaving your machine.

## Getting started

1. Clone the repository:
   ```bash
   git clone https://github.com/griffinlong/tarn.git
   cd tarn
   ```

2. Open the project in Xcode:
   ```bash
   open Tarn.xcodeproj
   ```

3. IMPORTANT: Configure code signing:
   - Select the **Tarn** target in the project navigator
   - Go to **Signing & Capabilities** tab
   - Select your **Team** from the dropdown (use your Apple ID's "Personal Team" if you don't have a paid developer account)

4. Build and run with `Cmd+R`

### Automated Local Build

If you don't want to open Xcode to configure code signing manually, you can use the provided script to set your Apple Developer Team ID and run the build directly from the terminal:

1. Apply your Team ID and a custom Bundle Identifier prefix:
   ```bash
   ./clean_pbxproj.sh YOUR_TEAM_ID com.yourname
   ```
   *(You can find your 10-character Team ID in your Apple Developer account)*

2. Build the app and generate the DMG:
   ```bash
   ./build_dmg.sh
   ```

### Submitting Pull Requests

When you select your team in step 3, Xcode modifies `project.pbxproj` with your team ID. **Do not include this change in your pull request.**

### Why Code Signing is Required

This app uses macOS Keychain to securely store database passwords. Keychain access requires a valid code signature, so even local development builds need to be signed with your team ID.

## Support

- Report bugs on [GitHub Issues](https://github.com/griffinlong/tarn/issues)

## Acknowledgments

Tarn is built on the shoulders of giants. Special thanks to:

- The [SQLite.swift](https://github.com/stephencelis/SQLite.swift) community
- The [Swift NIO](https://github.com/apple/swift-nio) project for the networking foundation
