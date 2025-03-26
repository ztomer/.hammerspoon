--[[
  layout.lua - Layout management for window tiling

  This module provides utilities for managing window layouts,
  including predefined layouts and layout switching.

  Usage:
    local Layout = require("modules.tiler.layout")

    -- Initialize with configuration
    Layout.init(config)

    -- Apply a specific layout to a screen
    Layout.applyToScreen("coding", screen)

    -- Save current window arrangement as a layout
    Layout.saveCurrentLayout("my_layout")

    -- Apply a layout to all screens
    Layout.applyLayout("dual_screen_browsing")
]] local logger = require("core.logger")
local utils = require("core.utils")
local state = require("core.state")
local Zone = require("modules.tiler.zone")
local Tile = require("modules.tiler.tile")
local grid = require("modules.tiler.grid")

local Layout = {}

-- Predefined layouts
Layout.predefined = {}

-- Currently active layouts by screen ID
Layout.active_layouts = {}

--- Initialize layout system
-- @param config table Configuration options
-- @return Layout module for chaining
function Layout.init(config)
    logger.info("Layout", "Initializing layout management system")

    -- Store configuration reference
    Layout.config = config or {}

    -- Load custom layouts from config
    if config and config.layouts and config.layouts.custom_layouts then
        for name, layout_def in pairs(config.layouts.custom_layouts) do
            Layout.predefined[name] = layout_def
        end
    end

    -- Load saved layouts from state
    local saved_layouts = state.get("layouts") or {}
    for name, layout_def in pairs(saved_layouts) do
        if not Layout.predefined[name] then
            Layout.predefined[name] = layout_def
        end
    end

    -- Initialize screen-specific layouts if provided in config
    if config and config.layouts and config.layouts.default_screen_layouts then
        for screen_name, layout_name in pairs(config.layouts.default_screen_layouts) do
            local screen = utils.findScreenByPattern(screen_name)
            if screen then
                Layout.applyToScreen(layout_name, screen, {
                    silent = true
                })
            end
        end
    end

    logger.debug("Layout", "Loaded %d predefined layouts", utils.tableCount(Layout.predefined))
    return Layout
end

--- Define a new layout
-- @param name string The name of the layout
-- @param layout_def table The layout definition
-- @param options table Optional settings
-- @return boolean True if successful
function Layout.define(name, layout_def, options)
    if not name or type(name) ~= "string" then
        logger.error("Layout", "Cannot define layout without valid name")
        return false
    end

    options = options or {}

    -- Validate layout definition minimally
    if type(layout_def) ~= "table" then
        logger.error("Layout", "Invalid layout definition for %s", name)
        return false
    end

    -- Add metadata
    layout_def.metadata = layout_def.metadata or {}
    layout_def.metadata.created = os.time()
    layout_def.metadata.description = layout_def.metadata.description or options.description

    -- Store the layout
    Layout.predefined[name] = layout_def

    -- Save to state if persistent
    if options.save ~= false then
        local layouts = state.get("layouts") or {}
        layouts[name] = layout_def
        state.set("layouts", layouts)
    end

    logger.debug("Layout", "Defined layout: %s", name)
    return true
end

--- Get a specific layout by name
-- @param name string The name of the layout
-- @return table The layout definition or nil if not found
function Layout.get(name)
    if not name then
        return nil
    end

    return Layout.predefined[name]
end

--- Check if a layout exists
-- @param name string The name of the layout
-- @return boolean True if the layout exists
function Layout.exists(name)
    return Layout.predefined[name] ~= nil
end

--- Delete a layout
-- @param name string The name of the layout
-- @return boolean True if successful
function Layout.delete(name)
    if not Layout.exists(name) then
        return false
    end

    -- Remove from predefined layouts
    Layout.predefined[name] = nil

    -- Remove from state
    local layouts = state.get("layouts") or {}
    layouts[name] = nil
    state.set("layouts", layouts)

    logger.debug("Layout", "Deleted layout: %s", name)
    return true
end

