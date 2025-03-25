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

-- Load cache for a specific screen
local function load_screen_cache(screen)
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
    if file then
        debug_log("Loading window position cache for screen:", screen_name)
        local content = file:read("*all")
        file:close()

        -- Try to parse the JSON content
        local status, data = pcall(function()
            return json.decode(content)
        end)
        if status and data and data.apps then
            window_memory.cache_data[screen_id].apps = data.apps
            debug_log("Loaded position data for", table.count(data.apps), "apps")
            return true
        else
            debug_log("Failed to parse cache file:", filename)
        end
    else
        debug_log("No existing cache file for screen:", screen_name)
    end

    return false
end

-- Save cache for a specific screen
local function save_screen_cache(screen)
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
    if file then
        file:write(json_str)
        file:close()
        debug_log("Saved window position cache for screen:", screen_name)
        return true
    else
        debug_log("Failed to write cache file:", filename)
        return false
    end
end

-- Get window positioning data for an app on a specific screen
function window_memory.get_window_position(app_name, screen)
    if not screen then
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
    if window_memory.cache_data[screen_id].apps[app_name] then
        return window_memory.cache_data[screen_id].apps[app_name]
    end

    return nil
end

-- Store window positioning data for an app on a specific screen
function window_memory.save_window_position(app_name, screen, position_data)
    if not screen then
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
    if not win or not win:isStandard() then
        return false
    end

    local app_name = win:application():name()
    local screen = win:screen()
    local win_id = win:id()

    -- Skip if app is in exclusion list
    if config.window_memory and config.window_memory.excluded_apps then
        for _, excluded_app in ipairs(config.window_memory.excluded_apps) do
            if app_name == excluded_app then
                debug_log("Skipping excluded app:", app_name)
                return false
            end
        end
    end

    -- Find the zone this window is in (if any)
    local current_zone_id = nil
    local current_tile_idx = nil

    for zone_id, zone in pairs(tiler._zone_id2zone) do
        if zone.window_to_tile_idx and zone.window_to_tile_idx[win_id] ~= nil then
            current_zone_id = zone_id
            current_tile_idx = zone.window_to_tile_idx[win_id]
            break
        end
    end

    -- If window is not in a known zone, use its current frame
    if not current_zone_id then
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
        local position_data = {
            zone_id = current_zone_id,
            tile_idx = current_tile_idx,
            timestamp = os.time()
        }

        -- Save this position
        return window_memory.save_window_position(app_name, screen, position_data)
    end
end

-- Update position cache when a window is moved
local function handle_window_moved(win)
    if not win or not win:isStandard() then
        return
    end

    -- Skip if the window was just created and is being positioned
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

