--[[
    UltraHDR Export Plugin for Darktable (CLI-based version)

    This plugin exports images to UltraHDR format using darktable-cli for HDR export.
    It modifies a copy of XMP files to adjust Sigmoid parameters.

    License: MIT
    Version: 1.0.0
]]

local dt = require "darktable"
local du = require "lib/dtutils"
local df = require "lib/dtutils.file"
local ds = require "lib/dtutils.string"
local dsys = require "lib/dtutils.system"

-- i18n
local gettext = dt.gettext.gettext

local function _(msg)
    return gettext(msg)
end

-- Plugin metadata
local PLUGIN_NAME<const> = "ultrahdr_export"
local PLUGIN_DISPLAY_NAME<const> = _("UltraHDR")

local script_data = {}
script_data.metadata = {
    name = _("UltraHDR Export"),
    purpose = _("UltraHDR exporter"),
    author = "Thomas Laroche <tho.laroche@gmail.com>"
}
script_data.destroy = nil -- function to destory the script
script_data.destroy_method = nil -- set to hide for libs since we can't destroy them commpletely yet
script_data.restart = nil -- how to restart the (lib) script after it's been hidden - i.e. make it visible again
script_data.show = nil -- only required for libs since the destroy_method only hides them

-- Check API version compatibility
du.check_min_api_version("7.0.0", PLUGIN_NAME)

-- Path separator
local PS<const> = dt.configuration.running_os == "windows" and "\\" or "/"

-- Helper function to get script directory
local function get_script_directory()
    local info = debug.getinfo(1, "S")
    if info and info.source then
        local script_path = info.source:match("^@(.*)$")
        if script_path then
            return df.get_path(script_path)
        end
    end
    return nil
end

-- Detect bundled ultrahdr_app executable
local function detect_bundled_ultrahdr_app()
    local script_dir = get_script_directory()
    if script_dir then
        local exe_name = dt.configuration.running_os == "windows" and "ultrahdr_app.exe" or "ultrahdr_app"
        local bundled_path = script_dir .. "/" .. exe_name
        if df.test_file(bundled_path, 'x') then
            return bundled_path
        end
    end
    return nil
end

local function default_to(value, default)
    if value == 0 or value == "" then
        return default
    end
    return value
end

-- Round to nearest power of 2
local function round_to_power_of_2(value)
    if value <= 1 then
        return 1
    end
    local log2 = math.log(value) / math.log(2)
    local rounded = math.floor(log2 + 0.5)
    return 2 ^ rounded
end


-- UI
local target_luminance_widget = dt.new_widget("slider") {
    label = _("Target Display Luminance"),
    tooltip = _("Target display luminance in nits"),
    hard_min = 100,
    hard_max = 1600,
    soft_min = 100,
    soft_max = 1600,
    value = default_to(dt.preferences.read(PLUGIN_NAME, "target_luminance", "integer"), 1600),
    step = 100,
    digits = 0,
    reset_callback = function(self)
        self.value = 1600
    end
}

local gainmap_quality_widget = dt.new_widget("slider") {
    label = _("Gainmap Quality"),
    tooltip = _("JPEG quality of the gainmap (1-100)"),
    hard_min = 1,
    hard_max = 100,
    soft_min = 1,
    soft_max = 100,
    value = default_to(dt.preferences.read(PLUGIN_NAME, "gainmap_quality", "integer"), 95),
    step = 1,
    digits = 0,
    reset_callback = function(self)
        self.value = 95
    end
}

local gainmap_downsampling_widget = dt.new_widget("slider") {
    label = _("Gainmap Downsampling"),
    tooltip = _("Downsampling factor for gainmap (1-128).\nMust be a power of 2"),
    hard_min = 1,
    hard_max = 128,
    soft_min = 1,
    soft_max = 128,
    value = default_to(dt.preferences.read(PLUGIN_NAME, "gainmap_downsampling", "integer"), 1),
    step = 1,
    digits = 0,
    reset_callback = function(self)
        self.value = 1
    end
}
local output_pattern_widget = dt.new_widget("entry") {
    tooltip = ds.get_substitution_tooltip(),
    text = default_to(dt.preferences.read(PLUGIN_NAME, "output_pattern", "string"),
        "$(FILE_FOLDER)/darktable_exported/$(FILE_NAME)"),
    reset_callback = function(self)
        self.text = "$(FILE_FOLDER)/darktable_exported/$(FILE_NAME)"
    end
}

