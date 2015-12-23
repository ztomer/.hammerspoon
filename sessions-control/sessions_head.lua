--Sessions control function file--
--[[
Author: PapEr (zw.paper@gmail.com)
--]]

--[[
--example of sessions
sessions = {
	{'scraper', {}},
	{'hammerspoon', {}},
	{'github', {}},
	{'wear', {}},
	{'work', {}}
}
-- each window is saved as {win, isFullScreen}
--]]

--[[
const
--]]
--index for each sessions
index_session = 1
index_windows = 2

--index for each windows
index_win = 1
index_isFull = 2

--[[
Variable
--]]
sessions = {}
current = 1
local path_session_save = hs.configdir .. '/sessions-control-hammerspoon/sessions.sav'
local path_config = hs.configdir .. '/sessions-control-hammerspoon/sessions.cfg'


--[[
Functions definition
--]]

-- session handling
function sessionsShow()
	if #sessions ~= 0 then
		local msg = ''
		for k, v in pairs(sessions) do
			if current == k then msg = msg .. '->' end
			msg = msg .. k .. ':' .. v[index_session] .. '(' .. #v[index_windows] .. ')' .. '  '
		end
		hs.notify.new({title='Sessions List:', informativeText=msg}):send():release()
	else
		hs.notify.new({title='Sessions List:', informativeText='No session'}):send():release()
	end
end


function sessionSwitch(new)
	hs.window.animationDuration = 0
	for k, v in pairs(sessions[current][index_windows]) do
		if v[index_win]:isVisible() then
			sessions[current][index_windows][k][index_isFull] = v[index_win]:isFullScreen()
			if v[index_win]:isFullScreen() then
				v[index_win]:setFullScreen(false)
				hs.timer.doAfter(2, function() v[index_win]:minimize() end);
			else
				v[index_win]:minimize()
			end
		elseif not hs.window.windowForID(v[index_win]:id()) then
			table.remove(sessions[current], k)
		end
	end

	for k, v in pairs(sessions[new][index_windows]) do
		if v[index_win]:isMinimized() then v[index_win]:unminimize() end
		if v[index_isFull] then hs.timer.doAfter(1, function() v[index_win]:setFullScreen(true) end) end
	end
	current = new
	hs.notify.new({title='Change session',
				  informativeText=current.. ': ' .. sessions[new][index_session] .. ' actived'})
				 :send():release()
	sessionsSave(sessions)
end


function sessionsReload()
	local file_config = io.open(path_config, "r")
	if file_config then
		new_sessions = {}
		for line in file_config:lines() do
			line = line:gsub("%s+", "")
			if line:sub(1, 2) == '--' or line:sub(1, 1) == '\n' then
				;
			elseif line ~= '' then
				local key = findNameInSessions(sessions, line)
				if key then
					table.insert(new_sessions, sessions[key])
				else
					table.insert(new_sessions, {line, {}})
				end
			end
		end
		sessions = new_sessions
		new_sessions = nil
		sessionsShow()
	else
		hs.notify.new({title='Read config file ' .. sessions[cur][index_session],
					  informativeText='Config file no found'})
					 :send():release()
	end
end


function sessionsToConfig(se)
-- Only run when hammerspoon reload
-- each line as a session name
-- Sync the sessions to config file
	local sessions_to_save = ''
	for k, v in pairs(se) do
		sessions_to_save = sessions_to_save .. v[1] .. '\n'
	end

	local file_sessions = assert(io.open(path_config, "w"))
	local err, msg = file_sessions:write(sessions_to_save)
	if not err then
		hs.notify.new({title='Write Error', informativeText='Can not sync sessions to config file'}):send():release()
		error('Save sessions error: ' .. msg)
	end
	file_sessions:flush()
	file_sessions:close()
end


