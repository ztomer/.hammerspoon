--- Pomodoro timer module
--------------------------------------------------------------------------------
local logger = require("core.logger")
local utils = require("core.utils")
local state = require("core.state")
local events = require("core.events")

local pom = {}

-- Initialize state
function pom.init(config)
    config = config or {}

    -- Set up configuration
    local pom_config = {
        enable_color_bar = config.enable_color_bar ~= false,
        work_period_sec = config.work_period_sec or (25 * 60),
        rest_period_sec = config.rest_period_sec or (5 * 60),
        indicator_height = config.indicator_height or 0.2,
        indicator_alpha = config.indicator_alpha or 0.3,
        indicator_in_all_spaces = config.indicator_in_all_spaces ~= false,
        color_time_remaining = config.color_time_remaining or hs.drawing.color.green,
        color_time_used = config.color_time_used or hs.drawing.color.red
    }

    -- Store configuration in state
    state.set("pomodoro", "config", pom_config)

    -- Initialize timer state
    state.set("pomodoro", "state", {
        is_active = false,
        disable_count = 0,
        work_count = 0,
        curr_active_type = "work", -- {"work", "rest"}
        time_left = pom_config.work_period_sec,
        max_time_sec = pom_config.work_period_sec
    })

    -- Set up display objects
    pom.bar = {
        indicator_height = pom_config.indicator_height,
        indicator_alpha = pom_config.indicator_alpha,
        indicator_in_all_spaces = pom_config.indicator_in_all_spaces,
        color_time_remaining = pom_config.color_time_remaining,
        color_time_used = pom_config.color_time_used,
        c_left = hs.drawing.rectangle(hs.geometry.rect(0, 0, 0, 0)),
        c_used = hs.drawing.rectangle(hs.geometry.rect(0, 0, 0, 0))
    }

    logger.info("Pomodoro", "Initialized with work period: %s, rest period: %s",
        utils.formatDuration(pom_config.work_period_sec),
        utils.formatDuration(pom_config.rest_period_sec))

    return pom
end

--------------------------------------------------------------------------------
-- Color bar for pomodoro indicator
--------------------------------------------------------------------------------

local function pom_del_indicators()
    pom.bar.c_left:delete()
    pom.bar.c_used:delete()
end

local function pom_draw_on_menu(target_draw, screen, offset, width, fill_color)
    local screeng = screen:fullFrame()
    local screen_frame_height = screen:frame().y
    local screen_full_frame_height = screeng.y
    local height_delta = screen_frame_height - screen_full_frame_height
    local height = pom.bar.indicator_height * (height_delta)

    target_draw:setSize(hs.geometry.rect(screeng.x + offset, screen_full_frame_height, width, height))
    target_draw:setTopLeft(hs.geometry.point(screeng.x + offset, screen_full_frame_height))
    target_draw:setFillColor(fill_color)
    target_draw:setFill(true)
    target_draw:setAlpha(pom.bar.indicator_alpha)
    target_draw:setLevel(hs.drawing.windowLevels.overlay)
    target_draw:setStroke(false)
    if pom.bar.indicator_in_all_spaces then
        target_draw:setBehavior(hs.drawing.windowBehaviors.canJoinAllSpaces)
    end
    target_draw:show()
end

local function pom_draw_indicator(time_left, max_time)
    local main_screen = hs.screen.mainScreen()
    local screeng = main_screen:fullFrame()

    local time_ratio = time_left / max_time
    local width = math.ceil(screeng.w * time_ratio)
    local left_width = screeng.w - width

    pom_draw_on_menu(pom.bar.c_left, main_screen, left_width, width, pom.bar.color_time_remaining)
    pom_draw_on_menu(pom.bar.c_used, main_screen, 0, left_width, pom.bar.color_time_used)
end

--------------------------------------------------------------------------------

-- Get Pomodoro state
local function get_pom_state()
    return state.get("pomodoro", "state") or {
        is_active = false,
        disable_count = 0,
        work_count = 0,
        curr_active_type = "work",
        time_left = 0,
        max_time_sec = 0
    }
end

-- Get Pomodoro config
local function get_pom_config()
    return state.get("pomodoro", "config") or {
        enable_color_bar = true,
        work_period_sec = 25 * 60,
        rest_period_sec = 5 * 60
    }
end

-- Update Pomodoro state
local function update_pom_state(updates)
    local current = get_pom_state()
    for k, v in pairs(updates) do
        current[k] = v
    end
    state.set("pomodoro", "state", current)

    -- Also save in pom.var for backward compatibility
    pom.var = current
end

