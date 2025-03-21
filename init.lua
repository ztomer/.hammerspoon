-- Hammerspoon configuration, heavily influenced by sdegutis default configuration
require "pomodoor"
-- This is how you should include the tiler module
local tiler = require "tiler"

-- Key combinations
local mash = {"ctrl", "cmd"}
local mash_app = {"shift", "ctrl"}
local mash_shift = {"shift", "ctrl", "cmd"}
local HYPER = {"shift", "ctrl", "alt", "cmd"}

-- Custom zone configs for portrait mode
local portrait_zones = {
    -- Top section
    ["y"] = {"a1", "a1:a2"}, -- Top cell, and top two cells

    -- Middle section
    ["h"] = {"a2", "a1:a3"}, -- Middle cell, and entire column

    -- Bottom section
    ["n"] = {"a3", "a2:a3"}, -- Bottom cell, and bottom two cells

    -- Disable other zones by setting them to empty tables
    ["u"] = {},
    ["j"] = {},
    ["m"] = {},
    ["i"] = {},
    ["k"] = {},
    [","] = {},
    ["o"] = {},
    ["l"] = {},
    ["."] = {},

    -- Center key still works for full-screen
    ["0"] = {"a1:a3", "a2", "a1"} -- Full column, middle, top
}

-- Cache frequently accessed functions
local appLaunchOrFocus = hs.application.launchOrFocus

-- Pre-compile application lists for faster lookups
local hide_workaround_apps = {'Arc'} -- Apps that need menu-based hiding

-- Apps that require exact mapping between launch name and display name
local special_app_mappings = {
    ["bambustudio"] = "bambu studio" -- Launch name → Display name
}

-- Ambiguous app pairs that should not be considered matching
local ambiguous_apps = {{'notion', 'notion calendar'}, {'notion', 'notion mail'}}

-- Application shortcuts with direct lowercase mapping
local appCuts = {
    q = 'BambuStudio',
    w = 'Whatsapp',
    e = 'Finder',
    r = 'Cronometer',
    t = 'iTerm',
    a = 'Notion',
    s = 'Notion Mail',
    d = 'Notion Calendar',
    f = 'Zen',
    g = 'Gmail',
    z = 'Nimble Commander',
    x = 'Claude',
    c = 'Arc',
    v = 'Visual Studio Code',
    b = 'Spotify'
}

local hyperAppCuts = {
    q = 'IBKR Desktop',
    w = 'Weather',
    e = 'Clock',
    r = 'Discord',
    t = 'ChatGpt'
}

-- Help text cache
local help_text = nil

-- Window filter
local watcher = hs.window.filter.new()

-- ===== Utility Functions =====

--[[
  Determines if two app names are ambiguous (one might be part of another)

  @param app_name (string) First application name to compare
  @param title (string) Second application name to compare
  @return (boolean) true if the app names are known to be ambiguous, false otherwise
]]
local function ambiguous_app_name(app_name, title)
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
local function toggle_app(app)
    -- Get information about currently focused app and target app
    local front_app = hs.application.frontmostApplication()
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
    if not ambiguous_app_name(front_app_lower, target_app_lower) then
        if string.find(front_app_lower, target_app_lower) or string.find(target_app_lower, front_app_lower) then
            switching_to_same_app = true
        end
    end

    if switching_to_same_app then
        -- Handle apps that need special hiding via menu
        for _, workaround_app in ipairs(hide_workaround_apps) do
            if front_app_name == workaround_app then
                front_app:selectMenuItem("Hide " .. front_app_name)
                return
            end
        end

        -- Normal hiding
        front_app:hide()
        return
    end

    -- Not on target app, so launch or focus it
    appLaunchOrFocus(target_app_name)
end

--[[
  Displays help screen with keyboard shortcuts
]]
local function display_help()
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
end

-- ===== Initialization Functions =====

--[[
  Initializes window management keybindings
]]
local function init_wm_binding()
    hs.hotkey.bind(mash_app, '/', display_help)

    -- Window focus
    hs.hotkey.bind(mash_shift, 'H', function()
        hs.window.focusedWindow():focusWindowWest()
    end)
    hs.hotkey.bind(mash_shift, 'L', function()
        hs.window.focusedWindow():focusWindowEast()
    end)
    hs.hotkey.bind(mash_shift, 'K', function()
        hs.window.focusedWindow():focusWindowNorth()
    end)
    hs.hotkey.bind(mash_shift, 'J', function()
        hs.window.focusedWindow():focusWindowSouth()
    end)

    hs.hotkey.bind(HYPER, '/', hs.hints.windowHints)

    -- Pomodoro bindings
    hs.hotkey.bind(mash, '9', pom_enable)
    hs.hotkey.bind(mash, '0', pom_disable)
    hs.hotkey.bind(mash_shift, '0', pom_reset_work)
end

--[[
  Initializes application shortcut keybindings
]]
local function init_app_binding()
    for key, app in pairs(appCuts) do
        hs.hotkey.bind(mash_app, key, function()
            toggle_app(app)
        end)
    end

    for key, app in pairs(hyperAppCuts) do
        hs.hotkey.bind(HYPER, key, function()
            toggle_app(app)
        end)
    end
end

--[[
  Initializes custom keybindings
]]
local function init_custom_binding()
    hs.hotkey.bind(HYPER, "=", function()
        toggle_app("Activity Monitor")
    end)
end

--[[
  Main initialization function
]]
local function init()

    -- Disable animation for speed
    hs.window.animationDuration = 0

    -- Load Spoons
    hs.loadSpoon("RoundedCorners")
    spoon.RoundedCorners:start()

    -- Initialize all components
    -- init_wm_binding()
    local tiler_config = {
        debug = true, -- Enable debug logging
        modifier = {"ctrl", "cmd"}, -- Set default modifier keys
        -- Add window margin configuration
        margins = {
            enabled = true, -- Enable margins between windows
            size = 5, -- Use 5 pixels for margins (adjust as needed)
            screen_edge = true -- Apply margins to screen edges too
        },
        -- Custom layouts for specific screens
        layouts = {
            custom = {
                ["DELL U3223QE"] = {
                    cols = 4,
                    rows = 3
                },
                ["LG IPS QHD"] = {
                    cols = 1,
                    rows = 3
                } -- 1×3 for portrait LG
            }
        },
        zone_configs_by_screen = {
            -- Portrait configuration for LG screen
            ["LG IPS QHD"] = portrait_zones
        }
    }

    -- Start tiler with the configuration
    tiler.start(tiler_config)
    tiler.setup_screen_movement_keys()

    init_wm_binding()
    init_app_binding()
    init_custom_binding()
end

-- Start the configuration
init()

