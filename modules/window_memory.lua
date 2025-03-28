-- Window memory utility for the tiler module
local window_memory = {}
local config = require "config"
local json = require "hs.json"

-- Hold a reference to the tiler module (will be set during initialization)
local tiler = nil

-- Debug logging function for window memory
local function debug_log(...)
    if window_memory.debug then
        print("[TilerWindowMemory]", ...)
    end
end

-- Enhanced debugging function with timestamp
local function enhanced_debug_log(...)
    if window_memory.debug then
        local args = {...}
        local message = ""
        for i, v in ipairs(args) do
            message = message .. tostring(v) .. " "
        end

        local timestamp = os.date("%Y-%m-%d %H:%M:%S")
        print(timestamp .. ": [WindowMemory] " .. message)
    end
end

-- Check if an app is in the exclusion list
local function isExcludedApp(app_name)
    if not config.window_memory or not config.window_memory.excluded_apps then
        return false
    end

    for _, excluded_app in ipairs(config.window_memory.excluded_apps) do
        if app_name == excluded_app then
            return true
        end
    end

    return false
end

-- Verify a window's position after placement and force reposition if needed
local function verify_window_position(win, target, screen, initial_frame)
    hs.timer.doAfter(0.2, function()
        -- Early return if window no longer valid
        if not win:isStandard() then
            return
        end

        local current_frame = win:frame()
        enhanced_debug_log("Final window position:", "x=" .. current_frame.x, "y=" .. current_frame.y,
            "w=" .. current_frame.w, "h=" .. current_frame.h)

        -- Create a standard frame object from target (could be a tile or a frame)
        local target_frame = {
            x = target.x,
            y = target.y,
            width = target.width or target.w,
            height = target.height or target.h
        }

        -- Check if window hasn't moved from initial position (if provided)
        if initial_frame and math.abs(current_frame.x - initial_frame.x) < 10 and
            math.abs(current_frame.y - initial_frame.y) < 10 then
            enhanced_debug_log("Window did not move from initial position, forcing resize")
            tiler.window_utils.apply_frame(win, target_frame, screen)
            enhanced_debug_log("Applied forced resize")
            return
        end

        -- Otherwise check if position doesn't match target
        if not tiler.rect.frames_match(current_frame, target_frame) then
            enhanced_debug_log("Window position doesn't match target, forcing resize")
            tiler.window_utils.apply_frame(win, target_frame, screen)
            enhanced_debug_log("Applied forced resize")
        end
    end)
end

-- Sanitize monitor name for filenames
local function sanitize_name(name)
    if not name then
        return "unknown"
    end

    -- Replace problematic characters with underscores
    name = name:gsub("[%s%-%.%:%(%)%[%]%{%}%+%*%?%/%\\]", "_")

    -- Remove any other non-alphanumeric characters
    name = name:gsub("[^%w_]", "")

    return name
end

-- Generate cache filename for a screen
local function get_cache_filename(screen)
    local screen_name = screen:name()
    local sanitized_name = sanitize_name(screen_name)
    return window_memory.cache_dir .. "/window_position_cache_" .. sanitized_name .. ".json"
end

-- Create directory if it doesn't exist
local function ensure_directory_exists(dir)
    local success = os.execute("mkdir -p " .. dir)
    if not success then
        debug_log("Failed to create directory:", dir)
        return false
    end
    return true
end

