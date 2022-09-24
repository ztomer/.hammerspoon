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

Area = {
    topleft_x = 0,
    topleft_y = 0,
    width = 0,
    height = 0
}

function Area:new(topleft_x, topleft_y, width, height)
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

-- Map between Window and area

-- map between area and window

function Tile:new(id, hotkey)
    self.id = id
    self.hotkey = hotkey
end

function Tile:add_area(topleft_x, topleft_y, width, height)
    -- Add areas - all areas MUST be added on init
    self._areas[self._areas_num] = new
    Area(topleft_x, topleft_y, width, height)

    self.areas_num = self.areas_num + 1
end

function Tile:get_next(window_id)
    -- Return the next area of the tile
    local area_idx = self._windows_area[window_id] + 1 % self._areas_num
    self.windows_area[window_id] = area_idx
    return self._areas[area_idx]
end

function Tile:get_curr(window_id)
    -- Get current window position
    local area_idx = self.windows_area[window_id]
    return self._areas[area_idx]
end

function Tile:add_window(window_id)
    -- Add a window to the tile
    if self._windows_area[window_id] ~= nil then
        return
    end
    self._windows_area[window_id] = 0
end

-- TODO: Move windows
-- TODO: map active windows to areas

function on_hot_key_activation()
    -- Also move window
    -- Get focused window id

    -- Get Tile, get area (can be empty)

    -- Get target Tile bound to the hotkey,
    -- If the target tile is the same as the one in the map,
    -- cycle between areas and move the window to the next area

    -- If the target tile and the current tile are not the same,
    -- remove the window id from the current Tile, add to the target tile,
    -- set the area inde to 0 and move the window to the area coordinates

    -- hw.window:setFrameInScreenBounds
    -- hs.window:setSize(size)
    -- hs.window:setTopLeft(point)
end
