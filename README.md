# UltraHDR Export Plugin for Darktable

A Darktable Lua plugin that enables automated export of images to UltraHDR (Ultra HDR JPEG) format using the Sigmoid tone mapping module.

## Overview

This plugin creates UltraHDR images by:
1. Exporting the image as SDR JPEG with default color profile
2. Automatically adjusting Sigmoid module's target display luminance
3. Exporting the image as 32-bit float OpenEXR with Rec2020 linear profile (HDR)
4. Converting the HDR image to RGBA float16 raw buffer using ImageMagick
5. Merging both images using `ultrahdr_app` to create the final UltraHDR JPEG

The plugin integrates directly into Darktable's export dialog as a custom storage target, making UltraHDR export as simple as any other export format.

## Prerequisites

### Required Software

1. **Darktable 4.0 or later**
   - The plugin requires API version 9.0.0 or higher
   - Download from: https://www.darktable.org/

2. **ultrahdr_app**
   - Command-line tool for creating UltraHDR images
   - Source: https://github.com/google/libultrahdr
   - Pre-built binaries may be available, or you'll need to compile from source

3. **ImageMagick**
   - Required for converting EXR to raw buffer format
   - Download from: https://imagemagick.org/
   - **Linux**: Usually available via package manager (`sudo apt install imagemagick`)
   - **Windows**: Download installer from official site

### Workflow Requirements

- Images must use the **Sigmoid** tone mapping module
- The plugin automatically adjusts Sigmoid settings during export
- Original Sigmoid settings are restored after export

## Installation

### Linux

1. **Copy the plugin file:**
   ```bash
   mkdir -p ~/.config/darktable/lua
   cp ultrahdr_export.lua ~/.config/darktable/lua/
   ```

2. **Enable the plugin:**

   Edit or create `~/.config/darktable/luarc`:
   ```bash
   nano ~/.config/darktable/luarc
   ```

   Add this line:
   ```lua
   require "ultrahdr_export"
   ```

3. **Restart Darktable**

### Windows

1. **Copy the plugin file:**
   ```
   Copy ultrahdr_export.lua to:
   %LOCALAPPDATA%\darktable\lua\

   (Usually: C:\Users\YourUsername\AppData\Local\darktable\lua\)
   ```

2. **Enable the plugin:**

   Edit or create the file:
   ```
   %LOCALAPPDATA%\darktable\luarc
   ```

   Add this line:
   ```lua
   require "ultrahdr_export"
   ```

3. **Restart Darktable**

### Verify Installation

After restarting Darktable, you should see:
- A message in the console: "UltraHDR Export plugin loaded successfully"
- "UltraHDR Export" appears in the storage dropdown in the export module

## Configuration

### First-Time Setup

1. **Open Export Module** in Darktable
2. **Select "UltraHDR Export"** from the storage dropdown
3. **Configure paths:**
   - Click "Select ultrahdr_app executable" and browse to your `ultrahdr_app` binary
   - (Optional) Set ImageMagick path if it's not in your system PATH
4. **Adjust quality settings** (optional):
   - Target Display Luminance: 100-1600% (default: 1600)
   - SDR JPEG Quality: 1-100 (default: 95)
   - Gainmap Quality: 1-100 (default: 95)
   - Gainmap Downsampling: 1-128 (default: 1)

Settings are saved and persist across Darktable sessions.

## Usage

### Basic Export

1. **Select images** in Lighttable or Darkroom
2. **Open Export module**
3. **Select "UltraHDR Export"** from storage dropdown
4. **Choose target directory** (if supported by your format selection)
5. **Click Export**

The plugin will:
- Validate dependencies before starting
- Process each image automatically
- Create UltraHDR JPEG files with the same base filename as originals
- Clean up temporary files
- Restore your original Sigmoid settings

### Output Files

- **Filename**: Original filename with `.jpg` extension
  - Example: `IMG_1234.CR2` → `IMG_1234.jpg`
- **Location**: Same directory as the original file (or configured export path)
- **Format**: UltraHDR JPEG (compatible with supported viewers/devices)

### Processing Details

For each image, the plugin:
1. Exports SDR version with your configured JPEG quality
2. Temporarily adjusts Sigmoid to target luminance
3. Exports HDR version as 32-bit OpenEXR
4. Converts to raw buffer format
5. Merges using ultrahdr_app with specified parameters
6. Removes temporary files

## Configuration Options

### Target Display Luminance (100-1600%)

