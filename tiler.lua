-- Zone Tiler for Hammerspoon
-- A window management system that allows defining zones on the screen
-- and cycling window sizes within those zones
require "homebrew"

-- Design notes:
-- - Mode - Per resolution/screen size Zones configuration
-- - Zone - areas of the screen, each with set of tiles
-- - Tile - pre-set size of windows for each zone

-- Define the Tiler namespace
local Tiler = {
    window_id2zone_id = {}, -- Maps window to zone_id
    zone_id2zone = {}, -- Maps zone_id to zone object
    modes = {}, -- All possible monitor modes
    windows = nil, -- handler for windows events
    debug = true, -- Enable debug logging
    version = "1.0.0"
}

-- Debug logging function
local function log(...)
    if Tiler.debug then
        print("[TilerDebug]", ...)
    end
end

--------------------------
-- Tile Class Definition --
--------------------------

-- Tile class - represents a specific window position and size
local Tile = {}
Tile.__index = Tile

function Tile.new(topleft_x, topleft_y, width, height)
    local self = setmetatable({}, Tile)
    self.topleft_x = topleft_x
    self.topleft_y = topleft_y
    self.width = width
    self.height = height
    return self
end

function Tile:toString()
    return string.format("Tile(x=%d, y=%d, w=%d, h=%d)",
        self.topleft_x, self.topleft_y, self.width, self.height)
end

--------------------------
-- Zone Class Definition --
--------------------------

-- Zone class - represents an area of the screen with multiple possible tile configurations
local Zone = {}
Zone.__index = Zone

function Zone.new(id, hotkey)
    local self = setmetatable({}, Zone)
    self._id = id
    self._hotkey = hotkey
    self._tiles = {}
    self._tiles_num = 0
    self._window_id2tile_idx = {}
    self._active_window_id = nil
    self._current_tile_idx = 0
    return self
end

function Zone:toString()
    return string.format("Zone(id=%s, tiles=%d)", self._id, self._tiles_num)
end

function Zone:add_tile(topleft_x, topleft_y, width, height)
    -- Add a new tile configuration to this zone
    self._tiles[self._tiles_num] = Tile.new(topleft_x, topleft_y, width, height)
    self._tiles_num = self._tiles_num + 1
    log("Added tile to zone", self._id, "total tiles:", self._tiles_num)
    return self
end

function Zone:tile_rotate(window_id)
    -- Rotate to the next tile configuration for a window
    if not self._window_id2tile_idx[window_id] then
        self._window_id2tile_idx[window_id] = 0
        return 0
    end

    -- Calculate next tile index with wrap-around
    local next_idx = (self._window_id2tile_idx[window_id] + 1) % self._tiles_num
    self._window_id2tile_idx[window_id] = next_idx
    log("Rotated window", window_id, "to tile index", next_idx, "in zone", self._id)
    return next_idx
end

function Zone:get_current_tile(window_id)
    -- Get the current tile for a window
    local tile_idx = self._window_id2tile_idx[window_id]
    if not tile_idx then
        return nil
    end
    return self._tiles[tile_idx]
end

function Zone:add_window(window_id)
    -- Add a window to this zone (assigns to the first tile by default)
    if self._window_id2tile_idx[window_id] ~= nil then
        log("Window", window_id, "already in zone", self._id)
        return
    end

    -- Map the window to this zone and set first tile (index 0)
    self._window_id2tile_idx[window_id] = 0
    Tiler.window_id2zone_id[window_id] = self._id
    log("Added window", window_id, "to zone", self._id)
end

function Zone:remove_window(window_id)
    -- Remove a window from this zone
    if self._window_id2tile_idx[window_id] == nil then
        log("Window", window_id, "not in zone", self._id)
        return
    end

    log("Removing window", window_id, "from zone", self._id)
    self._window_id2tile_idx[window_id] = nil
    Tiler.window_id2zone_id[window_id] = nil
end

function Zone:resize_window(window_id)
    -- Resize a window based on its current tile configuration
    local tile_idx = self._window_id2tile_idx[window_id]
    if not tile_idx then
        log("Cannot resize window", window_id, "- not in zone", self._id)
        return false
    end

    local tile = self._tiles[tile_idx]
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
    log("Resizing window", window_id, "to", tile:toString())
    window:setFrame({
        x = tile.topleft_x,
        y = tile.topleft_y,
        w = tile.width,
        h = tile.height
    })

    return true
end

-- Register the zone with the Tiler
function Zone:register()
    Tiler.zone_id2zone[self._id] = self
    log("Registered zone", self._id)

    -- Set up the hotkey for this zone
    if self._hotkey then
        hs.hotkey.bind(self._hotkey[1], self._hotkey[2], function()
            activate_move_zone(self._id)
        end)
        log("Bound hotkey", self._hotkey[1], self._hotkey[2], "to zone", self._id)
    end

    return self
end