function sessionsRead()
	local file_sessions = io.open(path_session_save, "r")
	if file_sessions then
		local close_win_counter = 0
		for line in file_sessions:lines() do
			line = line:gsub("%s+", "")
			if line:sub(1, 2) == '--' or line:sub(1, 1) == '\n' then
				;
			elseif line:sub(1, 1) == '{' then
				if #line < 2 then
					hs.notify.new({title='Read Error', informativeText='No session name after "{"'}):send():release()
					error('No session name after "{"')
				else
					table.insert(sessions, {line:sub(2, -1), {}})
				end
			elseif line:sub(1, 1) == '}' then
				if #line ~= 1 then
					hs.notify.new({title='Read Error', informativeText='Session not end with "}"'}):send():release()
					error('Session not end with "}"')
				end
				if close_win_counter ~= 0 then
					hs.notify.new({title='Read Sessions',
								  informativeText=close_win_counter .. ' in ' .. sessions[#sessions][index_session] .. ' closed'})
					 			 :send():release()
					close_win_counter = 0
				end
			elseif line:sub(1, 1) == '>' then
				current = tonumber(line:match('%d+', 2))
			else
				local id = line:match('%d+')
				local isFull = line:match('%d', -1)
				if not (id and isFull) then
					hs.notify.new({title='Read Error', informativeText='Data in sav file is wrong'}):send():release()
					error('Read windows error!')
				end

				local window = hs.window.windowForID(tonumber(id))
				if not window then
					close_win_counter = close_win_counter + 1
				else
					if isFull == '1' then
						isFull = true
					elseif isFull == '0' then
						isFull = false
					else
						hs.notify.new({title='Read Error', informativeText=isFull .. ' is not a valid value, unset fullscreen'})
									 :send():release()
						isFull = false
						-- error('Read is_window_full_screen error!')
					end
					table.insert(sessions[#sessions][index_windows], {window, isFull})
				end
			end
		end
	else
		sessionsSave{{'default', {}}}
		file_sessions = io.open(path_session_save, "r")
	end

	if current > #sessions or current < 1 then
		hs.notify.new({title='Read Error', informativeText=current .. ' is not a valid session number'}):send():release()
		error('session number error!')
	end
	sessionsShow()
end


function sessionsSave(se)
-- use a '{session ' start a scope,
-- each line as a win
-- end a scope using '}'
	local sessions_to_save = ''
	for k, v in pairs(se) do
		local one_session = '{' .. v[index_session] .. '\n'
		for key, val in pairs(v[index_windows]) do
			one_session = one_session .. val[index_win]:id() .. ':' .. (val[index_isFull] and '1' or '0') .. '\n'
		end
		one_session = one_session .. '}' .. '\n'
		sessions_to_save = sessions_to_save .. one_session
	end

	sessions_to_save = sessions_to_save .. '>' .. current .. '\n'

	local file_sessions = assert(io.open(path_session_save, "w"))
	local err, msg = file_sessions:write(sessions_to_save)
	if not err then
		hs.notify.new({title='Write Error', informativeText='Can not save sessions to disk'}):send():release()
		error('Save sessions error: ' .. msg)
	end
	file_sessions:flush()
	file_sessions:close()
end


-- Window handling
function winDelFromSession(win, cur)
	local key = findWinIdInSession(sessions[cur][index_windows], win)
	if key then
		table.remove(sessions[cur][index_windows], key)
		hs.notify.new({title='Del window from ' .. sessions[cur][index_session],
					  informativeText=win:title() .. ' Deleted' .. ' (All: '.. #sessions[cur][index_windows] .. ')'})
					 :send():release()
	else
		hs.notify.new({title='Del window from ' .. sessions[cur][index_session],
					  informativeText='Not in this session'}):send():release()
	end
end

function winAddToSession(win, cur)
	if findWinIdInSession(sessions[cur][index_windows], win) then
		hs.notify.new({title='Add window to ' .. sessions[cur][index_session],
					  informativeText='Already added'}):send():release()
		-- found win, return.
		return
	end

	local status = {}
	table.insert(status, win)
	table.insert(status, win:isFullScreen())
	table.insert(sessions[cur][index_windows], status)
	hs.notify.new({title='Add window to ' .. sessions[cur][index_session],
				  informativeText=win:title() .. ' added' .. ' (All: '.. #sessions[cur][index_windows] .. ')'})
				 :send():release()
end


--[[
utils
--]]

-- List: Current session
-- item: Window
function findWinIdInSession(list, item)
	if list and item then
		for k, v in pairs(list) do
			if item:id() == v[1]:id() then return k end
		end
	end
	return nil
end

-- List: All sessions
-- item: session name
function findNameInSessions(list, item)
	if list and item then
		for k, v in pairs(list) do
			if item == v[1] then return k end
		end
	end
	return nil
end



-- Handling sav file
-- '--' means comment

-- Read the front part of .sav file
-- A line for one sessions
function readUserSessions()

end

-- Read the end part of .sav file
-- Generated by function
-- Start from a line '##'
function loadSystemCache()

end
