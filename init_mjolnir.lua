-- refers to grid.lua in this directory, taken from the Hydra wiki:  
-- https://github.com/sdegutis/hydra/wiki/Useful-Hydra-libraries

--local application = require "mjolnir.application"
--local hotkey = require "mjolnir.hotkey"
--local window = require "mjolnir.window"
--local fnutil = require "mjolnir.fnutils"
--local grid = require "mjolnir.sd.grid"
--local geometry = require "mjolnir.geometry"
--local screen = require "mjolnir.screen"
--local keycodes = require "mjolnir.keycodes"
--local alert = require "mjolnir.alert"
--local appfinder = require "mjolnir.cmsj.appfinder"

local application = require "mjolnir.application"
local hotkey = require "mjolnir.hotkey"
local window = require "mjolnir.window"
local fnutil = require "mjolnir.fnutils"
local grid = require "mjolnir.bg.grid"
local geometry = require "mjolnir.geometry"
local screen = require "mjolnir.screen"
local keycodes = require "mjolnir.keycodes"
local alert = require "mjolnir.alert"
local appfinder = require "mjolnir.cmsj.appfinder"

-- init grid
grid.MARGINX = 0
grid.MARGINY = 0
grid.GRIDWIDTH = 7
grid.GRIDHEIGHT = 3

-- hydra.alert "Hydra, at your service. 

local mash_app = {"cmd", "alt", "ctrl"}
local mash = {"ctrl", "alt"}
local mashshift = {"ctrl", "alt", "shift"}

local function open_dictionary()
  --hydra.alert("Lexicon, at your service.", 0.75)
  application.launchorfocus("Dictionary")
end

local function open_terminal()
	application.launchorfocus("iterm")
end

local function open_pathfinder()
	application.launchorfocus("Path Finder")
end

local function open_chrome()
	application.launchorfocus("Google Chrome")
end

local function open_trello()
	application.launchorfocus("Trello X")
end

-- Launch applications
hotkey.bind(mash_app, 'D', open_dictionary)
hotkey.bind(mash_app, '1', open_terminal)
hotkey.bind(mash_app, '2', open_pathfinder)
hotkey.bind(mash_app, '3', open_chrome)
-- mash_app '4' reserved for dash global key
hotkey.bind(mash_app, '5', open_trello)

-- global operations
hotkey.bind(mash, ';', 
  function() grid.snap(window.focusedwindow()) end)
hotkey.bind(mash, "'", 
  function() fnutil.map(window.visiblewindows(), grid.snap) end)

-- adjust grid size
hotkey.bind(mash, '=', function() grid.adjustwidth( 1) end)
hotkey.bind(mash, '-', function() grid.adjustwidth(-1) end)
hotkey.bind(mash, ']', function() grid.adjustheight( 1) end)
hotkey.bind(mash, '[', function() grid.adjustheight(-1) end)

-- change focus
hotkey.bind(mashshift, 'H',
 function() window.focusedwindow():focuswindow_west() end)
hotkey.bind(mashshift, 'L',
 function() window.focusedwindow():focuswindow_east() end)
hotkey.bind(mashshift, 'K', 
  function() window.focusedwindow():focuswindow_north() end)
hotkey.bind(mashshift, 'J', 
  function() window.focusedwindow():focuswindow_south() end)

hotkey.bind(mash, 'M', grid.maximize_window)

hotkey.bind(mash, 'N', grid.pushwindow_nextscreen)
hotkey.bind(mash, 'P', grid.pushwindow_prevscreen)

-- move windows
hotkey.bind(mash, 'H', grid.pushwindow_left)
hotkey.bind(mash, 'J', grid.pushwindow_down)
hotkey.bind(mash, 'K', grid.pushwindow_up)
hotkey.bind(mash, 'L', grid.pushwindow_right)

-- resize windows
hotkey.bind(mash, 'Y', grid.resizewindow_thinner)
hotkey.bind(mash, 'U', grid.resizewindow_shorter)
hotkey.bind(mash, 'I', grid.resizewindow_taller)
hotkey.bind(mash, 'O', grid.resizewindow_wider)


