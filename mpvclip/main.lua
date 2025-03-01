local input = require "mp.input"

local function dump(arr)
    local result = ""
    for _, v in ipairs(arr) do
        result = result .. string.format("%q", v) .. ", "
    end
    return result
end

local function extend(arr1, arr2)
    for _, v in ipairs(arr2) do
        table.insert(arr1, v)
    end
end

local function do_clip(a, b, crf, two_pass_target, sub_track_id, path)
    local filterchain = nil
    if sub_track_id then
        filterchain = string.format("subtitles='%s':si=%d", path, sub_track_id - 1)
    end

    local out_path = string.format("clip_%d.mp4", os.time())
    local args = {
        "ffmpeg",
        "-hide_banner",
        "-loglevel", "warning",
        "-ss", a,
        "-to", b,
        "-copyts",
        "-i", path,
        "-ss", a,
        "-to", b,
    }
    if filterchain then
        extend(args, { "-filter_complex", filterchain })
    end
    if crf then
        extend(args, { "-crf", crf })
    end
    extend(args, {
        "-pix_fmt", "yuv420p",
        "-movflags", "+faststart",
        "-c:a", "libopus",
        "-b:a", "128k",
        out_path
    })

    print(dump(args))

    mp.command_native({ "subprocess", args })
    mp.osd_message("mpvclip: wrote clip to " .. out_path)
    print("Wrote clip to " .. out_path)
end

local function get_params()
    local a = mp.get_property("ab-loop-a")
    local b = mp.get_property("ab-loop-b")

    if a == "no" or b == "no" then
        mp.osd_message("mpvclip: a-b loop not set; doing nothing")
        return
    end

    local path = mp.get_property("path")
    local sub_track_id = mp.get_property_native("current-tracks/sub/id")

    input.select({
        prompt = "mpvclip: select encoding mode",
        items = { "CRF", "2-pass" },
        default_item = 1,
        keep_open = true,
        submit = function(id)
            if id == 1 then
                input.get({
                    prompt = "Choose CRF (0-51):",
                    default_text = "23",
                    submit = function(crf)
                        if tonumber(crf) then
                            do_clip(a, b, crf, nil, sub_track_id, path)
                        else
                            mp.osd_message("mpvclip: invalid CRF; doing nothing")
                        end
                    end,
                })
            end
        end,
    })
end

mp.add_key_binding("c", "clip-ab", get_params)
