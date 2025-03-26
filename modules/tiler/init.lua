--[[
  tiler/init.lua - Main module for window management

  This module ties together all the tiler components and provides
  a centralized API for the window management system.

  Usage:
    local tiler = require("modules.tiler")

    -- Initialize the tiler
    tiler.init(config)

    -- Position a window in a zone
    tiler.moveToZone("bottom_right")

    -- Apply a layout
    tiler.applyLayout("coding")

    -- Create a custom zone
    tiler.defineZone("custom", {
      screen = hs.screen.primaryScreen(),
      hotkey = "c",
      tiles = {"a1:b2", "a1", "b2"}
    })
]] local logger = require("core.logger")
local utils = require("core.utils")
local state = require("core.state")
local events = require("core.events")

-- Import module components
local grid = require("modules.tiler.grid")
local Tile = require("modules.tiler.tile")
local Zone = require("modules.tiler.zone")
local Layout = require("modules.tiler.layout")

-- Define tiler namespace
local tiler = {
    -- Version information
    _version = "2.0.0",

    -- Public references to sub-modules
    grid = grid,
    Tile = Tile,
    Zone = Zone,
    Layout = Layout,

    -- Module state
    _initialized = false,
    _window_watcher = nil,
    _screen_watcher = nil,
    config = {}
}

--- Initialize tiler with configuration
-- @param config table Configuration options
-- @return tiler module for chaining
function tiler.init(config)
    if tiler._initialized then
        logger.warn("Tiler", "Already initialized, use tiler.refresh() to reload")
        return tiler
    end

    logger.info("Tiler", "Initializing tiler v%s", tiler._version)

    -- Setup core logger
    if config and config.debug then
        logger.enable(true)
        logger.setLevel(logger.levels.DEBUG)
    end

    -- Store configuration
    tiler.config = config or {}

    -- Store config in state for other modules to access
    state.set("_config", "tiler", tiler.config)

    -- Initialize grid for all screens
    local grids = grid.initForAllScreens(config)

    -- Initialize zones for all screens
    local zones = Zone.initForAllScreens(config)

    -- Initialize layout system
    Layout.init(config)

    -- Setup screen watchers
    tiler._initScreenWatchers()

    -- Initialize window memory if configured
    if config and config.window_memory and config.window_memory.enabled ~= false then
        tiler._initWindowMemory()
    end

    -- Register hotkeys
    tiler._registerHotkeys()

    -- Set initialization flag
    tiler._initialized = true

    -- Map existing windows to zones (with slight delay to ensure layouts are fully initialized)
    hs.timer.doAfter(0.5, function()
        Zone.mapExistingWindows()
    end)

    -- Initialize event watchers last to ensure all extensions are loaded
    tiler._initEventWatchers()

    logger.info("Tiler", "Initialization complete")

    return tiler
end

--- Window watcher for handling window events
function tiler._initEventWatchers()
    logger.debug("Tiler", "Initializing event watchers")

    -- Window event filter
    tiler._window_watcher = hs.window.filter.new()
    tiler._window_watcher:setDefaultFilter({})
    tiler._window_watcher:setSortOrder(hs.window.filter.sortByFocusedLast)

    -- Subscribe to window events using a map (recommended approach)
    tiler._window_watcher:subscribe({
        windowDestroyed = function(win)
            tiler._handleWindowDestroyed(win)
        end,
        windowCreated = function(win)
            tiler._handleWindowCreated(win)
        end,
        windowMoved = function(win)
            tiler._handleWindowMoved(win)
        end,
        windowResized = function(win)
            tiler._handleWindowResized(win)
        end
    })

    -- Set up memory-related event handlers
    events.on("memory.zone.lookup", function(zone_id, win)
        local zone = Zone.getById(zone_id)
        if zone then
            state.set("_temp", "found_zone", zone)
        end
    end)

    events.on("memory.window.add_to_zone", function(zone_id, win_id, options)
        local zone = Zone.getById(zone_id)
        if zone then
            zone:addWindow(win_id, options)
        end
    end)

    events.on("memory.window.resize_in_zone", function(zone_id, win_id)
        local zone = Zone.getById(zone_id)
        if zone then
            zone:resizeWindow(win_id, {
                problem_apps = tiler.config.problem_apps
            })
        end
    end)

    events.on("memory.window.set_frame", function(win, frame)
        if win and frame then
            utils.applyFrameWithRetry(win, frame, {
                max_attempts = 3,
                is_problem_app = tiler._isProblemApp(win:application() and win:application():name())
            })
        end
    end)

    events.on("memory.zone.find", function(zone_id, win)
        if not win or not zone_id then
            return
        end

        local screen = win:screen()
        if not screen then
            return
        end

        -- Find matching zone on this screen
        local zones = state.get("zones") or {}
        local screen_id = tostring(screen:id())

        for id, zone_data in pairs(zones) do
            if zone_data.screen_id == screen_id and (id == zone_id or id:match("^" .. zone_id .. "_")) then
                local zone = Zone.getById(id)
                if zone then
                    state.set("_temp", "found_zone", zone)
                    break
                end
            end
        end
    end)

    logger.debug("Tiler", "Event watchers initialized")
