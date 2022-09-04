-- Hammerspoon configuration, heavily influenced by sdegutis default configuration

require "pomodoor"
--require "bar"

require "homebrew"

-- init grid
hs.grid.MARGINX 	= 0
hs.grid.MARGINY 	= 0
hs.grid.GRIDWIDTH 	= 7
hs.grid.GRIDHEIGHT 	= 3

-- disable animation
hs.window.animationDuration = 0
--hs.hints.style = "vimperator"

-- hotkey mash
local mash       = {"ctrl", "alt"}
-- local mash_app 	 = {"cmd", "alt", "ctrl"}
mash_app = {"shift", "ctrl"}
local mash_shift = {"ctrl", "alt", "shift"}
local mash_test	 = {"cntrl", "shift"}

--------------------------------------------------------------------------------
local appCuts = {
  d = 'Cron',
  i = 'iterm',
  c = 'Google Chrome',
  a = 'Notion',
  -- 4 reserved for dash shortcut
  w = 'Whatsapp',
  v = 'Visual Studio Code',
  s = 'spotify'
}

-- Display Help
local function display_help()
  local t = {}
  str = "Keyboard shortcuts\n"
  table.insert(t, str)
  str = "--------------------\n"
  table.insert(t, str)
  for key, app in pairs(appCuts) do
    str = "^-Alt-Meta-"..key.."\t :\t"..app.."\n"
    --hs.alert.show(str)
    table.insert(t,str)
  end
  t = table.concat(t)
  hs.alert.show(t, 2)
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
    for i,win in ipairs(wins) do
        local frame = win:frame()
        if not frame:inside(screenFrame) then
            win:moveToScreen(screen, true, true)
        end
    end
end

local function init_wm_binding()
	hs.hotkey.bind(mash_app, '/', function() display_help() end)

	-- global operations
	hs.hotkey.bind(mash, ';', function() hs.grid.snap(hs.window.focusedWindow()) end)
	hs.hotkey.bind(mash, "'", function() hs.fnutils.map(hs.window.visibleWindows(), hs.grid.snap) end)

	-- adjust grid size
	hs.hotkey.bind(mash, '=', function() hs.grid.adjustWidth( 1) end)
	hs.hotkey.bind(mash, '-', function() hs.grid.adjustWidth(-1) end)
	hs.hotkey.bind(mash, ']', function() hs.grid.adjustHeight( 1) end)
	hs.hotkey.bind(mash, '[', function() hs.grid.adjustHeight(-1) end)

	-- change focus
	hs.hotkey.bind(mash_shift, 'H', function() hs.window.focusedWindow():focusWindowWest() end)
	hs.hotkey.bind(mash_shift, 'L', function() hs.window.focusedWindow():focusWindowEast() end)
	hs.hotkey.bind(mash_shift, 'K', function() hs.window.focusedWindow():focusWindowNorth() end)
	hs.hotkey.bind(mash_shift, 'J', function() hs.window.focusedWindow():focusWindowSouth() end)

	hs.hotkey.bind(mash, 'M', hs.grid.maximizeWindow)

	-- multi monitor
	hs.hotkey.bind(mash, 'N', hs.grid.pushWindowNextScreen)
	hs.hotkey.bind(mash, 'P', hs.grid.pushWindowPrevScreen)

	-- move windows
	hs.hotkey.bind(mash, 'H', hs.grid.pushWindowLeft)
	hs.hotkey.bind(mash, 'J', hs.grid.pushWindowDown)
	hs.hotkey.bind(mash, 'K', hs.grid.pushWindowUp)
	hs.hotkey.bind(mash, 'L', hs.grid.pushWindowRight)
	hs.hotkey.bind(mash, 'R', function() rescue_windows() end)

	-- resize windows
	hs.hotkey.bind(mash, 'Y', hs.grid.resizeWindowThinner)
	hs.hotkey.bind(mash, 'U', hs.grid.resizeWindowShorter)
	hs.hotkey.bind(mash, 'I', hs.grid.resizeWindowTaller)
	hs.hotkey.bind(mash, 'O', hs.grid.resizeWindowWider)

	-- Window Hints
	-- hs.hotkey.bind(mash, '.', function() hs.hints.windowHints(hs.window.allWindows()) end)
	hs.hotkey.bind(mash, '.', hs.hints.windowHints)

	-- pomodoro key binding
	hs.hotkey.bind(mash, '9', function() pom_enable() end)
	hs.hotkey.bind(mash, '0', function() pom_disable() end)
	hs.hotkey.bind(mash_shift, '0', function() pom_reset_work() end)
end

-- Init Launch applications bindings
local function init_app_binding()
	for key, app in pairs(appCuts) do
	  hs.hotkey.bind(mash_app, key, function () hs.application.launchOrFocus(app) end)
	end
end

	init_wm_binding()˘˘
	-- start app launch watcher
	-- hs.application.watcher.new(auto_tile):start()
end

init()




