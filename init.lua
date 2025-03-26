--[[
  Hammerspoon Tiler - Refactored
  Main initialization file for Hammerspoon configuration
]] -- Load configuration
local config = require("config")

-- Initialize core modules first
local logger = require("core.logger").init()
local events = require("core.events").init()
local state = require("core.state").init()
local utils = require("core.utils")

-- Set up logger with configuration
logger.configure(config.logging)

logger.info("Init", "Initializing Hammerspoon configuration")

-- Display startup message
hs.alert.show("Hammerspoon Initialized", 1)

-- Initialize modules

-- Initialize window tiler
local tiler = require("modules.tiler")
tiler.init(config.tiler)

-- Memory module needs explicit initialization after tiler
local memory = require("modules.memory.memory")
memory.init(config.tiler.window_memory)

-- Initialize application switcher with keybindings
local appSwitcher = require("modules.app_switcher")
appSwitcher.init(config.app_switcher)
appSwitcher.init_bindings(config.appCuts, config.hyperAppCuts, config.keys.mash_app, config.keys.HYPER)

-- Initialize pomodoro timer
local pomodoro = require("modules.pomodoor")
pomodoro.init(config.pomodoro)

-- Setup custom event handlers from config if present
if config.tiler and config.tiler.event_handlers then
    for event_name, handler in pairs(config.tiler.event_handlers) do
        events.on(event_name, handler)
    end
end

-- Setup additional events required for memory functionality
events.on("memory.window.resize_in_zone", function(zone_id, win_id)
    local zone = tiler.Zone.getById(zone_id)
    if zone then
        zone:resizeWindow(win_id, {
            problem_apps = config.tiler.problem_apps
        })
    end
end)

events.on("memory.zone.find", function(zone_id, win)
    local screen = win:screen()
    local screen_id = screen:id()

    -- Find matching zone on this screen
    local zones = state.get("zones") or {}

    for id, zone_data in pairs(zones) do
        if zone_data.screen_id == tostring(screen_id) and (id == zone_id or id:match("^" .. zone_id .. "_")) then
            local zone = tiler.Zone.getById(id)
            if zone then
                state.set("_temp", "found_zone", zone)
                break
            end
        end
    end
end)

-- Add global hotkeys

-- Reload Hammerspoon configuration
hs.hotkey.bind(config.keys.mash_shift, "r", function()
    hs.reload()
end)

-- Show/Hide Hammerspoon console
hs.hotkey.bind(config.keys.mash_shift, "/", function()
    local console = hs.console
    if console.hswindow() and console.hswindow():isVisible() then
        console.hswindow():hide()
    else
        console.hswindow():show()
    end
end)

-- Toggle Pomodoro Timer
hs.hotkey.bind(config.keys.mash, "9", function()
    if pomodoro.get_state().is_active then
        pomodoro.disable()
    else
        pomodoro.enable()
    end
end)

-- Reset Pomodoro Timer
hs.hotkey.bind(config.keys.mash, "0", function()
    pomodoro.disable()
end)

-- Reset Pomodoro Work Count
hs.hotkey.bind(config.keys.mash_shift, "0", function()
    pomodoro.reset_work()
end)

-- Load Spoons if configured
if config.spoons and config.spoons.enabled then
    logger.info("Init", "Loading Spoons")

    if config.spoons.RoundedCorners then
        local roundedCorners = hs.loadSpoon("RoundedCorners")
        if roundedCorners then
            roundedCorners:start()
            logger.info("Spoons", "Loaded RoundedCorners")
        end
    end
end

-- Add system event watchers
local systemWatcher = hs.caffeinate.watcher.new(function(event)
    if event == hs.caffeinate.watcher.systemWillSleep then
        events.emit("system.sleep")
        logger.info("System", "System going to sleep")
    elseif event == hs.caffeinate.watcher.systemDidWake then
        events.emit("system.wakeup")
        logger.info("System", "System woke from sleep")

        -- Refresh tiler on wake to handle display changes
        hs.timer.doAfter(2, function()
            tiler.refresh()
        end)
    elseif event == hs.caffeinate.watcher.screensaverDidStart then
        events.emit("system.screensaver.started")
    elseif event == hs.caffeinate.watcher.screensaverDidStop then
        events.emit("system.screensaver.stopped")
    end
end)
systemWatcher:start()

-- Finalize initialization
logger.info("Init", "Hammerspoon initialization complete")

-- Define public module for debugging
local hammerspoonTiler = {
    config = config,
    logger = logger,
    events = events,
    state = state,
    utils = utils,
    tiler = tiler,
    appSwitcher = appSwitcher,
    pomodoro = pomodoro
}

return hammerspoonTiler