-- Apply a remembered position to a window
function window_memory.apply_remembered_position(win)
    if not win or not win:isStandard() then
        return false
    end

    local app_name = win:application():name()
    local screen = win:screen()
    local win_id = win:id()

    enhanced_debug_log("Applying remembered position for app:", app_name, "window:", win_id)

    -- Skip if app is in exclusion list
    if config.window_memory and config.window_memory.excluded_apps then
        for _, excluded_app in ipairs(config.window_memory.excluded_apps) do
            if app_name == excluded_app then
                enhanced_debug_log("Skipping excluded app:", app_name)
                return false
            end
        end
    end

    -- Get remembered position for this app
    local position_data = window_memory.get_window_position(app_name, screen)
    if not position_data then
        enhanced_debug_log("No remembered position for app:", app_name)
        return false
    end

    enhanced_debug_log("Found remembered position data:", position_data.zone_id or "frame-based",
        position_data.tile_idx or "")

    -- Apply the position based on the data type
    if position_data.zone_id then
        -- Find the zone
        local target_zone = nil

        -- Try to find exact zone match (including screen-specific zones)
        if tiler._zone_id2zone[position_data.zone_id] then
            target_zone = tiler._zone_id2zone[position_data.zone_id]
            enhanced_debug_log("Found exact zone match:", position_data.zone_id)
        else
            -- Look for zone with matching base name on this screen
            local base_id = position_data.zone_id:match("^([^_]+)")
            if base_id then
                local screen_id = screen:id()

                for id, zone in pairs(tiler._zone_id2zone) do
                    if zone.screen and zone.screen:id() == screen_id then
                        if id == base_id or id:match("^" .. base_id .. "_") then
                            target_zone = zone
                            enhanced_debug_log("Found screen-specific zone match:", id)
                            break
                        end
                    end
                end
            end
        end

        if target_zone then
            -- Add window to the zone at the remembered tile index
            enhanced_debug_log("Adding window to zone:", target_zone.id)
            target_zone:add_window(win_id)

            -- Set the specific tile index if provided
            if position_data.tile_idx ~= nil and position_data.tile_idx >= 0 then
                target_zone.window_to_tile_idx[win_id] = position_data.tile_idx

                -- Update global tracking
                if not tiler._window_state[win_id] then
                    tiler._window_state[win_id] = {}
                end
                tiler._window_state[win_id].zone_id = target_zone.id
                tiler._window_state[win_id].tile_idx = position_data.tile_idx

                enhanced_debug_log("Set tile index to:", position_data.tile_idx)
            end

            -- Apply the tile dimensions
            enhanced_debug_log("Applying tile dimensions")
            target_zone:resize_window(win_id)

            -- Check if the window actually moved
            hs.timer.doAfter(0.2, function()
                if win:isValid() then
                    local current_frame = win:frame()
                    enhanced_debug_log("Position after applying remembered zone:", "x=" .. current_frame.x,
                        "y=" .. current_frame.y, "w=" .. current_frame.w, "h=" .. current_frame.h)

                    -- Check if we need to force reposition
                    local tile = target_zone.tiles[position_data.tile_idx or 0]
                    if tile and (math.abs(current_frame.x - tile.x) > 10 or math.abs(current_frame.y - tile.y) > 10 or
                        math.abs(current_frame.w - tile.width) > 10 or math.abs(current_frame.h - tile.height) > 10) then

                        enhanced_debug_log("Window didn't resize correctly, trying more forceful approach")

                        -- More forceful approach for stubborn windows
                        local frame = hs.geometry.rect(tile.x, tile.y, tile.width, tile.height)

                        -- Force move to screen first
                        win:moveToScreen(target_zone.screen, false, true, 0)

                        -- Then set frame with animation disabled
                        local saved_duration = hs.window.animationDuration
                        hs.window.animationDuration = 0
                        win:setFrame(frame)
                        hs.window.animationDuration = saved_duration
                    end
                end
            end)

            return true
        else
            enhanced_debug_log("Could not find remembered zone:", position_data.zone_id)
        end
    elseif position_data.frame then
        -- Apply the exact frame
        enhanced_debug_log("Applying exact frame position")
        local frame = hs.geometry.rect(position_data.frame.x, position_data.frame.y, position_data.frame.w,
            position_data.frame.h)

        -- Save animation duration and disable animations temporarily
        local saved_duration = hs.window.animationDuration
        hs.window.animationDuration = 0

        win:setFrame(frame)

        -- Restore animation duration
        hs.window.animationDuration = saved_duration

        enhanced_debug_log("Applied remembered frame position for app:", app_name)

        -- Check if the window actually moved
        hs.timer.doAfter(0.2, function()
            if win:isValid() then
                local current_frame = win:frame()
                enhanced_debug_log("Position after applying remembered frame:", "x=" .. current_frame.x,
                    "y=" .. current_frame.y, "w=" .. current_frame.w, "h=" .. current_frame.h)

                -- Check if we need to force reposition
                if math.abs(current_frame.x - frame.x) > 10 or math.abs(current_frame.y - frame.y) > 10 or
                    math.abs(current_frame.w - frame.w) > 10 or math.abs(current_frame.h - frame.h) > 10 then

                    enhanced_debug_log("Window didn't move correctly, trying again with more force")

                    -- Try again with more force
                    hs.window.animationDuration = 0
                    win:setFrame(frame)
                    hs.window.animationDuration = saved_duration
                end
            end
        end)

        return true
    end

    return false
