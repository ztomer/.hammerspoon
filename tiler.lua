-- Manual Zoner window manager
require "homebrew"

-- Some design notes with no particular order:
-- Mode - Per resolution/ screen size Zones configuration
-- Zone - areas of the screen, each with set of tiles
-- Tile - pre-set size of windows for each zone
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
    -- Deines tile - a sub location in a Zone
    self.topleft_x = topleft_x
    self.topleft_y = topleft_y
    self.width = width
    self.height = height
end

Zone = {
    -- A Zone can contain multiple tiles, which defines the possible windows sizes
    -- for this Zone
    _id = nil, -- unique identifer for the Zone
    _hotkey = nil, -- hotkey to activate this Zone
    _tiles = {}, -- possible tiles attached to the Zone
    _tiles_num = 0, -- number of tiles attached to the Zone
    _window_id2tile_idx = {} -- map between window_id and active tile idx

}

-- map between tile and window

function Zone:new(id, hotkey)
    self._id = id
    self._hotkey = hotkey
end

function Zone:tile_add(topleft_x, topleft_y, width, height)
    -- Add tiles - all tiles MUST be added on init
    self._tiles[self._tiles_num] = new
    tile(topleft_x, topleft_y, width, height)

    self.tiles_num = self.tiles_num + 1
end

function Zone:tile_rotate(window_id)
    -- Return the next tile of the Zone
    local tile_idx = self._window_id2tile_idx[window_id] + 1 % self._tiles_num
    self.windows_tile[window_id] = tile_idx
end

function Zone:tile_get_curr(window_id)
    -- Get current window position
    local tile_idx = self._window_id2tile_idx[window_id]
    return self._tiles[tile_idx]
end

function Zone:add_window(window_id)
    -- Add a window to the Zone
    if self._window_id2tile_idx[window_id] ~= nil then
        return
    end

    -- Map a window to a zone, and window to tile (starting with default size (idx 0))
    self._window_id2tile_idx[window_id] = 0
    Tiler.window_id2zone_id[window_id] = self._id
end

function Zone:remove_window(window_id)
    -- Remove window from the Zone
    if self._window_id2tile_idx[window_id] == nil then
        return
    end
    self._window_id2tile_idx[window_id] = nil
    Tiler.window_id2zone_id[window_id] = nil
end

-- TODO: Move windows
-- TODO: map active windows to tiles

function Zone:resize_window(window_id)
    -- Get current Zone and tile
    local tile = self._window_id2tile_idx[window_id]

    -- Resize the window

    -- If the target Zone and the current Zone are not the same,
    -- remove the window id from the current Zone, add to the target Zone,
    -- set the tile inde to 0 and move the window to the tile coordinates
    -- hw.window:setFrameInScreenBounds
    -- hs.window:setSize(size)
    -- hs.window:setTopLeft(point)

end

function activate_move_zone(zone_id)
    -- Activates a move_zone operation on the focused window

    -- Also move window
    -- Get focused window id
    -- local app = hs.application.frontmostApplication()
    local win = hs.window.focusedWindow()
    local win_id = win:id()

    -- Get Zone, get tile (can be empty)
    local window_zone_id, window_tile_idx = Tiler.window_id2zone_id[win_id]
    local zone = Tiler.zone_id2zone(zone_id)

    if zone_id == nil then
        -- if the target Zone is empty, add the window, resize, and done
        zone.add_window(win_id)
    elseif zone_id ~= window_zone_id then
        -- If moving between Zones, remove from the first zone and add to the second
        local source_zone = Tiler.zone_id2zone(window_zone_id)
        source_zone.remove_window(window_zone_id)
        Zone.add_window(win_id)
    else
        -- Multiple calls to the same window on the same Zone, rotate between tiles
        Zone.tile_rotate(win_id)
    end
    Zone.resize_window(win_id)

end

function activate_window_event(win_obj, appName, event_name)
    -- The callback is generic and handles all subscribed events
    -- Remove a window ID when an application is terminated or a window is closed
    if event_name == "windowDestroyed" then
        local win_id = win_obj:id()
        local zone_id = Tiler.window_id2zone_id()
        local zone_obj = Tiler.zone_id2zone[zone_id]
        zone_obj.remove_window(win_id)
    end
end

function activate_window_display_moved()
    -- TODO: update the window caches when moving between hs.midi:displayName()
end