-- update display
local function pom_update_display()
    local pom_state = get_pom_state()
    local time_min = math.floor((pom_state.time_left / 60))
    local time_sec = pom_state.time_left - (time_min * 60)
    local str = string.format("[%s|%02d:%02d|#%02d]",
        pom_state.curr_active_type, time_min, time_sec, pom_state.work_count)

    if not pom_menu then
        pom_menu = hs.menubar.new()
    end

    pom_menu:setTitle(str)

    -- Emit state update event
    events.emit("pomodoro.updated", pom_state)
end

-- stop the clock
-- Stateful:
-- * Disabling once will pause the countdown
-- * Disabling twice will reset the countdown
-- * Disabling trice will shut down and hide the pomodoro timer
function pom.disable()
    local pom_state = get_pom_state()
    local pom_was_active = pom_state.is_active

    -- Update state
    update_pom_state({
        is_active = false,
        disable_count = pom_state.disable_count + 1
    })

    local pom_config = get_pom_config()

    -- Handle different disable stages
    if (pom_state.disable_count == 0) then
        if (pom_was_active) then
            if pom_timer then
                pom_timer:stop()
            end
            logger.info("Pomodoro", "Timer paused")
            events.emit("pomodoro.paused", pom_state)
        end
    elseif (pom_state.disable_count == 1) then
        -- Reset the timer
        update_pom_state({
            time_left = pom_config.work_period_sec,
            curr_active_type = "work"
        })
        pom_update_display()
        logger.info("Pomodoro", "Timer reset")
        events.emit("pomodoro.reset", get_pom_state())
    elseif (pom_state.disable_count >= 2) then
        if pom_menu == nil then
            update_pom_state({
                disable_count = 2
            })
            return
        end

        pom_menu:delete()
        pom_menu = nil
        if pom_timer then
            pom_timer:stop()
            pom_timer = nil
        end
        pom_del_indicators()
        logger.info("Pomodoro", "Timer stopped and hidden")
        events.emit("pomodoro.stopped", get_pom_state())
    end
end

-- update pomodoro timer
local function pom_update_time()
    local pom_state = get_pom_state()

    if pom_state.is_active == false then
        return
    else
        local new_time_left = pom_state.time_left - 1
        update_pom_state({
            time_left = new_time_left
        })

        if (new_time_left <= 0) then
            pom.disable()
            local pom_config = get_pom_config()

            if pom_state.curr_active_type == "work" then
                hs.alert.show("Work Complete!", 2)
                update_pom_state({
                    work_count = pom_state.work_count + 1,
                    curr_active_type = "rest",
                    time_left = pom_config.rest_period_sec,
                    max_time_sec = pom_config.rest_period_sec
                })
                logger.info("Pomodoro", "Work completed, starting rest period")
                events.emit("pomodoro.work_completed", get_pom_state())
            else
                hs.alert.show("Done resting", 2)
                update_pom_state({
                    curr_active_type = "work",
                    time_left = pom_config.work_period_sec,
                    max_time_sec = pom_config.work_period_sec
                })
                logger.info("Pomodoro", "Rest completed, ready for next work period")
                events.emit("pomodoro.rest_completed", get_pom_state())
            end
        end

        -- draw color bar indicator, if enabled.
        local pom_config = get_pom_config()
        if (pom_config.enable_color_bar) then
            pom_draw_indicator(pom_state.time_left, pom_state.max_time_sec)
        end
    end
end

-- update menu display
local function pom_update_menu()
    pom_update_time()
    pom_update_display()
end

local function pom_create_menu()
    if pom_menu == nil then
        pom_menu = hs.menubar.new()
        pom.bar.c_left = hs.drawing.rectangle(hs.geometry.rect(0, 0, 0, 0))
        pom.bar.c_used = hs.drawing.rectangle(hs.geometry.rect(0, 0, 0, 0))
    end
end

-- start the pomodoro timer
function pom.enable()
    update_pom_state({
        disable_count = 0
    })

    local pom_state = get_pom_state()

    if (pom_state.is_active) then
        return
    end

    pom_create_menu()
    pom_timer = hs.timer.new(1, pom_update_menu)

    update_pom_state({
        is_active = true
    })
    pom_timer:start()

    logger.info("Pomodoro", "Timer started")
    events.emit("pomodoro.started", get_pom_state())
end

-- reset work count
function pom.reset_work()
    update_pom_state({
        work_count = 0
    })
    pom_update_display()
    logger.info("Pomodoro", "Work count reset")
    events.emit("pomodoro.work_reset")
}

-- Get current state
function pom.get_state()
    return get_pom_state()
end

-- Return the module
return pom