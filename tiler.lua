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
local tiler = {
    -- Settings that can be modified by the user
    config = {
        debug = true, -- Enable debug logging
        modifier = {"ctrl", "cmd"} -- Default hotkey modifier
    },

    -- Internal state
    _version = "1.1.0",
    _window_id2zone_id = {}, -- Maps window ids to zone ids
    _zone_id2zone = {}, -- Maps zone ids to zone objects
    _modes = {}, -- Screen layout modes
    _window_watcher = nil, -- Window event watcher

    -- Public user configuration tables
    layouts = {
        -- Default layouts for different screen types
        default = {
            small = "2x2",
            medium = "3x2",
            large = "3x3",
            extra_large = "4x3"
        },

        -- Custom layouts for specific screens (by name)
        custom = {
            -- Example: ["DELL U3223QE"] = { cols = 4, rows = 3, modifier = {"ctrl", "alt"} }
        }
    },

    -- Zone configurations (can be modified by user)
    zone_configs = {}
}

-- Default configurations for each zone key
local DEFAULT_ZONE_CONFIGS = {
    -- Format: key = { array of grid coordinates to cycle through }

    -- Left side of keyboard - left side of screen
    ["y"] = {"a1:a2", "a1"}, -- Top-left region
    ["h"] = {"a1:b3", "a1:a3", "a1:c3"}, -- Left side in various widths
    ["n"] = {"a3", "a2:a3"}, -- Bottom-left corner/region
    ["u"] = {"b1:b3", "b1:b2", "b1"}, -- Middle column region variations
    ["j"] = {"b1:c3", "b1:b3", "b2"}, -- Middle area variations
    ["m"] = {"c1:c3", "c2:c3", "c3"}, -- Right-middle column variations

    -- Right side of keyboard - right side of screen
    ["i"] = {"d1:d3", "d1:d2", "d1"}, -- Right column variations
    ["k"] = {"c1:d3", "d1:d3", "c2"}, -- Right side variations
    [","] = {"d3", "d2:d3"}, -- Bottom-right corner/region
    ["o"] = {"d1", "c1:d1"}, -- Top-right cell/region
    ["l"] = {"d1:d3", "c1:d3"}, -- Right columns
    ["."] = {"c3:d3", "d3"}, -- Bottom-right region/cell

    -- Center key for center position
    ["0"] = {"b2:c2", "b1:c3", "a1:d3"}, -- Quarter, two-thirds, full screen

    -- Fallback for any key without specific config
    ["default"] = {"full", "center", "left-half", "right-half", "top-half", "bottom-half"}
}

-- Debug logging function
local function log(...)
    if tiler.config.debug then
        print("[TilerDebug]", ...)
    end
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
function Zone.new(id, hotkey)
    local self = setmetatable({}, Zone)
    self.id = id
    self.hotkey = hotkey
    self.tiles = {}
    self.tile_count = 0
    self.window_to_tile_idx = {}
    self.description = nil
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
    log("Added tile to zone", self.id, "total tiles:", self.tile_count,
        description and ("(" .. description .. ")") or "")
    return self -- For method chaining
end

-- Rotate a window through tile configurations
function Zone:rotate_tile(window_id)
    -- Initialize if window not already in this zone
    if not self.window_to_tile_idx[window_id] then
        self.window_to_tile_idx[window_id] = 0
        return 0
    end

    -- Advance to next tile configuration with wrap-around
    local next_idx = (self.window_to_tile_idx[window_id] + 1) % self.tile_count
    self.window_to_tile_idx[window_id] = next_idx

    local desc = ""
    if self.tiles[next_idx].description then
        desc = " - " .. self.tiles[next_idx].description
    end
    log("Rotated window", window_id, "to tile index", next_idx, "in zone", self.id, desc)
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
    if self.window_to_tile_idx[window_id] ~= nil then
        log("Window", window_id, "already in zone", self.id)
        return
    end

    -- Map the window to this zone and set first tile (index 0)
    self.window_to_tile_idx[window_id] = 0
    tiler._window_id2zone_id[window_id] = self.id
    log("Added window", window_id, "to zone", self.id)
end

-- Remove a window from this zone
function Zone:remove_window(window_id)
    if self.window_to_tile_idx[window_id] == nil then
        log("Window", window_id, "not in zone", self.id)
        return
    end

    log("Removing window", window_id, "from zone", self.id)
    self.window_to_tile_idx[window_id] = nil
    tiler._window_id2zone_id[window_id] = nil
end

