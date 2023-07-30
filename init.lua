-- Hammerspoon configuration, heavily influenced by sdegutis default configuration
require "pomodoor"
require "homebrew"

-- init grid
hs.grid.MARGINX = 5
hs.grid.MARGINY = 5
hs.grid.GRIDWIDTH = 7
hs.grid.GRIDHEIGHT = 3

-- disable animation
hs.window.animationDuration = 0
-- hs.hints.style = "vimperator"

-- hotkey mash
local mash = {"ctrl", "cmd"}
-- local mash_app 	 = {"cmd", "alt", "ctrl"}
local mash_app = {"shift", "ctrl"}
local mash_shift = {"shift", "ctrl", "cmd"}
local mash_test = {"ctrl", "shift"}

-- Hyper key, for the Kinesis360 CAPS
local HYPER = {"shift", "ctrl", "alt", "cmd"}
local watcher = hs.window.filter.new()

local function snap_to_grid(window)
    -- Snap a window to the grid
    if window and window:isStandard() and window:isVisible() then
        hs.grid.snap(window)
    end
end

local function snap_all_windows()
    -- Snap all the windows to the grid
    local windows = hs.window.visibleWindows()
    for _, window in ipairs(windows) do
        snap_to_grid(window)
    end
end

local function init_watcher()

    -- Init the automatic snapper
    watcher:subscribe(hs.window.filter.windowCreated, snap_to_grid)
    watcher:subscribe(hs.window.filter.windowFocused, snap_to_grid)
    -- watcher:start()
end

--------------------------------------------------------------------------------
local appCuts = {
    q = 'Twitter',
    w = 'Whatsapp',
    e = 'Finder',
    r = 'Cronometer',
    t = 'iterm',

    a = 'Notion',
    s = 'Spotify',
    d = 'Cron',
    f = 'Firefox',
    g = 'Gmail',

    z = 'Double Commander',
    x = 'Microsoft Edge',
    c = 'Google Chrome',
    v = 'Visual Studio Code',
    b = 'BingGPT'

}

-- Display Help
local function display_help()
    local t = {}
    table.insert(t, "Keyboard shortcuts\n")
    table.insert(t, "--------------------\n")

    for key, app in pairs(appCuts) do
        local str = "Control + CMD + " .. key .. "\t :\t" .. app .. "\n"
        -- hs.alert.show(str)
        table.insert(t, str)
    end
    local concat_t = table.concat(t)
    hs.alert.show(concat_t, 2)

end

-- snap all newly launched windows
local function auto_tile(appName, event)
    if event == hs.application.watcher.launched then
        local app = hs.appfinder.appFromName(appName)
        -- protect against unexpected restarting windows
        if app == nil then
            return
        end
        hs.fnutils.map(app:allWindows(), hs.grid.snap)
    end
end

-- Moves all windows outside the view into the curent view
local function rescue_windows()
    local screen = hs.screen.mainScreen()
    local screenFrame = screen:fullFrame()
    local wins = hs.window.visibleWindows()
    for i, win in ipairs(wins) do
        local frame = win:frame()
        if not frame:inside(screenFrame) then
            win:moveToScreen(screen, true, true)
        end
    end
end

local function init_wm_binding()
    hs.hotkey.bind(mash_app, '/', function()
        display_help()
    end)

    -- global operations
    hs.hotkey.bind(mash, ';', function()
        hs.grid.snap(hs.window.focusedWindow())
    end)
    hs.hotkey.bind(HYPER, "G", function()
        hs.fnutils.map(snap_all_windows, hs.grid.snap)
    end)

    -- adjust grid size
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
    --
    -- change focus
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

    -- multi monitor
    hs.hotkey.bind(mash, 'N', hs.grid.pushWindowNextScreen)
    hs.hotkey.bind(mash, 'P', hs.grid.pushWindowPrevScreen)

    -- move windows
    hs.hotkey.bind(mash, 'H', hs.grid.pushWindowLeft)
    hs.hotkey.bind(mash, 'J', hs.grid.pushWindowDown)
    hs.hotkey.bind(mash, 'K', hs.grid.pushWindowUp)
    hs.hotkey.bind(mash, 'L', hs.grid.pushWindowRight)
    hs.hotkey.bind(mash, 'R', function()
        rescue_windows()
    end)

    -- resize windows
    hs.hotkey.bind(mash, 'Y', hs.grid.resizeWindowThinner)
    hs.hotkey.bind(mash, 'U', hs.grid.resizeWindowShorter)
    hs.hotkey.bind(mash, 'I', hs.grid.resizeWindowTaller)
    hs.hotkey.bind(mash, 'O', hs.grid.resizeWindowWider)

    -- Window Hints
    -- hs.hotkey.bind(mash, '.', function() hs.hints.windowHints(hs.window.allWindows()) end)
    hs.hotkey.bind(mash, '.', hs.hints.windowHints)

    -- pomodoro key binding
    hs.hotkey.bind(mash, '9', function()
        pom_enable()
    end)
    hs.hotkey.bind(mash, '0', function()
        pom_disable()
    end)
    hs.hotkey.bind(mash_shift, '0', function()
        pom_reset_work()
    end)
end

local function toggle_app(app)
    -- Minimize the window if the focused window is the same as the launched window
    -- This is done to easliy pop and hide an application

    -- If the focused app is the one with assigned shortcut, hide it
    local front_app = hs.application.frontmostApplication()
    local app_name = app:lower()
    if app ~= nil then
        local title = front_app:name():lower()

        if title ~= nil then
            -- Check both ways, the naming conventions of the title are not consistent
            if string.find(title, app_name) or string.find(app_name, title) then
                front_app:hide()
                return
            end
        end
    end

    hs.application.launchOrFocus(app)

end

-- Init Launch applications bindings
local function init_app_binding()
    for key, app in pairs(appCuts) do
        -- hs.hotkey.bind(mash_app, key, function () hs.application.launchOrFocus(app) end)
        hs.hotkey.bind(mash_app, key, function()
            toggle_app(app)
        end)
    end
end

local function init_custom_binding()
    hs.hotkey.bind(HYPER, "ESCAPE", function()
        toggle_app("Activity Monitor")
    end)
end

local function increase_brightness()
    -- Get the currently focused screen
    local screen = hs.screen.mainScreen()
    local brightness = hs.screen.getBrightness()
    local target_brightness = math.min(brightness + 0.1, 1)
    ha.screen.setBrightness(target_brightness)

end

local function decrease_brightness()
    local screen = hs.screen.mainScreen()
    local brightness = hs.screen.getBrightness()
    local target_brightness = math.max(brightness - 0.1, 0)
    hs.screen.setBrightness(target_brightness)
end

local function init_brigheness()
    hs.hotkey.bind(HYPER, "up", function()
        increase_brightness()
    end)

    hs.hotkey.bind(HYPER, "down", function()
        decrease_brightness()
    end)
end

local function init()

    -- Load Spoons
    hs.loadSpoon("RoundedCorners")
    spoon.RoundedCorners:start()

    init_wm_binding()
    init_app_binding()
    init_custom_binding()
    init_watcher()
    --  init_brigheness() -- Doesn't work on my externl Dell display

    -- start app launch watcher
    -- hs.application.watcher.new(auto_tile):start()

end

init()