-- Count items in a table
local function count_table_items(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- Load cache for a specific screen
local function load_screen_cache(screen)
    if not screen then
        return false
    end

    local screen_id = screen:id()
    local screen_name = screen:name()
    local filename = get_cache_filename(screen)

    -- Initialize cache for this screen if not already present
    if not window_memory.cache_data[screen_id] then
        window_memory.cache_data[screen_id] = {
            screen_name = screen_name,
            apps = {}
        }
    end

    -- Try to read existing cache file
    local file = io.open(filename, "r")
    if not file then
        debug_log("No existing cache file for screen:", screen_name)
        return false
    end

    debug_log("Loading window position cache for screen:", screen_name)
    local content = file:read("*all")
    file:close()

    -- Try to parse the JSON content
    local status, data = pcall(function()
        return json.decode(content)
    end)

    if not status or not data or not data.apps then
        debug_log("Failed to parse cache file:", filename)
        return false
    end

    window_memory.cache_data[screen_id].apps = data.apps
    local app_count = count_table_items(data.apps)
    debug_log("Loaded position data for", app_count, "apps")
    return true
end

-- Save cache for a specific screen
local function save_screen_cache(screen)
    if not screen then
        return false
    end

    local screen_id = screen:id()
    local screen_name = screen:name()

    -- Ensure we have data for this screen
    if not window_memory.cache_data[screen_id] then
        debug_log("No cache data for screen:", screen_name)
        return false
    end

    local filename = get_cache_filename(screen)

    -- Ensure the directory exists
    if not ensure_directory_exists(window_memory.cache_dir) then
        return false
    end

    -- Create JSON data to save
    local data = {
        screen_name = screen_name,
        timestamp = os.time(),
        apps = window_memory.cache_data[screen_id].apps
    }

    -- Convert to JSON and save
    local json_str = json.encode(data)
    local file = io.open(filename, "w")
    if not file then
        debug_log("Failed to write cache file:", filename)
        return false
    end

    file:write(json_str)
    file:close()
    debug_log("Saved window position cache for screen:", screen_name)
    return true
end

-- Get window positioning data for an app on a specific screen
function window_memory.get_window_position(app_name, screen)
    if not app_name or not screen then
        return nil
    end

    local screen_id = screen:id()
    if not window_memory.cache_data[screen_id] then
        -- Try to load cache first
        load_screen_cache(screen)
    end

    -- Still no data for this screen
    if not window_memory.cache_data[screen_id] then
        return nil
    end

    -- Look up the app in the cache
    return window_memory.cache_data[screen_id].apps[app_name]
end

-- Store window positioning data for an app on a specific screen
function window_memory.save_window_position(app_name, screen, position_data)
    if not app_name or not screen or not position_data then
        return false
    end

    local screen_id = screen:id()

    -- Initialize screen data if needed
    if not window_memory.cache_data[screen_id] then
        window_memory.cache_data[screen_id] = {
            screen_name = screen:name(),
            apps = {}
        }
    end

    -- Update the data
    window_memory.cache_data[screen_id].apps[app_name] = position_data
    debug_log("Updated position data for app:", app_name, "on screen:", screen:name())

    -- Save to disk
    return save_screen_cache(screen)
end

-- Store current window position in cache
function window_memory.remember_current_window(win)
    -- Validate window using tiler's function
    if not win:isStandard() then
        return false
    end

    local app_name = win:application():name()
    local screen = win:screen()
    local win_id = win:id()

    if isExcludedApp(app_name) then
        debug_log("Skipping excluded app:", app_name)
        return false
    end

    -- Find the zone this window is in (if any)
    local zone, zone_id = tiler.window_state.get_window_zone(win_id)

    -- If window is not in a known zone, use its current frame
    if not zone_id then
        local frame = win:frame()
        local position_data = {
            frame = {
                x = frame.x,
                y = frame.y,
                w = frame.w,
                h = frame.h
            },
            timestamp = os.time()
        }

        -- Save this position
        return window_memory.save_window_position(app_name, screen, position_data)
    else
        -- Window is in a zone, remember the zone and tile index
        local tile_idx = zone.window_to_tile_idx and zone.window_to_tile_idx[win_id] or 0

        local position_data = {
            zone_id = zone_id,
            tile_idx = tile_idx,
            timestamp = os.time()
        }

        -- Save this position
        return window_memory.save_window_position(app_name, screen, position_data)
    end
end

-- Update position cache when a window is moved
local function handle_window_moved(win)
    if not win:isStandard() then
        return
    end

    local win_id = win:id()

    -- Debounce window move events (don't record every single move)
    if window_memory._move_timers[win_id] then
        -- Cancel the existing timer
        window_memory._move_timers[win_id]:stop()
    end

    -- Create a new timer to save the position after a short delay
    window_memory._move_timers[win_id] = hs.timer.doAfter(0.5, function()
        window_memory.remember_current_window(win)
        window_memory._move_timers[win_id] = nil
    end)
end

-- Place window in a zone with verification
local function place_window_in_zone(win, zone, tile_idx, initial_frame)
    if not win:isStandard() or not zone then
        return false
    end

    local win_id = win:id()
    enhanced_debug_log("Auto-snapping window to zone:", zone.id, "tile:", tile_idx)

    -- Use tiler's functions to place the window
    tiler.window_state.associate_window_with_zone(win_id, zone, tile_idx)
    tiler.zone_resize_window(zone, win_id)

    -- Verify position and force resize if needed
    local tile = zone.tiles[tile_idx or 0]
    if tile then
        verify_window_position(win, tile, zone.screen, initial_frame)
    end

    -- Remember this position for future windows of this app
    window_memory.remember_current_window(win)
    return true
end

-- Apply a remembered position to a window
function window_memory.apply_remembered_position(win)
    if not win:isStandard() then
        enhanced_debug_log("Cannot apply position - invalid window")
        return false
    end

    local app_name = win:application():name()
    local screen = win:screen()
    local win_id = win:id()

    enhanced_debug_log("Applying remembered position for app:", app_name, "window:", win_id)

    if isExcludedApp(app_name) then
        enhanced_debug_log("Skipping excluded app:", app_name)
        return false
    end

    -- Get remembered position for this app
    local position_data = window_memory.get_window_position(app_name, screen)
    if not position_data then
        enhanced_debug_log("No remembered position for app:", app_name)
        return false
    end

    enhanced_debug_log("Found remembered position data:", position_data.zone_id or "frame-based",
        position_data.tile_idx or "")

    -- Handle zone-based position
    if position_data.zone_id then
        -- Use tiler's function to find zone
        local target_zone = tiler.zone_finder.find_zone_by_id_on_screen(position_data.zone_id, screen)

        if not target_zone then
            enhanced_debug_log("Could not find remembered zone:", position_data.zone_id)
            return false
        end

        -- Add window to the zone with the remembered tile index
        enhanced_debug_log("Adding window to zone:", target_zone.id)
        local tile_idx = position_data.tile_idx or 0
        tiler.window_state.associate_window_with_zone(win_id, target_zone, tile_idx)

        -- Apply the tile dimensions
        enhanced_debug_log("Applying tile dimensions")
        tiler.zone_resize_window(target_zone, win_id)

        -- Verify position and force resize if needed
        local tile = target_zone.tiles[tile_idx]
        if tile then
            verify_window_position(win, tile, target_zone.screen)
        end

        return true

        -- Handle frame-based position
    elseif position_data.frame then
        enhanced_debug_log("Applying exact frame position")
        local frame = {
            x = position_data.frame.x,
            y = position_data.frame.y,
            width = position_data.frame.w,
            height = position_data.frame.h
        }

        -- Apply frame
        tiler.window_utils.apply_frame(win, frame)

        -- Verify position and force resize if needed
        verify_window_position(win, frame)

        return true
    end

    return false
end

-- Handle window creation for window memory
function window_memory.handle_window_created(win)
    if not win:isStandard() then
        enhanced_debug_log("Ignoring non-standard window")
        return
    end

    local app_name = win:application():name()
    local win_id = win:id()

    enhanced_debug_log("New window created - ID:", win_id, "App:", app_name)

    if isExcludedApp(app_name) then
        enhanced_debug_log("Skipping excluded app:", app_name)
        return
    end

    -- Check if window is already in a zone (for windows restored at startup)
    for zone_id, zone in pairs(tiler._zone_id2zone) do
        if zone.window_to_tile_idx and zone.window_to_tile_idx[win_id] ~= nil then
            enhanced_debug_log("Window", win_id, "already in zone", zone_id, "- skipping auto-tile")
            return
        end
    end

    -- Skip fullscreen windows
    if win:isFullScreen() then
        enhanced_debug_log("Window is fullscreen, skipping auto-tile")
        return
    end

    -- Get current frame before we do anything
    local initial_frame = win:frame()
    enhanced_debug_log("Initial window position:", "x=" .. initial_frame.x, "y=" .. initial_frame.y,
        "w=" .. initial_frame.w, "h=" .. initial_frame.h)

    -- Determine delay based on app
    local init_delay = 0.3
    if tiler.is_problem_app and tiler.is_problem_app(app_name) then
        init_delay = 0.5
        enhanced_debug_log("Using longer delay for problem app:", app_name)
    end

    enhanced_debug_log("Scheduling window positioning with delay:", init_delay, "seconds")

    hs.timer.doAfter(init_delay, function()
        if not win:isStandard() then
            enhanced_debug_log("Window is no longer valid")
            return
        end

        -- Try to apply remembered position first
        enhanced_debug_log("Attempting to apply remembered position for app:", app_name)
        local success = window_memory.apply_remembered_position(win)

        if success then
            enhanced_debug_log("Applied remembered position successfully")
            return
        end

        -- No remembered position, try to match to a zone
        enhanced_debug_log("No remembered position found, attempting zone matching")

        -- Use tiler's function to find best matching zone
        local match = tiler.zone_finder.find_best_zone_for_window(win)

        if match and match.zone then
            place_window_in_zone(win, match.zone, match.tile_idx, initial_frame)
            return
        end

        -- Fall back to default zone if configured
        if not config.window_memory or not config.window_memory.auto_tile_fallback then
            enhanced_debug_log("No matching zone found and no fallback configured")
            return
        end

        enhanced_debug_log("Using fallback auto-tiling for app:", app_name)

        -- Find default zone for this app
        local default_zone_id = config.window_memory.default_zone or "center"
        if config.window_memory.app_zones and config.window_memory.app_zones[app_name] then
            default_zone_id = config.window_memory.app_zones[app_name]
            enhanced_debug_log("Using app-specific default zone:", default_zone_id)
        end

        -- Find the zone on current screen
        local screen = win:screen()
        if not screen then
            enhanced_debug_log("Window has no screen")
            return
        end

        -- Use tiler's function to find zone
        local target_zone = tiler.zone_finder.find_zone_by_id_on_screen(default_zone_id, screen)
        if not target_zone then
            enhanced_debug_log("Could not find default zone:", default_zone_id, "on screen:", screen:name())
            return
        end

        place_window_in_zone(win, target_zone, 0, initial_frame)
    end)
end

-- Save the current window state
function window_memory.save_all_windows_state()
    debug_log("Saving window state for all screens")

    -- Get all visible standard windows
    local windows = hs.window.allWindows()
    local count = 0

    for _, win in ipairs(windows) do
        if win:isStandard() then
            if window_memory.remember_current_window(win) then
                count = count + 1
            end
        end
    end

    -- Save caches for all screens
    for _, screen in pairs(hs.screen.allScreens()) do
        save_screen_cache(screen)
    end

    debug_log("Window state saved for", count, "windows")
    return count
end

-- Command to manually capture positions for all open windows
function window_memory.capture_all_positions()
    debug_log("Capturing positions for all windows")
    local count = window_memory.save_all_windows_state()
    hs.alert.show("Window positions captured for " .. count .. " windows")
end

-- Command to apply remembered positions to all windows
function window_memory.apply_all_positions()
    debug_log("Applying remembered positions to all windows")

    -- Get all visible standard windows
    local windows = hs.window.allWindows()
    local success_count = 0

    for _, win in ipairs(windows) do
        if win:isStandard() then
            local success = window_memory.apply_remembered_position(win)
            if success then
                success_count = success_count + 1
            end
        end
    end

    debug_log("Applied positions to", success_count, "windows")
    hs.alert.show(string.format("Applied positions to %d windows", success_count))
end

-- Setup window watchers
function window_memory.setup_watchers()
    -- Set up window event handlers
    if not window_memory._window_watcher then
        window_memory._window_watcher = hs.window.filter.new()
        window_memory._window_watcher:setDefaultFilter{}

        -- Watch for window movement with the proper event constant
        window_memory._window_watcher:subscribe(hs.window.filter.windowMoved, handle_window_moved)
    end

    -- Screen watcher to handle new or changed screens
    if not window_memory._screen_watcher then
        window_memory._screen_watcher = hs.screen.watcher.new(function()
            hs.timer.doAfter(0.5, function()
                debug_log("Screen configuration changed, updating window memory caches")

                -- Load caches for all current screens
                for _, screen in pairs(hs.screen.allScreens()) do
                    load_screen_cache(screen)
                end
            end)
        end)
        window_memory._screen_watcher:start()
    end

    debug_log("Window memory watchers set up")
end

-- Add hotkeys for manual operations
function window_memory.setup_hotkeys()
    -- Check if hotkeys are configured
    if not config.window_memory or not config.window_memory.hotkeys then
        debug_log("No hotkey configuration found for window memory")
        return
    end

    -- Set up capture hotkey
    if config.window_memory.hotkeys.capture then
        local key = config.window_memory.hotkeys.capture[1]
        local mods = config.window_memory.hotkeys.capture[2]

        if key and mods then
            hs.hotkey.bind(mods, key, function()
                window_memory.capture_all_positions()
            end)
            debug_log("Set up capture hotkey:", key, "with modifiers:", table.concat(mods, "+"))
        end
    end

    -- Set up apply hotkey
    if config.window_memory.hotkeys.apply then
        local key = config.window_memory.hotkeys.apply[1]
        local mods = config.window_memory.hotkeys.apply[2]

        if key and mods then
            hs.hotkey.bind(mods, key, function()
                window_memory.apply_all_positions()
            end)
            debug_log("Set up apply hotkey:", key, "with modifiers:", table.concat(mods, "+"))
        end
    end
end

-- Initialize the window memory system
function window_memory.init(tiler_module)
    -- Store reference to tiler
    tiler = tiler_module

    -- Load configuration
    if config.window_memory then
        window_memory.debug = config.window_memory.debug or false
        window_memory.cache_dir = config.window_memory.cache_dir or os.getenv("HOME") .. "/.config/tiler"
    else
        window_memory.debug = false
        window_memory.cache_dir = os.getenv("HOME") .. "/.config/tiler"
    end

    -- Initialize state
    window_memory.cache_data = {}
    window_memory._move_timers = {}

    debug_log("Initializing window memory system")
    debug_log("Using cache directory:", window_memory.cache_dir)

    -- Ensure cache directory exists
    ensure_directory_exists(window_memory.cache_dir)

    -- Load caches for all current screens
    for _, screen in pairs(hs.screen.allScreens()) do
        load_screen_cache(screen)
    end

    -- Set up watchers
    window_memory.setup_watchers()

    -- Add a shutdown callback to save window positions
    local existing_callback = hs.shutdownCallback
    hs.shutdownCallback = function()
        window_memory.save_all_windows_state()
        if existing_callback then
            existing_callback()
        end
    end

    debug_log("Window memory system initialized")

    return window_memory
end

return window_memory
