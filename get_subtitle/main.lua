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
