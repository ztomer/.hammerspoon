--[[
  logger.lua - A unified logging system for Hammerspoon modules

  Usage:
    local logger = require("core.logger")

    -- Set logging level and enable/disable logging
    logger.setLevel(logger.levels.DEBUG)
    logger.enable(true)

    -- Log at different levels
    logger.debug("MyModule", "This is a debug message")
    logger.info("MyModule", "This is an info message")
    logger.warn("MyModule", "This is a warning message")
    logger.error("MyModule", "This is an error message")

    -- Format strings with parameters
    logger.info("MyModule", "Window %d moved to position %s", win_id, position)

  Configuration:
    Settings can be loaded from the config.lua file if it contains:
    config.logging = {
      enabled = true,          -- Enable/disable logging
      level = "DEBUG",         -- Default log level (DEBUG, INFO, WARN, ERROR)
      show_timestamp = true,   -- Include timestamps in log entries
      file_logging = false,    -- Write logs to a file
      log_path = "~/logs/hammerspoon.log" -- Path for log file
    }
]] local logger = {}

-- Define log levels
logger.levels = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4
}

-- Internal state
local _config = {
    enabled = false,
    level = logger.levels.INFO,
    show_timestamp = true,
    file_logging = false,
    log_path = nil,
    log_file = nil
}

-- Level name mapping for display
local _level_names = {
    [logger.levels.DEBUG] = "DEBUG",
    [logger.levels.INFO] = "INFO",
    [logger.levels.WARN] = "WARN",
    [logger.levels.ERROR] = "ERROR"
}

-- Convert level name to numeric level
local function _name_to_level(name)
    if type(name) == "string" then
        name = string.upper(name)
        for level_name, level in pairs(logger.levels) do
            if level_name == name then
                return level
            end
        end
    end
    -- Default to INFO if level name is invalid
    return logger.levels.INFO
end

-- Format a message with printf-style arguments
local function _format_message(message, ...)
    if select("#", ...) > 0 then
        local success, result = pcall(string.format, message, ...)
        if success then
            return result
        else
            return message .. " [format error: " .. result .. "]"
        end
    end
    return message
end

-- Generate log entry string
local function _format_log_entry(level, module, message, ...)
    local level_str = _level_names[level] or "UNKNOWN"
    local module_str = module or "UNKNOWN"
    local msg = _format_message(message, ...)

    local entry = ""
    if _config.show_timestamp then
        entry = os.date("%Y-%m-%d %H:%M:%S") .. " "
    end

    entry = entry .. "[" .. level_str .. "] "
    entry = entry .. "[" .. module_str .. "] "
    entry = entry .. msg

    return entry
end

-- Write log to file if enabled
local function _write_to_file(entry)
    if not _config.file_logging or not _config.log_path then
        return false
    end

    -- Lazy initialization of log file
    if not _config.log_file then
        -- Expand ~ to user's home directory if needed
        local path = _config.log_path:gsub("^~", os.getenv("HOME"))

        -- Create directory if it doesn't exist
        local dir = path:match("(.+)/[^/]+$")
        if dir then
            os.execute("mkdir -p " .. dir)
        end

        -- Try to open log file for appending
        local file, err = io.open(path, "a")
        if not file then
            -- If we can't open the file, disable file logging to avoid repeated errors
            _config.file_logging = false
            print("Logger: Failed to open log file: " .. tostring(err))
            return false
        end

        _config.log_file = file
    end

    -- Write log entry with newline
    _config.log_file:write(entry .. "\n")
    _config.log_file:flush()
    return true
end

-- Core logging function
local function _log(level, module, message, ...)
    -- Skip if logging is disabled or level is below threshold
    if not _config.enabled or level < _config.level then
        return
    end

    -- Format the log entry
    local entry = _format_log_entry(level, module, message, ...)

    -- Print to console
    print(entry)

    -- Write to file if enabled
    _write_to_file(entry)
end

-- Load configuration from config.lua if available
function logger.loadConfig()
    local success, config = pcall(require, "config")
    if success and config and config.logging then
        logger.configure(config.logging)
    end
    return logger
end

-- Configure the logger
function logger.configure(options)
    if type(options) ~= "table" then
        return logger
    end

    -- Update configuration
    if type(options.enabled) == "boolean" then
        _config.enabled = options.enabled
    end

    if options.level then
        _config.level = _name_to_level(options.level)
    end

    if type(options.show_timestamp) == "boolean" then
        _config.show_timestamp = options.show_timestamp
    end

    if type(options.file_logging) == "boolean" then
        _config.file_logging = options.file_logging
    end

    if type(options.log_path) == "string" then
        _config.log_path = options.log_path
        -- Reset log file to force reopen with new path
        if _config.log_file then
            _config.log_file:close()
            _config.log_file = nil
        end
    end

    return logger
end

-- Enable or disable logging
function logger.enable(enabled)
    _config.enabled = enabled and true or false
    return logger
end

-- Set the minimum log level
function logger.setLevel(level)
    if type(level) == "string" then
        level = _name_to_level(level)
    end

    if logger.levels[level] then
        _config.level = level
    elseif type(level) == "number" and level >= logger.levels.DEBUG and level <= logger.levels.ERROR then
        _config.level = level
    end

    return logger
end

-- Public logging functions for different levels
function logger.debug(module, message, ...)
    _log(logger.levels.DEBUG, module, message, ...)
end

function logger.info(module, message, ...)
    _log(logger.levels.INFO, module, message, ...)
end

function logger.warn(module, message, ...)
    _log(logger.levels.WARN, module, message, ...)
end

function logger.error(module, message, ...)
    _log(logger.levels.ERROR, module, message, ...)
end

-- Close logger and release resources
function logger.close()
    if _config.log_file then
        _config.log_file:close()
        _config.log_file = nil
    end
end

-- Initialize logging system
function logger.init()
    -- Auto-load config if available
    logger.loadConfig()

    -- Register function to close log file on Hammerspoon shutdown
    local old_callback = hs.shutdownCallback
    hs.shutdownCallback = function()
        logger.close()
        if old_callback then
            old_callback()
        end
    end

    return logger
end

return logger
