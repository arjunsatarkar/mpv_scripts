--[[
mpv scripts - get_subtitle
Copyright (C) 2025-present Arjun Satarkar

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License version 3.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License version 3 for
more details.
]]

Result = nil

local function main()
    local text = mp.get_property("sub-text")

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

mp.add_key_binding("g", "get-subtitle", main)