local overwrite_on_conflict_widget = dt.new_widget("check_button") {
    label = _("Overwrite if exists"),
    tooltip = _("If the output file already exists, overwrite it. If unchecked, a unique filename will be created instead."),
    value = default_to(dt.preferences.read(PLUGIN_NAME, "overwrite_on_conflict", "bool"), false),
    reset_callback = function(self)
        self.value = false
    end
}

local widget = dt.new_widget("box") {
    orientation = "vertical",
    output_pattern_widget,
    overwrite_on_conflict_widget,
    dt.new_widget("section_label") {
        label = _("UltraHDR Settings")
    },
    target_luminance_widget,
    gainmap_quality_widget,
    gainmap_downsampling_widget,
    df.executable_path_widget({"ultrahdr_app", "magick", "darktable-cli"})
}

local function save_preferences()
    gainmap_downsampling_widget.value = round_to_power_of_2(gainmap_downsampling_widget.value)
    dt.preferences.write(PLUGIN_NAME, "target_luminance", "integer", (target_luminance_widget.value + 0.5) // 1)
    dt.preferences.write(PLUGIN_NAME, "gainmap_quality", "integer", gainmap_quality_widget.value)
    dt.preferences.write(PLUGIN_NAME, "gainmap_downsampling", "integer", gainmap_downsampling_widget.value)
    dt.preferences.write(PLUGIN_NAME, "output_pattern", "string", output_pattern_widget.text)
    dt.preferences.write(PLUGIN_NAME, "overwrite_on_conflict", "bool", overwrite_on_conflict_widget.value)
end

-- Read file
local function read_file(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end

    local content = file:read("*all")
    file:close()
    return content
end

-- Write file
local function write_file(path, content)
    local file = io.open(path, "w")
    if not file then
        return false
    end

    file:write(content)
    file:close()
    return true
end

-- Convert hex string to binary
local function hex_to_bin(hex)
    return (hex:gsub('..', function(cc)
        return string.char(tonumber(cc, 16))
    end))
end

-- Convert binary to hex string
local function bin_to_hex(bin)
    local hex = bin:gsub('.', function(c)
        return string.format('%02x', c:byte())
    end)
    return hex
end

local function decode_sigmoid_v1(data)
    local middle_grey_contrast, contrast_skewness, display_white_target, display_black_target, color_processing,
        hue_preservation = string.unpack("<ffffif", data)
    return {
        middle_grey_contrast = middle_grey_contrast,
        contrast_skewness = contrast_skewness,
        display_white_target = display_white_target,
        display_black_target = display_black_target,
        color_processing = color_processing,
        hue_preservation = hue_preservation
    }
end

local function decode_sigmoid_v2(data)
    local middle_grey_contrast, contrast_skewness, display_white_target, display_black_target, color_processing,
        hue_preservation, red_inset, red_rotation, green_inset, green_rotation, blue_inset, blue_rotation, purity =
        string.unpack("<ffffiffffffff", data)
    return {
        middle_grey_contrast = middle_grey_contrast,
        contrast_skewness = contrast_skewness,
        display_white_target = display_white_target,
        display_black_target = display_black_target,
        color_processing = color_processing,
        hue_preservation = hue_preservation,
        red_inset = red_inset,
        red_rotation = red_rotation,
        green_inset = green_inset,
        green_rotation = green_rotation,
        blue_inset = blue_inset,
        blue_rotation = blue_rotation,
        purity = purity
    }
end

local function decode_sigmoid_v3(data)
    local middle_grey_contrast, contrast_skewness, display_white_target, display_black_target, color_processing,
        hue_preservation, red_inset, red_rotation, green_inset, green_rotation, blue_inset, blue_rotation, purity,
        base_primaries = string.unpack("<ffffiffffffffi", data)
    return {
        middle_grey_contrast = middle_grey_contrast,
        contrast_skewness = contrast_skewness,
        display_white_target = display_white_target,
        display_black_target = display_black_target,
        color_processing = color_processing,
        hue_preservation = hue_preservation,
        red_inset = red_inset,
        red_rotation = red_rotation,
        green_inset = green_inset,
        green_rotation = green_rotation,
        blue_inset = blue_inset,
        blue_rotation = blue_rotation,
        purity = purity,
        base_primaries = base_primaries
    }
end

local function decode_sigmoid(version, encoded)
    local data = hex_to_bin(encoded)
    if version == 1 then
        return decode_sigmoid_v1(data)
    elseif version == 2 then
        return decode_sigmoid_v2(data)
    elseif version == 3 then
        return decode_sigmoid_v3(data)
    else
        -- TODO: Not supported!
    end
end

local function encode_sigmoid_v1(params)
    return string.pack("<ffffif", params.middle_grey_contrast, params.contrast_skewness, params.display_white_target,
        params.display_black_target, params.color_processing, params.hue_preservation)
end

local function encode_sigmoid_v2(params)
    return string.pack("<ffffiffffffff", params.middle_grey_contrast, params.contrast_skewness,
        params.display_white_target, params.display_black_target, params.color_processing, params.hue_preservation,
        params.red_inset, params.red_rotation, params.green_inset, params.green_rotation, params.blue_inset,
        params.blue_rotation, params.purity)
end

local function encode_sigmoid_v3(params)
    return string.pack("<ffffiffffffffi", params.middle_grey_contrast, params.contrast_skewness,
        params.display_white_target, params.display_black_target, params.color_processing, params.hue_preservation,
        params.red_inset, params.red_rotation, params.green_inset, params.green_rotation, params.blue_inset,
        params.blue_rotation, params.purity, params.base_primaries)
end

local function encode_sigmoid(version, params)
    local data
    if version == 1 then
        data = encode_sigmoid_v1(params)
    elseif version == 2 then
        data = encode_sigmoid_v2(params)
    elseif version == 3 then
        data = encode_sigmoid_v3(params)
    else
        -- TODO: Not supported!
    end
    return bin_to_hex(data)
end

local function create_hdr_xmp(xmp, target_luminance)
    -- Find and edit the sigmoid module
    local hdr_xmp, replacements = xmp:gsub('<rdf:li[^>]*darktable:operation="sigmoid"[^>]*/>', function(sigmoid_xml)
        local version = tonumber(sigmoid_xml:match('darktable:modversion="(%d+)"'))
        local edited = sigmoid_xml:gsub('darktable:params="(%x+)"', function(encoded_params)
            local params = decode_sigmoid(version, encoded_params)
            params.display_white_target = target_luminance
            return 'darktable:params="' .. encode_sigmoid(version, params) .. '"'
        end)
        return edited
    end)

    return hdr_xmp
end

-- Initialize ultrahdr_app path with bundled one if not initialized
local ultrahdr_app_path = df.get_executable_path_preference("ultrahdr_app")
if not ultrahdr_app_path or ultrahdr_app_path == "" then
    ultrahdr_app_path = detect_bundled_ultrahdr_app()
    if ultrahdr_app_path ~= nil then
        df.set_executable_path_preference("ultrahdr_app", ultrahdr_app_path)
    end
end

local ultrahdr_app_path = df.check_if_bin_exists("ultrahdr_app")
local magick_path = df.check_if_bin_exists("magick")
local darktable_cli_path = df.check_if_bin_exists("darktable-cli")

-- only jpeg supported
local function support_format(storage, format)
    return string.lower(format.mime) == "image/jpeg"
end

local function initialize(storage, format, images, high_quality, extra_data)
    dt.print("Initialize")
    save_preferences()

    if not ultrahdr_app_path then
        dt.print_error("ultrahdr_app not found")
        dt.print(_("ERROR - ultrahdr_app not found"))
        return {}
    end
    if not magick_path then
        dt.print_error("magick not found")
        dt.print(_("ERROR - magick not found"))
        return {}
    end
    if not darktable_cli_path then
        dt.print_error("darktable_cli_path not found")
        dt.print(_("ERROR - darktable_cli_path not found"))
        return {}
    end

    return nil
end

local function export_exr_image(original_filename, xmp_filename, output_filename)
    local dt_cli_command = string.format(
        '%s "%s" "%s" "%s" --apply-custom-presets false --icc-type LIN_REC2020 --core --conf plugins/imageio/format/exr/compression=0 --conf plugins/imageio/format/exr/pixel_type=float',
        darktable_cli_path, original_filename, xmp_filename, output_filename:gsub(PS, "/"))

    local result = dsys.external_command(dt_cli_command)
    if result ~= 0 then
        dt.print_error(string.format("darktable-cli failed with exit code %d", result))
        dt.print(_("ERROR - Failed to export HDR image using darktable-cli. Check console for details."))
        return false
    end
    return true
end

local function convert_hdr_image(exr_filename, output_filename)
    local magick_command = string.format(
        '%s "%s" -alpha on -define quantum:format=floating-point -define quantum:precision=16 rgba:"%s"', magick_path,
        exr_filename, output_filename)

    local result = dsys.external_command(magick_command)
    if result ~= 0 then
        dt.print_error(string.format("ImageMagick convert failed with exit code %d", result))
        dt.print(_("ERROR - Failed to convert EXR to raw buffer using ImageMagick. Check if file exists and ImageMagick is properly installed."))
        return false
    end
    return true
end

local function create_ultrahdr_image(image, sdr_jpg_filename, hdr_raw_filename, output_jpg_filename, target_luminance)
    local downsampling_factor = round_to_power_of_2(gainmap_downsampling_widget.value)
    local ultrahdr_app_command = string.format(
        '%s -m 0 -i "%s" -p "%s" -a 4 -c 0 -C 2 -t 0 -L %d -Q %d -R 1 -M 1 -s %d -w %d -h %d -z "%s"',
        ultrahdr_app_path, sdr_jpg_filename, hdr_raw_filename, target_luminance, gainmap_quality_widget.value,
        downsampling_factor, image.final_width, image.final_height, output_jpg_filename)

    local result = dsys.external_command(ultrahdr_app_command)
    if result ~= 0 then
        dt.print_error(string.format("ultrahdr_app failed with exit code %d", result))
        dt.print(_("ERROR - Failed to create UltraHDR image. Check if input files are valid and ultrahdr_app is working correctly."))
        return false
    end
    return true
end

local function store(storage, image, format, filename, number, total, high_quality, extra_data)
    local output_file = ds.substitute(image, number, output_pattern_widget.text) .. ".jpg"
    if not overwrite_on_conflict_widget.value then
        output_file = df.create_unique_filename(output_file)
    end
    local output_path = ds.get_path(output_file)
    df.mkdir(output_path)

    local target_luminance = (target_luminance_widget.value + 0.5) // 1
    if target_luminance < 100 then target_luminance = 100 end
    if target_luminance > 1600 then target_luminance = 1600 end

    local xmp = read_file(image.sidecar)
    if not xmp then
        dt.print_error(string.format("Failed to read XMP sidecar: %s", image.sidecar))
        dt.print(_("ERROR - Failed to read XMP sidecar file. Make sure the image has been processed in Darktable."))
        os.remove(filename)
        return
    end

    local tmp_prefix = os.tmpname()
    local hdr_xmp = create_hdr_xmp(xmp, target_luminance)
    local hdr_xmp_filename = tmp_prefix .. ".xmp"
    if not write_file(hdr_xmp_filename, hdr_xmp) then
        dt.print_error(string.format("Failed to write temporary XMP file: %s", hdr_xmp_filename))
        dt.print(_("ERROR - Failed to write temporary XMP file. Check disk space and permissions."))
        os.remove(hdr_xmp_filename)
        os.remove(filename)
        return
    end

    local hdr_exr_filename = tmp_prefix .. ".exr"
    if not export_exr_image(image.path .. PS .. image.filename, hdr_xmp_filename, hdr_exr_filename) then
        os.remove(hdr_xmp_filename)
        os.remove(hdr_exr_filename)
        os.remove(filename)
        return
    end
    os.remove(hdr_xmp_filename) -- Not needed anymore

    local hdr_raw_filename = tmp_prefix .. ".raw"
    if not convert_hdr_image(hdr_exr_filename, hdr_raw_filename) then
        os.remove(hdr_exr_filename)
        os.remove(hdr_raw_filename)
        os.remove(filename)
        return
    end
    os.remove(hdr_exr_filename) -- Not needed anymore

    if not create_ultrahdr_image(image, filename, hdr_raw_filename, output_file, target_luminance) then
        os.remove(hdr_raw_filename)
        os.remove(filename)
        return
    end

    -- Cleanup on success
    os.remove(hdr_raw_filename)
    os.remove(filename)
end

-- Register the export storage
dt.register_storage(PLUGIN_NAME, PLUGIN_DISPLAY_NAME, store, nil, support_format, initialize, widget)

local function destroy()
    dt.destroy_storage(PLUGIN_NAME)
end

script_data.destroy = destroy

return script_data