end
-- Find the best matching zone for a window
function window_memory.find_best_zone_for_window(win)
    if not win or not win:isStandard() then
        return nil
    end

    local screen = win:screen()
    if not screen then
        return nil
    end

    local screen_id = screen:id()
    local win_frame = win:frame()

    -- Find zones on this specific screen
    local screen_zones = {}
    for id, zone in pairs(tiler._zone_id2zone) do
        if zone.screen and zone.screen:id() == screen_id then
            table.insert(screen_zones, zone)
        end
    end

    if #screen_zones == 0 then
        debug_log("No zones found for screen:", screen:name())
        return nil
    end

    -- Find best matching zone based on window position and size
    local best_zone = nil
    local best_match_score = 0
    local best_tile_idx = 0

    for _, zone in ipairs(screen_zones) do
        -- Skip zones with no tiles
        if zone.tile_count == 0 then
            goto next_zone
        end

        -- Check each tile in the zone
        for i = 0, zone.tile_count - 1 do
            local tile = zone.tiles[i]
            if not tile then
                goto next_tile
            end

            -- Calculate overlap between window and tile
            local tile_frame = {
                x = tile.x,
                y = tile.y,
                w = tile.width,
                h = tile.height
            }

            -- Calculate overlap area
            local x_overlap = math.max(0, math.min(win_frame.x + win_frame.w, tile_frame.x + tile_frame.w) -
                math.max(win_frame.x, tile_frame.x))

            local y_overlap = math.max(0, math.min(win_frame.y + win_frame.h, tile_frame.y + tile_frame.h) -
                math.max(win_frame.y, tile_frame.y))

            local overlap_area = x_overlap * y_overlap

            -- Calculate percentage of window area that overlaps with tile
            local win_area = win_frame.w * win_frame.h
            local overlap_percentage = win_area > 0 and (overlap_area / win_area) or 0

            -- Calculate size similarity (how close the window and tile are in size)
            local width_ratio = math.min(win_frame.w, tile_frame.w) / math.max(win_frame.w, tile_frame.w)
            local height_ratio = math.min(win_frame.h, tile_frame.h) / math.max(win_frame.h, tile_frame.h)
            local size_similarity = (width_ratio + height_ratio) / 2

            -- Calculate center distance
            local win_center_x = win_frame.x + win_frame.w / 2
            local win_center_y = win_frame.y + win_frame.h / 2
            local tile_center_x = tile_frame.x + tile_frame.w / 2
            local tile_center_y = tile_frame.y + tile_frame.h / 2
            local center_distance = math.sqrt((win_center_x - tile_center_x) ^ 2 + (win_center_y - tile_center_y) ^ 2)

            -- Normalize center distance to screen size
            local screen_frame = screen:frame()
            local screen_diagonal = math.sqrt(screen_frame.w ^ 2 + screen_frame.h ^ 2)
            local normalized_distance = 1 - (center_distance / screen_diagonal)

            -- Combined score (50% overlap, 30% size similarity, 20% center proximity)
            local score = (overlap_percentage * 0.5) + (size_similarity * 0.3) + (normalized_distance * 0.2)

            -- Check if this is best match so far
            if score > best_match_score and score > 0.4 then -- Must be at least 40% match
                best_match_score = score
                best_zone = zone
                best_tile_idx = i
            end

            ::next_tile::
        end

        ::next_zone::
    end

    if best_zone and best_match_score > 0 then
        debug_log("Found best matching zone:", best_zone.id, "with score:", best_match_score)
        return {
            zone = best_zone,
            tile_idx = best_tile_idx,
            score = best_match_score
        }
    end

    return nil
end