end

--- Handle window destroyed event
function tiler._handleWindowDestroyed(win)
    if not win then
        return
    end

    local win_id = win:id()
    logger.debug("Tiler", "Window destroyed: %s", win_id)

    -- Get window state
    local window_state = state.getWindowState(win_id)

    -- If window was in a zone, remove it
    if window_state and window_state.zone_id then
        local zone = Zone.getById(window_state.zone_id)
        if zone then
            zone:removeWindow(win_id)
        end
    end

    -- Clean up state
    state.remove("windows", tostring(win_id))

    -- Clean up focus tracking
    local focus_indices = state.get("focus_indices") or {}
    for key, _ in pairs(focus_indices) do
        if key:find(tostring(win_id)) then
            focus_indices[key] = nil
        end
    end
    state.set("focus_indices", focus_indices)
end

--- Handle window created event
function tiler._handleWindowCreated(win)
    if not win or not win:isStandard() then
        return
    end

    local win_id = win:id()
    local app = win:application()
    if not app then
        return
    end

    local app_name = app:name()

    logger.debug("Tiler", "Window created: %s - %s", win_id, app_name)

    -- Skip if app is in exclusion list
    if tiler.config.window_memory and tiler.config.window_memory.excluded_apps then
        for _, excluded_app in ipairs(tiler.config.window_memory.excluded_apps) do
            if app_name == excluded_app then
                logger.debug("Tiler", "Skipping excluded app: %s", app_name)
                return
            end
        end
    end

    -- If window memory enabled, handle window positioning
    if tiler.config.window_memory and tiler.config.window_memory.enabled ~= false then
        tiler._applyWindowMemory(win)
    end
end

