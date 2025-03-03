local input = require "mp.input"

local function log_cmd(args)
    local cmd = ""
    for _, v in ipairs(args) do
        cmd = cmd .. " " .. string.format("%s", v)
    end
    print("Running command:" .. cmd)
end

local function extend(arr1, arr2)
    for _, v in ipairs(arr2) do
        table.insert(arr1, v)
    end
end

local function copy_arr(arr)
    local result = {}
    for _, v in ipairs(arr) do
        table.insert(result, v)
    end
    return result
end

local function do_clip(a, b, crf, two_pass_target, video_track_id, audio_track_id, sub_track_id, path)
    local AUDIO_CODEC = "libopus"
    local AUDIO_BITRATE_KIBIBITS = 128
    local AUDIO_BITRATE = math.floor(AUDIO_BITRATE_KIBIBITS * 1024)
    local AUDIO_BYTES_PER_SECOND = math.floor(AUDIO_BITRATE / 8)
    local FILTERGRAPH_V_OUT = "v_out"

    local video_input_pad = "0:v:" .. tostring(video_track_id - 1)

    local audio_input_pad = ""
    if audio_track_id then
        audio_input_pad = "0:a:" .. tostring(audio_track_id - 1)
    end

    local filtergraph = nil
    if sub_track_id then
        --[[
        Not sure why this is the correct number of escapes, but it works.
        Ref: https://stackoverflow.com/a/10729560
        (slightly different context and approach, but helpful)
        --]]
        local squote_escaped_path = path:gsub("'", [['\\\'']])
        filtergraph = string.format(
            "[%s]subtitles='%s':si=%d[%s]",
            video_input_pad, squote_escaped_path, sub_track_id - 1, FILTERGRAPH_V_OUT
        )
    end

    local out_path = string.format("clip_%d.mp4", os.time())

    local base_args = {
        "ffmpeg",
        "-hide_banner",
        "-loglevel", "warning",
        "-ss", a,
        "-to", b,
        "-copyts",
        "-i", path,
        "-c:v", "libx264",
        "-ss", a,
        "-to", b,
    }
    if filtergraph then
        extend(base_args, {
            "-filter_complex", filtergraph,
            "-map", ("[%s]"):format(FILTERGRAPH_V_OUT)
        })
    else
        extend(base_args, { "-map", video_input_pad })
    end

    local audio_args = {}
    if audio_track_id then
        audio_args = {
            "-c:a", AUDIO_CODEC,
            "-b:a", tostring(AUDIO_BITRATE),
            "-map", audio_input_pad
        }
    end

    if crf then
        local args = copy_arr(base_args)
        extend(args, audio_args)
        extend(args, {
            "-crf", crf,
            "-pix_fmt", "yuv420p",
            "-movflags", "+faststart",
            out_path
        })

        log_cmd(args)
        mp.command_native({ name = "subprocess", args = args })
    elseif two_pass_target then
        local clip_secs = (tonumber(b) - tonumber(a))
        local total_bytes = two_pass_target * 1024 * 1024
        local audio_bytes = AUDIO_BYTES_PER_SECOND * clip_secs
        local video_bytes = total_bytes - audio_bytes
        local video_bitrate = video_bytes / clip_secs * 8

        print(string.format("Clip audio will take up %d bytes, leaving %d for video", audio_bytes, video_bytes))
        if video_bytes <= 0 then
            local message = "Can't clip: not enough space for video"
            mp.osd_message(message)
            print(message)
            return
        end

        local args = copy_arr(base_args)
        extend(args, {
            "-b:v", tostring(video_bitrate),
            "-pass", "1",
            "-an",
            "-f", "null",
            "-"
        })

        log_cmd(args)
        mp.command_native({ name = "subprocess", args = args })

        args = copy_arr(base_args)
        extend(args, audio_args)
        extend(args, {
            "-b:v", tostring(video_bitrate),
            "-pass", "2",
            out_path
        })

        log_cmd(args)
        mp.command_native({ name = "subprocess", args = args })

        local log_file_name = string.format("ffmpeg2pass-%d.log", video_track_id - 1)
        os.remove(log_file_name)
        os.remove(log_file_name .. ".mbtree")
    end

    local message = "Wrote clip to " .. out_path
    mp.osd_message(message)
    print(message)
end

local function get_params()
    local a = mp.get_property("ab-loop-a")
    local b = mp.get_property("ab-loop-b")

    if a == "no" or b == "no" then
        mp.osd_message("Can't clip: a-b loop not set; doing nothing")
        return
    end

    local path = mp.get_property("path")
    local video_track_id = mp.get_property_native("current-tracks/video/id")
    local audio_track_id = mp.get_property_native("current-tracks/audio/id")
    local sub_track_id = mp.get_property_native("current-tracks/sub/id")

    input.select({
        prompt = "Select encoding mode",
        items = { "CRF", "2-pass" },
        default_item = 1,
        keep_open = true,
        submit = function(id)
            if id == 1 then
                -- CRF mode
                input.get({
                    prompt = "Choose CRF (0-51):",
                    default_text = "23",
                    submit = function(crf)
                        if tonumber(crf) then
                            do_clip(a, b, crf, nil, video_track_id, audio_track_id, sub_track_id, path)
                        else
                            mp.osd_message("Invalid CRF; doing nothing")
                        end
                    end,
                })
            elseif id == 2 then
                -- 2-pass mode
                input.get({
                    prompt = "Choose target output size in mebibytes:",
                    default_text = "50",
                    submit = function(two_pass_target)
                        two_pass_target = tonumber(two_pass_target)
                        if two_pass_target then
                            do_clip(a, b, nil, two_pass_target, video_track_id, audio_track_id, sub_track_id, path)
                        else
                            mp.osd_message("Invalid size, doing nothing")
                        end
                    end,
                })
            end
        end,
    })
end

mp.add_key_binding("c", "clip-ab", get_params)