Controls the HDR headroom. Higher values preserve more highlight detail:
- **100%**: Standard SDR range
- **1600%**: Maximum HDR range (default)
- Intermediate values for specific display targets

### SDR JPEG Quality (1-100)

Quality of the base SDR image:
- **95** (default): High quality, larger file size
- **85-90**: Good balance
- Lower values reduce file size but may show compression artifacts

### Gainmap Quality (1-100)

Quality of the HDR gainmap:
- **95** (default): Highest quality HDR experience
- Lower values reduce file size but may affect HDR appearance

### Gainmap Downsampling (1-128)

Spatial resolution of the gainmap:
- **1** (default): Full resolution gainmap
- **2-4**: Slight reduction, usually imperceptible
- Higher values: Smaller files but potential HDR quality loss

## Troubleshooting

### "Please set the path to ultrahdr_app in preferences"

**Solution**: Configure the ultrahdr_app path in the export settings.

### "ultrahdr_app not found at: [path]"

**Solution**:
- Verify the file exists at the specified location
- Ensure the file is executable (`chmod +x ultrahdr_app` on Linux)
- On Windows, ensure the path includes `.exe` extension

### "ImageMagick not found" or conversion fails

**Solution**:
- Verify ImageMagick is installed: `magick --version`
- If not in PATH, set the full path in export settings
- Linux: `which magick` to find location
- Windows: Usually in `C:\Program Files\ImageMagick-X.X.X\magick.exe`

### Export fails with "Failed to export SDR JPEG" or "Failed to export HDR EXR"

**Possible causes**:
- Insufficient disk space
- Invalid export format configuration
- Permission issues in target directory

**Solution**:
- Check available disk space
- Verify you have write permissions to the output directory
- Check Darktable console for detailed error messages

### Sigmoid module not available

**Solution**:
- Ensure your image is using the Sigmoid tone mapping module
- The plugin requires Sigmoid to be available in the pixelpipe
- Check if Sigmoid is enabled in the darkroom

### Output colors look incorrect

**Possible causes**:
- Color profile configuration issues
- Sigmoid settings incompatible with HDR export

**Solution**:
- Verify your output color profile module settings
- Check that Rec2020 linear profile is being used for EXR export
- Review ultrahdr_app parameters

### Plugin doesn't appear in storage list

**Solution**:
- Check that `luarc` file is in the correct location
- Verify the `require` statement is correct
- Check Darktable console for Lua error messages
- Run Darktable with debug flag: `darktable -d lua`

### Windows: "Command failed" errors

**Solution**:
- Ensure all paths with spaces are properly handled
- Try using short paths (8.3 format) if long paths cause issues
- Check Windows Defender or antivirus isn't blocking executables

## Technical Details

### File Format Specifications

**SDR Image:**
- Format: JPEG
- Color space: As configured in Darktable (default profile)
- Bit depth: 8-bit
- Purpose: Base image visible on all devices

**HDR Image:**
- Format: OpenEXR (intermediate)
- Color space: Rec2020 linear
- Bit depth: 32-bit float → converted to 16-bit float raw
- Purpose: HDR information stored in gainmap

**Final Output:**
- Format: JPEG with embedded Ultra HDR gainmap
- Compatible with: Android 14+, supported photo viewers
- Fallback: Displays as standard JPEG on unsupported devices

### Performance Notes

- Export is serial (one image at a time)
- Processing time depends on image size and settings
- Temporary files are stored in system temp directory
- Typical processing time: 5-15 seconds per image on modern hardware

### Dependencies

The plugin uses the following Darktable Lua utilities:
- `lib/dtutils`: Core utilities
- `lib/dtutils.file`: File path handling
- `lib/dtutils.system`: Cross-platform command execution

## Contributing

Contributions are welcome! Please feel free to:
- Report bugs
- Suggest features
- Submit pull requests
- Improve documentation

## License

MIT License - See LICENSE file for details

## Credits

- Plugin developed for automated UltraHDR workflow in Darktable
- Uses Google's libultrahdr for UltraHDR creation
- Built on Darktable's Lua API

## Links

- **Darktable**: https://www.darktable.org/
- **libultrahdr**: https://github.com/google/libultrahdr
- **ImageMagick**: https://imagemagick.org/
- **UltraHDR Specification**: https://developer.android.com/media/platform/hdr-image-format

## Version History

### 1.0.0 (2025)
- Initial release
- Full UltraHDR export support
- Cross-platform compatibility (Windows & Linux)
- Configurable quality and luminance settings
- Automatic Sigmoid adjustment and restoration
