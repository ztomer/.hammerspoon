--[[
Zone Tiler for Hammerspoon
===========================

A window management system that allows defining zones on the screen and cycling window sizes within those zones.

Usage:
------

1. Load this module from your Hammerspoon init.lua:

   ```lua
   require "tiler"
   ```

2. Customize the configuration in your init.lua (optional):

   ```lua
   -- Change the default hotkey modifier
   tiler.config.modifier = {"ctrl", "alt"}

   -- Define custom layouts for specific screens
   tiler.layouts.custom["DELL U3223QE"] = { cols = 4, rows = 3 }

   -- Configure custom zone behavior
   tiler.configure_zone("y", { "a1:a2", "a1" })
   tiler.configure_zone("h", { "a1:b3", "a1:a3" })
   ```

Grid Coordinate System:
----------------------

The tiler uses a grid coordinate system with alphabetic columns and numeric rows:

```
    a    b    c    d
  +----+----+----+----+
1 | a1 | b1 | c1 | d1 |
  +----+----+----+----+
2 | a2 | b2 | c2 | d2 |
  +----+----+----+----+
3 | a3 | b3 | c3 | d3 |
  +----+----+----+----+
```

You can define regions using:

1. String coordinates like "a1" (single cell) or "a1:b2" (rectangle from a1 to b2)
2. Named positions like "center", "left-half", "top-half", etc.
3. Table coordinates like {1,1,2,2} for programmatic definitions

Default Zone Configurations:
---------------------------

The default configuration provides the following key bindings with modifier (usually ctrl+cmd):

Left side of keyboard:
- y: Top-left region cycling: "a1:a2", "a1"
- h: Left side cycling: "a1:b3", "a1:a3", "a1:c3"
- n: Bottom-left cycling: "a3", "a2:a3"
- u: Upper-middle cycling: "b1:b3", "b1:b2", "b1"
- j: Middle cycling: "b1:c3", "b1:b3", "b2"
- m: Bottom-middle cycling: "c1:c3", "c2:c3", "c3"

Right side of keyboard:
- i: Top-right cycling: "d1:d3", "d1:d2", "d1"
- k: Right side cycling: "c1:d3", "d1:d3", "c2"
- ,: Bottom-right cycling: "d3", "d2:d3"
- o: Top-right cell cycling: "d1", "c1:d1"
- l: Right columns cycling: "d1:d3", "c1:d3"
- .: Bottom-right cycling: "c3:d3", "d3"

Center:
- 0: Center cycling: "b2:c2", "b1:c3", "a1:d3" (quarter, two-thirds, full)

Many more keys are bound automatically based on your grid size.
]] -- Define the tiler namespace
local config = require "config" -- Configuration file

-- Define the tiler namespace
local tiler = {
    -- Settings placeholder (will be populated from config)
    config = {},

    -- Internal state
    _version = "1.1.0",
    _window_id2zone_id = {},
    _zone_id2zone = {},
    _modes = {},
    _window_watcher = nil,

    -- Public user configuration tables
    layouts = {
        default = {
            small = "2x2",
            medium = "3x2",
            large = "3x3",
            extra_large = "4x3"
        },
        custom = {}
    },

    -- Zone configurations
    zone_configs = {}
}

-- Debug logging function
local function debug_log(...)
    if tiler.config.debug then
        print("[TilerDebug]", ...)
    end
end

-- Function to set configuration from config.lua
function tiler.set_config()
    -- Load basic settings
    tiler.config = {
        debug = config.tiler.debug,
        modifier = config.tiler.modifier,
        focus_modifier = config.tiler.focus_modifier,
        flash_on_focus = config.tiler.flash_on_focus,
        smart_placement = config.tiler.smart_placement,
        margins = config.tiler.margins,
        problem_apps = config.tiler.problem_apps
    }

    -- Load custom layouts
    if config.tiler.layouts and config.tiler.layouts.custom then
        tiler.layouts.custom = config.tiler.layouts.custom
    end

    -- Load default zone configurations
    tiler.default_zone_configs = config.tiler.default_zone_configs

    -- Initialize zone_configs with the default values
    for key, value in pairs(tiler.default_zone_configs) do
        tiler.zone_configs[key] = value
    end

    -- Set up screen-specific configs
    tiler.zone_configs_by_screen = {}

    -- Load portrait_zones for the LG screen if applicable
    if config.tiler.portrait_zones then
        tiler.zone_configs_by_screen["LG IPS QHD"] = {}

        -- Copy portrait_zones configs
        for key, value in pairs(config.tiler.portrait_zones) do
            tiler.zone_configs_by_screen["LG IPS QHD"][key] = value
        end
    end

    debug_log("Configuration loaded from config.lua")
    return tiler
end

------------------------------------------
-- Tile Class: Represents a window position
------------------------------------------

local Tile = {}
Tile.__index = Tile

-- Create a new tile with position and size
function Tile.new(x, y, width, height)
    local self = setmetatable({}, Tile)
    self.x = x
    self.y = y
    self.width = width
    self.height = height
    self.description = nil -- Optional description
    return self
end

-- Convert tile to string for logging
function Tile:to_string()
    local desc = self.description and (" - " .. self.description) or ""
    return string.format("Tile(x=%.1f, y=%.1f, w=%.1f, h=%.1f%s)", self.x, self.y, self.width, self.height, desc)
end

-- Set human-readable description for this tile
function Tile:set_description(desc)
    self.description = desc
    return self -- For method chaining
end

------------------------------------------
-- Zone Class: Represents a screen region
------------------------------------------

local Zone = {}
Zone.__index = Zone

-- Create a new zone
function Zone.new(id, hotkey, screen)
    local self = setmetatable({}, Zone)
    self.id = id
    self.hotkey = hotkey
    self.tiles = {}
    self.tile_count = 0
    self.window_to_tile_idx = {}
    self.description = nil
    self.screen = screen -- Store reference to the screen this zone belongs to
    return self
end

-- Convert zone to string for logging
function Zone:to_string()
    local desc = self.description and (" - " .. self.description) or ""
    return string.format("Zone(id=%s, tiles=%d%s)", self.id, self.tile_count, desc)
end

-- Set human-readable description for this zone
function Zone:set_description(desc)
    self.description = desc
    return self -- For method chaining
end

-- Add a new tile configuration to this zone
function Zone:add_tile(x, y, width, height, description)
    local tile = Tile.new(x, y, width, height)
    if description then
        tile:set_description(description)
    end
    self.tiles[self.tile_count] = tile
    self.tile_count = self.tile_count + 1
    debug_log("Added tile to zone", self.id, "total tiles:", self.tile_count,
        description and ("(" .. description .. ")") or "")
    return self -- For method chaining
end

function Zone:rotate_tile(window_id)
    -- Always initialize if window not already in this zone
    if not self.window_to_tile_idx[window_id] then
        debug_log("Window not properly tracked in zone - initializing")
        self.window_to_tile_idx[window_id] = 0

        -- Update global tracking
        if not tiler._window_state[window_id] then
            tiler._window_state[window_id] = {}
        end
        tiler._window_state[window_id].zone_id = self.id
        tiler._window_state[window_id].tile_idx = 0

        return 0
    end

    -- Advance to next tile configuration with wrap-around
    local next_idx = (self.window_to_tile_idx[window_id] + 1) % self.tile_count
    self.window_to_tile_idx[window_id] = next_idx

    -- Update global tracking
    if not tiler._window_state[window_id] then
        tiler._window_state[window_id] = {}
    end
    tiler._window_state[window_id].zone_id = self.id
    tiler._window_state[window_id].tile_idx = next_idx

    local desc = ""
    if self.tiles[next_idx] and self.tiles[next_idx].description then
        desc = " - " .. self.tiles[next_idx].description
    end
    debug_log("Rotated window", window_id, "to tile index", next_idx, "in zone", self.id, desc)

    -- Update the memory for this screen
    if self.screen and tiler._screen_memory[window_id] then
        local screen_id = self.screen:id()
        if not tiler._screen_memory[window_id] then
            tiler._screen_memory[window_id] = {}
        end

        tiler._screen_memory[window_id][screen_id] = {
            zone_id = self.id,
            tile_idx = next_idx
        }
        debug_log("Updated remembered position for window", window_id, "on screen", screen_id, "zone", self.id, "tile",
            next_idx)
    end

    return next_idx