--- Apply window memory to a window
function tiler._applyWindowMemory(win)
    if not win or not win:isStandard() then
        return
    end

    local win_id = win:id()
    local app = win:application()
    if not app then
        return
    end

    local app_name = app:name()
    local screen = win:screen()

    -- Log initial window position
    local initial_frame = win:frame()
    logger.debug("Tiler", "Initial window position: %s at x=%d, y=%d, w=%d, h=%d", app_name, initial_frame.x,
        initial_frame.y, initial_frame.w, initial_frame.h)

    -- Longer delay for all apps to ensure they're fully initialized
    local init_delay = 0.3

    -- Even longer delay for known problem apps
    if tiler._isProblemApp(app_name) then
        init_delay = 0.5
        logger.debug("Tiler", "Using longer delay for problem app: %s", app_name)
    end

    -- Store window reference locally to prevent it from being collected
    local window_ref = win
    hs.timer.doAfter(init_delay, function()
        -- Add nil check before calling isValid()
        if not window_ref or not window_ref:isValid() then
            logger.debug("Tiler", "Window is no longer valid")
            return
        end

        -- Try to find remembered position for this app on this screen
        local position_data = state.getWindowMemory(app_name, screen:id())

        if position_data then
            logger.debug("Tiler", "Found remembered position for %s", app_name)

            -- Apply position based on type (zone or frame)
            if position_data.zone_id then
                -- Try to find the zone
                local target_zone = nil

                -- Find zones on current screen
                local zones = state.get("zones") or {}
                for zone_id, zone_data in pairs(zones) do
                    if zone_data.screen_id == tostring(screen:id()) and
                        (zone_id == position_data.zone_id or zone_id:match("^" .. position_data.zone_id .. "_")) then
                        target_zone = Zone.getById(zone_id)
                        break
                    end
                end

                if target_zone then
                    logger.debug("Tiler", "Adding window to remembered zone: %s, tile: %d", target_zone.id,
                        position_data.tile_idx or 1)

                    target_zone:addWindow(win_id, {
                        tile_idx = position_data.tile_idx or 1
                    })

                    target_zone:resizeWindow(win_id, {
                        problem_apps = tiler.config.problem_apps
                    })
                else
                    logger.debug("Tiler", "Could not find remembered zone: %s", position_data.zone_id)
                end
            elseif position_data.frame then
                -- Apply exact frame
                logger.debug("Tiler", "Applying remembered frame position")

                local frame = {
                    x = position_data.frame.x,
                    y = position_data.frame.y,
                    w = position_data.frame.w,
                    h = position_data.frame.h
                }

                -- Apply with retry for problem apps
                utils.applyFrameWithRetry(window_ref, frame, {
                    max_attempts = 3,
                    is_problem_app = tiler._isProblemApp(app_name)
                })
            end
        else
            logger.debug("Tiler", "No remembered position found for %s", app_name)

            -- Use fallback auto-tiling if configured
            if tiler.config.window_memory and tiler.config.window_memory.auto_tile_fallback then
                tiler._applyFallbackPosition(window_ref)
            else
                -- Try to match to an appropriate zone
                local match = Zone.findBestZoneForWindow(window_ref)

                if match and match.zone then
                    logger.debug("Tiler", "Auto-matching window to zone: %s", match.zone.id)

                    match.zone:addWindow(win_id, {
                        tile_idx = match.tile_idx
                    })

                    match.zone:resizeWindow(win_id, {
                        problem_apps = tiler.config.problem_apps
                    })

                    -- Remember this position for future windows of this app
                    tiler._rememberWindowPosition(window_ref)
                end
            end
        end
    end)
end

--- Apply fallback positioning for a window
function tiler._applyFallbackPosition(win)
    if not win or not win:isStandard() then
        return
    end

    local win_id = win:id()
    local app = win:application()
    if not app then
        return
    end

    local app_name = app:name()
    local screen = win:screen()

    logger.debug("Tiler", "Using fallback auto-tiling for: %s", app_name)

    -- Find default zone for this app
    local default_zone = "center"

    if tiler.config.window_memory and tiler.config.window_memory.default_zone then
        default_zone = tiler.config.window_memory.default_zone
    end

    -- Check for app-specific default zone
    if tiler.config.window_memory and tiler.config.window_memory.app_zones and
        tiler.config.window_memory.app_zones[app_name] then
        default_zone = tiler.config.window_memory.app_zones[app_name]
        logger.debug("Tiler", "Using app-specific default zone: %s", default_zone)
    end

    -- Try to find a matching zone on this screen
    local target_zone = nil
    local zones = state.get("zones") or {}

    for zone_id, zone_data in pairs(zones) do
        if zone_data.screen_id == tostring(screen:id()) and
            (zone_id == default_zone or zone_id:match("^" .. default_zone .. "_")) then
            target_zone = Zone.getById(zone_id)
            break
        end
    end

    if target_zone then
        -- Add the window to the zone
        logger.debug("Tiler", "Adding window to default zone: %s", target_zone.id)

        target_zone:addWindow(win_id)
        target_zone:resizeWindow(win_id, {
            problem_apps = tiler.config.problem_apps
        })

        -- Remember this position for future windows of this app
        tiler._rememberWindowPosition(win)
    else
        logger.debug("Tiler", "Could not find default zone: %s", default_zone)
    end
end