-- Handle window creation for window memory
function window_memory.handle_window_created(win)
    if not win or not win:isStandard() then
        enhanced_debug_log("Ignoring non-standard window")
        return
    end

    local app_name = win:application():name()
    local win_id = win:id()

    enhanced_debug_log("New window created - ID:", win_id, "App:", app_name)

    -- Skip if app is in exclusion list
    if config.window_memory and config.window_memory.excluded_apps then
        for _, excluded_app in ipairs(config.window_memory.excluded_apps) do
            if app_name == excluded_app then
                enhanced_debug_log("Skipping excluded app:", app_name)
                return
            end
        end
    end

    -- Check if window is already in a zone (for windows restored at startup)
    local already_in_zone = false
    for zone_id, zone in pairs(tiler._zone_id2zone) do
        if zone.window_to_tile_idx and zone.window_to_tile_idx[win_id] ~= nil then
            already_in_zone = true
            enhanced_debug_log("Window", win_id, "already in zone", zone_id, "- skipping auto-tile")
            break
        end
    end

    -- Don't auto-tile windows that are already assigned to a zone
    if already_in_zone then
        return
    end

    -- If a window is fullscreen, don't auto-tile it
    if win:isFullScreen() then
        enhanced_debug_log("Window is fullscreen, skipping auto-tile")
        return
    end

    -- Get current frame before we do anything
    local initial_frame = win:frame()
    enhanced_debug_log("Initial window position:", "x=" .. initial_frame.x, "y=" .. initial_frame.y,
        "w=" .. initial_frame.w, "h=" .. initial_frame.h)

    -- Longer delay for all apps to ensure they're fully initialized
    local init_delay = 0.3

    -- Even longer delay for known problem apps
    if tiler.is_problem_app and tiler.is_problem_app(app_name) then
        init_delay = 0.5
        enhanced_debug_log("Using longer delay for problem app:", app_name)
    end

    enhanced_debug_log("Scheduling window positioning with delay:", init_delay, "seconds")

    hs.timer.doAfter(init_delay, function()
        -- Window might no longer be valid
        if not win:isValid() then
            enhanced_debug_log("Window is no longer valid")
            return
        end

        -- Try to apply remembered position
        enhanced_debug_log("Attempting to apply remembered position for app:", app_name)
        local success = window_memory.apply_remembered_position(win)

        if success then
            enhanced_debug_log("Applied remembered position successfully")

            -- Double-check final position after a short delay
            hs.timer.doAfter(0.2, function()
                if win:isValid() then
                    local current_frame = win:frame()
                    enhanced_debug_log("Final window position:", "x=" .. current_frame.x, "y=" .. current_frame.y,
                        "w=" .. current_frame.w, "h=" .. current_frame.h)
                end
            end)
        else
            enhanced_debug_log("No remembered position found, attempting zone matching")
            -- No remembered position, try to match to a zone
            local match = window_memory.find_best_zone_for_window(win)

            if match and match.zone then
                local zone = match.zone
                local tile_idx = match.tile_idx

                enhanced_debug_log("Auto-snapping window to zone:", zone.id, "tile:", tile_idx)

                -- Add the window to the zone
                zone:add_window(win_id)

                -- Set the specific tile index
                zone.window_to_tile_idx[win_id] = tile_idx

                -- Update global tracking
                if not tiler._window_state[win_id] then
                    tiler._window_state[win_id] = {}
                end
                tiler._window_state[win_id].zone_id = zone.id
                tiler._window_state[win_id].tile_idx = tile_idx

                -- Apply the tile dimensions
                enhanced_debug_log("Applying zone dimensions")
                zone:resize_window(win_id)

                -- Double-check final position after a short delay
                hs.timer.doAfter(0.2, function()
                    if win:isValid() then
                        local current_frame = win:frame()
                        enhanced_debug_log("Final window position:", "x=" .. current_frame.x, "y=" .. current_frame.y,
                            "w=" .. current_frame.w, "h=" .. current_frame.h)

                        -- If position is still near initial, force resize again
                        if math.abs(current_frame.x - initial_frame.x) < 10 and
                            math.abs(current_frame.y - initial_frame.y) < 10 then
                            enhanced_debug_log("Window did not move, forcing resize again")

                            -- Try again with a bit more force for stubborn windows
                            local tile = zone.tiles[tile_idx]
                            if tile then
                                local frame = hs.geometry.rect(tile.x, tile.y, tile.width, tile.height)

                                -- Force move to screen first
                                win:moveToScreen(zone.screen, false, true, 0)

                                -- Then set frame with animation disabled
                                local saved_duration = hs.window.animationDuration
                                hs.window.animationDuration = 0
                                win:setFrame(frame)
                                hs.window.animationDuration = saved_duration

                                enhanced_debug_log("Applied forced resize")
                            end
                        end
                    end
                end)

                -- Remember this position for future windows of this app
                window_memory.remember_current_window(win)
            elseif config.window_memory and config.window_memory.auto_tile_fallback then
                -- If configured, fall back to default auto-tiling
                enhanced_debug_log("Using fallback auto-tiling for app:", app_name)

                -- Find default zone for this app
                local default_zone = config.window_memory.default_zone or "center"
                if config.window_memory.app_zones and config.window_memory.app_zones[app_name] then
                    default_zone = config.window_memory.app_zones[app_name]
                    enhanced_debug_log("Using app-specific default zone:", default_zone)
                end

                -- Try to find a matching zone on this screen
                local screen = win:screen()
                if screen then
                    local screen_id = screen:id()
                    local target_zone = nil

                    -- Look for a zone with matching ID on this screen
                    for id, zone in pairs(tiler._zone_id2zone) do
                        if zone.screen and zone.screen:id() == screen_id then
                            if id == default_zone or id:match("^" .. default_zone .. "_") then
                                target_zone = zone
                                enhanced_debug_log("Found matching default zone:", id)
                                break
                            end
                        end
                    end

                    if target_zone then
                        -- Add the window to the zone
                        enhanced_debug_log("Adding window to default zone:", target_zone.id)
                        target_zone:add_window(win_id)

                        -- Apply the tile dimensions
                        enhanced_debug_log("Applying default zone dimensions")
                        target_zone:resize_window(win_id)

                        -- Double-check final position after a short delay
                        hs.timer.doAfter(0.2, function()
                            if win:isValid() then
                                local current_frame = win:frame()
                                enhanced_debug_log("Final window position:", "x=" .. current_frame.x,
                                    "y=" .. current_frame.y, "w=" .. current_frame.w, "h=" .. current_frame.h)

                                -- If position is still near initial, force resize again
                                if math.abs(current_frame.x - initial_frame.x) < 10 and
                                    math.abs(current_frame.y - initial_frame.y) < 10 then
                                    enhanced_debug_log("Window did not move, forcing resize again")

                                    -- Try again with a bit more force for stubborn windows
                                    local tile = target_zone.tiles[0] -- Use first tile configuration
                                    if tile then
                                        local frame = hs.geometry.rect(tile.x, tile.y, tile.width, tile.height)

                                        -- Force move to screen first
                                        win:moveToScreen(target_zone.screen, false, true, 0)

                                        -- Then set frame with animation disabled
                                        local saved_duration = hs.window.animationDuration
                                        hs.window.animationDuration = 0
                                        win:setFrame(frame)
                                        hs.window.animationDuration = saved_duration

                                        enhanced_debug_log("Applied forced resize")
                                    end
                                end
                            end
                        end)

                        -- Remember this position for future windows of this app
                        window_memory.remember_current_window(win)
                    else
                        enhanced_debug_log("Could not find default zone:", default_zone, "on screen:", screen:name())
                    end
                else
                    enhanced_debug_log("Window has no screen")
                end
            else
                enhanced_debug_log("No matching zone found and no fallback configured")
            end
        end
    end)