end

-- Get the current tile for a window
function Zone:get_current_tile(window_id)
    local tile_idx = self.window_to_tile_idx[window_id]
    if not tile_idx then
        return nil
    end
    return self.tiles[tile_idx]
end

-- Add a window to this zone
function Zone:add_window(window_id)
    if not window_id then
        debug_log("Cannot add nil window to zone", self.id)
        return
    end

    -- First, ensure we remove the window from any other zones
    for _, zone in pairs(tiler._zone_id2zone) do
        if zone.window_to_tile_idx and zone.window_to_tile_idx[window_id] ~= nil then
            zone.window_to_tile_idx[window_id] = nil
            debug_log("Removed window", window_id, "from zone", zone.id, "during add")

            -- Also remove from the zone_windows list
            if tiler._zone_windows[zone.id] then
                for i, wid in ipairs(tiler._zone_windows[zone.id]) do
                    if wid == window_id then
                        table.remove(tiler._zone_windows[zone.id], i)
                        debug_log("Removed window", window_id, "from zone_windows for zone", zone.id)
                        break
                    end
                end
            end
        end
    end

    -- Initialize global tracking if needed
    if not tiler._window_state[window_id] then
        tiler._window_state[window_id] = {}
    end

    -- Map the window to this zone and set first tile (index 0)
    self.window_to_tile_idx[window_id] = 0
    tiler._window_id2zone_id[window_id] = self.id

    -- Track in global state
    tiler._window_state[window_id].zone_id = self.id
    tiler._window_state[window_id].tile_idx = 0

    debug_log("Added window", window_id, "to zone", self.id)

    -- Store position in screen memory
    if self.screen then
        -- Initialize window's memory if needed
        if not tiler._screen_memory[window_id] then
            tiler._screen_memory[window_id] = {}
        end

        local screen_id = self.screen:id()
        tiler._screen_memory[window_id][screen_id] = {
            zone_id = self.id,
            tile_idx = 0
        }
        debug_log("Remembered position for window", window_id, "on screen", screen_id, "zone", self.id, "tile", 0)
    end

    -- After adding the window to the zone, track it in the zone windows list
    if not tiler._zone_windows[self.id] then
        tiler._zone_windows[self.id] = {}
    end

    -- Check if window is already in the list before adding
    local found = false
    for i, wid in ipairs(tiler._zone_windows[self.id]) do
        if wid == window_id then
            found = true
            break
        end
    end

    if not found then
        table.insert(tiler._zone_windows[self.id], window_id)
        debug_log("Added window", window_id, "to zone windows list for zone", self.id)
    end
end

-- Remove a window from this zone
function Zone:remove_window(window_id)
    if self.window_to_tile_idx[window_id] == nil then
        debug_log("Window", window_id, "not in zone", self.id)
        return
    end

    debug_log("Removing window", window_id, "from zone", self.id)
    self.window_to_tile_idx[window_id] = nil

    -- Only remove from global mapping if it points to THIS zone
    if tiler._window_id2zone_id[window_id] == self.id then
        tiler._window_id2zone_id[window_id] = nil
    end

    -- If this is a screen-specific zone ID with an underscore
    local base_id = self.id:match("^([^_]+)_")
    if base_id and tiler._window_id2zone_id[window_id] == base_id then
        tiler._window_id2zone_id[window_id] = nil
    end

    -- Remove from zone windows list
    if tiler._zone_windows[self.id] then
        for i, wid in ipairs(tiler._zone_windows[self.id]) do
            if wid == window_id then
                table.remove(tiler._zone_windows[self.id], i)
                debug_log("Removed window", window_id, "from zone windows list for zone", self.id)
                break
            end
        end
    end

end

-- Utility function to check if an app is in the problem list
-- Add this in the utility functions section
local function is_problem_app(app_name)
    if not tiler.config.problem_apps then
        return false
    end

    local lower_app_name = app_name:lower()
    for _, name in ipairs(tiler.config.problem_apps) do
        if name:lower() == lower_app_name then
            return true
        end
    end

    return false
end

local function compute_distance_map(screen, cell_size)
    local screen_frame = screen:frame()
    local grid_width = math.ceil(screen_frame.w / cell_size)
    local grid_height = math.ceil(screen_frame.h / cell_size)

    -- Initialize grid: 0 means empty
    local grid = {}
    for i = 1, grid_height do
        grid[i] = {}
        for j = 1, grid_width do
            grid[i][j] = 0
        end
    end

    -- Mark cells occupied by existing windows
    for _, win in pairs(hs.window.allWindows()) do
        if win:screen() == screen then
            local frame = win:frame()
            local x1 = math.floor(frame.x / cell_size) + 1
            local y1 = math.floor(frame.y / cell_size) + 1
            local x2 = math.ceil((frame.x + frame.w) / cell_size)
            local y2 = math.ceil((frame.y + frame.h) / cell_size)
            for i = math.max(1, y1), math.min(grid_height, y2) do
                for j = math.max(1, x1), math.min(grid_width, x2) do
                    grid[i][j] = 1 -- 1 means occupied
                end
            end
        end
    end

    -- BFS to compute distances
    local distance = {}
    for i = 1, grid_height do
        distance[i] = {}
        for j = 1, grid_width do
            distance[i][j] = grid[i][j] == 1 and 0 or -1 -- -1 means unvisited
        end
    end

    local queue = {}
    for i = 1, grid_height do
        for j = 1, grid_width do
            if grid[i][j] == 1 then
                table.insert(queue, {i, j})
            end
        end
    end

    local directions = {{0, 1}, {0, -1}, {1, 0}, {-1, 0}}
    while #queue > 0 do
        local cell = table.remove(queue, 1)
        local i, j = cell[1], cell[2]
        for _, dir in pairs(directions) do
            local ni, nj = i + dir[1], j + dir[2]
            if ni >= 1 and ni <= grid_height and nj >= 1 and nj <= grid_width and distance[ni][nj] == -1 then
                distance[ni][nj] = distance[i][j] + 1
                table.insert(queue, {ni, nj})
            end
        end
    end

    return distance
end

local function find_best_position(screen, window_width, window_height, cell_size, distance_map)
    local screen_frame = screen:frame()
    local grid_width = math.ceil(screen_frame.w / cell_size)
    local grid_height = math.ceil(screen_frame.h / cell_size)
    local window_grid_width = math.ceil(window_width / cell_size)
    local window_grid_height = math.ceil(window_height / cell_size)

    local best_score = -1
    local best_pos = {
        x = 0,
        y = 0
    }

    for i = 1, grid_height - window_grid_height + 1 do
        for j = 1, grid_width - window_grid_width + 1 do
            local min_distance = math.huge
            for di = 0, window_grid_height - 1 do
                for dj = 0, window_grid_width - 1 do
                    local dist = distance_map[i + di][j + dj]
                    if dist < min_distance then
                        min_distance = dist
                    end
                end
            end
            if min_distance > best_score then
                best_score = min_distance
                best_pos = {
                    x = (j - 1) * cell_size,
                    y = (i - 1) * cell_size
                }
            end
        end
    end

    return best_pos
end

-- Add this new function for handling problematic apps
function apply_frame_to_problem_app(window, frame, app_name)
    debug_log("Using special handling for app:", app_name)

    -- Strategy 1: Multiple attempts with delays
    local max_attempts = 10

    -- First attempt with animation
    local saved_duration = hs.window.animationDuration
    hs.window.animationDuration = 0.01
    window:setFrame(frame)
    hs.window.animationDuration = saved_duration

    -- Additional attempts if needed
    for attempt = 2, max_attempts do
        hs.timer.doAfter((attempt - 1) * 0.1, function()
            -- Check if the window moved from where we put it
            local current_frame = window:frame()
            if current_frame.x ~= frame.x or current_frame.y ~= frame.y or current_frame.w ~= frame.w or current_frame.h ~=
                frame.h then
                debug_log("Detected position change, forcing position (attempt " .. attempt .. ")")
                window:setFrame(frame)
            end
        end)
    end

    -- Final verification with a longer delay
    hs.timer.doAfter(0.5, function()
        local final_frame = window:frame()
        if final_frame.x ~= frame.x or final_frame.y ~= frame.y or final_frame.w ~= frame.w or final_frame.h ~= frame.h then
            debug_log("Final position check failed, forcing position one last time")
            window:setFrame(frame)

            -- Log the final position for debugging
            hs.timer.doAfter(0.1, function()
                local result_frame = window:frame()
                debug_log(
                    "Final position: x=" .. result_frame.x .. ", y=" .. result_frame.y .. ", w=" .. result_frame.w ..
                        ", h=" .. result_frame.h)
            end)
        end
    end)