--- Store current window position in memory
function tiler._rememberWindowPosition(win)
    if not win or not win:isStandard() then
        return
    end

    local win_id = win:id()
    local app = win:application()
    if not app then
        return
    end

    local app_name = app:name()
    local screen = win:screen()

    -- Skip if app is in exclusion list
    if tiler.config.window_memory and tiler.config.window_memory.excluded_apps then
        for _, excluded_app in ipairs(tiler.config.window_memory.excluded_apps) do
            if app_name == excluded_app then
                logger.debug("Tiler", "Skipping position memory for excluded app: %s", app_name)
                return
            end
        end
    end

    -- Get window state
    local window_state = state.getWindowState(win_id)

    if window_state and window_state.zone_id then
        -- Window is in a zone, remember the zone and tile index
        logger.debug("Tiler", "Remembering zone position for %s: %s, tile: %d", app_name, window_state.zone_id,
            window_state.tile_idx or 1)

        state.saveWindowMemory(app_name, screen:id(), {
            zone_id = window_state.zone_id,
            tile_idx = window_state.tile_idx or 1,
            timestamp = os.time()
        })
    else
        -- Window is not in a zone, remember its current frame
        local frame = win:frame()

        logger.debug("Tiler", "Remembering frame position for %s", app_name)

        state.saveWindowMemory(app_name, screen:id(), {
            frame = {
                x = frame.x,
                y = frame.y,
                w = frame.w,
                h = frame.h
            },
            timestamp = os.time()
        })
    end
end

--- Handle window moved event
function tiler._handleWindowMoved(win)
    if not win or not win:isStandard() then
        return
    end

    local win_id = win:id()

    -- Check if this is a window we're tracking
    local window_state = state.getWindowState(win_id)

    -- Skip tracking moves for windows that are being positioned by us
    if window_state and window_state.positioning_timer then
        local time_diff = os.time() - window_state.positioning_timer
        if time_diff < 1 then
            return
        end
    end

    -- Debounce window move events
    tiler._debounceWindowEvent(win, "move", function(w)
        -- Remember window position after user move
        tiler._rememberWindowPosition(w)
    end)
end

--- Handle window resized event
function tiler._handleWindowResized(win)
    if not win or not win:isStandard() then
        return
    end

    -- Skip tracking resizes for windows that are being positioned by us
    local win_id = win:id()
    local window_state = state.getWindowState(win_id)

    if window_state and window_state.positioning_timer then
        local time_diff = os.time() - window_state.positioning_timer
        if time_diff < 1 then
            return
        end
    end

    -- Debounce window resize events
    tiler._debounceWindowEvent(win, "resize", function(w)
        -- Remember window position after user resize
        tiler._rememberWindowPosition(w)
    end)
end

-- Window event debouncing
tiler._event_timers = {}

--- Debounce window events
function tiler._debounceWindowEvent(win, event_type, callback)
    if not win or not win:isStandard() then
        return
    end

    local win_id = win:id()
    local timer_key = tostring(win_id) .. "_" .. event_type

    -- Cancel existing timer if any
    if tiler._event_timers[timer_key] then
        tiler._event_timers[timer_key]:stop()
    end

    -- Create a new timer with delay
    tiler._event_timers[timer_key] = hs.timer.doAfter(0.5, function()
        if win and win:isValid() then
            callback(win)
        end
        tiler._event_timers[timer_key] = nil
    end)
end

--- Screen watcher for handling display changes
function tiler._initScreenWatchers()
    logger.debug("Tiler", "Initializing screen watchers")

    -- Enhanced screen change watcher
    if tiler._screen_watcher then
        tiler._screen_watcher:stop()
    end

    tiler._screen_watcher = hs.screen.watcher.new(function()
        tiler._handleDisplayChange()
    end)

    tiler._screen_watcher:start()
    logger.debug("Tiler", "Screen watcher initialized and started")
end

