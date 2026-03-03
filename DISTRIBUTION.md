# SwiftEditor Distribution Guide

## Prerequisites

- macOS 15+ with Xcode 16+
- Apple Developer Program membership
- **Developer ID Application** certificate installed in Keychain
- App-specific password for notarization (generate at appleid.apple.com)

## Project Structure

```
Sources/SwiftEditorApp/Resources/
    SwiftEditorApp.entitlements   # App Sandbox + capabilities
    Info.plist                     # Bundle metadata, UTIs, document types
scripts/
    notarize.sh                   # Automated archive/sign/notarize/staple
```

## Build

### Debug Build (SPM)

```bash
swift build
```

### Release Build (SPM)

```bash
swift build -c release
```

### Xcode Build

Generate the Xcode project, then build from Xcode:

```bash
open Package.swift  # Opens in Xcode
```

Select the **SwiftEditorApp** scheme and build for **My Mac**.

## Code Signing

The entitlements file (`SwiftEditorApp.entitlements`) enables:

| Entitlement | Purpose |
|---|---|
| `com.apple.security.app-sandbox` | App Sandbox required for distribution |
| `files.user-selected.read-write` | Read/write access to user-chosen files |
| `network.client` | Outbound network connections |
| `device.camera` | Live capture and recording |
| `device.audio-input` | Microphone for voiceover/recording |

When archiving via Xcode, select the entitlements file under **Signing & Capabilities** or pass it during `codesign`:

```bash
codesign --force --options runtime --timestamp \
    --entitlements Sources/SwiftEditorApp/Resources/SwiftEditorApp.entitlements \
    --sign "Developer ID Application: YOUR NAME (TEAM_ID)" \
    build/SwiftEditor.app
```

## Notarization

### Automated (recommended)

```bash
export TEAM_ID="YOUR_TEAM_ID"
export APPLE_ID="your@email.com"
export APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"

./scripts/notarize.sh
```

Or pass as flags:

```bash
./scripts/notarize.sh \
    --team-id YOUR_TEAM_ID \
    --apple-id your@email.com \
    --password xxxx-xxxx-xxxx-xxxx
```

### Manual Steps

1. **Archive** the app via Xcode (Product > Archive)
2. **Export** with "Developer ID" distribution method
3. **Submit** for notarization:
   ```bash
   xcrun notarytool submit SwiftEditor.zip \
       --apple-id EMAIL --team-id TEAM_ID --password PASSWORD --wait
   ```
4. **Staple** the ticket:
   ```bash
   xcrun stapler staple SwiftEditor.app
   ```
5. **Verify**:
   ```bash
   spctl --assess --type execute --verbose SwiftEditor.app
   ```

### Storing Credentials

To avoid passing credentials each time:

```bash
xcrun notarytool store-credentials "SwiftEditor" \
    --apple-id EMAIL --team-id TEAM_ID --password PASSWORD
```

Then use `--keychain-profile "SwiftEditor"` instead of explicit credentials.

## Distribution

### Direct Download (DMG)

The notarize script produces `build/SwiftEditor.dmg`, which is signed, notarized, and stapled. Distribute this file from your website or GitHub Releases.

### Custom File Types

SwiftEditor registers the `.nleproj` extension as its native project format (UTI: `com.swifteditor.nleproj`). It also declares viewer support for common video, audio, and image formats. See `Info.plist` for the full list.

## Troubleshooting

**"SwiftEditor.app is damaged"** -- The app was not notarized or the ticket was not stapled. Re-run notarization.

**Notarization rejected** -- Check the log:
```bash
xcrun notarytool log <submission-id> \
    --apple-id EMAIL --team-id TEAM_ID --password PASSWORD
```

Common issues: unsigned frameworks, missing hardened runtime, or disallowed entitlements.

**Sandbox file access errors** -- The app can only access files the user explicitly opens via the file picker. Use `NSOpenPanel` / `NSSavePanel` for all file I/O.