end

-- Replace the existing Zone:resize_window function with this one
function Zone:resize_window(window_id)
    local tile_idx = self.window_to_tile_idx[window_id]
    if not tile_idx then
        debug_log("Cannot resize window", window_id, "- not in zone", self.id)
        return false
    end

    local tile = self.tiles[tile_idx]
    if not tile then
        debug_log("Invalid tile index", tile_idx, "for window", window_id)
        return false
    end

    local window = hs.window.get(window_id)
    if not window then
        debug_log("Cannot find window with ID", window_id)
        return false
    end

    -- Get the screen for this zone
    local target_screen = self.screen
    if not target_screen then
        -- Fallback to current screen if zone doesn't have one assigned
        target_screen = window:screen()
        debug_log("Zone has no screen assigned, using window's current screen:", target_screen:name())
    end

    -- Get the application name for special handling check
    local app_name = window:application():name()
    local needs_special_handling = is_problem_app(app_name)

    -- Apply the tile dimensions to the window on the correct screen
    -- For portrait monitor with negative coordinates, explicitly move to screen first
    local screen_name = target_screen:name()
    local is_portrait = target_screen:frame().h > target_screen:frame().w
    local has_negative_coords = target_screen:frame().x < 0 or target_screen:frame().y < 0

    -- Create the frame that will be applied
    local frame = {
        x = tile.x,
        y = tile.y,
        w = tile.width,
        h = tile.height
    }

    if is_portrait and has_negative_coords then
        -- Special handling for portrait monitors with negative coordinates
        debug_log("Special handling for portrait monitor:", screen_name)

        -- Force move to the screen first to ensure we're on the right screen
        window:moveToScreen(target_screen, false, false, 0)

        -- Then set the position - use a very short delay to ensure the window has time to move
        hs.timer.doAfter(0.05, function()
            debug_log("Setting frame with delay for window", window_id, "to", tile:to_string(), "on screen",
                target_screen:name())

            if needs_special_handling then
                -- Special handling for problem apps
                apply_frame_to_problem_app(window, frame, app_name)
            else
                -- Normal handling
                window:setFrame(frame)
            end
        end)
    else
        -- Normal case - set frame directly
        debug_log("Setting frame for window", window_id, "to", tile:to_string(), "on screen", target_screen:name())

        if needs_special_handling then
            -- Special handling for problem apps
            apply_frame_to_problem_app(window, frame, app_name)
        else
            -- Normal handling
            window:setFrame(frame)
        end
    end

    return true
end

-- Register the zone with the Tiler
function Zone:register()
    -- Create a unique zone ID that includes the screen
    local full_id = self.id
    if self.screen then
        -- Add screen ID to make it unique, but keep original ID for hotkey referencing
        full_id = self.id .. "_" .. self.screen:id()
    end

    tiler._zone_id2zone[full_id] = self

    -- Also register with the simple ID, if not already registered
    -- This ensures that hotkeys will find a zone even if they don't specify a screen
    if not tiler._zone_id2zone[self.id] then
        tiler._zone_id2zone[self.id] = self
    end

    debug_log("Registered zone", full_id)

    -- Set up the hotkey for this zone
    if self.hotkey then
        hs.hotkey.bind(self.hotkey[1], self.hotkey[2], function()
            activate_move_zone(self.id)
        end)
        debug_log("Bound hotkey", self.hotkey[1], self.hotkey[2], "to zone", self.id)

        -- Focus hotkey for switching between windows in this zone
        local focus_modifier = tiler.config.focus_modifier or {"shift", "ctrl", "cmd"}
        hs.hotkey.bind(focus_modifier, self.hotkey[2], function()
            focus_zone_windows(self.id)
        end)
        debug_log("Bound focus hotkey", focus_modifier, self.hotkey[2], "to zone", self.id)
    end

    return self -- For method chaining
end

-- Table to store window positions for each screen
tiler._screen_memory = {} -- Format: [window_id][screen_id] = {zone_id, tile_idx}
tiler._window_state = {} -- Global tracking of window state
tiler._zone_windows = {} -- Maps zone IDs to arrays of window IDs
tiler._window_focus_idx = {} -- Initialize focus tracking table
tiler._position_group_idx = {} -- Tracks which position group was last focused

--------------------------
-- Core Functions
--------------------------

-- Calculate tile position from grid coordinates
local function calculate_tile_position(screen, col_start, row_start, col_end, row_end, rows, cols)
    local frame = screen:frame()
    local w = frame.w
    local h = frame.h
    local x = frame.x
    local y = frame.y

    -- Get margin settings
    local use_margins = tiler.config.margins.enabled
    local margin_size = tiler.config.margins.size or 0
    local screen_edge_margins = tiler.config.margins.screen_edge

    -- Add debugging for portrait monitors
    local is_portrait = h > w
    if is_portrait then
        debug_log(string.format("Portrait monitor detected: %s (%.1f x %.1f)", screen:name(), w, h))
    end

    -- Calculate grid cell dimensions
    local col_width = w / cols
    local row_height = h / rows

    -- Calculate absolute position and size without margins
    local tile_x = x + (col_start - 1) * col_width
    local tile_y = y + (row_start - 1) * row_height
    local tile_width = (col_end - col_start + 1) * col_width
    local tile_height = (row_end - row_start + 1) * row_height

    -- Apply margins if enabled
    if use_margins then
        -- Apply screen edge margins if enabled
        if screen_edge_margins then
            -- Left edge
            if col_start == 1 then
                tile_x = tile_x + margin_size
                tile_width = tile_width - margin_size
            end

            -- Top edge
            if row_start == 1 then
                tile_y = tile_y + margin_size
                tile_height = tile_height - margin_size
            end

            -- Right edge
            if col_end == cols then
                tile_width = tile_width - margin_size
            end

            -- Bottom edge
            if row_end == rows then
                tile_height = tile_height - margin_size
            end
        end

        -- Apply internal margins between cells
        -- Only subtract from width if this isn't the rightmost column
        if col_end < cols then
            tile_width = tile_width - margin_size
        end

        -- Only subtract from height if this isn't the bottom row
        if row_end < rows then
            tile_height = tile_height - margin_size
        end

        -- Add margin to x position if not in the leftmost column
        if col_start > 1 and not screen_edge_margins then
            tile_x = tile_x + margin_size
            tile_width = tile_width - margin_size
        end

        -- Add margin to y position if not in the top row
        if row_start > 1 and not screen_edge_margins then
            tile_y = tile_y + margin_size
            tile_height = tile_height - margin_size
        end
    end

    -- Ensure tiles stay within screen bounds
    if tile_x + tile_width > x + w then
        tile_width = (x + w) - tile_x
    end

    if tile_y + tile_height > y + h then
        tile_height = (y + h) - tile_y
    end

    -- Log the calculation details for debugging
    if tiler.config.debug then
        print(string.format(
            "[TilerDebug] Grid calc: screen %s, cell=%.1fx%.1f, position=%.1f,%.1f to %.1f,%.1f → x=%.1f, y=%.1f, w=%.1f, h=%.1f",
            screen:name(), col_width, row_height, col_start, row_start, col_end, row_end, tile_x, tile_y, tile_width,
            tile_height))
    end

    return {
        x = tile_x,
        y = tile_y,
        width = tile_width,
        height = tile_height
    }
end

