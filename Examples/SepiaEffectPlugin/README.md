# Sepia Effect Plugin

A sample SwiftEditor video effect plugin that applies a sepia tone filter to video frames.

## Overview

This plugin demonstrates how to build a custom video effect for SwiftEditor by conforming to the `VideoEffect` protocol from `PluginKit`. It includes:

- A `PluginManifest` declaring the plugin's identity, category, and capabilities
- A `PluginBundle` entry point for discovery by the host app
- A `VideoEffect` implementation with parameterized sepia tone processing
- Two adjustable parameters: **Intensity** (0-1) and **Warmth** (0-1)

## Building

```bash
cd Examples/SepiaEffectPlugin
swift build
```

## Installing

1. Build the plugin as a dynamic library:
   ```bash
   swift build -c release
   ```

2. Create a `.plugin` bundle directory:
   ```bash
   mkdir -p SepiaEffect.plugin/Contents/MacOS
   cp .build/release/libSepiaEffectPlugin.dylib SepiaEffect.plugin/Contents/MacOS/
   ```

3. Create `SepiaEffect.plugin/Contents/Info.plist`:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
     "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>CFBundleIdentifier</key>
       <string>com.example.sepiaEffect</string>
       <key>CFBundleName</key>
       <string>Sepia Tone</string>
       <key>CFBundleVersion</key>
       <string>1.0.0</string>
       <key>NSPrincipalClass</key>
       <string>SepiaEffectBundle</string>
   </dict>
   </plist>
   ```

4. Copy the `.plugin` bundle to the SwiftEditor plugins directory:
   ```bash
   cp -r SepiaEffect.plugin ~/Library/Application\ Support/SwiftEditor/Plugins/
   ```

## Plugin Architecture

### PluginManifest

Declares metadata used by the host for categorization and compatibility checks:

```swift
PluginManifest(
    identifier: "com.example.sepiaEffect",
    name: "Sepia Tone",
    version: "1.0.0",
    author: "SwiftEditor Examples",
    category: .videoEffect,
    minimumHostVersion: "1.0.0",
    capabilities: [.realTimeCapable, .keyframeable]
)
```

### Parameter Declaration

Parameters are declared as `ParameterDescriptor` values and accessed at runtime via `ParameterValues`:

```swift
let parameterDescriptors: [ParameterDescriptor] = [
    .float(name: "intensity", displayName: "Intensity",
           defaultValue: 1.0, min: 0.0, max: 1.0),
    .float(name: "warmth", displayName: "Warmth",
           defaultValue: 0.5, min: 0.0, max: 1.0)
]
```

### Processing Pipeline

The effect provides two processing paths:

- **CPU path** (`process(input:parameters:time:)`) — Works with `CVPixelBuffer`, always available
- **GPU path** (`process(input:output:parameters:time:commandBuffer:)`) — Uses Metal textures for hardware acceleration

The host chooses the optimal path based on available hardware and pipeline configuration.