--------------------------
-- Core Functions --
--------------------------

function activate_move_zone(zone_id)
    -- Handle moving a window to a zone or cycling its tile if already in the zone
    log("Activating zone", zone_id)

    -- Get focused window
    local win = hs.window.focusedWindow()
    if not win then
        log("No focused window")
        return
    end

    local win_id = win:id()

    -- Get the window's current zone
    local current_zone_id = Tiler.window_id2zone_id[win_id]
    local zone = Tiler.zone_id2zone[zone_id]

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
        local source_zone = Tiler.zone_id2zone[current_zone_id]
        log("Moving window", win_id, "from zone", current_zone_id, "to zone", zone_id)

        if source_zone then
            source_zone:remove_window(win_id)
        end

        zone:add_window(win_id)
    else
        -- Window already in this zone, rotate through tiles
        log("Rotating window", win_id, "in zone", zone_id)
        zone:tile_rotate(win_id)
    end

    -- Apply the new tile dimensions
    zone:resize_window(win_id)
end

function activate_window_event(win_obj, appName, event_name)
    -- Handle window events (destruction, creation, etc.)
    log("Window event:", event_name, "for app:", appName)

    if event_name == "windowDestroyed" and win_obj then
        local win_id = win_obj:id()
        local zone_id = Tiler.window_id2zone_id[win_id]

        if zone_id then
            local zone = Tiler.zone_id2zone[zone_id]
            if zone then
                log("Window destroyed, removing from zone:", zone_id)
                zone:remove_window(win_id)
            end
        end
    end
end

local function activate_window_display_moved()
    -- Handle windows when displays are changed
    log("Screen configuration changed")

    -- Clear existing modes since screen positions may have changed
    Tiler.modes = {}

    for _, screen in pairs(hs.screen.allScreens()) do
        local screen_id = screen:id()
        local screen_name = screen:name()
        log("Processing screen:", screen_name, "ID:", screen_id)

        -- Check for custom configuration for this specific screen
        local mode_config
        if Tiler.layouts.custom[screen_name] then
            log("Using custom layout for screen:", screen_name)
            mode_config = Tiler.layouts.custom[screen_name]
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
        for window_id, zone_id in pairs(Tiler.window_id2zone_id) do
            local zone = Tiler.zone_id2zone[zone_id]
            if zone then
                log("Resizing window", window_id, "in zone", zone_id)
                zone:resize_window(window_id)
            end
        end
    end)
end

local function get_mode_for_screen(screen)
    -- Determine which layout mode to use based on screen properties
    local screen_frame = screen:frame()
    local width = screen_frame.w
    local height = screen_frame.h

    log("Screen dimensions:", width, "x", height)

    -- Apply different grids based on screen size
    if width >= 3840 and height >= 2160 then
        return "4x3"  -- 4K monitors get a 4×3 grid
    elseif width >= 2560 then
        return "3x3"  -- Wide monitors get a 3×3 grid
    elseif width >= 1920 and height >= 1080 then
        return "3x2"  -- Full HD gets a 3×2 grid
    else
        return "2x2"  -- Smaller screens get a simple 2×2 grid
    end
end

--------------------------
-- Mode Initialization --
--------------------------

-- Define keyboard layout for auto-mapping
local keyboard_layouts = {
    -- Define rows of keys for easy grid mapping
    number_row = {"6", "7", "8", "9", "0"},
    top_row = {"y", "u", "i", "o", "p"},
    home_row = {"h", "j", "k", "l", ";"},
    bottom_row = {"n", "m", ",", ".", "/"}
}

function create_key_map(rows, cols)
    -- Creates a 2D array of key mappings based on the keyboard layout
    -- rows: number of rows in the grid
    -- cols: number of columns in the grid

    local mapping = {}
    local available_rows = {
        keyboard_layouts.top_row,
        keyboard_layouts.home_row,
        keyboard_layouts.bottom_row,
        keyboard_layouts.number_row
    }

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

function init_mode(screen, mode_config)
    -- Initialize a screen layout mode using a configuration
    -- mode_config can be either a string like "3x3" or a table with detailed settings

    local grid_cols, grid_rows, key_map, modifier

    if type(mode_config) == "string" then
        -- Parse a simple configuration like "3x3"
        local cols, rows = mode_config:match("(%d+)x(%d+)")
        grid_cols = tonumber(cols) or 3
        grid_rows = tonumber(rows) or 3
        key_map = create_key_map(grid_rows, grid_cols)
        modifier = {"ctrl", "cmd"}
    elseif type(mode_config) == "table" then
        -- Use detailed configuration
        grid_cols = mode_config.cols or 3
        grid_rows = mode_config.rows or 3
        key_map = mode_config.key_map or create_key_map(grid_rows, grid_cols)
        modifier = mode_config.modifier or {"ctrl", "cmd"}
    else
        -- Default to 3x3 grid
        grid_cols = 3
        grid_rows = 3
        key_map = create_key_map(grid_rows, grid_cols)
        modifier = {"ctrl", "cmd"}
    end

    log("Initializing", grid_cols, "×", grid_rows, "grid for screen", screen:name())

    -- Create the grid layout
    return create_grid_layout(screen, grid_cols, grid_rows, key_map, modifier)