-- Handle moving a window to a zone or cycling its tile
-- This is made global (non-local) so hotkey callbacks can access it
function activate_move_zone(zone_id)
    debug_log("Activating zone", zone_id)

    -- Get focused window
    local win = hs.window.focusedWindow()
    if not win then
        debug_log("No focused window")
        return
    end

    local win_id = win:id()
    local current_screen = win:screen()
    local current_screen_id = current_screen:id()
    local screen_name = current_screen:name()

    debug_log("Window is on screen: " .. screen_name .. " (ID: " .. current_screen_id .. ")")

    -- First look for zones that match our ID and are specifically on this screen
    local target_zone = nil

    -- First try to find a screen-specific match (like "y_4")
    local screen_specific_id = zone_id .. "_" .. current_screen_id
    if tiler._zone_id2zone[screen_specific_id] then
        debug_log("Found exact screen-specific match: " .. screen_specific_id)
        target_zone = tiler._zone_id2zone[screen_specific_id]
    else
        -- Look for any zone with this ID on this screen
        for id, zone in pairs(tiler._zone_id2zone) do
            if zone.screen and zone.screen:id() == current_screen_id then
                if id == zone_id or id:match("^" .. zone_id .. "_%d+$") then
                    debug_log("Found zone match on current screen: " .. id)
                    target_zone = zone
                    break
                end
            end
        end
    end

    -- If no zones found on current screen, give up
    if not target_zone then
        debug_log("No matching zones found on current screen. Not moving window.")
        return
    end

    -- At this point we have a valid target zone
    debug_log("Using zone: " .. target_zone.id .. " on screen: " .. screen_name)

    -- Check where the window is currently
    local current_zone_id = nil

    -- Check the global state first
    if tiler._window_state[win_id] and tiler._window_state[win_id].zone_id then
        current_zone_id = tiler._window_state[win_id].zone_id
        debug_log("Found window in global state tracker: zone", current_zone_id)
    else
        -- Fall back to the original tracking
        current_zone_id = tiler._window_id2zone_id[win_id]
    end

    -- Check if window is actually in this zone (sanity check)
    local is_in_zone = false
    if target_zone.window_to_tile_idx and target_zone.window_to_tile_idx[win_id] ~= nil then
        is_in_zone = true
    end

    -- Ensure consistent state
    if (current_zone_id == target_zone.id) ~= is_in_zone then
        debug_log("Inconsistent state detected: id match =", (current_zone_id == target_zone.id), "is_in_zone =",
            is_in_zone, "- repairing")

        -- If it claims to be in this zone but isn't, add it
        if current_zone_id == target_zone.id and not is_in_zone then
            target_zone.window_to_tile_idx[win_id] = 0
        end

        -- If it's in this zone but not tracked, update tracking
        if is_in_zone and current_zone_id ~= target_zone.id then
            tiler._window_id2zone_id[win_id] = target_zone.id

            if not tiler._window_state[win_id] then
                tiler._window_state[win_id] = {}
            end
            tiler._window_state[win_id].zone_id = target_zone.id
        end
    end

    -- Handle the three possible cases
    if not current_zone_id then
        -- Window is not in any zone, add it to the target zone
        debug_log("Adding window", win_id, "to zone", target_zone.id)
        target_zone:add_window(win_id)
    elseif current_zone_id ~= target_zone.id then
        -- Window is in a different zone, move it to the target zone
        debug_log("Moving window", win_id, "from zone", current_zone_id, "to zone", target_zone.id)

        -- Find and remove from the old zone
        for id, zone in pairs(tiler._zone_id2zone) do
            if zone.window_to_tile_idx and zone.window_to_tile_idx[win_id] ~= nil then
                debug_log("Removing window from zone", id)
                zone.window_to_tile_idx[win_id] = nil
            end
        end

        -- Add to the new zone
        target_zone:add_window(win_id)
    else
        -- Window already in this zone, rotate through tiles
        debug_log("Rotating window", win_id, "in zone", target_zone.id)
        target_zone:rotate_tile(win_id)
    end

    -- Apply the new tile dimensions
    target_zone:resize_window(win_id)

    -- For debugging, confirm the new position
    hs.timer.doAfter(0.1, function()
        local new_frame = win:frame()
        debug_log("Position after applying tile: " ..
                      string.format("x=%.1f, y=%.1f, w=%.1f, h=%.1f", new_frame.x, new_frame.y, new_frame.w, new_frame.h))
    end)
end

-- Handle window events (destruction, creation, etc.)
local function handle_window_event(win_obj, appName, event_name)
    debug_log("Window event:", event_name, "for app:", appName)

    if event_name == "windowDestroyed" and win_obj then
        local win_id = win_obj:id()
        local zone_id = tiler._window_id2zone_id[win_id]

        if zone_id then
            local zone = tiler._zone_id2zone[zone_id]
            if zone then
                debug_log("Window destroyed, removing from zone:", zone_id)
                zone:remove_window(win_id)
            end
        end

        -- Clean up from all zone tracking
        for zone_id, windows in pairs(tiler._zone_windows) do
            for i, wid in ipairs(windows) do
                if wid == win_id then
                    table.remove(windows, i)
                    debug_log("Cleaned up destroyed window", win_id, "from zone", zone_id)
                    break
                end
            end
        end

        -- Clean up focus tracking - safely check if table exists first
        if tiler._window_focus_idx then
            tiler._window_focus_idx[win_id] = nil
        end
    end
end

-- Handle windows when displays are changed
local function handle_display_change()
    debug_log("Screen configuration changed")

    -- Clear existing modes since screen positions may have changed
    tiler._modes = {}

    for _, screen in pairs(hs.screen.allScreens()) do
        local screen_id = screen:id()
        local screen_name = screen:name()
        debug_log("Processing screen:", screen_name, "ID:", screen_id)

        -- Check for custom configuration for this specific screen
        local mode_config
        if tiler.layouts.custom[screen_name] then
            debug_log("Using custom layout for screen:", screen_name)
            mode_config = tiler.layouts.custom[screen_name]
        else
            -- Use default configuration based on screen size
            local mode_type = get_mode_for_screen(screen)
            debug_log("Using default layout:", mode_type)
            mode_config = mode_type
        end

        -- Initialize mode for this screen
        init_mode(screen, mode_config)
    end

    -- Resize windows that are assigned to zones
    -- Use a delayed callback to ensure windows have settled after display change
    hs.timer.doAfter(0.5, function()
        for window_id, zone_id in pairs(tiler._window_id2zone_id) do
            local zone = tiler._zone_id2zone[zone_id]
            if zone then
                debug_log("Resizing window", window_id, "in zone", zone_id)
                zone:resize_window(window_id)
            end
        end
    end)
end

