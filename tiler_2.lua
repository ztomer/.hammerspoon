require "homebrew"

-- Design notes:
-- - Mode - Per resolution/screen size Zones configuration
-- - Zone - areas of the screen, each with set of tiles
-- - Tile - pre-set size of windows for each zone
--
-- Windows are not automatically resized when switching modes manually
-- Windows are resized when switching modes automatically
-- Modes are selected automatically per screen identifier
-- (32" 4k will be width: 1/4, 1/2, 1/4,  heights: 1/2, 1/3, 2/3)
-- (14" will be widths 1/2, heights 1/2)
-- (vertical screen will be width: 1/2, 1/2, heights: 1/3, 2/3, 1 )

-- Zone Objects, allows cycling between multiple tiles of different sizes
-- Store the windows in an LRU DLL, on keybinding to zone cycle between the windows in this Zone

-- References:
-- https://github.com/szymonkaliski/hhtwm/blob/master/hhtwm/init.lua
-- https://github.com/miromannino/miro-windows-manager/blob/master/MiroWindowsManager.spoon/init.lua
-- https://github.com/mogenson/PaperWM.spoon
-- https://thume.ca/2016/07/16/advanced-hackery-with-the-hammerspoon-window-manager/
-- https://livingissodear.com/posts/using-hammerspoon-for-window-management/
-- https://github.com/peterklijn/hammerspoon-shiftit (++)
-- https://github.com/ashfinal/awesome-hammerspoon/blob/master/Spoons/WinWin.spoon/init.lua (GC--)

-- https://github.com/AdamWagner/stackline (Good chache handling)
---- https://github.com/AdamWagner/stackline/blob/main/stackline/stackline.lua
-- https://github.com/jpf/Zoom.spoon/blob/main/init.lua (zoom plugin)
-- https://github.com/szymonkaliski/hhtwm
-- https://www.hammerspoon.org/Spoons/ArrangeDesktop.html
-- https://www.hammerspoon.org/Spoons/RoundedCorners.html
-- https://www.hammerspoon.org/Spoons/WindowSigils.html
-- https://github.com/dmgerman/dmg-hammerspoon/blob/f8da75d121c37df40c0971336eb3f67c73d67187/dmg.spoon/init.lua#L115-L224
--- Callbacks (cool trick - store the id of the current window in a global, if destroyed or closed, remove the global
-- value from the cache and update the currently focused winid to be the global)
-- https://github.com/mobily/awesome-keys

-- local namespace
local Tiler = {
    window_id2zone_id = {}, -- Maps window to zone_id
    zone_id2zone = {}, -- Maps zone_id to zone object
    modes = {}, -- All possible monitor modes
    windows = nil -- handler for windows events
}

Tile = {
    topleft_x = 0,
    topleft_y = 0,
    width = 0,
    height = 0
}

function Tile:new(topleft_x, topleft_y, width, height)
    -- Defines tile - a sub location in a Zone
    self.topleft_x = topleft_x
    self.topleft_y = topleft_y
    self.width = width
    self.height = height
end

Zone = {
    -- A Zone can contain multiple tiles, which defines the possible windows sizes
    -- for this Zone
    _id = nil, -- unique identifier for the Zone
    _hotkey = nil, -- hotkey to activate this Zone
    _tiles = {}, -- possible tiles attached to the Zone
    _tiles_num = 0, -- number of tiles attached to the Zone
    _window_id2tile_idx = {} -- map between window_id and active tile idx

}

-- map between tile
Zone = {
    -- ... other fields ...
    _active_window_id = nil, -- Store the currently active window ID
    _current_tile_idx = 0 -- Track the currently active tile index
}

function Zone:resize_window(window_id)
    local tile_idx = self._window_id2tile_idx[window_id]
    local tile = self._tiles[tile_idx]
    local window = hs.window.get(window_id)

    if window and tile then
        window:setFrameInScreenBounds(tile.topleft_x, tile.topleft_y, tile.width, tile.height)
    end
end

function activate_window_display_moved()
    for _, screen in pairs(hs.screen.allScreens()) do
        -- Determine appropriate mode based on screen size and configuration
        local mode = get_mode_for_screen(screen) -- Implement this function

        -- Update mode if necessary
        if mode and not Tiler.modes[screen:id()] then
            init_mode_3(screen) -- Or other mode initialization function
        end

        -- Remap window-zone associations and resize windows
        for window_id, zone_id in pairs(Tiler.window_id2zone_id) do
            local zone = Tiler.zone_id2zone[zone_id]
            if zone then
                zone:resize_window(window_id)
            end
        end
    end
end

hs.hotkey.bind({"cmd", "alt", "ctrl"}, "H", function()
    activate_move_zone("zone_1") -- Replace with desired zone ID
end)

function get_mode_for_screen(screen)
    -- Example logic based on screen resolution
    local screen_frame = screen:fullFrame()
    local width = screen_frame.w
    local height = screen_frame.h

    if width >= 3840 and height >= 2160 then
        return "mode_4k"
    elseif width >= 2560 then
        return "mode_wide"
    else
        return "mode_standard"
    end
end

-- Within the Zone object
Zone = {
    -- ... other fields ...
    _lru_head = nil, -- Head of the LRU list
    _lru_tail = nil -- Tail of the LRU list
}

-- Functions for LRU management (insert, update, remove, cycle)
-- ... (implementation details omitted for brevity)

local json = require "hs.json"

function load_config(config_path)
    local file = io.open(config_path, "r")
    local config_data = json.decode(file:read("*a"))
    file:close()

    -- Parse configuration data and create Zone layouts accordingly
    -- ... (implementation based on your configuration format)
end
