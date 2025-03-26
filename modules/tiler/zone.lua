--[[
  zone.lua - Zone class for window management

  This module defines the Zone class which represents a screen region
  with multiple tile configurations for window placement.

  Usage:
    local Zone = require("modules.tiler.zone")
    local Tile = require("modules.tiler.tile")

    -- Create a new zone
    local zone = Zone.new("left_side", {
      screen = hs.screen.mainScreen(),
      hotkey = {"ctrl", "cmd", "h"}
    })

    -- Add tile configurations to the zone
    zone:addTile(Tile.new(0, 0, 400, 800):setDescription("Left half"))
    zone:addTile(Tile.new(0, 0, 200, 800):setDescription("Left quarter"))

    -- Register the zone to enable hotkeys
    zone:register()

    -- Assign a window to this zone
    zone:addWindow(window_id)

    -- Cycle window through tile configurations
    zone:cycleWindow(window_id)

    -- Resize window according to current tile configuration
    zone:resizeWindow(window_id)
]] local logger = require("core.logger")
local utils = require("core.utils")
local state = require("core.state")
local Tile = require("modules.tiler.tile")

-- Define the Zone class
local Zone = {}
Zone.__index = Zone

--- Create a new zone
-- @param id string The unique identifier for this zone
-- @param options table Optional settings for the zone
-- @return Zone The new zone instance
function Zone.new(id, options)
    if not id or type(id) ~= "string" then
        logger.error("Zone", "Cannot create zone without valid ID")
        id = "zone_" .. utils.generateUUID()
    end

    local self = setmetatable({}, Zone)

    -- Core properties
    self.id = id
    self.tiles = {}
    self.window_to_tile_idx = {}
    self.description = nil

    -- Options
    options = options or {}
    self.screen = options.screen
    self.hotkey = options.hotkey
    self.focus_hotkey = options.focus_hotkey
    self.description = options.description or id
    self.tags = options.tags or {}

    -- Generate screen-specific ID if screen is provided
    if self.screen then
        self.screen_specific_id = id .. "_" .. self.screen:id()
    else
        self.screen_specific_id = nil
    end

    return self
end

--- Set human-readable description for this zone
-- @param desc string The description text
-- @return Zone self (for method chaining)
function Zone:setDescription(desc)
    self.description = desc
    return self
end

--- Add a tag to this zone
-- @param tag string The tag to add
-- @return Zone self (for method chaining)
function Zone:addTag(tag)
    if type(tag) == "string" and not utils.tableContains(self.tags, tag) then
        table.insert(self.tags, tag)
    end
    return self
end

--- Check if this zone has a specific tag
-- @param tag string The tag to check for
-- @return boolean True if the zone has the tag
function Zone:hasTag(tag)
    return utils.tableContains(self.tags, tag)
end