end

-- Save the current window state
function window_memory.save_all_windows_state()
    debug_log("Saving window state for all screens")

    -- Get all visible standard windows
    local windows = hs.window.allWindows()
    for _, win in ipairs(windows) do
        if win:isStandard() and not win:isMinimized() then
            window_memory.remember_current_window(win)
        end
    end

    -- Save caches for all screens
    for _, screen in pairs(hs.screen.allScreens()) do
        save_screen_cache(screen)
    end

    debug_log("Window state saved")
end

-- Command to manually capture positions for all open windows
function window_memory.capture_all_positions()
    debug_log("Capturing positions for all windows")
    window_memory.save_all_windows_state()
    hs.alert.show("Window positions captured")
end

-- Command to apply remembered positions to all windows
function window_memory.apply_all_positions()
    debug_log("Applying remembered positions to all windows")

    -- Get all visible standard windows
    local windows = hs.window.allWindows()
    local success_count = 0

    for _, win in ipairs(windows) do
        if win:isStandard() and not win:isMinimized() then
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

        -- Watch for window movement and changes
        window_memory._window_watcher:subscribe(hs.window.filter.windowMoved, handle_window_moved)
        window_memory._window_watcher:subscribe(hs.window.filter.windowResized, handle_window_moved)
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

        if config.window_memory.cache_dir then
            window_memory.cache_dir = config.window_memory.cache_dir
        else
            window_memory.cache_dir = os.getenv("HOME") .. "/.config/tiler"
        end
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
