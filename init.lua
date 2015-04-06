-- Hammerspoon configuration, heavily influenced by sdegutis default configuration

require "pomodoor"

-- init grid
hs.grid.MARGINX 	= 0
hs.grid.MARGINY 	= 0
hs.grid.GRIDWIDTH 	= 7
hs.grid.GRIDHEIGHT 	= 3

-- disable animation
hs.window.animationDuration = 0


-- hotkey mash
local mash       = {"ctrl", "alt"}
local mash_app 	 = {"cmd", "alt", "ctrl"}
local mash_shift = {"ctrl", "alt", "shift"}
local mash_test	 = {"cntrl", "shift"}	

--------------------------------------------------------------------------------

-- application help
local function open_help()
  help_str = 	"d - Dictionary, 1 - Terminal, 2 - Calendar, " ..
            	"3 - Chrome, 4 - Dash, 5 - Trello, 6 - Quiver, 7 - Reeder"        
  hs.alert.show(help_str, 2)
end

-- Launch applications
hs.hotkey.bind(mash_app, 'D', function () hs.application.launchOrFocus("Dictionary") end)
hs.hotkey.bind(mash_app, '1', function () hs.application.launchOrFocus("iterm") end)
hs.hotkey.bind(mash_app, '2', function () hs.application.launchOrFocus("Fantastical 2") end)
hs.hotkey.bind(mash_app, '3', function () hs.application.launchOrFocus("Google Chrome") end)
-- mash_app '4' reserved for dash global key
hs.hotkey.bind(mash_app, '5', function () hs.application.launchOrFocus("Trello X") end)
hs.hotkey.bind(mash_app, '6', function () hs.application.launchOrFocus("Quiver") end)
hs.hotkey.bind(mash_app, '7', function () hs.application.launchOrFocus("Reeder") end)
hs.hotkey.bind(mash_app, '/', open_help)

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