end

function create_grid_layout(screen, cols, rows, key_map, modifier)
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

                local zone_x = x + (c-1) * col_width
                local zone_y = y + (r-1) * row_height

                local zone = Zone.new(zone_id, hotkey)

                -- Basic tile for this grid cell (default size)
                zone:add_tile(zone_x, zone_y, col_width, row_height)

                -- Full width for this row
                if cols > 1 then
                    zone:add_tile(x, zone_y, w, row_height)
                end

                -- Full height for this column
                if rows > 1 then
                    zone:add_tile(zone_x, y, col_width, h)
                end

                -- Cell-specific special tiles (like spanning multiple cells)
                if c == 1 then  -- Left column
                    if r == 1 then  -- Top-left
                        zone:add_tile(x, y, col_width*2, row_height*2)
                    elseif r == rows then  -- Bottom-left
                        zone:add_tile(x, y+(r-2)*row_height, col_width*2, row_height*2)
                    end
                elseif c == cols then  -- Right column
                    if r == 1 then  -- Top-right
                        zone:add_tile(x+(c-2)*col_width, y, col_width*2, row_height*2)
                    elseif r == rows then  -- Bottom-right
                        zone:add_tile(x+(c-2)*col_width, y+(r-2)*row_height, col_width*2, row_height*2)
                    end
                end

                -- Middle cell gets some special treatment for centered windows
                if cols > 2 and rows > 2 and c == math.ceil(cols/2) and r == math.ceil(rows/2) then
                    -- Center quarter
                    zone:add_tile(x + w/4, y + h/4, w/2, h/2)
                    -- Center third
                    zone:add_tile(x + w/3, y + h/3, w/3, h/3)
                    -- Full screen
                    zone:add_tile(x, y, w, h)
                end

                zone:register()
                table.insert(zones, zone)
            end
        end
    end

    -- Create special zone for center regardless of grid size
    local center_key = "0"
    local center_zone = Zone.new("center", {modifier, center_key})
    center_zone:add_tile(x + w/4, y + h/4, w/2, h/2)
    center_zone:add_tile(x + w/6, y + h/6, w*2/3, h*2/3)
    center_zone:add_tile(x, y, w, h)
    center_zone:register()
    table.insert(zones, center_zone)

    local mode = {
        screen_id = screen:id(),
        cols = cols,
        rows = rows,
        zones = zones
    }

    Tiler.modes[screen:id()] = mode
    return mode
end

--------------------------
-- Initialization --
--------------------------

local function init_listeners()
    -- Initialize event listeners
    log("Initializing event listeners")

    -- Window event filter
    Tiler.windows = hs.window.filter.new()
    Tiler.windows:setDefaultFilter{}
    Tiler.windows:setSortOrder(hs.window.filter.sortByFocusedLast)

    -- Subscribe to window events
    Tiler.windows:subscribe(hs.window.filter.windowDestroyed, activate_window_event)

    -- Screen change events
    hs.screen.watcher.new(activate_window_display_moved):start()
end

-- User-configurable layouts
Tiler.layouts = {
    -- Default layouts for different screen types
    default = {
        small = "2x2",
        medium = "3x2",
        large = "3x3",
        extra_large = "4x3"
    },

    -- Custom layouts for specific screens (by name)
    custom = {
        -- Example: ["LG UltraFine"] = { cols = 4, rows = 3, modifier = {"ctrl", "alt"} }
    }
}

local function tiler_init()
    log("Initializing Tiler")

    -- Set up event listeners
    init_listeners()

    -- Initialize layouts for all screens
    for _, screen in pairs(hs.screen.allScreens()) do
        local screen_name = screen:name()
        log("Configuring screen:", screen_name)

        -- Check for custom configuration for this specific screen
        local mode_config
        if Tiler.layouts.custom[screen_name] then
            log("Using custom layout for screen:", screen_name)
            mode_config = Tiler.layouts.custom[screen_name]
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
        Tiler.debug = not Tiler.debug
        log("Debug mode:", Tiler.debug ? "enabled" : "disabled")
    end)

    log("Tiler initialization complete")
end

-- Utility function to configure a custom layout for a screen
function Tiler.configure_screen(screen_name, config)
    log("Setting custom configuration for screen:", screen_name)
    Tiler.layouts.custom[screen_name] = config

    -- If the screen is currently connected, apply the config immediately
    for _, screen in pairs(hs.screen.allScreens()) do
        if screen:name() == screen_name then
            init_mode(screen, config)
            break
        end
    end
end

-- Start the Tiler
tiler_init()