local function init_mode_3(screen)
    -- Size 3 superset - right cluster
    -- Note this should be one per screen, so bad implementation
    -- Overall layout:
    -- [Y--|U-----|I--]
    -- [H--|J-----|K--]
    -- [N--|M-----|,--]
    -- TODO: Should be done per screen
    -- TODO: This should be read from a config file

    local display_rect = screen:frame()
    local w = display_rect.w
    local h = display_rect.h
    local x = display_rect.x
    local y = display_rect.y

    -- Y width is the first quarter, heights are half, third, two thirds
    local quarter_screen = w // 4
    local half_screen = w // 2
    local half_height = h // 2
    local two_third_height = (h * 2) // 3
    local third_height = h // 3
    local y_zone = Zone:new("Y", {"ctrl", "cmd", "y"})
    y_zone.tile_add(x, y, quarter_screen, half_height) -- Top half
    y_zone.tile_add(x, y, quarter_screen, two_third_height) -- Top 2/3
    y_zone.tile_add(x, y, quarter_screen, third_height) -- Top third

    local h_zone = Zone:new("H", {"ctrl", "cmd", "u"})
    h_zone.tile_add(x, y, quarter_screen, h) -- full left third
    h_zone.tile_add(x, y + third_height + 1, quarter_screen, third_height)

    local n_zone = Zone:new("N", {"ctrl", "cmd", "i"})
    n_zone.tile_add(x, y + half_height + 1, quarter_screen, half_height) -- Bottom half
    n_zone.tile_add(x, y + third_height + 1, quarter_screen, two_third_height) -- Bottom 2/3
    n_zone.tile_add(x, y + two_third_height + 1, quarter_screen, third_height) -- Bottom third

    -- Middle set, half of the screen
    x = quarter_screen + 1
    w = half_screen
    local u_zone = Zone:new("U", {"ctrl", "cmd", "h"})
    u_zone.tile_add(x, y, half_screen, half_height) -- middle half
    u_zone.tile_add(x, y, half_screen, two_third_height) -- Top 2/3
    u_zone.tile_add(x, y, half_screen, third_height)

    local j_zone = Zone:new("J", {"ctrl", "cmd", "j"})
    j_zone.tile_add(x, y, half_screen, h) -- Full middle
    j_zone.tile_add(x, y + third_height + 1, third_height)
    local m_Zone = Zone:new("M", {"ctrl", "cmd", "k"})
    n_zone.tile_add(x, y + half_height + 1, half_screen, half_height) -- Bottom half
    n_zone.tile_add(x, y + third_height + 1, half_screen, two_third_height) -- Bottom 2/3
    n_zone.tile_add(x, y + two_third_height + 1, half_screen, third_height) -- Bottom third

    -- Move to last quarter
    w = x + w + 1
    w = quarter_screen

    local i_zone = Zone:new("I", {"ctrl", "cmd", "n"})
    i_zone.tile_add(x, y, quarter_screen, half_height) -- Top half
    i_zone.tile_add(x, y, quarter_screen, two_third_height) -- Top 2/3
    i_zone.tile_add(x, y, quarter_screen, third_height) -- Top third

    local k_zone = Zone:new("K", {"ctrl", "cmd", "m"})
    k_zone.tile_add(x, y, quarter_screen, h) -- full left third
    k_zone.tile_add(x, y + third_height + 1, quarter_screen, third_height)

    local m1_zone = Zone:new("M1", {"ctrl", "cmd", ","})
    m1_zone.tile_add(x, y + half_height + 1, quarter_screen, half_height) -- Bottom half
    m1_zone.tile_add(x, y + third_height + 1, quarter_screen, two_third_height) -- Bottom 2/3
    m1_zone.tile_add(x, y + two_third_height + 1, quarter_screen, third_height) -- Bottom third

    local mode_3 = {y_zone, u_zone, i_zone, --
    h_zone, j_zone, k_zone, --
    n_zone, m_zone, m1_zone --
    }

    return mode_3
end

function init_listener()
    -- Initialize event filter
    Tiler.windows = hs.window.filter.new()
    Tiler.windows:setDefaultFilter{}
    Tiler.windows:setSortOrder(hs.window.filter.sortByFocusedLast)

    -- subscribe to a Window closed event
    Tiler.windows:subscribe(hs.window.filter.windowDestroyed, activate_window_event)

end

function tiler_init()
    -- Create Zones supersets (1, 2, 3 tiles) (modes)
    -- TODO (let's start with size three)
    local main_screen = hs.screen.mainScreen()
    local main_screen_name = screen.name()
    print("screen name:", main_screen_name) -- DEBUG

    -- Add tiles to Zones, map hotkeys,
    init_listener()
    local mode_3 = init_mode_3(main_screen)
    Tile.modes[3] = mode_3

    -- listen on window destruction for cleanups (can be very problematic if ids are recycled)

    -- listen on monitor switches
end
