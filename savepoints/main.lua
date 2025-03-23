--[[
mpv scripts - savepoints
Copyright (C) 2025-present Arjun Satarkar

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License version 3.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License version 3 for
more details.
]]
---@diagnostic disable: param-type-mismatch, need-check-nil

local input = require("mp.input")
local utils = require("mp.utils")

local home_dir = os.getenv("HOME")
local savepoints_dir = utils.join_path(home_dir, "mpv-savepoints")

local savepoints = nil
local savepoints_hms = nil

local media_path = nil

local function bsearch_next_index(arr, val, past_end)
    local low = 1
    local high = #arr + (past_end and 1 or 0)

    while true do
        if high <= low then
            return high
        end
        local i = math.floor((high + low) / 2)
        if arr[i] <= val then
            low = i + 1
        else
            high = i
        end
    end
end

local function to_hms(pos)
    local hours = math.floor(pos / (60 * 60))
    local minutes = math.floor((pos / 60) % 60)
    local seconds = math.floor(pos % 60)
    local milliseconds = math.floor(pos % 1 * 1000)

    return ("%02d:%02d:%02d.%03d"):format(hours, minutes, seconds, milliseconds)
end

local function savepoints_cache_initialized()
    return savepoints ~= nil and savepoints_hms ~= nil
end

local function open_savepoint_file(mode)
    if media_path == nil then
        return nil
    end
    local _, media_filename = utils.split_path(media_path)
    local savepoint_filename = ("%s.txt"):format(media_filename)
    return io.open(utils.join_path(savepoints_dir, savepoint_filename), mode)
end

local function load_savepoints()
    savepoints = {}
    savepoints_hms = {}

    mp.command_native({
        name = "subprocess",
        args = { "mkdir", "-p", savepoints_dir },
        playback_only = false
    })

    local file = open_savepoint_file("r")
    if file then
        for line in file:lines() do
            table.insert(savepoints, tonumber(line))
        end
        table.sort(savepoints)
        for _, v in ipairs(savepoints) do
            table.insert(savepoints_hms, to_hms(v))
        end
        file:close()
    end
end

local function add_savepoint()
    if not savepoints_cache_initialized() then
        return
    end

    local function cache_savepoint(pos)
        local i = bsearch_next_index(savepoints, pos, true)
        table.insert(savepoints, i, pos)
        table.insert(savepoints_hms, i, to_hms(pos))
    end

    local file = open_savepoint_file("a")
    if file then
        local pos_str = mp.get_property("time-pos/full")
        local pos = tonumber(pos_str)
        cache_savepoint(pos)
        file:write(pos_str .. "\n")
        file:close()
    end
end

local function jump_to_savepoint()
    if not savepoints_cache_initialized() then
        return
    end
    if next(savepoints) == nil then
        mp.osd_message("No savepoints for this file!")
        return
    end

    input.select({
        prompt = "Jump to savepoint:",
        items = savepoints_hms,
        default_item = bsearch_next_index(savepoints, tonumber(mp.get_property("time-pos/full"))),
        submit = function(i)
            mp.commandv("seek", tostring(savepoints[i]), "absolute+exact")
        end
    })
end

mp.add_key_binding("a", "add-savepoint", add_savepoint)
mp.add_key_binding("ctrl+a", "jump-to-savepoint", jump_to_savepoint)
mp.observe_property("path", "string", function(_, p)
    media_path = p
    load_savepoints()
end)
