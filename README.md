# UltraHDR Export Plugin for Darktable

A Darktable Lua plugin that enables automated export of images to UltraHDR (Ultra HDR JPEG) format using darktable-cli and XMP copy modification.

## Overview

This plugin creates UltraHDR images by:

1. Exporting the SDR JPEG using Darktable's standard export
2. Copying and modifying the image's XMP sidecar to adjust Sigmoid target display luminance
3. Using darktable-cli to export HDR version as 32-bit float OpenEXR with Rec2020 linear profile
4. Converting the HDR OpenEXR to RGBA float16 raw buffer using ImageMagick
5. Merging both images using `ultrahdr_app` to create the final UltraHDR JPEG

The plugin integrates directly into Darktable's export dialog as a custom storage target, making UltraHDR export as simple as selecting it from the storage dropdown.

## Prerequisites

### Required Software

1. **Darktable 4.0 or later**
   - The plugin requires API version 7.0.0 or higher
   - Download from: <https://www.darktable.org/>

2. **darktable-cli**
   - Command-line interface for Darktable (included with Darktable installation)
   - Used for HDR export with modified XMP
   - **Windows**: Usually in `C:\Program Files\darktable\bin\darktable-cli.exe`
   - **Linux**: Typically `/usr/bin/darktable-cli`

3. **ultrahdr_app**
   - Command-line tool for creating UltraHDR images
   - Source: <https://github.com/google/libultrahdr>
   - **Windows**: Bundled with this plugin as `ultrahdr_app.exe`
   - **Linux**: Must be compiled from source or obtained separately

4. **ImageMagick**
   - Required for converting EXR to raw buffer format
   - Download from: <https://imagemagick.org/>
   - **Linux**: `sudo apt install imagemagick`
   - **Windows**: Download installer from official site or `winget install ImageMagick.ImageMagick`

### Workflow Requirements

- Images must have XMP sidecars (process them in Darktable first)
- Images must use the **Sigmoid** tone mapping module (only on instance)
- Sigmoid must be enabled and configured in the pixelpipe

## Installation

### Linux/MacOS

    cd ~/.config/darktable/lua
    git clone https://github.com/Mikayex/dt_ultrahdr

### Windows

    cd %LOCALAPPDATA%\darktable\lua
    git clone https://github.com/Mikayex/dt_ultrahdr

## Enable

Add a line to the luarc `require "dt_ultrahdr/ultrahdr_export"`.

If you are using script_manager to manage your scripts, then you will see a new category, dt_ultrahdr.  Select that and enable/disable the script.

## Update

Open terminal and change directory to the dt_ultrahdr directory.  Do a `git pull`.

## Configuration

### First-Time Setup

1. **Open Export Module** in Darktable
2. **Select "UltraHDR"** from the storage dropdown
3. **Configure executables** (if needed):
   - ultrahdr_app: Auto-detected if bundled, otherwise set manually
   - magick: Uses PATH by default, set manually if needed
   - darktable-cli: Auto-detected, set manually if needed

4. **Configure output pattern** (optional):
   - Default: `$(FILE_FOLDER)/darktable_exported/$(FILE_NAME)`
   - Supports Darktable's variable substitution syntax
   - Example: `$(FILE_FOLDER)/ultrahdr/$(FILE_NAME)_uhdr`

5. **Adjust quality settings**:
   - Target Display Luminance: 100-1600 nits (default: 1600)
   - Gainmap Quality: 1-100 (default: 95)
   - Gainmap Downsampling: 1-128, rounded to power of 2 (default: 1)

Settings are saved automatically and persist across Darktable sessions.

## Usage

### Basic Export

1. **Process images** in Darktable darkroom (creates XMP sidecars)
2. **Ensure Sigmoid module is enabled** with your desired settings
3. **Select images** in Lighttable
4. **Open Export module**
5. **Select "UltraHDR"** from storage dropdown
6. **Configure output settings** (optional)
7. **Click Export**

The plugin will:

- Validate dependencies before starting
- Process each image automatically
- Create UltraHDR JPEG files based on output pattern
- Clean up all temporary files
- Report completion status

### Output Files

- **Filename**: Based on configured output pattern + `.jpg` extension
- **Location**: Configurable via output pattern (supports variables)
- **Format**: UltraHDR JPEG (backward-compatible with standard JPEG viewers)
- **Overwrite**: Optionally create unique filenames instead of overwriting

### Processing Details

For each image, the plugin:

1. Exports SDR JPEG using standard Darktable export (respects format settings)
2. Reads the image's XMP sidecar file
3. Decodes Sigmoid parameters from hex-encoded binary data
4. Modifies `display_white_target` to the configured target luminance
5. Encodes modified parameters back to hex
6. Writes modified XMP to temporary file
7. Uses darktable-cli to export HDR EXR with modified XMP
8. Converts EXR to RGBA float16 raw buffer via ImageMagick
9. Calls ultrahdr_app to merge SDR and HDR into UltraHDR JPEG
10. Cleans up all temporary files