--- Handle screen configuration changes
function tiler._handleDisplayChange()
    logger.info("Tiler", "Screen configuration change detected")

    -- Add a delay to allow the OS to fully register screens
    hs.timer.doAfter(0.5, function()
        -- Log screens for debugging
        local screens = hs.screen.allScreens()
        local screen_info = ""
        for i, screen in ipairs(screens) do
            screen_info = screen_info .. i .. ": " .. screen:name() .. " (" .. screen:id() .. ")\n"
        end
        logger.debug("Tiler", "Current screens:\n%s", screen_info)

        -- Re-initialize grid for all screens
        grid.initForAllScreens(tiler.config)

        -- Re-initialize zones for all screens
        Zone.initForAllScreens(tiler.config)

        -- Add a small delay to map windows to new zones first
        hs.timer.doAfter(0.3, function()
            logger.debug("Tiler", "Mapping windows to new screen configuration")
            Zone.mapExistingWindows()
        end)

        -- Then resize windows with another delay
        hs.timer.doAfter(0.5, function()
            logger.debug("Tiler", "Resizing windows after screen change")
            local windows = state.get("windows") or {}

            for win_id, win_state in pairs(windows) do
                -- Skip if no zone assigned
                if not win_state.zone_id then
                    goto continue
                end

                -- Get the zone
                local zone = Zone.getById(win_state.zone_id)
                if zone then
                    logger.debug("Tiler", "Resizing window %s in zone %s", win_id, zone.id)
                    zone:resizeWindow(win_id, {
                        problem_apps = tiler.config.problem_apps
                    })
                end

                ::continue::
            end
        end)
    end)
end

--- Initialize window memory system
function tiler._initWindowMemory()
    logger.debug("Tiler", "Initializing window memory system")

    -- Setup hotkeys if configured
    if tiler.config.window_memory and tiler.config.window_memory.hotkeys then
        -- Hotkey for capturing positions
        if tiler.config.window_memory.hotkeys.capture then
            -- Debug the values
            logger.debug("Tiler", "Capture hotkey: mods=%s, key=%s",
                hs.inspect(tiler.config.window_memory.hotkeys.capture[1]),
                hs.inspect(tiler.config.window_memory.hotkeys.capture[2]))

            -- Check the types
            local mods = tiler.config.window_memory.hotkeys.capture[1]
            local key = tiler.config.window_memory.hotkeys.capture[2]

            -- Make sure key is a string
            if key and type(key) ~= "string" and type(key) ~= "number" then
                logger.error("Tiler", "Invalid key type for capture hotkey: %s", type(key))
                return
            end

            if mods and type(mods) == "table" then
                hs.hotkey.bind(mods, key, function()
                    tiler.captureWindowPositions()
                end)

                logger.debug("Tiler", "Set up capture positions hotkey: %s+%s", table.concat(mods, "+"), key)
            end
        end

        -- Same checks for apply hotkey
        if tiler.config.window_memory.hotkeys.apply then
            local mods = tiler.config.window_memory.hotkeys.apply[1]
            local key = tiler.config.window_memory.hotkeys.apply[2]

            -- Make sure key is a string
            if key and type(key) ~= "string" and type(key) ~= "number" then
                logger.error("Tiler", "Invalid key type for apply hotkey: %s", type(key))
                return
            end

            if mods and type(mods) == "table" then
                hs.hotkey.bind(mods, key, function()
                    tiler.applyWindowPositions()
                end)

                logger.debug("Tiler", "Set up apply positions hotkey: %s+%s", table.concat(mods, "+"), key)
            end
        end
    end
end

--- Check if an app is a problem app
function tiler._isProblemApp(app_name)
    if not tiler.config.problem_apps or not app_name then
        return false
    end

    for _, name in ipairs(tiler.config.problem_apps) do
        if name:lower() == app_name:lower() then
            return true
        end
    end

    return false
end

--- Register hotkeys for screen movement and focus
function tiler._registerHotkeys()
    logger.debug("Tiler", "Registering hotkeys")

    -- Screen movement hotkeys
    if tiler.config.modifier then
        hs.hotkey.bind(tiler.config.modifier, "p", function()
            tiler.moveToNextScreen()
        end)

        hs.hotkey.bind(tiler.config.modifier, ";", function()
            tiler.moveToPreviousScreen()
        end)

        logger.debug("Tiler", "Screen movement keys set up")
    end

    -- Screen focus hotkeys
    if tiler.config.focus_modifier then
        hs.hotkey.bind(tiler.config.focus_modifier, "p", function()
            tiler.focusNextScreen()
        end)

        hs.hotkey.bind(tiler.config.focus_modifier, ";", function()
            tiler.focusPreviousScreen()
        end)

        logger.debug("Tiler", "Screen focus keys set up")
    end

    -- Layout hotkeys
    if tiler.config.layouts and tiler.config.layouts.hotkeys then
        Layout.setupHotkeys(tiler.config)
    end

    -- Add keyboard shortcut to toggle debug mode
    hs.hotkey.bind({"ctrl", "cmd", "shift"}, "D", function()
        local debug_mode = not logger.isEnabled() or (logger.getLevel() ~= logger.levels.DEBUG)

        logger.enable(true)
        if debug_mode then
            logger.setLevel(logger.levels.DEBUG)
            hs.alert.show("Tiler Debug: ON")
        else
            logger.setLevel(logger.levels.INFO)
            hs.alert.show("Tiler Debug: OFF")
        end

        logger.info("Tiler", "Debug mode: %s", debug_mode and "enabled" or "disabled")
    end)