function focus_zone_windows(zone_id)
    debug_log("Focusing on windows in zone", zone_id)

    -- Get focused window
    local current_win = hs.window.focusedWindow()
    if not current_win then
        debug_log("No focused window")
        return
    end

    local current_win_id = current_win:id()
    local current_screen = current_win:screen()
    local current_screen_id = current_screen:id()
    local screen_name = current_screen:name()

    debug_log("Looking for zone", zone_id, "on screen", screen_name, "(ID:", current_screen_id, ")")

    -- Find the appropriate zone
    local screen_specific_id = zone_id .. "_" .. current_screen_id
    local target_zone_id = nil
    local target_zone = nil

    -- First try screen-specific zone
    if tiler._zone_id2zone[screen_specific_id] then
        target_zone_id = screen_specific_id
        target_zone = tiler._zone_id2zone[screen_specific_id]
        debug_log("Found exact screen-specific zone:", screen_specific_id)
    else
        -- Look for other matching zones on this screen
        for id, zone in pairs(tiler._zone_id2zone) do
            if zone.screen and zone.screen:id() == current_screen_id then
                if id == zone_id or id:match("^" .. zone_id .. "_") then
                    target_zone_id = id
                    target_zone = zone
                    debug_log("Found matching zone on current screen:", id)
                    break
                end
            end
        end
    end

    -- Fallback to base zone ID if needed
    if not target_zone and tiler._zone_id2zone[zone_id] then
        target_zone_id = zone_id
        target_zone = tiler._zone_id2zone[zone_id]
        debug_log("Using base zone (not screen-specific):", zone_id)
    end

    if not target_zone then
        debug_log("No matching zone found on screen", screen_name)
        return
    end

    -- Now we have a valid zone, check if it has tile definitions
    if target_zone.tile_count == 0 then
        debug_log("Zone has no tile definitions")
        return
    end

    -- Create a tracking key for this zone+screen combination
    local focus_key = target_zone_id .. "_screen_" .. current_screen_id

    -- Initialize focus index tracking if needed
    if not tiler._window_focus_idx then
        tiler._window_focus_idx = {}
    end

    -- Find all windows in this zone
    local zone_windows = {}

    -- 1. First check for windows explicitly assigned to this zone
    if tiler._zone_windows[target_zone_id] then
        for _, win_id in ipairs(tiler._zone_windows[target_zone_id]) do
            local win = hs.window.get(win_id)
            if win and win:isStandard() and not win:isMinimized() and win:screen():id() == current_screen_id then
                table.insert(zone_windows, win_id)
            end
        end
    end

    -- 2. Then, find windows that significantly overlap with the primary zone tile(s)
    local primary_tiles = {}

    -- Determine which tile positions are primary for this zone
    -- To do this, we'll get the first 1-2 tile configurations from the zone
    -- Since these represent the most common/characteristic configurations
    local tiles_to_check = math.min(2, target_zone.tile_count)
    for i = 0, tiles_to_check - 1 do
        if target_zone.tiles[i] then
            table.insert(primary_tiles, target_zone.tiles[i])
        end
    end

    -- We'll also specifically check if any tile index is assigned to current window
    -- and include that tile as well (if not already included)
    if target_zone.window_to_tile_idx and target_zone.window_to_tile_idx[current_win_id] ~= nil then
        local idx = target_zone.window_to_tile_idx[current_win_id]
        local found = false

        -- Check if this tile is already in primary_tiles
        for _, tile in ipairs(primary_tiles) do
            if tile == target_zone.tiles[idx] then
                found = true
                break
            end
        end

        if not found and target_zone.tiles[idx] then
            table.insert(primary_tiles, target_zone.tiles[idx])
        end
    end

    -- Check all windows for significant overlap with primary tiles
    local all_windows = hs.window.allWindows()
    for _, win in ipairs(all_windows) do
        if win:isStandard() and not win:isMinimized() and win:screen():id() == current_screen_id then
            local win_id = win:id()

            -- Skip if already in our list
            local already_included = false
            for _, existing_id in ipairs(zone_windows) do
                if existing_id == win_id then
                    already_included = true
                    break
                end
            end

            if not already_included then
                local win_frame = win:frame()

                -- Check each primary tile for significant overlap
                for _, tile in ipairs(primary_tiles) do
                    local overlap = calculate_overlap_percentage(win_frame, tile)

                    -- Only include windows with significant overlap (50% or more)
                    if overlap >= 0.5 then
                        table.insert(zone_windows, win_id)
                        break -- No need to check other tiles
                    end
                end
            end
        end
    end

    if #zone_windows == 0 then
        debug_log("No windows found in zone", target_zone_id, "on screen", screen_name)
        return
    end

    debug_log("Found", #zone_windows, "windows in zone", target_zone_id)

    -- Determine which window to focus next
    local next_win_idx = 1

    -- Check if current window is in the list
    local current_idx = nil
    for i, win_id in ipairs(zone_windows) do
        if win_id == current_win_id then
            current_idx = i
            break
        end
    end

    if current_idx then
        -- Move to next window in cycle
        next_win_idx = (current_idx % #zone_windows) + 1
        debug_log("Current window is in list at position", current_idx, "moving to", next_win_idx)
    else
        -- Current window not in list, use remembered index or start from beginning
        if tiler._window_focus_idx[focus_key] then
            next_win_idx = ((tiler._window_focus_idx[focus_key]) % #zone_windows) + 1
            debug_log("Using remembered index", next_win_idx)
        else
            debug_log("Starting from first window in list")
        end
    end

    -- Update remembered index
    tiler._window_focus_idx[focus_key] = next_win_idx

    -- Focus the next window
    local next_win_id = zone_windows[next_win_idx]
    local next_win = hs.window.get(next_win_id)

    if next_win then
        next_win:focus()
        debug_log("Focused window", next_win_id, "in zone", target_zone_id, "(", next_win_idx, "of", #zone_windows, ")")

        -- Visual feedback
        if tiler.config.flash_on_focus then
            local frame = next_win:frame()
            local flash = hs.canvas.new(frame):appendElements({
                type = "rectangle",
                action = "fill",
                fillColor = {
                    red = 0.5,
                    green = 0.5,
                    blue = 1.0,
                    alpha = 0.3
                }
            })
            flash:show()
            hs.timer.doAfter(0.2, function()
                flash:delete()
            end)
        end
    else
        debug_log("Failed to focus window", next_win_id, "- window may have been closed")
    end
end

-- Calculate what percentage of a window overlaps with a tile
function calculate_overlap_percentage(win_frame, tile)
    -- Get tile frame
    local tile_frame = {
        x = tile.x,
        y = tile.y,
        w = tile.width,
        h = tile.height
    }

    -- Calculate intersection
    local x_overlap = math.max(0, math.min(win_frame.x + win_frame.w, tile_frame.x + tile_frame.w) -
        math.max(win_frame.x, tile_frame.x))

    local y_overlap = math.max(0, math.min(win_frame.y + win_frame.h, tile_frame.y + tile_frame.h) -
        math.max(win_frame.y, tile_frame.y))

    -- Calculate overlap area and window area
    local overlap_area = x_overlap * y_overlap
    local win_area = win_frame.w * win_frame.h

    -- Return overlap as percentage of window area
    if win_area > 0 then
        return overlap_area / win_area
    else
        return 0
    end
end
-- Function to move focus to next/previous screen
function tiler.focus_next_screen()
    debug_log("Moving focus to next screen")

    -- Get all screens
    local screens = hs.screen.allScreens()
    if #screens < 2 then
        debug_log("Only one screen detected, focus move canceled")
        return
    end

    -- Get current screen
    local current_screen = hs.screen.mainScreen()
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
        debug_log("Couldn't identify next screen")
        return
    end

    -- Find windows on the next screen
    local next_windows = {}
    local all_windows = hs.window.allWindows()

    for _, win in ipairs(all_windows) do
        if win:isStandard() and not win:isMinimized() and win:screen():id() == next_screen:id() then
            table.insert(next_windows, win)
        end
    end

    if #next_windows == 0 then
        debug_log("No windows found on next screen:", next_screen:name())
        return
    end

    -- Focus the frontmost window on that screen
    table.sort(next_windows, function(a, b)
        return a:id() > b:id() -- Usually more recent windows have higher IDs
    end)

    next_windows[1]:focus()
    debug_log("Focused window", next_windows[1]:id(), "on screen", next_screen:name())
end

function tiler.focus_previous_screen()
    debug_log("Moving focus to previous screen")

    -- Get all screens
    local screens = hs.screen.allScreens()
    if #screens < 2 then
        debug_log("Only one screen detected, focus move canceled")
        return
    end

    -- Get current screen
    local current_screen = hs.screen.mainScreen()
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
        debug_log("Couldn't identify previous screen")
        return
    end

    -- Find windows on the previous screen
    local prev_windows = {}
    local all_windows = hs.window.allWindows()

    for _, win in ipairs(all_windows) do
        if win:isStandard() and not win:isMinimized() and win:screen():id() == prev_screen:id() then
            table.insert(prev_windows, win)
        end
    end

    if #prev_windows == 0 then
        debug_log("No windows found on previous screen:", prev_screen:name())
        return
    end

    -- Focus the frontmost window on that screen
    table.sort(prev_windows, function(a, b)
        return a:id() > b:id() -- Usually more recent windows have higher IDs
    end)

    prev_windows[1]:focus()
    debug_log("Focused window", prev_windows[1]:id(), "on screen", prev_screen:name())
end

-- Function to set up screen focus movement hotkeys
function tiler.setup_screen_focus_keys()
    hs.hotkey.bind(tiler.config.focus_modifier, "p", tiler.focus_next_screen)
    hs.hotkey.bind(tiler.config.focus_modifier, ";", tiler.focus_previous_screen)
    debug_log("Screen focus movement keys set up")
end

-- Determine which layout mode to use based on screen properties
function get_mode_for_screen(screen)
    local screen_frame = screen:frame()
    local width = screen_frame.w
    local height = screen_frame.h
    local is_portrait = height > width

    debug_log(string.format("Screen dimensions: %.1f x %.1f", width, height))

    -- Get screen name for better identification
    local screen_name = screen:name()
    debug_log("Screen name: " .. screen_name)

    -- First check if there's a custom layout for this specific screen
    if tiler.layouts.custom[screen_name] then
        local config = tiler.layouts.custom[screen_name]
        debug_log("Using custom layout for screen:", screen_name)
        return config
    end

    -- Check for pattern matches in screen name
    for pattern, layout in pairs(config.tiler.screen_detection.patterns) do
        if screen_name:match(pattern) then
            debug_log("Matched screen pattern: " .. pattern .. " - using layout", layout.cols .. "x" .. layout.rows)
            return layout
        end
    end

    -- Try to extract screen size from name
    local size_pattern = "(%d+)[%s%-]?inch"
    local size_match = screen_name:match(size_pattern)

    if size_match then
        local screen_size = tonumber(size_match)
        debug_log("Extracted screen size from name: " .. screen_size .. " inches")

        if is_portrait then
            -- Portrait mode layouts
            for _, size_config in pairs(config.tiler.screen_detection.portrait) do
                if (size_config.min and screen_size >= size_config.min) or
                    (size_config.max and screen_size <= size_config.max) or
                    (size_config.min and size_config.max and screen_size >= size_config.min and screen_size <=
                        size_config.max) then
                    debug_log("Using portrait layout: " .. size_config.layout)
                    return size_config.layout
                end
            end
        else
            -- Landscape mode layouts
            for _, size_config in pairs(config.tiler.screen_detection.sizes) do
                if (size_config.min and screen_size >= size_config.min) or
                    (size_config.max and screen_size <= size_config.max) or
                    (size_config.min and size_config.max and screen_size >= size_config.min and screen_size <=
                        size_config.max) then
                    debug_log("Using landscape layout: " .. size_config.layout)
                    return size_config.layout
                end
            end
        end
    end

    -- Fallback to resolution-based detection
    if is_portrait then
        -- Portrait orientation
        if width >= 1440 or height >= 2560 then
            debug_log("High-resolution portrait screen - using 1x3 layout")
            return "1x3"
        else
            debug_log("Standard portrait screen - using 1x2 layout")
            return "1x2"
        end
    else
        -- Landscape orientation
        local aspect_ratio = width / height
        local is_ultrawide = aspect_ratio > 2.0

        if width >= 3840 or height >= 2160 then
            -- 4K or higher
            debug_log("Detected 4K or higher resolution - using 4x3 layout")
            return "4x3"
        elseif width >= 3440 or is_ultrawide then
            -- Ultrawide or similar
            debug_log("Detected ultrawide monitor - using 4x2 layout")
            return "4x2"
        elseif width >= 2560 or height >= 1440 then
            -- QHD/WQHD (1440p) or similar
            debug_log("Detected 1440p resolution - using 3x3 layout")
            return "3x3"
        elseif width >= 1920 or height >= 1080 then
            -- Full HD (1080p) or similar
            debug_log("Detected 1080p resolution - using 3x2 layout")
            return "3x2"
        else
            -- Smaller resolutions
            debug_log("Detected smaller resolution - using 2x2 layout")
            return "2x2"
        end
    end
end

--------------------------
-- Layout Initialization
--------------------------

-- Define keyboard layout for auto-mapping
local keyboard_layouts = {
    -- Define rows of keys for easy grid mapping
    number_row = {"6", "7", "8", "9", "0"},
    top_row = {"y", "u", "i", "o", "p"},
    home_row = {"h", "j", "k", "l", ";"},
    bottom_row = {"n", "m", ",", ".", "/"}
}

-- Creates a 2D array of key mappings based on the keyboard layout
function create_key_map(rows, cols)
    local mapping = {}
    local available_rows = {keyboard_layouts.top_row, keyboard_layouts.home_row, keyboard_layouts.bottom_row,
                            keyboard_layouts.number_row}

    -- Ensure we don't exceed available keys
    rows = math.min(rows, #available_rows)
    cols = math.min(cols, 5) -- Max 5 columns from each row

    debug_log("Creating key map for", rows, "×", cols, "grid")

    for r = 1, rows do
        mapping[r] = {}
        local key_row = available_rows[r]
        for c = 1, cols do
            mapping[r][c] = key_row[c]
        end
    end

    return mapping
end
-- Create a tile based on grid coordinates
local function create_tile_from_grid_coords(screen, grid_coords, rows, cols)
    -- Get the screen's absolute frame
    local display_rect = screen:frame()
    local w = display_rect.w
    local h = display_rect.h
    local x = display_rect.x
    local y = display_rect.y

    if tiler.config.debug then
        print(string.format("[TilerDebug] Creating tile on screen %s with frame: x=%.1f, y=%.1f, w=%.1f, h=%.1f",
            screen:name(), x, y, w, h))
    end

    -- Parse grid coordinates like "a1:b2" (top-left to bottom-right)
    local col_start, row_start, col_end, row_end

    -- Handle different coordinate formats
    if type(grid_coords) == "string" then
        -- Named positions
        if grid_coords == "full" then
            return {
                x = x,
                y = y,
                width = w,
                height = h,
                description = "Full screen"
            }
        elseif grid_coords == "center" then
            return {
                x = x + w / 4,
                y = y + h / 4,
                width = w / 2,
                height = h / 2,
                description = "Center"
            }
        elseif grid_coords == "left-half" then
            return {
                x = x,
                y = y,
                width = w / 2,
                height = h,
                description = "Left half"
            }
        elseif grid_coords == "right-half" then
            return {
                x = x + w / 2,
                y = y,
                width = w / 2,
                height = h,
                description = "Right half"
            }
        elseif grid_coords == "top-half" then
            return {
                x = x,
                y = y,
                width = w,
                height = h / 2,
                description = "Top half"
            }
        elseif grid_coords == "bottom-half" then
            return {
                x = x,
                y = y + h / 2,
                width = w,
                height = h / 2,
                description = "Bottom half"
            }
        end

        -- Parse string format like "a1:b2" or "a1"
        local pattern = "([a-z])([0-9]+):?([a-z]?)([0-9]*)"
        local col_start_char, row_start_str, col_end_char, row_end_str = grid_coords:match(pattern)

        if not col_start_char or not row_start_str then
            debug_log("Invalid grid coordinates:", grid_coords)
            return nil
        end

        -- Convert column letters to numbers (a=1, b=2, etc.)
        col_start = string.byte(col_start_char) - string.byte('a') + 1
        row_start = tonumber(row_start_str)

        -- If end coordinates not provided, use start coords to create a single cell
        if col_end_char == "" or row_end_str == "" then
            col_end = col_start
            row_end = row_start
        else
            col_end = string.byte(col_end_char) - string.byte('a') + 1
            row_end = tonumber(row_end_str)
        end

        -- Ensure coordinates don't exceed grid bounds
        col_start = math.max(1, math.min(col_start, cols))
        row_start = math.max(1, math.min(row_start, rows))
        col_end = math.max(1, math.min(col_end, cols))
        row_end = math.max(1, math.min(row_end, rows))
    elseif type(grid_coords) == "table" then
        -- Parse table format like {col_start, row_start, col_end, row_end}
        col_start = grid_coords[1]
        row_start = grid_coords[2]
        col_end = grid_coords[3] or col_start
        row_end = grid_coords[4] or row_start

        -- Ensure coordinates don't exceed grid bounds
        col_start = math.max(1, math.min(col_start, cols))
        row_start = math.max(1, math.min(row_start, rows))
        col_end = math.max(1, math.min(col_end, cols))
        row_end = math.max(1, math.min(row_end, rows))
    else
        debug_log("Invalid grid coordinates format:", grid_coords)
        return nil
    end

    -- Calculate pixel coordinates using our helper function
    local tile_pos = calculate_tile_position(screen, col_start, row_start, col_end, row_end, rows, cols)

    -- Add the description to the returned table
    tile_pos.description = grid_coords

    return tile_pos
end

-- Get all tiles for a zone configuration
local function get_zone_tiles(screen, zone_key, rows, cols)
    -- Get the screen name
    local screen_name = screen:name()
    local config_entry = nil

    -- First check if there are screen-specific configurations
    if tiler.zone_configs_by_screen then
        -- Check if there's a config for this specific screen
        if tiler.zone_configs_by_screen[screen_name] and tiler.zone_configs_by_screen[screen_name][zone_key] then
            config_entry = tiler.zone_configs_by_screen[screen_name][zone_key]
            debug_log("Using screen-specific zone config for " .. screen_name .. ", key: " .. zone_key)
        end
    end

    -- If no screen-specific config found, check general zone configs
    if not config_entry then
        config_entry = tiler.zone_configs[zone_key] or tiler.zone_configs["default"]
    end

    -- If the config is an empty table, return empty tiles
    if config_entry and #config_entry == 0 then
        debug_log("Zone " .. zone_key .. " disabled for screen " .. screen_name)
        return {}
    end

    -- Process the tiles
    local tiles = {}

    for _, coords in ipairs(config_entry) do
        local tile = create_tile_from_grid_coords(screen, coords, rows, cols)
        if tile then
            table.insert(tiles, tile)
        end
    end

    return tiles
end

-- Create a grid layout for a screen
local function create_grid_layout(screen, cols, rows, key_map, modifier)
    local display_rect = screen:frame()
    local w = display_rect.w
    local h = display_rect.h
    local x = display_rect.x
    local y = display_rect.y

    -- Store the screen reference for later use
    local screen_id = screen:id()
    local screen_name = screen:name()

    -- Calculate dimensions for a regular grid
    local col_width = w / cols
    local row_height = h / rows

    debug_log("Grid cell size:", col_width, "×", row_height)

    local zones = {}

    -- Create a zone for each grid cell
    for r = 1, rows do
        for c = 1, cols do
            local zone_id = key_map[r][c] or (r .. "_" .. c)
            local key = key_map[r][c]

            if key then
                local hotkey = modifier and key and {modifier, key}
                debug_log("Creating zone", zone_id, "with hotkey", key)

                local zone = Zone.new(zone_id, hotkey, screen):set_description(string.format(
                    "Row %d, Col %d - Screen: %s", r, c, screen:name()))

                -- Get tile configurations for this zone
                local zone_tiles = get_zone_tiles(screen, key, rows, cols)

                -- Add each tile to the zone
                for _, tile in ipairs(zone_tiles) do
                    zone:add_tile(tile.x, tile.y, tile.width, tile.height, tile.description)
                end

                -- If no tiles were added, add a default one
                if zone.tile_count == 0 then
                    local zone_x = x + (c - 1) * col_width
                    local zone_y = y + (r - 1) * row_height
                    zone:add_tile(zone_x, zone_y, col_width, row_height, "Default size")
                end

                zone:register()
                table.insert(zones, zone)
            end
        end
    end

    -- Create special zone for center
    local center_key = "0"
    local center_zone = Zone.new("center", {modifier, center_key}, screen):set_description("Center zone - Screen: " ..
                                                                                               screen:name())

    local center_tiles = get_zone_tiles(screen, "0", rows, cols)
    for _, tile in ipairs(center_tiles) do
        center_zone:add_tile(tile.x, tile.y, tile.width, tile.height, tile.description)
    end

    -- Add default center tiles if none were configured
    if center_zone.tile_count == 0 then
        center_zone:add_tile(x + w / 4, y + h / 4, w / 2, h / 2, "Center")
        center_zone:add_tile(x + w / 6, y + h / 6, w * 2 / 3, h * 2 / 3, "Large center")
        center_zone:add_tile(x, y, w, h, "Full screen")
    end

    center_zone:register()
    table.insert(zones, center_zone)

    local mode = {
        screen_id = screen:id(),
        cols = cols,
        rows = rows,
        zones = zones
    }

    tiler._modes[screen:id()] = mode
    return mode
end

function init_mode(screen, mode_config)
    local grid_cols, grid_rows, key_map, modifier

    if type(mode_config) == "string" then
        -- Parse a simple configuration like "3x3"
        local cols, rows = mode_config:match("(%d+)x(%d+)")
        grid_cols = tonumber(cols) or 3
        grid_rows = tonumber(rows) or 3
        key_map = create_key_map(grid_rows, grid_cols)
        modifier = tiler.config.modifier
    elseif type(mode_config) == "table" then
        -- Use detailed configuration
        grid_cols = mode_config.cols or 3
        grid_rows = mode_config.rows or 3
        key_map = mode_config.key_map or create_key_map(grid_rows, grid_cols)
        modifier = mode_config.modifier or tiler.config.modifier
    else
        -- Default to 3x3 grid
        grid_cols = 3
        grid_rows = 3
        key_map = create_key_map(grid_rows, grid_cols)
        modifier = tiler.config.modifier
    end

    debug_log("Initializing", grid_cols, "×", grid_rows, "grid for screen", screen:name())

    -- Create the grid layout
    return create_grid_layout(screen, grid_cols, grid_rows, key_map, modifier)
end

--------------------------
-- Initialization
--------------------------

-- Initialize event listeners
local function init_listeners()
    debug_log("Initializing event listeners")

    -- Window event filter
    tiler._window_watcher = hs.window.filter.new()
    tiler._window_watcher:setDefaultFilter{}
    tiler._window_watcher:setSortOrder(hs.window.filter.sortByFocusedLast)

    -- Subscribe to window events
    tiler._window_watcher:subscribe(hs.window.filter.windowDestroyed, handle_window_event)

    -- Subscribe to window creation for smart placement
    tiler._window_watcher:subscribe(hs.window.filter.windowCreated, function(win)
        if tiler.smart_placement then
            -- Smart placement logic
            local screen = win:screen()
            local cell_size = 50 -- Grid size for placement calculation
            local distance_map = compute_distance_map(screen, cell_size) -- Function to map occupied areas
            local frame = win:frame()
            local pos = find_best_position(screen, frame.w, frame.h, cell_size, distance_map) -- Find least cluttered spot
            win:setFrame({
                x = pos.x,
                y = pos.y,
                w = frame.w,
                h = frame.h
            })
        end
    end)

    -- Screen change events
    hs.screen.watcher.new(handle_display_change):start()
end

-- Configure a custom layout for a screen
function tiler.configure_screen(screen_name, config)
    debug_log("Setting custom configuration for screen:", screen_name)
    tiler.layouts.custom[screen_name] = config

    -- If the screen is currently connected, apply the config immediately
    for _, screen in pairs(hs.screen.allScreens()) do
        if screen:name() == screen_name then
            init_mode(screen, config)
            break
        end
    end
end

-- Helper function to move window to screen and restore position
local function move_window_to_screen(win, target_screen)
    if not win or not target_screen then
        return false
    end

    local win_id = win:id()
    local target_screen_id = target_screen:id()

    -- First move the window to the target screen
    win:moveToScreen(target_screen)

    -- Check if we have a remembered position for this window on the target screen
    if tiler._screen_memory[win_id] and tiler._screen_memory[win_id][target_screen_id] then
        local memory = tiler._screen_memory[win_id][target_screen_id]
        local zone_id = memory.zone_id
        local tile_idx = memory.tile_idx

        debug_log("Restoring window", win_id, "to remembered position on screen", target_screen_id, "zone", zone_id,
            "tile", tile_idx)

        -- Find the zone (look for both simple ID and screen-specific ID)
        local target_zone = nil
        for id, zone in pairs(tiler._zone_id2zone) do
            if (id == zone_id or id:match("^" .. zone_id .. "_%d+$")) and zone.screen and zone.screen:id() ==
                target_screen_id then
                target_zone = zone
                break
            end
        end

        if target_zone then
            -- Remove the window from any current zone
            local current_zone_id = tiler._window_id2zone_id[win_id]
            if current_zone_id and tiler._zone_id2zone[current_zone_id] then
                tiler._zone_id2zone[current_zone_id]:remove_window(win_id)
            end

            -- Add to the remembered zone
            target_zone.window_to_tile_idx[win_id] = tile_idx
            tiler._window_id2zone_id[win_id] = target_zone.id

            -- Resize to the remembered tile
            target_zone:resize_window(win_id)

            return true
        end
    else
        debug_log("No remembered position for window", win_id, "on screen", target_screen_id)
    end

    -- If we reached here, either there's no remembered position or we couldn't restore it
    -- In this case, the window is moved to the target screen but not positioned
    return false
end

-- Function to move to next screen with position memory
function move_to_next_screen()
    local win = hs.window.focusedWindow()
    if not win then
        return
    end

    -- Get all screens
    local screens = hs.screen.allScreens()
    if #screens < 2 then
        return
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

    if next_screen then
        debug_log("Moving window to next screen: " .. next_screen:name())
        move_window_to_screen(win, next_screen)
    end
end

-- Function to move to previous screen with position memory
function move_to_previous_screen()
    local win = hs.window.focusedWindow()
    if not win then
        return
    end

    -- Get all screens
    local screens = hs.screen.allScreens()
    if #screens < 2 then
        return
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

    if prev_screen then
        debug_log("Moving window to previous screen: " .. prev_screen:name())
        move_window_to_screen(win, prev_screen)
    end
end

-- Function to set up screen movement hotkeys
function tiler.setup_screen_movement_keys()
    hs.hotkey.bind(tiler.config.modifier, "p", move_to_next_screen)
    hs.hotkey.bind(tiler.config.modifier, ";", move_to_previous_screen)
    debug_log("Screen movement keys set up")
end

-- Configure zone behavior
function tiler.configure_zone(zone_key, tile_configs)
    debug_log("Setting custom configuration for zone key:", zone_key)
    tiler.zone_configs[zone_key] = tile_configs

    -- Return a function that can be used to trigger a refresh
    -- (since we don't want to force a refresh on every config change)
    return function()
        handle_display_change()
    end
end
-- Map windows to zones based on their positions, with proper screen handling
function tiler.map_existing_windows()
    debug_log("Mapping existing windows to zones")

    -- Get all visible windows
    local all_windows = hs.window.allWindows()
    local mapped_count = 0

    -- Track zones by screen for better reporting
    local screen_mapped = {}

    for _, win in ipairs(all_windows) do
        -- Skip windows that are already mapped
        local win_id = win:id()
        if tiler._window_id2zone_id[win_id] then
            debug_log("Window", win_id, "already mapped to zone", tiler._window_id2zone_id[win_id])
            goto continue
        end

        -- Skip non-standard or minimized windows
        if not win:isStandard() or win:isMinimized() then
            goto continue
        end

        -- Get window position and screen
        local win_frame = win:frame()
        local win_screen = win:screen()
        if not win_screen then
            debug_log("Window", win_id, "has no screen, skipping")
            goto continue
        end

        local screen_id = win_screen:id()
        local screen_name = win_screen:name()
        local screen_frame = win_screen:frame()

        -- Find zones on this specific screen
        local screen_zones = {}
        for id, zone in pairs(tiler._zone_id2zone) do
            if zone.screen and zone.screen:id() == screen_id then
                table.insert(screen_zones, zone)
            end
        end

        if #screen_zones == 0 then
            debug_log("No zones found for screen", screen_name, "skipping window", win_id)
            goto continue
        end

        -- Find best matching zone based on window position
        local best_zone = nil
        local best_match_score = 0

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
                local overlap_area = calculate_overlap_area(win_frame, tile)

                -- Calculate percentage of window area that overlaps with tile
                local win_area = win_frame.w * win_frame.h
                local overlap_percentage = overlap_area / win_area

                -- Calculate center distance
                local win_center_x = win_frame.x + win_frame.w / 2
                local win_center_y = win_frame.y + win_frame.h / 2
                local tile_center_x = tile.x + tile.width / 2
                local tile_center_y = tile.y + tile.height / 2
                local center_distance = math.sqrt((win_center_x - tile_center_x) ^ 2 + (win_center_y - tile_center_y) ^
                                                      2)

                -- Normalize center distance to screen size
                local screen_diagonal = math.sqrt(screen_frame.w ^ 2 + screen_frame.h ^ 2)
                local normalized_distance = 1 - (center_distance / screen_diagonal)

                -- Combined score (70% overlap, 30% center proximity)
                local score = (overlap_percentage * 0.7) + (normalized_distance * 0.3)

                -- Check if this is best match so far
                if score > best_match_score and score > 0.5 then -- Must be at least 50% match
                    best_match_score = score
                    best_zone = zone
                    -- Remember the tile index for later
                    tiler._temp_best_tile_idx = i
                end

                ::next_tile::
            end

            ::next_zone::
        end

        -- Assign window to best matching zone if found
        if best_zone and best_match_score > 0 then
            debug_log("Mapping window", win_id, "to zone", best_zone.id, "with match score", best_match_score)

            -- Keep track of which screen this window was mapped on
            if not screen_mapped[screen_id] then
                screen_mapped[screen_id] = 0
            end
            screen_mapped[screen_id] = screen_mapped[screen_id] + 1

            -- Add window to zone
            best_zone:add_window(win_id)

            -- Set the tile index to the best matching one
            if tiler._temp_best_tile_idx then
                best_zone.window_to_tile_idx[win_id] = tiler._temp_best_tile_idx
                tiler._temp_best_tile_idx = nil
            end

            mapped_count = mapped_count + 1
        end

        ::continue::
    end

    -- Log mapping results by screen
    for screen_id, count in pairs(screen_mapped) do
        local screen_name = "Unknown"
        for _, screen in pairs(hs.screen.allScreens()) do
            if screen:id() == screen_id then
                screen_name = screen:name()
                break
            end
        end
        debug_log("Mapped", count, "windows on screen", screen_name)
    end

    debug_log("Mapped", mapped_count, "windows to zones total")
    return mapped_count
end

-- Helper function to calculate overlap area between window and tile
function calculate_overlap_area(win_frame, tile)
    -- Get tile frame
    local tile_frame = {
        x = tile.x,
        y = tile.y,
        w = tile.width,
        h = tile.height
    }

    -- Calculate intersection
    local x_overlap = math.max(0, math.min(win_frame.x + win_frame.w, tile_frame.x + tile_frame.w) -
        math.max(win_frame.x, tile_frame.x))

    local y_overlap = math.max(0, math.min(win_frame.y + win_frame.h, tile_frame.y + tile_frame.h) -
        math.max(win_frame.y, tile_frame.y))

    -- Return overlap area
    return x_overlap * y_overlap
end

function tiler.start()
    debug_log("Starting Tiler v" .. tiler._version)

    -- Load configuration from config.lua
    tiler.set_config()

    -- Log margin settings for debugging
    if tiler.config.debug then
        debug_log("Using margin settings: enabled=" .. tostring(tiler.config.margins.enabled) .. ", size=" ..
                      tostring(tiler.config.margins.size) .. ", screen_edge=" ..
                      tostring(tiler.config.margins.screen_edge))
    end

    -- Initialize the tiler
    init_listeners()

    -- Initialize layouts for all screens
    for _, screen in pairs(hs.screen.allScreens()) do
        local screen_name = screen:name()
        debug_log("Configuring screen:", screen_name)

        -- Check for custom configuration for this specific screen
        local mode_config
        if tiler.layouts.custom[screen_name] then
            debug_log("Using custom layout for screen:", screen_name)
            mode_config = tiler.layouts.custom[screen_name]
        else
            -- Use default configuration based on screen size
            local mode_type = get_mode_for_screen(screen)
            debug_log("Using default layout:", mode_type)
            mode_config = mode_type
        end

        init_mode(screen, mode_config)
    end

    -- Add keyboard shortcut to toggle debug mode
    hs.hotkey.bind({"ctrl", "cmd", "shift"}, "D", function()
        tiler.config.debug = not tiler.config.debug
        debug_log("Debug mode: " .. (tiler.config.debug and "enabled" or "disabled"))
    end)

    -- Map existing windows (with slight delay to ensure layouts are fully initialized)
    hs.timer.doAfter(0.5, function()
        tiler.map_existing_windows()
    end)

    debug_log("Tiler initialization complete")
    return tiler
end

-- Return the tiler object for configuration
return tiler
