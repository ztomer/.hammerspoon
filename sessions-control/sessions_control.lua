--Sessions control--
--[[
A script for hammerspoon(Mac)

Description:
Use a set of hotkeys to control some sessions which is a set of windows.
You can easily minimize all windows of a session, and unminimize the another one.
We will also save the full screen status, will set window full screen if it was.

Author: PapEr (zw.paper@gmail.com)
--]]


require('sessions-control-hammerspoon/sessions_head')

-- init
sessionsRead()

key_fn = {'cmd','alt','ctrl'}
key_sessions_reload = 'O'
key_session_show = 'P'
key_session_pre = '['
key_session_next = ']'
key_win_add_to_curr = 'L'
key_win_del_from_curr = ';'
--[[
Key bindings
--]]

-- Reload sessions
hs.hotkey.bind(key_fn, key_sessions_reload, sessionsReload)

-- Show sessions list
hs.hotkey.bind(key_fn, key_session_show, sessionsShow)

-- Switch to previous session
hs.hotkey.bind(key_fn, key_session_pre, function()
	local i = current - 1
	if current == 1 then i = #sessions end
	sessionSwitch(i)
end)

-- Switch to next session
hs.hotkey.bind(key_fn, key_session_next, function()
	local i = current + 1
	if current == #sessions then i = 1 end
	sessionSwitch(i)
end)

-- Binding numbers for fast switching
for i = 1, #sessions do
	hs.hotkey.bind(key_fn, tostring(i), function() sessionSwitch(i) end)
end
-- Add current window into current session
hs.hotkey.bind(key_fn, key_win_add_to_curr, function()
	local win = hs.window.focusedWindow()
	if win and win:id() then
		winAddToSession(win, current)
	else
		hs.notify.new({title='Add window to ' .. sessions[current][index_session],
			   		  informativeText='No focused window'}):send():release()
	end
end)

-- Del current window from currunt session
hs.hotkey.bind(key_fn, key_win_del_from_curr, function()
	local win = hs.window.focusedWindow()
	if win and win:id() then
		winDelFromSession(win, current)
	else
		hs.notify.new({title='Del window from ' .. sessions[current][index_session],
			   		  informativeText='No focused window'}):send():release()
	end
end)
