--[[
mpv scripts - get_subtitle
https://github.com/arjunsatarkar/mpv_scripts
Copyright (C) 2025-present Arjun Satarkar

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License version 3.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License version 3 for
more details.
]]

local utils = require("mp.utils")

Result = nil

local function get_subtitle()
    return mp.get_property("sub-text")
end

-- Enough to prevent the subs from XSSing you at least
local function html_escape(text)
    return text
        :gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
        :gsub('"', "&quot;")
        :gsub("'", "&#x27;")
end

local function copy_subtitle()
    local text = get_subtitle()

    local args = {
        "xclip",
        "-rmlastnl",
        "-selection", "clipboard"
    }

    --[[
    I honestly don't understand the behaviour of the xclip process.
    When not run async, this script seems to hang forever, I assume because
    xclip is waiting for more input. When run async, even if the
    abort_async_command call is omitted, the number of xclip processes in ps
    output doesn't increase - i.e. it is somehow not a process leak?

    Other long-lived processes do show the expected behaviour without
    abort_async_command, and uncommenting it does limit the total number to 1.

    So I'm leaving it like this. It works fine, evidently. If you understand
    what exactly is up, open an issue.
    ]]
    if Result then
        mp.abort_async_command(Result)
    end
    Result = mp.command_native_async({ name = "subprocess", args = args, stdin_data = text })
    if Result then
        mp.osd_message("Copied subtitle!")
    end
end

local function open_subtitle_in_browser()
    local text = html_escape(get_subtitle())
    local title_and_time = html_escape(("%s (%s)"):format(mp.get_property("media-title"), mp.get_property_osd("playback-time")))
    local script_dir = mp.get_script_directory()

    tmp_file_path = utils.join_path(script_dir, "get_subtitle_tmp.html")

    local file = io.open(tmp_file_path, "w")
    if file then
        file:write(string.format([[
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>%s</title>
    <style>
        html, body {
            margin: 0;
            padding: 0;
        }
        body {
            display: flex;
            align-items: center;
            justify-content: center;
            height: 100vh;
            font-size: xxx-large;
            background-color: black;
            color: white;
        }
    </style>
</head>
<body>
    <div>
        <div>%s</div>
        <br><cite>&mdash; %s</cite>
    </div>
</body>
</html>]], title_and_time, text, title_and_time))
        file:close()
    end

    mp.command_native({name = "subprocess", args = {"xdg-open", tmp_file_path}})
end

mp.add_key_binding("g", "copy-subtitle", copy_subtitle)
mp.add_key_binding("ctrl+g", "open-subtitle-in-browser", open_subtitle_in_browser)