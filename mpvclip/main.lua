local input = require "mp.input"

local function log_cmd(args)
    local cmd = ""
    for _, v in ipairs(args) do
        cmd = cmd .. string.format("%q", v) .. ", "
    end
    print("Running command: " .. cmd)
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

local function do_clip(a, b, crf, two_pass_target, sub_track_id, path)
    local AUDIO_CODEC = "libopus"
    local AUDIO_BITRATE_KIBIBITS = 128
    local AUDIO_BITRATE_STR = tostring(AUDIO_BITRATE_KIBIBITS) .. "k"

    local filterchain = nil
    if sub_track_id then
        filterchain = string.format("subtitles='%s':si=%d", path, sub_track_id - 1)
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
    if filterchain then
        extend(base_args, { "-filter_complex", filterchain })
    end

    if crf then
        local args = copy_arr(base_args)
        extend(args, {
            "-crf", crf,
            "-pix_fmt", "yuv420p",
            "-movflags", "+faststart",
            "-c:a", AUDIO_CODEC,
            "-b:a", AUDIO_BITRATE_STR,
            out_path
        })

        log_cmd(args)
        mp.command_native({ name = "subprocess", args = args })
    elseif two_pass_target then
        local clip_secs = (tonumber(b) - tonumber(a))
        local total_bytes = two_pass_target * 1024 * 1024
        local audio_bytes = AUDIO_BITRATE_KIBIBITS * (1024 / 8) * clip_secs
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
        extend(args, {
            "-b:v", tostring(video_bitrate),
            "-pass", "2",
            "-c:a", AUDIO_CODEC,
            "-b:a", AUDIO_BITRATE_STR,
            out_path
        })

        log_cmd(args)
        mp.command_native({ name = "subprocess", args = args })

        os.remove("ffmpeg2pass-0.log")
        os.remove("ffmpeg2pass-0.log.mbtree")
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
                            do_clip(a, b, crf, nil, sub_track_id, path)
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
                            do_clip(a, b, nil, two_pass_target, sub_track_id, path)
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
