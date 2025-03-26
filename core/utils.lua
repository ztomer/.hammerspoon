--[[
  utils.lua - Shared utility functions for Hammerspoon modules

  This module provides common utility functions that can be used
  across all other modules in the project to reduce code duplication
  and standardize common operations.

  Usage:
    local utils = require("core.utils")

    -- Safe function calling
    local result = utils.safeCall(myFunction, arg1, arg2)

    -- Table operations
    local copied_table = utils.deepCopy(my_table)
    local merged_table = utils.merge(table1, table2)

    -- Geometry helpers
    local overlap = utils.calculateOverlap(rect1, rect2)

    -- String utilities
    local safe_name = utils.sanitizeName("My Screen (1)")
]] local logger = require("core.logger")
local utils = {}

-- ===== ERROR HANDLING =====

-- Safely call a function with error handling
function utils.safeCall(fn, ...)
    if type(fn) ~= "function" then
        logger.error("Utils", "safeCall: Not a function")
        return nil
    end

    local success, result = pcall(fn, ...)
    if not success then
        logger.error("Utils", "Error in function call: %s", result)
        return nil
    end

    return result
end

-- Safely require a module with error handling
function utils.safeRequire(module_name)
    local success, module = pcall(require, module_name)
    if not success then
        logger.error("Utils", "Failed to require module '%s': %s", module_name, module)
        return nil
    end

    return module
end

-- ===== TABLE OPERATIONS =====

-- Deep copy a table
function utils.deepCopy(orig)
    local orig_type = type(orig)
    local copy

    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[utils.deepCopy(orig_key)] = utils.deepCopy(orig_value)
        end
        setmetatable(copy, utils.deepCopy(getmetatable(orig)))
    else
        -- number, string, boolean, etc
        copy = orig
    end

    return copy
end

-- Merge two tables (source values override target)
function utils.merge(target, source)
    if type(target) ~= "table" or type(source) ~= "table" then
        return target
    end

    for k, v in pairs(source) do
        if type(v) == "table" and type(target[k]) == "table" then
            utils.merge(target[k], v)
        else
            target[k] = v
        end
    end

    return target
end

-- Find an item in a table that matches a predicate
function utils.find(tbl, predicate)
    if type(tbl) ~= "table" or type(predicate) ~= "function" then
        return nil
    end

    for k, v in pairs(tbl) do
        if predicate(v, k, tbl) then
            return v, k
        end
    end

    return nil
end

-- Count the number of items in a table
function utils.tableCount(tbl)
    if type(tbl) ~= "table" then
        return 0
    end

    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end

    return count
end

-- Check if a table contains a value
function utils.tableContains(tbl, value)
    if type(tbl) ~= "table" then
        return false
    end

    for _, v in pairs(tbl) do
        if v == value then
            return true
        end
    end

    return false
end

-- Filter a table based on a predicate
function utils.filter(tbl, predicate)
    if type(tbl) ~= "table" or type(predicate) ~= "function" then
        return {}
    end

    local result = {}
    for k, v in pairs(tbl) do
        if predicate(v, k, tbl) then
            result[k] = v
        end
    end

    return result
end

-- Map a function over a table
function utils.map(tbl, fn)
    if type(tbl) ~= "table" or type(fn) ~= "function" then
        return {}
    end

    local result = {}
    for k, v in pairs(tbl) do
        result[k] = fn(v, k, tbl)
    end

    return result
end

-- ===== STRING OPERATIONS =====

-- Sanitize a string for use as a filename or identifier
function utils.sanitizeName(name)
    if type(name) ~= "string" then
        return "unknown"
    end

    -- Replace problematic characters with underscores
    local sanitized = name:gsub("[%s%-%.%:%(%)%[%]%{%}%+%*%?%/%\\]", "_")

    -- Remove any other non-alphanumeric characters
    sanitized = sanitized:gsub("[^%w_]", "")

    -- Return fallback if empty
    if sanitized == "" then
        return "unknown"
    end

    return sanitized
end

-- Split a string by delimiter
function utils.split(str, delimiter)
    if type(str) ~= "string" then
        return {}
    end

    delimiter = delimiter or ","
    local result = {}
    for match in (str .. delimiter):gmatch("(.-)" .. delimiter) do
        table.insert(result, match)
    end

    return result
end

-- Trim whitespace from a string
function utils.trim(str)
    if type(str) ~= "string" then
        return ""
    end

    return str:match("^%s*(.-)%s*$")
end

-- Format string with replacements (alternative to string.format)
-- Example: utils.template("Hello, {{name}}!", {name = "World"}) => "Hello, World!"
function utils.template(str, replacements)
    if type(str) ~= "string" or type(replacements) ~= "table" then
        return str
    end

    return str:gsub("{{([^}]+)}}", function(key)
        return tostring(replacements[utils.trim(key)] or "")
    end)
end

-- ===== GEOMETRY HELPERS =====

