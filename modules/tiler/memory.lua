--[[
  memory.lua - Window position memory system

  This module manages remembering and restoring window positions
  across application launches and screen changes.

  Usage:
    local memory = require("modules.tiler.memory")

    -- Initialize with configuration
    memory.init(config)

    -- Remember current window position
    memory.rememberPosition(window)

    -- Apply remembered position to a window
    memory.applyPosition(window)

    -- Capture all window positions
    memory.captureAllPositions()
]] local logger = require("core.logger")
local utils = require("core.utils")
local state = require("core.state")
local events = require("core.events")

local memory = {}

-- Configuration
memory.config = {
    enabled = true,
    excluded_apps = {},
    auto_tile_fallback = true,
    default_zone = "center",
    app_zones = {}
}

--- Initialize the memory system
-- @param config table Configuration options
-- @return memory module for chaining
function memory.init(config)
    logger.info("Memory", "Initializing window position memory system")

    -- Update configuration
    if config then
        memory.config.enabled = config.enabled ~= false

        if config.excluded_apps then
            memory.config.excluded_apps = config.excluded_apps
        end

        if config.auto_tile_fallback ~= nil then
            memory.config.auto_tile_fallback = config.auto_tile_fallback
        end

        if config.default_zone then
            memory.config.default_zone = config.default_zone
        end

        if config.app_zones then
            memory.config.app_zones = config.app_zones
        end
    end

    -- Subscribe to window events
    events.on("window.created", function(win)
        if memory.config.enabled then
            memory.applyPosition(win)
        end
    end)

    events.on("window.moved", function(win)
        if memory.config.enabled then
            -- Debounce the remember operation
            memory._debounceRemember(win)
        end
    end)

    events.on("window.resized", function(win)
        if memory.config.enabled then
            -- Debounce the remember operation
            memory._debounceRemember(win)
        end
    end)

    -- Register shutdown callback to save positions
    local original_shutdown = hs.shutdownCallback
    hs.shutdownCallback = function()
        -- Save all window positions
        if memory.config.enabled then
            memory.captureAllPositions()
        end

        -- Call original callback if it exists
        if original_shutdown then
            original_shutdown()
        end
    end

    return memory
end

-- Track debounced operations
memory._timers = {}

--- Debounce window position remembering
-- @param win hs.window The window to remember
function memory._debounceRemember(win)
    if not win or not win:isStandard() then
        return
    end

    local win_id = win:id()
    local timer_key = tostring(win_id) .. "_remember"

    -- Cancel existing timer if any
    if memory._timers[timer_key] then
        memory._timers[timer_key]:stop()
    end

    -- Create a new timer with delay
    memory._timers[timer_key] = hs.timer.doAfter(0.5, function()
        if win:isValid() then
            memory.rememberPosition(win)
        end
        memory._timers[timer_key] = nil
    end)
end

--- Check if an app should be excluded
-- @param app_name string The application name
-- @return boolean True if the app should be excluded
function memory._isExcludedApp(app_name)
    if not app_name then
        return false
    end

    for _, excluded_app in ipairs(memory.config.excluded_apps) do
        if app_name == excluded_app then
            return true
        end
    end

    return false
end

--- Remember the current position of a window
-- @param win hs.window The window to remember
-- @return boolean True if position was remembered
function memory.rememberPosition(win)
    if not win or not win:isStandard() then
        return false
    end

    local win_id = win:id()
    local app = win:application()
    if not app then
        return false
    end

    local app_name = app:name()
    local screen = win:screen()

    -- Skip if app is in exclusion list
    if memory._isExcludedApp(app_name) then
        logger.debug("Memory", "Skipping excluded app: %s", app_name)
        return false
    end

    -- Get window state
    local window_state = state.getWindowState(win_id)

    if window_state and window_state.zone_id then
        -- Window is in a zone, remember the zone and tile index
        logger.debug("Memory", "Remembering zone position for %s: %s, tile: %d", app_name, window_state.zone_id,
            window_state.tile_idx or 1)

        state.saveWindowMemory(app_name, screen:id(), {
            zone_id = window_state.zone_id,
            tile_idx = window_state.tile_idx or 1,
            timestamp = os.time()
        })

        -- Emit event
        events.emit("memory.position.saved", win, "zone", window_state.zone_id)

        return true
    else
        -- Window is not in a zone, remember its current frame
        local frame = win:frame()

        logger.debug("Memory", "Remembering frame position for %s", app_name)

        state.saveWindowMemory(app_name, screen:id(), {
            frame = {
                x = frame.x,
                y = frame.y,
                w = frame.w,
                h = frame.h
            },
            timestamp = os.time()
        })

        -- Emit event
        events.emit("memory.position.saved", win, "frame", frame)

        return true
    end
end

