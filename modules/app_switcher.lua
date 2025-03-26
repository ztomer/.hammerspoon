-- App switching module for Hammerspoon
local logger = require("core.logger")
local utils = require("core.utils")
local state = require("core.state")
local events = require("core.events")

local appSwitcher = {}

-- Cache frequently accessed functions
local appLaunchOrFocus = hs.application.launchOrFocus

--- Initialize state from config
-- @param config table The configuration settings
-- @return void
function appSwitcher.init(config)
    if not config then
        return
    end

    -- Store configuration in state
    state.set("app_switcher", "config", {
        -- Apps that need menu-based hiding
        hide_workaround_apps = config.hide_workaround_apps or {},

        -- Apps that require exact mapping between launch name and display name
        special_app_mappings = config.special_app_mappings or {},

        -- Ambiguous app pairs that should not be considered matching
        ambiguous_apps = config.ambiguous_apps or {}
    })

    logger.info("AppSwitcher", "Initialized app switcher")
end

--[[
  Determines if two app names are ambiguous (one might be part of another)

  @param app_name (string) First application name to compare
  @param title (string) Second application name to compare
  @return (boolean) true if the app names are known to be ambiguous, false otherwise
]]
function appSwitcher.ambiguous_app_name(app_name, title)
    -- Get configuration
    local config = state.get("app_switcher", "config") or {}
    local ambiguous_apps = config.ambiguous_apps or {}

    -- Some application names are ambiguous - may be part of a different app name or vice versa.
    -- this function disambiguates some known applications.
    for _, tuple in ipairs(ambiguous_apps) do
        if (app_name == tuple[1] and title == tuple[2]) or (app_name == tuple[2] and title == tuple[1]) then
            return true
        end
    end

    return false
end

--[[
  Toggles an application between focused and hidden states

  @param app (string) The name of the application to toggle
]]
function appSwitcher.toggle_app(app)
    logger.debug("AppSwitcher", "Toggle app: %s", app)

    -- Get configuration
    local config = state.get("app_switcher", "config") or {}
    local hide_workaround_apps = config.hide_workaround_apps or {}
    local special_app_mappings = config.special_app_mappings or {}

    -- Get information about currently focused app and target app
    local front_app = hs.application.frontmostApplication()
    if not front_app then
        logger.debug("AppSwitcher", "No frontmost application")
        appLaunchOrFocus(app)
        events.emit("app_switcher.launched", app)
        return
    end

    local front_app_name = front_app:name()
    local front_app_lower = front_app_name:lower()
    local target_app_name = app
    local target_app_lower = app:lower()

    -- Check if the front app is the one we're trying to toggle
    local switching_to_same_app = false

    -- Handle special app mappings (launch name ≠ display name)
    if special_app_mappings[target_app_lower] == front_app_lower or (target_app_lower == front_app_lower) then
        switching_to_same_app = true
    end

    -- Check if they're related apps with different naming conventions
    if not appSwitcher.ambiguous_app_name(front_app_lower, target_app_lower) then
        if string.find(front_app_lower, target_app_lower) or string.find(target_app_lower, front_app_lower) then
            switching_to_same_app = true
        end
    end

    if switching_to_same_app then
        -- Handle apps that need special hiding via menu
        for _, workaround_app in ipairs(hide_workaround_apps) do
            if front_app_name == workaround_app then
                logger.debug("AppSwitcher", "Hiding %s via menu", front_app_name)
                front_app:selectMenuItem("Hide " .. front_app_name)
                events.emit("app_switcher.hidden", front_app_name)
                return
            end
        end

        -- Normal hiding
        logger.debug("AppSwitcher", "Hiding %s", front_app_name)
        front_app:hide()
        events.emit("app_switcher.hidden", front_app_name)
        return
    end

    -- Not on target app, so launch or focus it
    logger.debug("AppSwitcher", "Launching/focusing %s", target_app_name)
    appLaunchOrFocus(target_app_name)
    events.emit("app_switcher.toggled", target_app_name)
end

--[[
  Displays help screen with keyboard shortcuts
]]
function appSwitcher.display_help(appCuts, hyperAppCuts)
    local help_text = nil

    if not help_text then
        local t = {"Keyboard shortcuts\n", "--------------------\n"}

        for key, app in pairs(appCuts) do
            table.insert(t, "Control + CMD + " .. key .. "\t :\t" .. app .. "\n")
        end

        for key, app in pairs(hyperAppCuts) do
            table.insert(t, "HYPER + " .. key .. "\t:\t" .. app .. "\n")
        end

        help_text = table.concat(t)
    end

    hs.alert.show(help_text, 2)
    events.emit("app_switcher.help_displayed")
end

--[[
  Initializes application shortcut keybindings
]]
function appSwitcher.init_bindings(appCuts, hyperAppCuts, mash_app, HYPER)
    logger.info("AppSwitcher", "Initializing keyboard bindings")

    -- Initialize configuration if not done yet
    if not state.get("app_switcher", "config") then
        appSwitcher.init({})
    end

    -- Store keybindings in state
    state.set("app_switcher", "bindings", {
        appCuts = appCuts or {},
        hyperAppCuts = hyperAppCuts or {},
        mash_app = mash_app,
        HYPER = HYPER
    })

    for key, app in pairs(appCuts) do
        hs.hotkey.bind(mash_app, key, function()
            appSwitcher.toggle_app(app)
        end)
        logger.debug("AppSwitcher", "Bound key %s to app %s", key, app)
    end

    for key, app in pairs(hyperAppCuts) do
        hs.hotkey.bind(HYPER, key, function()
            appSwitcher.toggle_app(app)
        end)
        logger.debug("AppSwitcher", "Bound HYPER+%s to app %s", key, app)
    end

    -- Help binding
    hs.hotkey.bind(mash_app, '/', function()
        appSwitcher.display_help(appCuts, hyperAppCuts)
    end)
    logger.debug("AppSwitcher", "Bound help key to /")

    logger.info("AppSwitcher", "Initialized %d standard and %d hyper key bindings", utils.tableCount(appCuts),
        utils.tableCount(hyperAppCuts))

    -- Listen for app launch/termination events
    local app_watcher = hs.application.watcher.new(function(app_name, event_type, app_obj)
        if event_type == hs.application.watcher.launched then
            events.emit("application.launched", app_name, app_obj)
            logger.debug("AppSwitcher", "Application launched: %s", app_name)
        elseif event_type == hs.application.watcher.terminated then
            events.emit("application.terminated", app_name, app_obj)
            logger.debug("AppSwitcher", "Application terminated: %s", app_name)
        elseif event_type == hs.application.watcher.activated then
            events.emit("application.activated", app_name, app_obj)
            logger.debug("AppSwitcher", "Application activated: %s", app_name)
        elseif event_type == hs.application.watcher.deactivated then
            events.emit("application.deactivated", app_name, app_obj)
            logger.debug("AppSwitcher", "Application deactivated: %s", app_name)
        elseif event_type == hs.application.watcher.hidden then
            events.emit("application.hidden", app_name, app_obj)
            logger.debug("AppSwitcher", "Application hidden: %s", app_name)
        elseif event_type == hs.application.watcher.shown then
            events.emit("application.shown", app_name, app_obj)
            logger.debug("AppSwitcher", "Application shown: %s", app_name)
        end
    end)

    app_watcher:start()
    state.set("app_switcher", "watcher", app_watcher)

    return appSwitcher
end

return appSwitcher