-- Calculate overlap area between two rects
function utils.calculateOverlap(rect1, rect2)
    if not rect1 or not rect2 then
        return 0
    end

    -- Ensure we have all required fields
    local rect1_x = rect1.x or rect1[1] or 0
    local rect1_y = rect1.y or rect1[2] or 0
    local rect1_w = rect1.w or rect1.width or rect1[3] or 0
    local rect1_h = rect1.h or rect1.height or rect1[4] or 0

    local rect2_x = rect2.x or rect2[1] or 0
    local rect2_y = rect2.y or rect2[2] or 0
    local rect2_w = rect2.w or rect2.width or rect2[3] or 0
    local rect2_h = rect2.h or rect2.height or rect2[4] or 0

    -- Calculate intersection
    local x_overlap = math.max(0, math.min(rect1_x + rect1_w, rect2_x + rect2_w) - math.max(rect1_x, rect2_x))
    local y_overlap = math.max(0, math.min(rect1_y + rect1_h, rect2_y + rect2_h) - math.max(rect1_y, rect2_y))

    -- Return overlap area
    return x_overlap * y_overlap
end

-- Calculate overlap percentage between two rects
function utils.calculateOverlapPercentage(rect1, rect2)
    local overlap_area = utils.calculateOverlap(rect1, rect2)

    -- Calculate rect1 area
    local rect1_w = rect1.w or rect1.width or rect1[3] or 0
    local rect1_h = rect1.h or rect1.height or rect1[4] or 0
    local rect1_area = rect1_w * rect1_h

    -- Avoid division by zero
    if rect1_area <= 0 then
        return 0
    end

    return overlap_area / rect1_area
end

-- Create a standardized rect representation
function utils.standardizeRect(rect)
    if not rect then
        return {
            x = 0,
            y = 0,
            w = 0,
            h = 0
        }
    end

    -- Extract values, handling different rect formats
    local x = rect.x or rect[1] or 0
    local y = rect.y or rect[2] or 0
    local w = rect.w or rect.width or rect[3] or 0
    local h = rect.h or rect.height or rect[4] or 0

    return {
        x = x,
        y = y,
        w = w,
        h = h
    }
end

-- Check if a point is inside a rect
function utils.pointInRect(point, rect)
    if not point or not rect then
        return false
    end

    local standard_rect = utils.standardizeRect(rect)
    local px = point.x or point[1] or 0
    local py = point.y or point[2] or 0

    return px >= standard_rect.x and px <= standard_rect.x + standard_rect.w and py >= standard_rect.y and py <=
               standard_rect.y + standard_rect.h
end

-- Calculate the center point of a rect
function utils.rectCenter(rect)
    local standard_rect = utils.standardizeRect(rect)

    return {
        x = standard_rect.x + standard_rect.w / 2,
        y = standard_rect.y + standard_rect.h / 2
    }
end

-- Calculate distance between two points
function utils.distance(point1, point2)
    if not point1 or not point2 then
        return 0
    end

    local x1 = point1.x or point1[1] or 0
    local y1 = point1.y or point1[2] or 0
    local x2 = point2.x or point2[1] or 0
    local y2 = point2.y or point2[2] or 0

    return math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
end

-- ===== SCREEN HELPERS =====

-- Get screen layout information
function utils.getScreenLayout()
    local screens = hs.screen.allScreens()
    local layout = {}

    for i, screen in ipairs(screens) do
        local frame = screen:frame()
        layout[i] = {
            id = screen:id(),
            name = screen:name(),
            frame = {
                x = frame.x,
                y = frame.y,
                w = frame.w,
                h = frame.h
            },
            is_primary = screen:isPrimary(),
            is_retina = screen:currentMode().scale > 1
        }
    end

    return layout
end

-- Find screen by name pattern
function utils.findScreenByPattern(pattern)
    if type(pattern) ~= "string" then
        return nil
    end

    for _, screen in ipairs(hs.screen.allScreens()) do
        local screen_name = screen:name()
        if screen_name:match(pattern) then
            return screen
        end
    end

    return nil
end

-- ===== WINDOW HELPERS =====

-- Apply frame with retry for problematic apps
function utils.applyFrameWithRetry(window, frame, options)
    if not window or not frame then
        return false
    end

    options = options or {}
    local max_attempts = options.max_attempts or 3
    local delay = options.delay or 0.1
    local is_problem_app = options.is_problem_app or false

    -- First attempt
    local saved_duration = hs.window.animationDuration
    hs.window.animationDuration = options.animation_duration or 0.01
    window:setFrame(frame)
    hs.window.animationDuration = saved_duration

    -- For problem apps, do additional retries
    if is_problem_app then
        for attempt = 2, max_attempts do
            hs.timer.doAfter((attempt - 1) * delay, function()
                -- Check if the window moved from where we put it
                if not window:isValid() then
                    return
                end

                local current_frame = window:frame()
                if current_frame.x ~= frame.x or current_frame.y ~= frame.y or current_frame.w ~= frame.w or
                    current_frame.h ~= frame.h then

                    logger.debug("Utils", "Detected position change, forcing position (attempt %d)", attempt)
                    window:setFrame(frame)
                end
            end)
        end

        -- Final verification with a longer delay
        hs.timer.doAfter(delay * max_attempts, function()
            if not window:isValid() then
                return
            end

            local final_frame = window:frame()
            if final_frame.x ~= frame.x or final_frame.y ~= frame.y or final_frame.w ~= frame.w or final_frame.h ~=
                frame.h then

                logger.debug("Utils", "Final position check failed, forcing position one last time")
                window:setFrame(frame)
            end
        end)
    end

    return true