--- Convert zone to string for logging
-- @return string A string representation of this zone
function Zone:toString()
    local desc = self.description and (" - " .. self.description) or ""
    local screen_name = self.screen and (" on " .. self.screen:name()) or ""
    return string.format("Zone(id=%s, tiles=%d%s%s)", self.id, #self.tiles, desc, screen_name)
end

--- Add a new tile configuration to this zone
-- @param tile Tile|table The tile to add
-- @param description string Optional description for the tile
-- @return Zone self (for method chaining)
function Zone:addTile(tile, description)
    -- Convert table to Tile if needed
    if type(tile) == "table" and not getmetatable(tile) == Tile then
        tile = Tile.from(tile)
    end

    -- Set description if provided
    if description and type(tile) == "table" then
        tile:setDescription(description)
    end

    -- Validate tile
    if not tile or type(tile) ~= "table" then
        logger.error("Zone", "Cannot add invalid tile to zone %s", self.id)
        return self
    end

    -- Add to tiles array
    table.insert(self.tiles, tile)

    logger.debug("Zone", "Added tile to zone %s, total tiles: %d %s", self.id, #self.tiles,
        tile.description and ("(" .. tile.description .. ")") or "")

    return self
end

--- Get the current tile for a window
-- @param window_id number The window ID
-- @return Tile|nil The current tile or nil if not found
function Zone:getCurrentTile(window_id)
    local tile_idx = self.window_to_tile_idx[window_id]
    if not tile_idx then
        return nil
    end

    return self.tiles[tile_idx]
end

--- Get the tile at a specific index
-- @param idx number The tile index
-- @return Tile|nil The tile or nil if not found
function Zone:getTile(idx)
    return self.tiles[idx]
end

--- Get the number of tiles in this zone
-- @return number The number of tiles
function Zone:getTileCount()
    return #self.tiles
end

--- Get all tiles in this zone
-- @return table Array of tiles
function Zone:getAllTiles()
    return utils.deepCopy(self.tiles)
end

--- Add a window to this zone
-- @param window_id number The window ID
-- @param options table Optional settings
-- @return boolean True if successful
function Zone:addWindow(window_id, options)
    if not window_id then
        logger.error("Zone", "Cannot add nil window to zone %s", self.id)
        return false
    end

    options = options or {}
    local initial_tile_idx = options.tile_idx or 1
    local silent = options.silent or false

    -- First, ensure we remove the window from any other zones
    local zones = state.get("zones") or {}
    for zone_id, zone_data in pairs(zones) do
        if zone_data.id ~= self.id and zone_data.window_to_tile_idx and zone_data.window_to_tile_idx[window_id] ~= nil then

            -- Use Zone instance if available
            if Zone.getById and Zone.getById(zone_id) then
                local other_zone = Zone.getById(zone_id)
                other_zone:removeWindow(window_id, {
                    silent = true
                })
            else
                -- Remove directly from state
                zone_data.window_to_tile_idx[window_id] = nil
                logger.debug("Zone", "Removed window %s from zone %s during add", window_id, zone_id)
            end
        end
    end

    -- Initialize window tracking in this zone
    self.window_to_tile_idx[window_id] = initial_tile_idx

    -- Update global state tracking
    state.update("zones", self.id, {
        window_to_tile_idx = self.window_to_tile_idx
    }, true)

    -- Track the window in the global window state
    state.trackWindow(window_id, {
        zone_id = self.id,
        screen_id = self.screen and self.screen:id() or nil,
        tile_idx = initial_tile_idx,
        last_updated = os.time()
    })

    -- Log unless silent
    if not silent then
        logger.debug("Zone", "Added window %s to zone %s", window_id, self.id)
    end

    -- Store position in screen memory if screen is defined
    if self.screen and state.get("memory") then
        local window = hs.window.get(window_id)
        if window and window:application() then
            local app_name = window:application():name()
            local screen_id = self.screen:id()

            -- Store position data
            state.saveWindowMemory(app_name, screen_id, {
                zone_id = self.id,
                tile_idx = initial_tile_idx,
                timestamp = os.time()
            })

            logger.debug("Zone", "Remembered position for %s on screen %s: zone=%s, tile=%d", app_name, screen_id,
                self.id, initial_tile_idx)
        end
    end

    return true
end

--- Remove a window from this zone
-- @param window_id number The window ID
-- @param options table Optional settings
-- @return boolean True if successful
function Zone:removeWindow(window_id, options)
    if not window_id then
        return false
    end

    options = options or {}
    local silent = options.silent or false

    if self.window_to_tile_idx[window_id] == nil then
        if not silent then
            logger.debug("Zone", "Window %s not in zone %s", window_id, self.id)
        end
        return false
    end

    if not silent then
        logger.debug("Zone", "Removing window %s from zone %s", window_id, self.id)
    end

    -- Remove from local tracking
    self.window_to_tile_idx[window_id] = nil

    -- Update state
    state.update("zones", self.id, {
        window_to_tile_idx = self.window_to_tile_idx
    }, true)

    -- Clean up global window state
    local window_state = state.getWindowState(window_id)
    if window_state and window_state.zone_id == self.id then
        -- Remove or update window state
        if options.update_state == false then
            state.remove("windows", tostring(window_id), true)
        else
            state.update("windows", tostring(window_id), {
                zone_id = nil,
                tile_idx = nil,
                last_updated = os.time()
            }, true)
        end
    end

    return true
end

--- Cycle a window through tile configurations
-- @param window_id number The window ID
-- @param options table Optional settings
-- @return number The new tile index
function Zone:cycleWindow(window_id, options)
    if not window_id then
        logger.error("Zone", "Cannot cycle nil window in zone %s", self.id)
        return nil
    end

    options = options or {}
    local direction = options.direction or "forward"

    -- Always initialize if window not already in this zone
    if not self.window_to_tile_idx[window_id] then
        logger.debug("Zone", "Window not properly tracked in zone - initializing")
        self:addWindow(window_id, {
            silent = options.silent
        })
        return 1
    end

    local current_idx = self.window_to_tile_idx[window_id]
    local next_idx

    -- Calculate next index based on direction
    if direction == "forward" then
        next_idx = (current_idx % #self.tiles) + 1
    elseif direction == "backward" then
        next_idx = ((current_idx - 2) % #self.tiles) + 1
    elseif direction == "first" then
        next_idx = 1
    elseif direction == "last" then
        next_idx = #self.tiles
    elseif type(direction) == "number" then
        -- Use direction as explicit index
        next_idx = ((direction - 1) % #self.tiles) + 1
    else
        -- Default to forward
        next_idx = (current_idx % #self.tiles) + 1
    end

    -- Update tracking
    self.window_to_tile_idx[window_id] = next_idx

    -- Update global state
    state.update("windows", tostring(window_id), {
        zone_id = self.id,
        tile_idx = next_idx,
        last_updated = os.time()
    }, true)

    -- Update zone state
    state.update("zones", self.id, {
        window_to_tile_idx = self.window_to_tile_idx
    }, true)

    -- Update memory
    if self.screen then
        local window = hs.window.get(window_id)
        if window and window:application() then
            local app_name = window:application():name()
            local screen_id = self.screen:id()

            state.saveWindowMemory(app_name, screen_id, {
                zone_id = self.id,
                tile_idx = next_idx,
                timestamp = os.time()
            })
        end
    end

    -- Log the rotation
    if not options.silent then
        local desc = ""
        if self.tiles[next_idx] and self.tiles[next_idx].description then
            desc = " - " .. self.tiles[next_idx].description
        end

        logger.debug("Zone", "Rotated window %s to tile index %d in zone %s%s", window_id, next_idx, self.id, desc)
    end

    return next_idx
end

--- Resize a window according to its current tile configuration
-- @param window_id number The window ID
-- @param options table Optional settings
-- @return boolean True if successful
function Zone:resizeWindow(window_id, options)
    if not window_id then
        logger.error("Zone", "Cannot resize nil window in zone %s", self.id)
        return false
    end

    options = options or {}

    -- Get tile index for this window
    local tile_idx = self.window_to_tile_idx[window_id]
    if not tile_idx then
        logger.error("Zone", "Cannot resize window %s - not in zone %s", window_id, self.id)
        return false
    end

    -- Get the tile
    local tile = self.tiles[tile_idx]
    if not tile then
        logger.error("Zone", "Invalid tile index %d for window %s in zone %s", tile_idx, window_id, self.id)
        return false
    end

    -- Get the window
    local window = hs.window.get(window_id)
    if not window then
        logger.error("Zone", "Cannot find window with ID %s", window_id)
        return false
    end

    -- Get the screen for this zone
    local target_screen = self.screen
    if not target_screen then
        -- Fallback to current screen if zone doesn't have one assigned
        target_screen = window:screen()
        logger.debug("Zone", "Zone has no screen assigned, using window's current screen: %s", target_screen:name())
    end

    -- Check if we need to move to a different screen first
    local current_screen = window:screen()
    if current_screen:id() ~= target_screen:id() then
        logger.debug("Zone", "Moving window %s to screen %s before resizing", window_id, target_screen:name())

        -- Force move to the screen first
        window:moveToScreen(target_screen, false, false, 0)

        -- Add a small delay to ensure the window has time to move
        hs.timer.doAfter(0.05, function()
            -- Now apply the tile
            tile:applyToWindow(window, {
                problem_apps = options.problem_apps
            })
        end)

        return true
    end

    -- Apply the tile directly if already on the correct screen
    return tile:applyToWindow(window, {
        problem_apps = options.problem_apps
    })
end

--- Find the best matching zone for a window position
-- @param window hs.window The window to match
-- @param options table Optional settings
-- @return table Best match with zone, tile_idx and score
function Zone.findBestZoneForWindow(window, options)
    if not window or not window:isStandard() then
        return nil
    end

    options = options or {}

    local screen = window:screen()
    if not screen then
        return nil
    end

    local screen_id = screen:id()
    local win_frame = window:frame()

    -- Find zones on this specific screen
    local screen_zones = {}
    local all_zones = state.get("zones") or {}

    for zone_id, zone_data in pairs(all_zones) do
        if zone_data.screen_id == screen_id then
            -- Try to get Zone instance
            local zone
            if Zone.getById then
                zone = Zone.getById(zone_id)
            end

            -- If we can't get Zone instance, create one from data
            if not zone then
                zone = Zone.new(zone_data.id, {
                    screen = screen,
                    description = zone_data.description
                })

                -- Add tiles
                if zone_data.tiles then
                    for _, tile_data in ipairs(zone_data.tiles) do
                        zone:addTile(Tile.from(tile_data))
                    end
                end
            end

            table.insert(screen_zones, zone)
        end
    end

    if #screen_zones == 0 then
        logger.debug("Zone", "No zones found for screen %s", screen:name())
        return nil
    end

    -- Find best matching zone based on window position and size
    local best_zone = nil
    local best_match_score = 0
    local best_tile_idx = 0

    for _, zone in ipairs(screen_zones) do
        -- Skip zones with no tiles
        if zone:getTileCount() == 0 then
            goto next_zone
        end

        -- Check each tile in the zone
        for i = 1, zone:getTileCount() do
            local tile = zone:getTile(i)
            if not tile then
                goto next_tile
            end

            -- Calculate overlap percentage
            local overlap_percentage = tile:calculateOverlapPercentage(win_frame)

            -- Calculate size similarity (how close the window and tile are in size)
            local width_ratio = math.min(win_frame.w, tile.width) / math.max(win_frame.w, tile.width)
            local height_ratio = math.min(win_frame.h, tile.height) / math.max(win_frame.h, tile.height)
            local size_similarity = (width_ratio + height_ratio) / 2

            -- Calculate center distance
            local win_center = {
                x = win_frame.x + win_frame.w / 2,
                y = win_frame.y + win_frame.h / 2
            }

            local normalized_distance = 1 - (tile:distanceFromCenter(win_center) / 1000)
            normalized_distance = math.max(0, math.min(1, normalized_distance))

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
        logger.debug("Zone", "Found best matching zone: %s with score: %.2f", best_zone.id, best_match_score)

        return {
            zone = best_zone,
            tile_idx = best_tile_idx,
            score = best_match_score
        }
    end

    return nil
end

--- Register hotkeys and store zone in state
-- @param options table Optional settings
-- @return Zone self (for method chaining)
function Zone:register(options)
    options = options or {}

    -- Create a screen-specific ID for state storage
    local state_id = self.screen_specific_id or self.id

    -- Store in state
    state.set("zones", state_id, {
        id = self.id,
        description = self.description,
        screen_id = self.screen and self.screen:id() or nil,
        screen_name = self.screen and self.screen:name() or nil,
        tiles = utils.map(self.tiles, function(tile)
            return tile:toTable()
        end),
        window_to_tile_idx = self.window_to_tile_idx,
        tags = self.tags
    })

    -- Register the hotkey for this zone
    if self.hotkey and not options.no_hotkeys then
        hs.hotkey.bind(self.hotkey[1], self.hotkey[2], function()
            -- Find active window
            local window = hs.window.focusedWindow()
            if not window then
                logger.debug("Zone", "No focused window")
                return
            end

            local window_id = window:id()

            -- Check if the window is already in this zone
            local already_in_zone = (self.window_to_tile_idx[window_id] ~= nil)

            if already_in_zone then
                -- Cycle through tiles if already in zone
                self:cycleWindow(window_id)
            else
                -- Otherwise add to zone
                self:addWindow(window_id)
            end

            -- Apply the tile dimensions
            self:resizeWindow(window_id, {
                problem_apps = options.problem_apps
            })
        end)

        logger.debug("Zone", "Bound hotkey %s to zone %s", table.concat(self.hotkey[1], "+") .. "+" .. self.hotkey[2],
            self.id)
    end

    -- Register focus hotkey
    if self.focus_hotkey and not options.no_hotkeys then
        hs.hotkey.bind(self.focus_hotkey[1], self.focus_hotkey[2], function()
            -- Focus windows in this zone
            Zone.focusWindowsInZone(self.id)
        end)

        logger.debug("Zone", "Bound focus hotkey %s to zone %s",
            table.concat(self.focus_hotkey[1], "+") .. "+" .. self.focus_hotkey[2], self.id)
    end

    logger.debug("Zone", "Registered zone %s", state_id)
    return self
end

--- Get list of windows in this zone
-- @return table Array of window IDs
function Zone:getWindowsInZone()
    local result = {}

    for window_id, _ in pairs(self.window_to_tile_idx) do
        table.insert(result, window_id)
    end

    return result
end

--- Check if a window is in this zone
-- @param window_id number The window ID
-- @return boolean True if the window is in this zone
function Zone:hasWindow(window_id)
    return self.window_to_tile_idx[window_id] ~= nil
end

--- Convert all tiles to specific screen
-- @param screen hs.screen The screen to convert tiles to
-- @return Zone self (for method chaining)
function Zone:convertTilesToScreen(screen)
    if not screen or not self.screen then
        return self
    end

    -- Skip if already on this screen
    if screen:id() == self.screen:id() then
        return self
    end

    local source_frame = self.screen:frame()
    local target_frame = screen:frame()

    -- Calculate scaling factors
    local scale_x = target_frame.w / source_frame.w
    local scale_y = target_frame.h / source_frame.h

    -- Convert each tile
    for i, tile in ipairs(self.tiles) do
        -- Calculate new position
        local new_x = target_frame.x + (tile.x - source_frame.x) * scale_x
        local new_y = target_frame.y + (tile.y - source_frame.y) * scale_y
        local new_width = tile.width * scale_x
        local new_height = tile.height * scale_y

        -- Create new tile with adjusted position
        self.tiles[i] = Tile.new(new_x, new_y, new_width, new_height, {
            description = tile.description,
            id = tile.id,
            tags = tile.tags,
            metadata = tile.metadata
        })
    end

    -- Update screen reference
    self.screen = screen

    -- Update screen-specific ID
    self.screen_specific_id = self.id .. "_" .. screen:id()

    return self
end

--- Get a zone by ID from state
-- @param zone_id string The zone ID
-- @return Zone|nil The zone or nil if not found
function Zone.getById(zone_id)
    if not zone_id then
        return nil
    end

    local zone_data = state.get("zones", zone_id)
    if not zone_data then
        return nil
    end

    -- Create zone instance from data
    local screen = nil
    if zone_data.screen_id then
        -- Try to find the screen
        for _, s in ipairs(hs.screen.allScreens()) do
            if tostring(s:id()) == tostring(zone_data.screen_id) then
                screen = s
                break
            end
        end
    end

    local zone = Zone.new(zone_data.id, {
        screen = screen,
        description = zone_data.description,
        tags = zone_data.tags
    })

    -- Add tiles
    if zone_data.tiles then
        for _, tile_data in ipairs(zone_data.tiles) do
            zone:addTile(Tile.from(tile_data))
        end
    end

    -- Set window tracking
    if zone_data.window_to_tile_idx then
        zone.window_to_tile_idx = utils.deepCopy(zone_data.window_to_tile_idx)
    end

    return zone
end

--- Focus windows in a specific zone (global function)
-- @param zone_id string The zone ID
-- @param options table Optional settings
-- @return boolean True if successful
function Zone.focusWindowsInZone(zone_id, options)
    options = options or {}

    logger.debug("Zone", "Focusing on windows in zone %s", zone_id)

    -- Get focused window
    local current_win = hs.window.focusedWindow()
    if not current_win then
        logger.debug("Zone", "No focused window")
        return false
    end

    local current_win_id = current_win:id()
    local current_screen = current_win:screen()
    local current_screen_id = current_screen:id()

    -- Find the appropriate zone
    local target_zone = nil

    -- Try to find the zone in state
    local zones = state.get("zones") or {}

    -- First try exact ID match
    if zones[zone_id] then
        target_zone = Zone.getById(zone_id)
    end

    -- Try screen-specific ID
    if not target_zone then
        local screen_specific_id = zone_id .. "_" .. current_screen_id
        if zones[screen_specific_id] then
            target_zone = Zone.getById(screen_specific_id)
        end
    end

    -- Look for any zone with matching ID on current screen
    if not target_zone then
        for id, zone_data in pairs(zones) do
            if zone_data.screen_id == current_screen_id and (id == zone_id or id:match("^" .. zone_id .. "_")) then

                target_zone = Zone.getById(id)
                break
            end
        end
    end

    if not target_zone then
        logger.debug("Zone", "No matching zone found for %s on screen %s", zone_id, current_screen:name())
        return false
    end

    logger.debug("Zone", "Found zone %s for focus", target_zone.id)

    -- Now we have a valid zone, find all windows in this zone
    local zone_windows = {}

    -- Get windows directly assigned to the zone
    for win_id in pairs(target_zone.window_to_tile_idx) do
        local win = hs.window.get(win_id)
        if win and win:isStandard() and not win:isMinimized() and win:screen():id() == current_screen_id then

            table.insert(zone_windows, win_id)
        end
    end

    -- Find other visible windows that overlap significantly with zone tiles
    for _, win in ipairs(hs.window.allWindows()) do
        if win:isStandard() and not win:isMinimized() and win:screen():id() == current_screen_id then

            local win_id = win:id()

            -- Skip if already in our list
            if utils.tableContains(zone_windows, win_id) then
                goto continue
            end

            local win_frame = win:frame()

            -- Check overlap with each tile in the zone
            for i = 1, target_zone:getTileCount() do
                local tile = target_zone:getTile(i)
                if tile then
                    local overlap = tile:calculateOverlapPercentage(win_frame)

                    -- Include windows with significant overlap (50% or more)
                    if overlap >= 0.5 then
                        table.insert(zone_windows, win_id)
                        break
                    end
                end
            end

            ::continue::
        end
    end

    if #zone_windows == 0 then
        logger.debug("Zone", "No windows found in zone %s", target_zone.id)
        return false
    end

    logger.debug("Zone", "Found %d windows in zone %s", #zone_windows, target_zone.id)

    -- Create a key for tracking focus in this zone
    local focus_key = target_zone.id .. "_screen_" .. current_screen_id

    -- Get current focus index
    local focus_indices = state.get("focus_indices") or {}
    local current_idx = nil

    -- Check if current window is in the list
    for i, win_id in ipairs(zone_windows) do
        if win_id == current_win_id then
            current_idx = i
            break
        end
    end

    -- Determine which window to focus next
    local next_idx = 1

    if current_idx then
        -- Move to next window in cycle
        next_idx = (current_idx % #zone_windows) + 1
        logger.debug("Zone", "Current window is in list at position %d, moving to %d", current_idx, next_idx)
    else
        -- Current window not in list, use remembered index or start from beginning
        if focus_indices[focus_key] then
            next_idx = ((focus_indices[focus_key]) % #zone_windows) + 1
            logger.debug("Zone", "Using remembered index %d", next_idx)
        else
            logger.debug("Zone", "Starting from first window in list")
        end
    end

    -- Update remembered index
    focus_indices[focus_key] = next_idx
    state.set("focus_indices", focus_indices)

    -- Focus the next window
    local next_win_id = zone_windows[next_idx]
    local next_win = hs.window.get(next_win_id)

    if next_win then
        next_win:focus()
        logger.debug("Zone", "Focused window %s in zone %s (%d of %d)", next_win_id, target_zone.id, next_idx,
            #zone_windows)

        -- Visual feedback if enabled
        if options.flash_on_focus then
            local frame = next_win:frame()
            local flash = hs.canvas.new(frame):appendElements({
                type = "rectangle",
                action = "fill",
                fillColor = options.flash_color or {
                    red = 0.5,
                    green = 0.5,
                    blue = 1.0,
                    alpha = 0.3
                }
            })

            flash:show()
            hs.timer.doAfter(options.flash_duration or 0.2, function()
                flash:delete()
            end)
        end

        return true
    else
        logger.debug("Zone", "Failed to focus window %s - window may have been closed", next_win_id)
        return false
    end
end

--- Initialize zones for all screens
-- @param config table Configuration options
-- @return table Initialized zones
function Zone.initForAllScreens(config)
    logger.info("Zone", "Initializing zones for all screens")

    local screens = hs.screen.allScreens()
    local all_zones = {}

    -- Clear existing zones
    state.clear("zones")

    for _, screen in ipairs(screens) do
        local screen_zones = Zone.createZonesForScreen(screen, config)

        for _, zone in ipairs(screen_zones) do
            all_zones[zone.id] = zone
        end
    end

    return all_zones
end

--- Create zones for a screen based on configuration
-- @param screen hs.screen The screen to create zones for
-- @param config table Configuration options
-- @return table Array of created zones
function Zone.createZonesForScreen(screen, config)
    if not screen then
        logger.error("Zone", "Cannot create zones without screen")
        return {}
    end

    config = config or {}
    local zones = {}
    local screen_name = screen:name()

    logger.debug("Zone", "Creating zones for screen: %s", screen_name)

    -- Determine grid dimensions
    local grid_config = require("modules.tiler.grid")
    local grid = grid_config.getGridForScreen(screen, config)

    if not grid then
        logger.error("Zone", "Failed to create grid for screen %s", screen_name)
        return {}
    end

    local cols = grid.cols
    local rows = grid.rows

    logger.debug("Zone", "Using %dx%d grid for screen %s", cols, rows, screen_name)

    -- Get layout type
    local layout_type = cols .. "x" .. rows

    -- Create zones based on configuration
    local zone_configs

    -- 1. Look for specific screen configuration
    if config.layouts and config.layouts.custom and config.layouts.custom[screen_name] then
        zone_configs = config.layouts.custom[screen_name]
        logger.debug("Zone", "Using custom layout for screen: %s", screen_name)

        -- 2. Look for layout type configuration
    elseif config.layouts and config.layouts[layout_type] then
        zone_configs = config.layouts[layout_type]
        logger.debug("Zone", "Using %s layout for screen: %s", layout_type, screen_name)

        -- 3. Fall back to default configuration
    elseif config.layouts and config.layouts["default"] then
        zone_configs = config.layouts["default"]
        logger.debug("Zone", "Using default layout for screen: %s", screen_name)
    else
        logger.error("Zone", "No layout configuration found for screen %s", screen_name)
        return {}
    end

    -- Create zones based on configuration
    for zone_key, tile_configs in pairs(zone_configs) do
        -- Skip default fallback entry
        if zone_key == "default" then
            goto continue
        end

        -- Create zone
        local zone = Zone.new(zone_key, {
            screen = screen,
            description = "Zone " .. zone_key .. " - Screen: " .. screen_name,
            hotkey = config.modifier and {config.modifier, zone_key} or nil,
            focus_hotkey = config.focus_modifier and {config.focus_modifier, zone_key} or nil
        })

        -- Add tiles based on configuration
        for _, tile_spec in ipairs(tile_configs) do
            local position

            if type(tile_spec) == "string" then
                -- String format like "a1:b2" or named position
                position = grid_config.getPositionForRegion(grid, tile_spec)
            elseif type(tile_spec) == "table" then
                -- Table format with coordinates
                position = grid_config.getPositionForRegion(grid, tile_spec)
            end

            if position then
                local tile = Tile.new(position.x, position.y, position.w, position.h, {
                    description = position.description
                })

                zone:addTile(tile)
            end
        end

        -- If no tiles were added, add a default one
        if zone:getTileCount() == 0 then
            logger.debug("Zone", "No tiles configured for zone %s, adding default", zone_key)

            local position = grid_config.getPositionForRegion(grid, "full")
            if position then
                zone:addTile(Tile.new(position.x, position.y, position.w, position.h, {
                    description = "Default size"
                }))
            end
        end

        -- Register the zone
        zone:register({
            problem_apps = config.problem_apps
        })

        table.insert(zones, zone)
        ::continue::
    end

    -- Create special zone for center
    local center_key = "0"
    local center_zone = Zone.new("center", {
        screen = screen,
        description = "Center zone - Screen: " .. screen_name,
        hotkey = config.modifier and {config.modifier, center_key} or nil,
        focus_hotkey = config.focus_modifier and {config.focus_modifier, center_key} or nil
    })

    -- Add center tiles
    local center_configs = zone_configs["0"] or {"center", "full"}

    for _, tile_spec in ipairs(center_configs) do
        local position = grid_config.getPositionForRegion(grid, tile_spec)

        if position then
            center_zone:addTile(Tile.new(position.x, position.y, position.w, position.h, {
                description = position.description
            }))
        end
    end

    -- If no tiles were added, add default center tiles
    if center_zone:getTileCount() == 0 then
        local frame = screen:frame()

        center_zone:addTile(Tile.new(frame.x + frame.w / 4, frame.y + frame.h / 4, frame.w / 2, frame.h / 2, {
            description = "Center"
        }))

        center_zone:addTile(Tile.new(frame.x + frame.w / 6, frame.y + frame.h / 6, frame.w * 2 / 3, frame.h * 2 / 3, {
            description = "Large center"
        }))

        center_zone:addTile(Tile.new(frame.x, frame.y, frame.w, frame.h, {
            description = "Full screen"
        }))
    end

    center_zone:register({
        problem_apps = config.problem_apps
    })

    table.insert(zones, center_zone)

    return zones
end

--- Map existing windows to zones based on their positions
-- @param options table Optional settings
-- @return number Number of windows mapped
function Zone.mapExistingWindows(options)
    options = options or {}

    logger.info("Zone", "Mapping existing windows to zones")

    -- Get all visible windows
    local all_windows = hs.window.allWindows()
    local mapped_count = 0

    -- Track zones by screen for better reporting
    local screen_mapped = {}

    for _, win in ipairs(all_windows) do
        -- Skip non-standard or minimized windows
        if not win:isStandard() or win:isMinimized() then
            goto continue
        end

        -- Skip windows that are already mapped
        local win_id = win:id()
        local window_state = state.getWindowState(win_id)

        if window_state and window_state.zone_id then
            logger.debug("Zone", "Window %s already mapped to zone %s", win_id, window_state.zone_id)
            goto continue
        end

        -- Find best matching zone
        local match = Zone.findBestZoneForWindow(win)

        if match and match.zone then
            logger.debug("Zone", "Mapping window %s to zone %s with match score %.2f", win_id, match.zone.id,
                match.score)

            -- Track which screen this window was mapped on
            local screen_id = match.zone.screen:id()
            screen_mapped[screen_id] = (screen_mapped[screen_id] or 0) + 1

            -- Add window to zone at the best matching tile index
            match.zone:addWindow(win_id, {
                tile_idx = match.tile_idx,
                silent = options.silent
            })

            mapped_count = mapped_count + 1
        end

        ::continue::
    end

    -- Log mapping results by screen
    for screen_id, count in pairs(screen_mapped) do
        local screen_name = "Unknown"
        for _, screen in ipairs(hs.screen.allScreens()) do
            if tostring(screen:id()) == tostring(screen_id) then
                screen_name = screen:name()
                break
            end
        end
        logger.debug("Zone", "Mapped %d windows on screen %s", count, screen_name)
    end

    logger.info("Zone", "Mapped %d windows to zones", mapped_count)
    return mapped_count
end

return Zone
