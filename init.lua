-- Hammerspoon configuration, heavily influenced by sdegutis default configuration
require "pomodoor"
require "tiler"

-- Initialize constants
local GRID_MARGIN_X = 5
local GRID_MARGIN_Y = 5
local GRID_WIDTH = 4
local GRID_HEIGHT = 3

-- Key combinations
local mash = {"ctrl", "cmd"}
local mash_app = {"shift", "ctrl"}
local mash_shift = {"shift", "ctrl", "cmd"}
local HYPER = {"shift", "ctrl", "alt", "cmd"}

-- Cache frequently accessed functions
local gridSnap = hs.grid.snap
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
  Snaps a window to the grid

  @param window (hs.window) The window to snap
]]
local function snap_to_grid(window)
    if window and window:isStandard() and window:isVisible() then
        gridSnap(window)
    end
end

--[[
  Snaps all visible windows to the grid
]]
local function snap_all_windows()
    for _, window in ipairs(hs.window.visibleWindows()) do
        snap_to_grid(window)
    end
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

--[[
  Moves all windows outside the view into the current view
]]
local function rescue_windows()
    local screen = hs.screen.mainScreen()
    local screenFrame = screen:fullFrame()

    for _, win in ipairs(hs.window.visibleWindows()) do
        if not win:frame():inside(screenFrame) then
            win:moveToScreen(screen, true, true)
        end
    end
end

-- ===== Initialization Functions =====

--[[
  Initializes window management keybindings
]]
local function init_wm_binding()
    hs.hotkey.bind(mash_app, '/', display_help)
    hs.hotkey.bind(HYPER, ";", function()
        gridSnap(hs.window.focusedWindow())
    end)
    hs.hotkey.bind(HYPER, "g", snap_all_windows)

    -- Grid size adjustments
    hs.hotkey.bind(mash, '=', function()
        hs.grid.adjustWidth(1)
    end)
    hs.hotkey.bind(mash, '-', function()
        hs.grid.adjustWidth(-1)
    end)
    hs.hotkey.bind(mash, ']', function()
        hs.grid.adjustHeight(1)
    end)
    hs.hotkey.bind(mash, '[', function()
        hs.grid.adjustHeight(-1)
    end)

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

    hs.hotkey.bind(mash, 'M', hs.grid.maximizeWindow)
    hs.hotkey.bind(mash, 'N', hs.grid.pushWindowNextScreen)
    hs.hotkey.bind(mash, 'P', hs.grid.pushWindowPrevScreen)

    -- Window movement
    hs.hotkey.bind(mash, 'H', hs.grid.pushWindowLeft)
    hs.hotkey.bind(mash, 'J', hs.grid.pushWindowDown)
    hs.hotkey.bind(mash, 'K', hs.grid.pushWindowUp)
    hs.hotkey.bind(mash, 'L', hs.grid.pushWindowRight)
    hs.hotkey.bind(mash, 'R', rescue_windows)

    -- Window resizing
    hs.hotkey.bind(mash, 'Y', hs.grid.resizeWindowThinner)
    hs.hotkey.bind(mash, 'U', hs.grid.resizeWindowShorter)
    hs.hotkey.bind(mash, 'I', hs.grid.resizeWindowTaller)
    hs.hotkey.bind(mash, 'O', hs.grid.resizeWindowWider)

    hs.hotkey.bind(mash, '.', hs.hints.windowHints)

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
  Initializes window watcher
]]
local function init_watcher()
    watcher:subscribe(hs.window.filter.windowCreated, snap_to_grid)
    watcher:subscribe(hs.window.filter.windowFocused, snap_to_grid)
end

--[[
  Main initialization function
]]
local function init()

    -- Disable animation for speed
    hs.window.animationDuration = 0

    -- Configure grid
    hs.grid.MARGINX = GRID_MARGIN_X
    hs.grid.MARGINY = GRID_MARGIN_Y
    hs.grid.GRIDWIDTH = GRID_WIDTH
    hs.grid.GRIDHEIGHT = GRID_HEIGHT

    -- Load Spoons
    hs.loadSpoon("RoundedCorners")
    spoon.RoundedCorners:start()

    -- Initialize all components
    -- init_wm_binding()
    init_app_binding()
    init_custom_binding()
    init_watcher()
end

-- Start the configuration
init()
