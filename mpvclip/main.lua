--[[
mpv scripts - mpvclip
Copyright (C) 2025-present Arjun Satarkar

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License version 3.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License version 3 for
more details.
]]

local input = require "mp.input"

local function log_cmd(args)
    local cmd = ""
    for _, v in ipairs(args) do
        cmd = cmd .. " " .. v
    end
    print("Running command:" .. cmd)
end

local function run_subprocess(args)
    mp.command_native({ name = "subprocess", args = args, playback_only = false })
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

    local video_input_pad = "0:v:" .. (video_track_id - 1)

    local audio_input_pad = ""
    if audio_track_id then
        audio_input_pad = "0:a:" .. (audio_track_id - 1)
    end

    local filtergraph = nil
    if sub_track_id then
        -- Ref: https://ffmpeg.org/ffmpeg-filters.html#filtergraph-escaping
        local squote_escaped_path = path:gsub("'", [['\\\'']])
        filtergraph = ("[%s]subtitles='%s':si=%d[%s]"):format(
            video_input_pad, squote_escaped_path, sub_track_id - 1, FILTERGRAPH_V_OUT
        )
    end

    local out_path = ("clip_%d.mp4"):format(os.time())

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
        "-pix_fmt", "yuv420p",
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
            "-movflags", "+faststart",
            out_path
        })

        log_cmd(args)
        run_subprocess(args)
    elseif two_pass_target then
        local clip_secs = (tonumber(b) - tonumber(a))
        local total_bytes = two_pass_target * 1024 * 1024
        local audio_bytes = AUDIO_BYTES_PER_SECOND * clip_secs
        local video_bytes = total_bytes - audio_bytes
        local video_bitrate = video_bytes / clip_secs * 8

        print(("Clip audio will take up %d bytes, leaving %d for video"):format(audio_bytes, video_bytes))
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
        run_subprocess(args)

        args = copy_arr(base_args)
        extend(args, audio_args)
        extend(args, {
            "-b:v", tostring(video_bitrate),
            "-pass", "2",
            out_path
        })

        log_cmd(args)
        run_subprocess(args)

        local log_file_name = ("ffmpeg2pass-%d.log"):format(video_track_id - 1)
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