--- Apply remembered position to a window
-- @param win hs.window The window to position
-- @param options table Optional settings
-- @return boolean True if position was applied
function memory.applyPosition(win)
    if not win or not win:isStandard() then
        return false
    end

    local win_id = win:id()
    local app = win:application()
    if not app then
        return false
    end

    local app_name = app:name()
    local screen = win:screen()

    -- Skip if app is in exclusion list
    if memory._isExcludedApp(app_name) then
        logger.debug("Memory", "Skipping excluded app: %s", app_name)
        return false
    end

    logger.debug("Memory", "Applying position for app: %s", app_name)

    -- Get initial window position for debugging
    local initial_frame = win:frame()
    logger.debug("Memory", "Initial position: x=%d, y=%d, w=%d, h=%d", initial_frame.x, initial_frame.y,
        initial_frame.w, initial_frame.h)

    -- Try to find remembered position for this app on this screen
    local position_data = state.getWindowMemory(app_name, screen:id())

    if position_data then
        logger.debug("Memory", "Found remembered position for %s", app_name)

        -- Wait for the window to fully initialize
        local init_delay = 0.3

        -- Apply position after delay
        hs.timer.doAfter(init_delay, function()
            -- Window might no longer be valid
            if not win:isValid() then
                logger.debug("Memory", "Window is no longer valid")
                return
            end

            if position_data.zone_id then
                -- Try to apply zone position
                local applied = memory._applyZonePosition(win, position_data)

                if not applied and memory.config.auto_tile_fallback then
                    -- Fall back to default zone if configured
                    memory._applyFallbackPosition(win)
                end
            elseif position_data.frame then
                -- Apply remembered frame position
                memory._applyFramePosition(win, position_data.frame)
            end
        end)

        return true
    else
        logger.debug("Memory", "No remembered position found for %s", app_name)

        -- Try fallback positioning if enabled
        if memory.config.auto_tile_fallback then
            memory._applyFallbackPosition(win)
            return true
        end
    end

    return false
end

--- Apply a zone-based position to a window
-- @param win hs.window The window to position
-- @param position_data table The position data
-- @return boolean True if position was applied
function memory._applyZonePosition(win, position_data)
    if not win or not position_data or not position_data.zone_id then
        return false
    end

    local win_id = win:id()
    local screen = win:screen()

    -- Find matching zone on current screen
    local target_zone = nil

    -- Use event system to find the zone
    events.emit("memory.zone.lookup", position_data.zone_id, win)

    -- Wait for response - would be better with promises!
    hs.timer.usleep(10000) -- 10ms

    -- Get zone that was found by event
    target_zone = state.get("_temp", "found_zone")
    state.remove("_temp", "found_zone")

    if not target_zone then
        logger.debug("Memory", "Could not find zone %s on screen %s", position_data.zone_id, screen:name())
        return false
    end

    logger.debug("Memory", "Adding window to zone %s with tile %d", target_zone.id, position_data.tile_idx or 1)

    -- Add window to zone at remembered position
    events.emit("memory.window.add_to_zone", target_zone.id, win_id, {
        tile_idx = position_data.tile_idx or 1
    })

    -- Resize window according to zone
    events.emit("memory.window.resize_in_zone", target_zone.id, win_id)

    return true
end

--- Apply a frame position to a window
-- @param win hs.window The window to position
-- @param frame table The frame data
-- @return boolean True if position was applied
function memory._applyFramePosition(win, frame)
    if not win or not frame then
        return false
    end

    logger.debug("Memory", "Applying frame position: x=%d, y=%d, w=%d, h=%d", frame.x, frame.y, frame.w, frame.h)

    -- Create frame object
    local frame_obj = {
        x = frame.x,
        y = frame.y,
        w = frame.w,
        h = frame.h
    }

    -- Apply with retry for problem apps
    events.emit("memory.window.set_frame", win, frame_obj)

    return true
end

--- Apply fallback positioning to a window
-- @param win hs.window The window to position
-- @return boolean True if position was applied
function memory._applyFallbackPosition(win)
    if not win or not win:isStandard() then
        return false
    end

    local win_id = win:id()
    local app = win:application()
    if not app then
        return false
    end

    local app_name = app:name()

    logger.debug("Memory", "Using fallback positioning for %s", app_name)

    -- Find default zone for this app
    local default_zone = memory.config.default_zone

    -- Check for app-specific default zone
    if memory.config.app_zones and memory.config.app_zones[app_name] then
        default_zone = memory.config.app_zones[app_name]
        logger.debug("Memory", "Using app-specific default zone: %s", default_zone)
    end

    -- Emit event to find a zone
    events.emit("memory.zone.find", default_zone, win)

    -- Wait for response - would be better with promises!
    hs.timer.usleep(10000) -- 10ms

    -- Get zone that was found by event
    local target_zone = state.get("_temp", "found_zone")
    state.remove("_temp", "found_zone")

    if not target_zone then
        logger.debug("Memory", "Could not find default zone: %s", default_zone)
        return false
    end

    logger.debug("Memory", "Adding window to default zone: %s", target_zone.id)

    -- Add window to default zone
    events.emit("memory.window.add_to_zone", target_zone.id, win_id)

    -- Resize window according to zone
    events.emit("memory.window.resize_in_zone", target_zone.id, win_id)

    -- Remember this position for future
    memory.rememberPosition(win)

    return true
end

--- Capture positions of all windows
-- @return number Number of windows captured
function memory.captureAllPositions()
    logger.info("Memory", "Capturing positions for all windows")

    local count = 0

    -- Get all visible windows
    local windows = hs.window.allWindows()
    for _, win in ipairs(windows) do
        if win:isStandard() and not win:isMinimized() then
            if memory.rememberPosition(win) then
                count = count + 1
            end
        end
    end

    logger.info("Memory", "Captured positions for %d windows", count)
    return count
end

--- Apply positions to all windows
-- @return number Number of windows positioned
function memory.applyAllPositions()
    logger.info("Memory", "Applying positions to all windows")

    local count = 0

    -- Get all visible windows
    local windows = hs.window.allWindows()
    for _, win in ipairs(windows) do
        if win:isStandard() and not win:isMinimized() then
            if memory.applyPosition(win) then
                count = count + 1
            end
        end
    end

    logger.info("Memory", "Applied positions to %d windows", count)
    return count
end

return memory