end

-- Move window to screen and restore position
function utils.moveWindowToScreen(window, screen, position)
    if not window or not screen then
        return false
    end

    -- Move window to target screen
    window:moveToScreen(screen, false, false, 0)

    -- Apply position if provided
    if position then
        hs.timer.doAfter(0.05, function()
            if not window:isValid() then
                return
            end

            if type(position) == "function" then
                -- If position is a function, call it with the window
                position(window)
            elseif type(position) == "table" then
                -- If position is a frame, apply it
                utils.applyFrameWithRetry(window, position)
            end
        end)
    end

    return true
end

-- ===== DEBUGGING HELPERS =====

-- Print a table recursively for debugging
function utils.dump(o, indent)
    if type(o) ~= "table" then
        return tostring(o)
    end

    indent = indent or 0
    local indent_str = string.rep("  ", indent)
    local s = "{\n"

    for k, v in pairs(o) do
        if type(k) ~= "number" then
            k = '"' .. tostring(k) .. '"'
        end
        s = s .. indent_str .. "  [" .. k .. "] = " .. utils.dump(v, indent + 1) .. ",\n"
    end

    return s .. indent_str .. "}"
end

-- Format memory size for display
function utils.formatBytes(bytes, decimals)
    if not bytes or type(bytes) ~= "number" then
        return "0 B"
    end

    decimals = decimals or 2
    local k = 1024
    local sizes = {"B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"}

    local i = math.floor(math.log(bytes) / math.log(k))
    if i < 1 then
        i = 1
    end

    return string.format("%." .. decimals .. "f %s", bytes / math.pow(k, i - 1), sizes[i])
end

-- Format a time duration
function utils.formatDuration(seconds)
    if not seconds or type(seconds) ~= "number" then
        return "0s"
    end

    if seconds < 60 then
        return string.format("%.1fs", seconds)
    elseif seconds < 3600 then
        return string.format("%dm %ds", math.floor(seconds / 60), seconds % 60)
    else
        local hours = math.floor(seconds / 3600)
        local mins = math.floor((seconds % 3600) / 60)
        local secs = seconds % 60
        return string.format("%dh %dm %ds", hours, mins, secs)
    end
end

-- ===== FILE OPERATIONS =====

-- Check if a file exists
function utils.fileExists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

-- Create a directory if it doesn't exist
function utils.ensureDirectoryExists(path)
    if not path then
        return false
    end

    -- Expand ~ to home directory
    path = path:gsub("^~", os.getenv("HOME"))

    -- Try to create the directory
    local success = os.execute("mkdir -p " .. path)
    if not success then
        logger.error("Utils", "Failed to create directory: %s", path)
        return false
    end

    return true
end

-- Read file contents
function utils.readFile(path)
    if not path then
        return nil
    end

    -- Expand ~ to home directory
    path = path:gsub("^~", os.getenv("HOME"))

    local file = io.open(path, "r")
    if not file then
        return nil
    end

    local content = file:read("*all")
    file:close()

    return content
end

-- Write content to a file
function utils.writeFile(path, content)
    if not path or not content then
        return false
    end

    -- Expand ~ to home directory
    path = path:gsub("^~", os.getenv("HOME"))

    -- Ensure directory exists
    local dir = path:match("(.+)/[^/]+$")
    if dir then
        utils.ensureDirectoryExists(dir)
    end

    local file = io.open(path, "w")
    if not file then
        logger.error("Utils", "Failed to open file for writing: %s", path)
        return false
    end

    file:write(content)
    file:close()

    return true
end

-- ===== SYSTEM INTEGRATION =====

-- Create a unique ID
function utils.generateUUID()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    local uuid = string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
    return uuid
end

-- Get information about this system
function utils.getSystemInfo()
    local info = {}

    -- OS version
    info.os = hs.host.operatingSystemVersion()
    info.hostname = hs.host.localizedName()

    -- Screen info
    info.screens = {}
    for i, screen in ipairs(hs.screen.allScreens()) do
        local frame = screen:frame()
        info.screens[i] = {
            name = screen:name(),
            id = screen:id(),
            width = frame.w,
            height = frame.h
        }
    end

    -- Memory info
    local memory_raw = hs.host.vmStat()
    info.memory = {
        physical = utils.formatBytes(memory_raw.hw_memsize),
        free = utils.formatBytes(memory_raw.free * memory_raw.pagesize),
        active = utils.formatBytes(memory_raw.active * memory_raw.pagesize)
    }

    -- Add timestamp
    info.timestamp = os.time()
    info.datetime = os.date("%Y-%m-%d %H:%M:%S")

    return info
end

-- Run a shell command and get the output
function utils.runCommand(command)
    local handle = io.popen(command)
    local result = handle:read("*a")
    handle:close()

    return result:gsub("[\n\r]+$", "") -- Trim trailing newlines
end

return utils