-- Resize a window based on its current tile configuration
function Zone:resize_window(window_id)
    local tile_idx = self.window_to_tile_idx[window_id]
    if not tile_idx then
        log("Cannot resize window", window_id, "- not in zone", self.id)
        return false
    end

    local tile = self.tiles[tile_idx]
    if not tile then
        log("Invalid tile index", tile_idx, "for window", window_id)
        return false
    end

    local window = hs.window.get(window_id)
    if not window then
        log("Cannot find window with ID", window_id)
        return false
    end

    -- Apply the tile dimensions to the window
    log("Resizing window", window_id, "to", tile:to_string())
    window:setFrame({
        x = tile.x,
        y = tile.y,
        w = tile.width,
        h = tile.height
    })

    return true
end

-- Register the zone with the tiler
function Zone:register()
    tiler._zone_id2zone[self.id] = self
    log("Registered zone", self.id)

    -- Set up the hotkey for this zone
    if self.hotkey then
        hs.hotkey.bind(self.hotkey[1], self.hotkey[2], function()
            activate_move_zone(self.id)
        end)
        log("Bound hotkey", self.hotkey[1], self.hotkey[2], "to zone", self.id)
    end

    return self -- For method chaining
end

--------------------------
-- Core Functions
--------------------------

-- Handle moving a window to a zone or cycling its tile
local function activate_move_zone(zone_id)
    log("Activating zone", zone_id)

    -- Get focused window
    local win = hs.window.focusedWindow()
    if not win then
        log("No focused window")
        return
    end

    local win_id = win:id()

    -- Get the window's current zone
    local current_zone_id = tiler._window_id2zone_id[win_id]
    local zone = tiler._zone_id2zone[zone_id]

    if not zone then
        log("Zone", zone_id, "not found")
        return
    end

    if not current_zone_id then
        -- Window is not in any zone, add it to the target zone
        log("Adding window", win_id, "to zone", zone_id)
        zone:add_window(win_id)
    elseif current_zone_id ~= zone_id then
        -- Window is in a different zone, move it to the target zone
        local source_zone = tiler._zone_id2zone[current_zone_id]
        log("Moving window", win_id, "from zone", current_zone_id, "to zone", zone_id)

        if source_zone then
            source_zone:remove_window(win_id)
        end

        zone:add_window(win_id)
    else
        -- Window already in this zone, rotate through tiles
        log("Rotating window", win_id, "in zone", zone_id)
        zone:rotate_tile(win_id)
    end

    -- Apply the new tile dimensions
    zone:resize_window(win_id)
end

-- Handle window events (destruction, creation, etc.)
local function handle_window_event(win_obj, appName, event_name)
    log("Window event:", event_name, "for app:", appName)

    if event_name == "windowDestroyed" and win_obj then
        local win_id = win_obj:id()
        local zone_id = tiler._window_id2zone_id[win_id]

        if zone_id then
            local zone = tiler._zone_id2zone[zone_id]
            if zone then
                log("Window destroyed, removing from zone:", zone_id)
                zone:remove_window(win_id)
            end
        end
    end
end

-- Handle windows when displays are changed
local function handle_display_change()
    log("Screen configuration changed")

    -- Clear existing modes since screen positions may have changed
    tiler._modes = {}

    for _, screen in pairs(hs.screen.allScreens()) do
        local screen_id = screen:id()
        local screen_name = screen:name()
        log("Processing screen:", screen_name, "ID:", screen_id)

        -- Check for custom configuration for this specific screen
        local mode_config
        if tiler.layouts.custom[screen_name] then
            log("Using custom layout for screen:", screen_name)
            mode_config = tiler.layouts.custom[screen_name]
        else
            -- Use default configuration based on screen size
            local mode_type = get_mode_for_screen(screen)
            log("Using default layout:", mode_type)
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
                log("Resizing window", window_id, "in zone", zone_id)
                zone:resize_window(window_id)
            end
        end
    end)
end

-- Determine which layout mode to use based on screen properties
function get_mode_for_screen(screen)
    local screen_frame = screen:frame()
    local width = screen_frame.w
    local height = screen_frame.h

    log("Screen dimensions:", width, "x", height)

    -- Apply different grids based on screen size
    if width >= 3840 and height >= 2160 then
        return "4x3" -- 4K monitors get a 4×3 grid
    elseif width >= 2560 then
        return "3x3" -- Wide monitors get a 3×3 grid
    elseif width >= 1920 and height >= 1080 then
        return "3x2" -- Full HD gets a 3×2 grid
    else
        return "2x2" -- Smaller screens get a simple 2×2 grid
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

    log("Creating key map for", rows, "×", cols, "grid")

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
    local display_rect = screen:frame()
    local w = display_rect.w
    local h = display_rect.h
    local x = display_rect.x
    local y = display_rect.y

    local col_width = w / cols
    local row_height = h / rows

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
            log("Invalid grid coordinates:", grid_coords)
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
    elseif type(grid_coords) == "table" then
        -- Parse table format like {col_start, row_start, col_end, row_end}
        col_start = grid_coords[1]
        row_start = grid_coords[2]
        col_end = grid_coords[3] or col_start
        row_end = grid_coords[4] or row_start
    else
        log("Invalid grid coordinates format:", grid_coords)
        return nil
    end

    -- Calculate pixel coordinates
    local tile_x = x + (col_start - 1) * col_width
    local tile_y = y + (row_start - 1) * row_height
    local tile_width = (col_end - col_start + 1) * col_width
    local tile_height = (row_end - row_start + 1) * row_height

    return {
        x = tile_x,
        y = tile_y,
        width = tile_width,
        height = tile_height,
        description = grid_coords
    }