--- Save current window arrangement as a layout
-- @param name string The name to save the layout as
-- @param options table Optional settings
-- @return boolean True if successful
function Layout.saveCurrentLayout(name, options)
    if not name or type(name) ~= "string" then
        logger.error("Layout", "Cannot save layout without valid name")
        return false
    end

    options = options or {}

    -- Get all visible windows
    local windows = hs.window.allWindows()
    local layout_def = {
        windows = {},
        screens = {},
        metadata = {
            created = os.time(),
            description = options.description or ("Layout saved on " .. os.date("%Y-%m-%d %H:%M")),
            zone_based = options.zone_based ~= false
        }
    }

    -- Save screen information
    for _, screen in ipairs(hs.screen.allScreens()) do
        local screen_id = tostring(screen:id())
        local frame = screen:frame()

        layout_def.screens[screen_id] = {
            name = screen:name(),
            frame = {
                x = frame.x,
                y = frame.y,
                w = frame.w,
                h = frame.h
            },
            grid = grid.getGridForScreen(screen, Layout.config) and {
                cols = grid.getGridForScreen(screen, Layout.config).cols,
                rows = grid.getGridForScreen(screen, Layout.config).rows
            } or {
                cols = 3,
                rows = 2
            }
        }
    end

    -- Process windows
    for _, win in ipairs(windows) do
        -- Skip non-standard or minimized windows
        if not win:isStandard() or win:isMinimized() then
            goto continue
        end

        local window_id = win:id()
        local app = win:application()
        local screen = win:screen()

        if not app or not screen then
            goto continue
        end

        local app_name = app:name()
        local screen_id = tostring(screen:id())
        local frame = win:frame()

        -- Get window state
        local window_state = state.getWindowState(window_id)
        local window_info = {
            app = app_name,
            screen_id = screen_id,
            frame = {
                x = frame.x,
                y = frame.y,
                w = frame.w,
                h = frame.h
            },
            title = win:title() or ""
        }

        -- If zone-based layout and window is in a zone, save zone information
        if options.zone_based ~= false and window_state and window_state.zone_id then
            window_info.zone_id = window_state.zone_id
            window_info.tile_idx = window_state.tile_idx
        end

        -- Add window to layout
        table.insert(layout_def.windows, window_info)

        ::continue::
    end

    -- Save the layout
    Layout.define(name, layout_def, {
        description = options.description,
        save = true
    })

    logger.info("Layout", "Saved current layout as: %s with %d windows", name, #layout_def.windows)

    return true
end

--- Apply a layout to a specific screen
-- @param layout_name string The name of the layout
-- @param screen hs.screen The screen to apply to
-- @param options table Optional settings
-- @return boolean True if successful
function Layout.applyToScreen(layout_name, screen, options)
    if not layout_name or not screen then
        logger.error("Layout", "Cannot apply layout without name and screen")
        return false
    end

    options = options or {}

    -- Get the layout
    local layout_def = Layout.get(layout_name)
    if not layout_def then
        logger.error("Layout", "Layout not found: %s", layout_name)
        return false
    end

    local screen_id = tostring(screen:id())

    -- Store active layout for this screen
    Layout.active_layouts[screen_id] = layout_name

    -- Apply zone-based layout if available
    if layout_def.zones and layout_def.zones[screen_id] then
        -- Clear existing zones for this screen
        local existing_zones = state.get("zones") or {}
        for id, zone_data in pairs(existing_zones) do
            if zone_data.screen_id == screen_id then
                state.remove("zones", id)
            end
        end

        -- Create zones from layout
        for zone_id, zone_def in pairs(layout_def.zones[screen_id]) do
            local zone = Zone.new(zone_id, {
                screen = screen,
                description = zone_def.description,
                hotkey = zone_def.hotkey and {Layout.config.modifier, zone_def.hotkey} or nil,
                focus_hotkey = zone_def.focus_hotkey and {Layout.config.focus_modifier, zone_def.focus_hotkey} or nil
            })

            -- Add tiles
            if zone_def.tiles then
                for _, tile_def in ipairs(zone_def.tiles) do
                    zone:addTile(Tile.from(tile_def))
                end
            end

            zone:register({
                no_hotkeys = options.no_hotkeys
            })
        end

        if not options.silent then
            logger.info("Layout", "Applied zone-based layout %s to screen %s", layout_name, screen:name())
        end
    end

    -- Apply window-based layout
    if layout_def.windows then
        for _, win_def in ipairs(layout_def.windows) do
            -- Only apply to windows on this screen
            if win_def.screen_id == screen_id then
                -- Find matching application windows
                local app_windows = {}
                for _, win in ipairs(hs.window.allWindows()) do
                    if win:isStandard() and not win:isMinimized() and win:application() and win:application():name() ==
                        win_def.app then
                        table.insert(app_windows, win)
                    end
                end

                -- Try to find best matching window
                local target_window = nil

                -- If we have a title, try to match by title
                if win_def.title and #win_def.title > 0 then
                    for _, win in ipairs(app_windows) do
                        if win:title() and win:title():find(win_def.title, 1, true) then
                            target_window = win
                            break
                        end
                    end
                end

                -- If no match by title or no title, use the first window
                if not target_window and #app_windows > 0 then
                    target_window = app_windows[1]
                end

                -- Apply position to the target window
                if target_window then
                    -- Move to correct screen first
                    if target_window:screen():id() ~= screen:id() then
                        target_window:moveToScreen(screen, false, false, 0)

                        -- Add delay to ensure screen move completes
                        hs.timer.doAfter(0.1, function()
                            -- Apply position based on zone or frame
                            if win_def.zone_id then
                                -- Try to find the zone
                                local zones = state.get("zones") or {}
                                for zone_id, _ in pairs(zones) do
                                    if zone_id == win_def.zone_id or zone_id:match("^" .. win_def.zone_id .. "_") then
                                        local zone = Zone.getById(zone_id)
                                        if zone then
                                            zone:addWindow(target_window:id(), {
                                                tile_idx = win_def.tile_idx or 1
                                            })
                                            zone:resizeWindow(target_window:id())
                                            break
                                        end
                                    end
                                end
                            else
                                -- Apply direct frame
                                if win_def.frame then
                                    local frame = {
                                        x = win_def.frame.x,
                                        y = win_def.frame.y,
                                        w = win_def.frame.w,
                                        h = win_def.frame.h
                                    }

                                    target_window:setFrame(frame)
                                end
                            end
                        end)
                    else
                        -- Already on correct screen, apply position
                        if win_def.zone_id then
                            -- Try to find the zone
                            local zones = state.get("zones") or {}
                            for zone_id, _ in pairs(zones) do
                                if zone_id == win_def.zone_id or zone_id:match("^" .. win_def.zone_id .. "_") then
                                    local zone = Zone.getById(zone_id)
                                    if zone then
                                        zone:addWindow(target_window:id(), {
                                            tile_idx = win_def.tile_idx or 1
                                        })
                                        zone:resizeWindow(target_window:id())
                                        break
                                    end
                                end
                            end
                        else
                            -- Apply direct frame
                            if win_def.frame then
                                local frame = {
                                    x = win_def.frame.x,
                                    y = win_def.frame.y,
                                    w = win_def.frame.w,
                                    h = win_def.frame.h
                                }

                                target_window:setFrame(frame)
                            end
                        end
                    end
                end
            end
        end

        if not options.silent then
            logger.info("Layout", "Applied window positioning from layout %s to screen %s", layout_name, screen:name())
        end
    end

    return true
end

--- Apply a layout to all screens
-- @param layout_name string The name of the layout
-- @param options table Optional settings
-- @return boolean True if successful
function Layout.applyLayout(layout_name, options)
    if not layout_name then
        logger.error("Layout", "Cannot apply layout without name")
        return false
    end

    options = options or {}

    -- Get the layout
    local layout_def = Layout.get(layout_name)
    if not layout_def then
        logger.error("Layout", "Layout not found: %s", layout_name)
        return false
    end

    logger.info("Layout", "Applying layout: %s", layout_name)

    -- Get all screens
    local screens = hs.screen.allScreens()

    -- Apply to each screen
    local success = true
    for _, screen in ipairs(screens) do
        local screen_id = tostring(screen:id())

        -- Check if layout has specific configuration for this screen
        if layout_def.screens and layout_def.screens[screen_id] then
            -- Apply to this screen
            local screen_success = Layout.applyToScreen(layout_name, screen, {
                silent = true,
                no_hotkeys = options.no_hotkeys
            })

            success = success and screen_success
        else
            -- Try to find best matching screen by name
            local matched = false
            if layout_def.screens then
                for layout_screen_id, screen_info in pairs(layout_def.screens) do
                    if screen:name() == screen_info.name then
                        -- Apply to this screen
                        local screen_success = Layout.applyToScreen(layout_name, screen, {
                            silent = true,
                            no_hotkeys = options.no_hotkeys
                        })

                        success = success and screen_success
                        matched = true
                        break
                    end
                end
            end

            -- If no match, apply default layout if specified
            if not matched and options.default_layout then
                local screen_success = Layout.applyToScreen(options.default_layout, screen, {
                    silent = true,
                    no_hotkeys = options.no_hotkeys
                })

                success = success and screen_success
            end
        end
    end

    if success then
        logger.info("Layout", "Successfully applied layout: %s", layout_name)
    else
        logger.warn("Layout", "Some screens failed when applying layout: %s", layout_name)
    end

    return success
end

--- Get current active layout for a screen
-- @param screen hs.screen The screen to check
-- @return string The layout name or nil if none
function Layout.getActiveLayout(screen)
    if not screen then
        return nil
    end

    return Layout.active_layouts[tostring(screen:id())]
end

--- Get all predefined layouts
-- @return table Table of layouts
function Layout.getAll()
    return utils.deepCopy(Layout.predefined)
end

--- Create a layout from screen zones
-- @param name string The name for the new layout
-- @param options table Optional settings
-- @return boolean True if successful
function Layout.createFromZones(name, options)
    if not name or type(name) ~= "string" then
        logger.error("Layout", "Cannot create layout without valid name")
        return false
    end

    options = options or {}

    -- Create new layout definition
    local layout_def = {
        zones = {},
        screens = {},
        metadata = {
            created = os.time(),
            description = options.description or ("Zone layout created on " .. os.date("%Y-%m-%d %H:%M")),
            zone_based = true
        }
    }

    -- Get all zones from state
    local zones = state.get("zones") or {}

    -- Group zones by screen
    local screens_processed = {}

    for zone_id, zone_data in pairs(zones) do
        -- Skip if no screen association
        if not zone_data.screen_id then
            goto continue
        end

        local screen_id = zone_data.screen_id

        -- Initialize screen in layout if needed
        if not layout_def.zones[screen_id] then
            layout_def.zones[screen_id] = {}

            -- Add screen info
            local screen = nil
            for _, s in ipairs(hs.screen.allScreens()) do
                if tostring(s:id()) == screen_id then
                    screen = s
                    break
                end
            end

            if screen then
                local frame = screen:frame()
                layout_def.screens[screen_id] = {
                    name = screen:name(),
                    frame = {
                        x = frame.x,
                        y = frame.y,
                        w = frame.w,
                        h = frame.h
                    }
                }

                -- Add grid info if available
                local grid_obj = grid.getGridForScreen(screen, Layout.config)
                if grid_obj then
                    layout_def.screens[screen_id].grid = {
                        cols = grid_obj.cols,
                        rows = grid_obj.rows
                    }
                end

                screens_processed[screen_id] = true
            end
        end

        -- Skip screen-specific zone IDs, we'll use the base ID
        if zone_id:find("_[0-9]+$") then
            local base_id = zone_id:match("^(.-)_[0-9]+$")
            if base_id and zones[base_id] then
                goto continue
            end
        end

        -- Create zone definition
        local zone_def = {
            description = zone_data.description,
            tiles = {},
            hotkey = utils.find(zone_data.tags, function(tag)
                return tag:match("^hotkey:")
            end) and zone_data.hotkey
        }

        -- Add tiles
        if zone_data.tiles then
            for _, tile_data in ipairs(zone_data.tiles) do
                table.insert(zone_def.tiles, {
                    x = tile_data.x,
                    y = tile_data.y,
                    width = tile_data.width,
                    height = tile_data.height,
                    description = tile_data.description
                })
            end
        end

        -- Add zone to layout
        layout_def.zones[screen_id][zone_id] = zone_def

        ::continue::
    end

    -- Only save if we have at least one screen with zones
    if utils.tableCount(screens_processed) > 0 then
        -- Save the layout
        Layout.define(name, layout_def, {
            description = options.description,
            save = true
        })

        logger.info("Layout", "Created layout %s from zones on %d screens", name, utils.tableCount(screens_processed))

        return true
    else
        logger.error("Layout", "No zones found on any screen to create layout")
        return false
    end
end

--- Switch to next layout for a screen
-- @param screen hs.screen The screen to switch
-- @param options table Optional settings
-- @return boolean True if successful
function Layout.switchToNextLayout(screen, options)
    if not screen then
        return false
    end

    options = options or {}
    local screen_id = tostring(screen:id())

    -- Get all layouts
    local layouts = {}
    for name, _ in pairs(Layout.predefined) do
        table.insert(layouts, name)
    end

    if #layouts == 0 then
        logger.warn("Layout", "No layouts available to switch to")
        return false
    end

    -- Sort layouts alphabetically for consistent ordering
    table.sort(layouts)

    -- Find current layout index
    local current_layout = Layout.active_layouts[screen_id]
    local current_idx = 1

    if current_layout then
        for i, name in ipairs(layouts) do
            if name == current_layout then
                current_idx = i
                break
            end
        end
    end

    -- Calculate next layout
    local next_idx
    if options.direction == "previous" then
        next_idx = current_idx - 1
        if next_idx < 1 then
            next_idx = #layouts
        end
    else
        next_idx = (current_idx % #layouts) + 1
    end

    local next_layout = layouts[next_idx]

    -- Apply next layout
    local success = Layout.applyToScreen(next_layout, screen, options)

    if success and not options.silent then
        hs.alert.show("Layout: " .. next_layout, 1)
    end

    return success
end

--- Create hotkeys for layout management
-- @param config table Configuration options
-- @return boolean True if successful
function Layout.setupHotkeys(config)
    if not config then
        logger.error("Layout", "Cannot set up hotkeys without configuration")
        return false
    end

    -- Hotkey for saving current layout
    if config.hotkeys and config.hotkeys.save_layout then
        local mods = config.hotkeys.save_layout[1]
        local key = config.hotkeys.save_layout[2]

        hs.hotkey.bind(mods, key, function()
            -- Prompt for layout name
            hs.dialog.textPrompt("Save Layout", "Enter a name for the current layout:", "", "Save", "Cancel",
                function(button, text)
                    if button == "Save" and text ~= "" then
                        Layout.saveCurrentLayout(text)
                        hs.alert.show("Layout saved: " .. text)
                    end
                end)
        end)

        logger.debug("Layout", "Set up save layout hotkey: %s+%s", table.concat(mods, "+"), key)
    end

    -- Hotkey for next layout
    if config.hotkeys and config.hotkeys.next_layout then
        local mods = config.hotkeys.next_layout[1]
        local key = config.hotkeys.next_layout[2]

        hs.hotkey.bind(mods, key, function()
            local screen = hs.screen.mainScreen()
            Layout.switchToNextLayout(screen)
        end)

        logger.debug("Layout", "Set up next layout hotkey: %s+%s", table.concat(mods, "+"), key)
    end

    -- Hotkey for previous layout
    if config.hotkeys and config.hotkeys.prev_layout then
        local mods = config.hotkeys.prev_layout[1]
        local key = config.hotkeys.prev_layout[2]

        hs.hotkey.bind(mods, key, function()
            local screen = hs.screen.mainScreen()
            Layout.switchToNextLayout(screen, {
                direction = "previous"
            })
        end)

        logger.debug("Layout", "Set up previous layout hotkey: %s+%s", table.concat(mods, "+"), key)
    end

    -- Individual layout hotkeys
    if config.hotkeys and config.hotkeys.layouts then
        for layout_name, hotkey in pairs(config.hotkeys.layouts) do
            local mods = hotkey[1]
            local key = hotkey[2]

            hs.hotkey.bind(mods, key, function()
                Layout.applyLayout(layout_name)
                hs.alert.show("Layout: " .. layout_name)
            end)

            logger.debug("Layout", "Set up hotkey for layout %s: %s+%s", layout_name, table.concat(mods, "+"), key)
        end
    end

    return true
end

return Layout
