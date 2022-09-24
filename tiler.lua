-- Manual tiler window manager
require "homebrew"

-- Some design notes with no particular order:
-- Mode contains Tiles, tiles contains Areas
-- Windows are not automatically resized when switching modes manually
-- Windows are resized when switching modes automatically
-- Modes are selected automatically per screen identifier
-- (32" 4k will be width: 1/4, 1/2, 1/4,  heights: 1/2, 1/3, 2/3)
-- (14" will be widths 1/2, heights 1/2)
-- (vertical screen will be width: 1/2, 1/2, heights: 1/3, 2/3, 1 )

-- Tile Objects, allows cycling between multiple area of different sizes

-- local namespace
local Tiler = {
    window2tile = {}, -- Maps window to tile_id and area_id
    tile_id2tile = {} -- Maps tile_id to tile object
}

Area = {
    topleft_x = 0,
    topleft_y = 0,
    width = 0,
    height = 0
}

function Area:new(topleft_x, topleft_y, width, height)
    -- Deines Area - a sub location in a Tile
    self.topleft_x = topleft_x
    self.topleft_y = topleft_y
    self.width = width
    self.height = height
end

Tile = {
    -- A tile can contain multiple areas, which defines the possible windows sizes
    -- for this tile
    _id = nil, -- unique identifer for the tile
    _hotkey = nil, -- hotkey to activate this tile
    _areas = {}, -- possible areas attached to the tile
    _areas_num = 0, -- number of areas attached to the tile
    _windows_area = {} -- map between window and active area

}

-- map between area and window

function Tile:new(id, hotkey)
    self._id = id
    self._hotkey = hotkey
end

function Tile:area_add(topleft_x, topleft_y, width, height)
    -- Add areas - all areas MUST be added on init
    self._areas[self._areas_num] = new
    Area(topleft_x, topleft_y, width, height)

    self.areas_num = self.areas_num + 1
end

function Tile:area_rotate(window_id)
    -- Return the next area of the tile
    local area_idx = self._windows_area[window_id] + 1 % self._areas_num
    self.windows_area[window_id] = area_idx
end

function Tile:area_get_curr(window_id)
    -- Get current window position
    local area_idx = self._windows_area[window_id]
    return self._areas[area_idx]
end

function Tile:add_window(window_id)
    -- Add a window to the tile
    if self._windows_area[window_id] ~= nil then
        return
    end
    self._windows_area[window_id] = 0

    -- add to global window2Tile array
    Tiler.window2tile[window_id] = {self._id, 0}
end

function Tile:remove_window(window_id)
    -- Remove window from the tile
    if self._windows_area[window_id] == nil then
        return
    end
    self._windows_area[window_id] = nil
    Tiler.window2Tile[window_id] = nil
end

-- TODO: Move windows
-- TODO: map active windows to areas

function Tile:resize_window(window_id)
    -- Get current tile and area
    local area = self._windows_area[window_id]

    -- Resize the window

    -- If the target tile and the current tile are not the same,
    -- remove the window id from the current Tile, add to the target tile,
    -- set the area inde to 0 and move the window to the area coordinates
    -- hw.window:setFrameInScreenBounds
    -- hs.window:setSize(size)
    -- hs.window:setTopLeft(point)

end

function activate_move_tile(tile_id)
    -- Activates a move_tile operation on the focused window

    -- Also move window
    -- Get focused window id
    -- local app = hs.application.frontmostApplication()
    local win = hs.window.focusedWindow()
    local win_id = win:id()

    -- Get Tile, get area (can be empty)
    local window_tile_id, window_area_idx = Tiler.window2Tile[win_id]
    local tile = Tiler.tile_id2tile(tile_id)

    if tile_id == nil then
        -- if the target tile is empty, add the window, resize, and done
        tile.add_window(win_id)
    elseif tile_id ~= window_tile_id then
        -- If moving between tiles,
        local source_tile = Tiler.tile_id2tile(window_tile_id)
        source_tile.remove_window(window_tile_id)
        tile.add_window(win_id)
    else
        -- Multiple calls to the same window on the same tile, rotate between areas
        tile.area_roate(win_id)
    end
    tile.resize_window(win_id)

end

function activate_window_closed()
    -- TODO: remove a window ID when an application is terminated or a window is closed
end

function activate_window_display_moved()
    -- TODO: update the window caches when moving between hs.midi:displayName()
end

function tiler_init()
    -- Create tiles supersets (1, 2, 3 areas)

    -- Add areas to tiles

    -- bind hotkeys to tile supersets

    -- Bind hotkeys to tiles per superset (needs to be moved to a different function)

    -- listen on window destruction for cleanups (can be very problematic if ids are recycled)

    -- listen on monitor switches
end
