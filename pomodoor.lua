-- Pomodoro module
local pom_work_period_sec  = 25 * 60
local pom_rest_period_sec  = 5 * 60
local pom_work_count       = 0
local pom_curr_active_type = "work" -- {"work", "rest"}
local pom_is_active        = false
local pom_time_left        = pom_work_period_sec
local pom_disable_count    = 0

-- update display
local function pom_update_display()
  local time_min = math.floor( (pom_time_left / 60))
  local time_sec = pom_time_left - (time_min * 60)
  local str = string.format ("[%s|%02d:%02d|#%02d]", pom_curr_active_type, time_min, time_sec, pom_work_count)
  pom_menu:setTitle(str)
end

-- stop the clock
function pom_disable()
  -- disabling pomodoro twice will reset the countdown
  local pom_was_active = pom_is_active
  pom_is_active = false

  if (pom_disable_count == 0) then
     if (pom_was_active) then
      pom_timer:stop()
    end
  elseif (pom_disable_count == 1) then
    pom_time_left     = pom_work_period_sec
    pom_update_display()
  elseif (pom_disable_count >= 2) then
    if pom_menu == nil then 
      pom_disable_count = 2
      return
    end
    pom_menu:delete()
    pom_menu = nil
    pom_timer:stop()
    pom_timer = nil
  end

  pom_disable_count = pom_disable_count + 1
 
end

-- update pomodoro timer
local function pom_update_time()
  if pom_is_active == false then
    return
  else
    pom_time_left = pom_time_left - 1

    if (pom_time_left <= 0 ) then
      pom_disable()
      if pom_curr_active_type == "work" then 
        hs.alert.show("Work Complete!", 2)
        pom_work_count        =  pom_work_count + 1 
        pom_curr_active_type  = "rest"
        pom_time_left         = pom_rest_period_sec
      else 
          hs.alert.show("Done resting",2)
          pom_curr_active_type  = "work"
          pom_time_left         = pom_work_period_sec   
      end
    end
  end
end

-- update menu display
local function pom_update_menu()
  pom_update_time()
  pom_update_display()
end

local function pom_create_menu(pom_origin)
  if pom_menu == nil then
    pom_menu = hs.menubar.new()
  end
end

function pom_enable()
  pom_disable_count = 0;
  if (pom_is_active) then
    return
  elseif pom_timer == nil then
    pom_create_menu()
    pom_timer = hs.timer.new(1, pom_update_menu)
  end

  pom_is_active = true
  pom_timer:start()
end

-- Usage examples:

-- init pomodoro -- show menu immediately
-- pom_create_menu()
-- pom_update_menu()

-- show menu only on first pom_enable
--hs.hotkey.bind(mash, '9', function() pom_enable() end)
--hs.hotkey.bind(mash, '0', function() pom_disable() end)