end

-- ===== PUBLIC API =====

--- Force refresh the tiler (for config changes)
-- @return tiler module for chaining
function tiler.refresh()
    logger.info("Tiler", "Refreshing tiler configuration")

    -- Re-initialize screen grid
    grid.initForAllScreens(tiler.config)

    -- Re-initialize zones for all screens
    Zone.initForAllScreens(tiler.config)

    -- Map existing windows to zones
    Zone.mapExistingWindows()

    return tiler
end

--- Move the focused window to a specific zone
-- @param zone_id string The zone ID to move to
-- @return boolean True if successful
function tiler.moveToZone(zone_id)
    logger.debug("Tiler", "Moving to zone: %s", zone_id)

    -- Get focused window
    local win = hs.window.focusedWindow()
    if not win then
        logger.debug("Tiler", "No focused window")
        return false
    end

    local win_id = win:id()
    local current_screen = win:screen()
    local current_screen_id = current_screen:id()

    -- Find matching zone for this screen
    local target_zone = nil

    -- Try screen-specific ID first
    local screen_specific_id = zone_id .. "_" .. current_screen_id
    local zones = state.get("zones") or {}

    if zones[screen_specific_id] then
        target_zone = Zone.getById(screen_specific_id)
        logger.debug("Tiler", "Found exact screen-specific zone: %s", screen_specific_id)
    else
        -- Look for any zone with this ID on current screen
        for id, zone_data in pairs(zones) do
            if zone_data.screen_id == tostring(current_screen_id) and (id == zone_id or id:match("^" .. zone_id .. "_")) then
                target_zone = Zone.getById(id)
                logger.debug("Tiler", "Found matching zone on current screen: %s", id)
                break
            end
        end
    end

    -- If no zones found on current screen, give up
    if not target_zone then
        logger.debug("Tiler", "No matching zones found on current screen")
        return false
    end

    -- Get current window state
    local window_state = state.getWindowState(win_id)
    local current_zone_id = window_state and window_state.zone_id

    -- Check if window is already in this zone
    local is_in_zone = target_zone:hasWindow(win_id)

    if is_in_zone then
        -- Cycle through tiles if already in zone
        logger.debug("Tiler", "Cycling window in zone: %s", target_zone.id)
        target_zone:cycleWindow(win_id)
    else
        -- Otherwise add to zone
        logger.debug("Tiler", "Adding window to zone: %s", target_zone.id)
        target_zone:addWindow(win_id)
    end

    -- Apply the tile dimensions
    target_zone:resizeWindow(win_id, {
        problem_apps = tiler.config.problem_apps
    })

    return true
end

