-- Hammerspoon configuration, heavily influenced by sdegutis default configuration
require "pomodoor"
require "homebrew"

-- Initialize constants
local GRID_MARGIN_X = 5
local GRID_MARGIN_Y = 5
local GRID_WIDTH = 7
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
local hide_workaround_apps = {
    arc = true
} -- lowercase map for O(1) lookups

-- Special cases where launch name differs from UI name (with both directions for complete matching)
local app_name_pairs = {
    ["bambustudio_bambu studio"] = true,
    ["bambu studio_bambustudio"] = true,
    ["notion_notion calendar"] = true,
    ["notion calendar_notion"] = true,
    ["notion_notion mail"] = true,
    ["notion mail_notion"] = true
}

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
    f = 'Firefox',
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
  Checks if two app names are a known pair (either ambiguous or special cases)

  @param name1 (string) First application name
  @param name2 (string) Second application name
  @return (boolean) true if the app names are a known pair, false otherwise
]]
local function is_app_name_pair(name1, name2)
    local key = name1 .. "_" .. name2
    return app_name_pairs[key] == true
end

--[[
  Toggles an application between focused and hidden states

  @param app (string) The name of the application to toggle
]]
local function toggle_app(app)
    local front_app = hs.application.frontmostApplication()
    local front_app_name = front_app:name():lower()
    local target_app_name = app:lower()

    -- Check if we're already on the app we want to toggle
    local is_same_app = false

    -- Check if they're a known pair (special cases like BambuStudio/Bambu Studio or ambiguous apps)
    if is_app_name_pair(front_app_name, target_app_name) then
        is_same_app = true
    else
        -- Standard check for app name match
        if string.find(front_app_name, target_app_name, 1, true) or
            string.find(target_app_name, front_app_name, 1, true) then
            is_same_app = true
        end
    end

    if is_same_app then
        -- Use direct lookup instead of iteration for apps that need special hiding
        if hide_workaround_apps[front_app_name] then
            front_app:selectMenuItem("Hide " .. front_app:name())
            return
        end

        -- Hide the application
        front_app:hide()
        return
    end

    -- Not on target app, so launch or focus it
    appLaunchOrFocus(app)
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
    init_wm_binding()
    init_app_binding()
    init_custom_binding()
    init_watcher()
end

-- Start the configuration
init()