end

-- Get all tiles for a zone configuration
local function get_zone_tiles(screen, zone_key, rows, cols)
    -- Get the configuration for this key
    local config = tiler.zone_configs[zone_key] or DEFAULT_ZONE_CONFIGS[zone_key]

    -- If no specific config, use the default
    if not config then
        config = DEFAULT_ZONE_CONFIGS["default"]
    end

    local tiles = {}

    for _, coords in ipairs(config) do
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

    -- Calculate dimensions for a regular grid
    local col_width = w / cols
    local row_height = h / rows

    log("Grid cell size:", col_width, "×", row_height)

    local zones = {}

    -- Create a zone for each grid cell
    for r = 1, rows do
        for c = 1, cols do
            local zone_id = key_map[r][c] or (r .. "_" .. c)
            local key = key_map[r][c]

            if key then
                local hotkey = modifier and key and {modifier, key}
                log("Creating zone", zone_id, "with hotkey", key)

                local zone = Zone.new(zone_id, hotkey):set_description(string.format("Row %d, Col %d", r, c))

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
    local center_zone = Zone.new("center", {modifier, center_key}):set_description("Center zone")

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

-- Initialize a screen layout mode using a configuration
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

    log("Initializing", grid_cols, "×", grid_rows, "grid for screen", screen:name())

    -- Create the grid layout
    return create_grid_layout(screen, grid_cols, grid_rows, key_map, modifier)
end

--------------------------
-- Initialization
--------------------------

-- Initialize event listeners
local function init_listeners()
    log("Initializing event listeners")

    -- Window event filter
    tiler._window_watcher = hs.window.filter.new()
    tiler._window_watcher:setDefaultFilter{}
    tiler._window_watcher:setSortOrder(hs.window.filter.sortByFocusedLast)

    -- Subscribe to window events
    tiler._window_watcher:subscribe(hs.window.filter.windowDestroyed, handle_window_event)

    -- Screen change events
    hs.screen.watcher.new(handle_display_change):start()
end

-- Initialize the tiler
local function init()
    log("Initializing Tiler v" .. tiler._version)

    -- Set up event listeners
    init_listeners()

    -- Initialize layouts for all screens
    for _, screen in pairs(hs.screen.allScreens()) do
        local screen_name = screen:name()
        log("Configuring screen:", screen_name)

        -- Check for custom configuration for this specific screen
        local mode_config
        if tiler.layouts.custom[screen_name] then
            log("Using custom layout for screen:", screen_name)
            mode_config = tiler.layouts.custom[screen_name]
        else
            -- Use default configuration based on screen size
            local mode_type = get_mode_for_screen(screen)
            log("Using default layout:", mode_type)
            mode_config = mode_type
        end

        init_mode(screen, mode_config)
    end

    -- Add keyboard shortcut to toggle debug mode
    hs.hotkey.bind({"ctrl", "cmd", "shift"}, "D", function()
        tiler.config.debug = not tiler.config.debug
        log("Debug mode: " .. (tiler.config.debug and "enabled" or "disabled"))
    end)

    log("Tiler initialization complete")
end

-- Configure a custom layout for a screen
function tiler.configure_screen(screen_name, config)
    log("Setting custom configuration for screen:", screen_name)
    tiler.layouts.custom[screen_name] = config

    -- If the screen is currently connected, apply the config immediately
    for _, screen in pairs(hs.screen.allScreens()) do
        if screen:name() == screen_name then
            init_mode(screen, config)
            break
        end
    end
end

-- Configure zone behavior
function tiler.configure_zone(zone_key, tile_configs)
    log("Setting custom configuration for zone key:", zone_key)
    tiler.zone_configs[zone_key] = tile_configs

    -- Return a function that can be used to trigger a refresh
    -- (since we don't want to force a refresh on every config change)
    return function()
        handle_display_change()
    end
end

-- Start the tiler
init()

-- Return the tiler object for configuration
return tiler