--- Move the focused window to the next screen
-- @return boolean True if successful
function tiler.moveToNextScreen()
    logger.debug("Tiler", "Moving window to next screen")

    local win = hs.window.focusedWindow()
    if not win then
        logger.debug("Tiler", "No focused window")
        return false
    end

    -- Get all screens
    local screens = hs.screen.allScreens()
    if #screens < 2 then
        logger.debug("Tiler", "Only one screen available")
        return false
    end

    -- Find current screen
    local current_screen = win:screen()
    local current_screen_id = current_screen:id()

    -- Find next screen
    local next_screen = nil
    for i, screen in ipairs(screens) do
        if screen:id() == current_screen_id then
            next_screen = screens[(i % #screens) + 1]
            break
        end
    end

    if not next_screen then
        logger.error("Tiler", "Could not determine next screen")
        return false
    end

    logger.debug("Tiler", "Moving window to screen: %s", next_screen:name())

    -- Move window to the target screen
    win:moveToScreen(next_screen, false, false, 0)

    -- Check if we have remembered position for this app on the target screen
    local app = win:application()
    if app then
        local app_name = app:name()
        local position_data = state.getWindowMemory(app_name, next_screen:id())

        if position_data then
            logger.debug("Tiler", "Found remembered position on target screen")

            -- Add slight delay to ensure screen move completes
            hs.timer.doAfter(0.1, function()
                if not win:isValid() then
                    return
                end

                if position_data.zone_id then
                    -- Find matching zone on target screen
                    local zones = state.get("zones") or {}
                    for zone_id, zone_data in pairs(zones) do
                        if zone_data.screen_id == tostring(next_screen:id()) and
                            (zone_id == position_data.zone_id or zone_id:match("^" .. position_data.zone_id .. "_")) then

                            local zone = Zone.getById(zone_id)
                            if zone then
                                zone:addWindow(win:id(), {
                                    tile_idx = position_data.tile_idx or 1
                                })

                                zone:resizeWindow(win:id(), {
                                    problem_apps = tiler.config.problem_apps
                                })

                                break
                            end
                        end
                    end
                elseif position_data.frame then
                    -- Apply remembered frame with adjustment for new screen
                    local current_screen_frame = current_screen:frame()
                    local next_screen_frame = next_screen:frame()

                    -- Calculate position deltas between screens
                    local delta_x = next_screen_frame.x - current_screen_frame.x
                    local delta_y = next_screen_frame.y - current_screen_frame.y

                    -- Adjust frame to new screen
                    local frame = {
                        x = position_data.frame.x + delta_x,
                        y = position_data.frame.y + delta_y,
                        w = position_data.frame.w,
                        h = position_data.frame.h
                    }

                    -- Apply with retry for problem apps
                    utils.applyFrameWithRetry(win, frame, {
                        max_attempts = 3,
                        is_problem_app = tiler._isProblemApp(app_name)
                    })
                end
            end)
        else
            logger.debug("Tiler", "No remembered position on target screen")
        end
    end

    return true
end

--- Move the focused window to the previous screen
-- @return boolean True if successful
function tiler.moveToPreviousScreen()
    logger.debug("Tiler", "Moving window to previous screen")

    local win = hs.window.focusedWindow()
    if not win then
        logger.debug("Tiler", "No focused window")
        return false
    end

    -- Get all screens
    local screens = hs.screen.allScreens()
    if #screens < 2 then
        logger.debug("Tiler", "Only one screen available")
        return false
    end

    -- Find current screen
    local current_screen = win:screen()
    local current_screen_id = current_screen:id()

    -- Find previous screen
    local prev_screen = nil
    for i, screen in ipairs(screens) do
        if screen:id() == current_screen_id then
            prev_screen = screens[((i - 2) % #screens) + 1]
            break
        end
    end

    if not prev_screen then
        logger.error("Tiler", "Could not determine previous screen")
        return false
    end

    logger.debug("Tiler", "Moving window to screen: %s", prev_screen:name())

    -- Similar logic as moveToNextScreen but with the previous screen
    win:moveToScreen(prev_screen, false, false, 0)

    -- Check if we have remembered position for this app on the target screen
    local app = win:application()
    if app then
        local app_name = app:name()
        local position_data = state.getWindowMemory(app_name, prev_screen:id())

        if position_data then
            logger.debug("Tiler", "Found remembered position on target screen")

            -- Add slight delay to ensure screen move completes
            hs.timer.doAfter(0.1, function()
                if not win:isValid() then
                    return
                end

                if position_data.zone_id then
                    -- Find matching zone on target screen
                    local zones = state.get("zones") or {}
                    for zone_id, zone_data in pairs(zones) do
                        if zone_data.screen_id == tostring(prev_screen:id()) and
                            (zone_id == position_data.zone_id or zone_id:match("^" .. position_data.zone_id .. "_")) then

                            local zone = Zone.getById(zone_id)
                            if zone then
                                zone:addWindow(win:id(), {
                                    tile_idx = position_data.tile_idx or 1
                                })

                                zone:resizeWindow(win:id(), {
                                    problem_apps = tiler.config.problem_apps
                                })

                                break
                            end
                        end
                    end
                elseif position_data.frame then
                    -- Apply remembered frame with adjustment for new screen
                    local current_screen_frame = current_screen:frame()
                    local prev_screen_frame = prev_screen:frame()

                    -- Calculate position deltas between screens
                    local delta_x = prev_screen_frame.x - current_screen_frame.x
                    local delta_y = prev_screen_frame.y - current_screen_frame.y

                    -- Adjust frame to new screen
                    local frame = {
                        x = position_data.frame.x + delta_x,
                        y = position_data.frame.y + delta_y,
                        w = position_data.frame.w,
                        h = position_data.frame.h
                    }

                    -- Apply with retry for problem apps
                    utils.applyFrameWithRetry(win, frame, {
                        max_attempts = 3,
                        is_problem_app = tiler._isProblemApp(app_name)
                    })
                end
            end)
        else
            logger.debug("Tiler", "No remembered position on target screen")
        end
    end

    return true
end

--- Focus the next screen
-- @return boolean True if successful
function tiler.focusNextScreen()
    local screens = hs.screen.allScreens()
    if #screens <= 1 then
        return false
    end

    local current_screen = hs.screen.mainScreen()
    local next_screen = nil

    for i, screen in ipairs(screens) do
        if screen:id() == current_screen:id() then
            next_screen = screens[(i % #screens) + 1]
            break
        end
    end

    if next_screen then
        -- Find a window to focus on the next screen
        local windows = hs.window.filter.new(function(w)
            return w:isStandard() and not w:isMinimized() and w:screen():id() == next_screen:id()
        end):getWindows()

        if #windows > 0 then
            windows[1]:focus()
            return true
        end
    end

    return false
end

--- Focus the previous screen
-- @return boolean True if successful
function tiler.focusPreviousScreen()
    local screens = hs.screen.allScreens()
    if #screens <= 1 then
        return false
    end

    local current_screen = hs.screen.mainScreen()
    local prev_screen = nil

    for i, screen in ipairs(screens) do
        if screen:id() == current_screen:id() then
            prev_screen = screens[((i - 2) % #screens) + 1]
            break
        end
    end

    if prev_screen then
        -- Find a window to focus on the previous screen
        local windows = hs.window.filter.new(function(w)
            return w:isStandard() and not w:isMinimized() and w:screen():id() == prev_screen:id()
        end):getWindows()

        if #windows > 0 then
            windows[1]:focus()
            return true
        end
    end

    return false
end

--- Apply a layout to all screens
-- @param layout_name string The name of the layout
-- @return boolean True if successful
function tiler.applyLayout(layout_name)
    return Layout.applyLayout(layout_name)
end

--- Save current window arrangement as a layout
-- @param name string The name to save the layout as
-- @param options table Optional settings
-- @return boolean True if successful
function tiler.saveCurrentLayout(name, options)
    return Layout.saveCurrentLayout(name, options)
end

--- Capture positions of all windows
-- @return number Number of windows captured
function tiler.captureWindowPositions()
    local memory = require("modules.tiler.memory")
    return memory.captureAllPositions()
end

--- Apply positions to all windows
-- @return number Number of windows positioned
function tiler.applyWindowPositions()
    local memory = require("modules.tiler.memory")
    return memory.applyAllPositions()
end

--- Define a new zone
-- @param id string The zone ID
-- @param options table Zone options including screen, hotkey, tiles
-- @return Zone The created zone
function tiler.defineZone(id, options)
    if not id or not options or not options.screen then
        logger.error("Tiler", "Cannot define zone without ID and screen")
        return nil
    end

    local zone = Zone.new(id, options)

    -- Add tiles if specified
    if options.tiles then
        for _, tile_spec in ipairs(options.tiles) do
            local screen_grid = grid.getGridForScreen(options.screen, tiler.config)
            if screen_grid then
                local position = grid.getPositionForRegion(screen_grid, tile_spec)
                if position then
                    zone:addTile(Tile.new(position.x, position.y, position.w, position.h, {
                        description = position.description
                    }))
                end
            end
        end
    end

    -- Register the zone
    zone:register()

    return zone
end

return tiler
