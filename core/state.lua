--[[
  state.lua - Centralized state management for Hammerspoon modules

  This module provides a unified state store for all Hammerspoon modules,
  ensuring consistent data access and preventing state inconsistencies
  between different parts of the application.

  Usage:
    local state = require("core.state").init()

    -- Store data
    state.set("zones", "center", { id = "center", tiles = {...} })

    -- Get data
    local zone = state.get("zones", "center")

    -- Track window state
    state.trackWindow(win_id, { zone_id = "center", tile_idx = 2 })

    -- Get window state
    local window_state = state.getWindowState(win_id)

    -- Subscribe to state changes
    state.subscribe("windows", function(window_id, new_state, old_state)
      -- Handle state change
    end)
]] local logger = require("core.logger")
local state = {}

-- Internal state storage
local _store = {
    zones = {}, -- Zones by ID
    windows = {}, -- Window state by window ID
    screens = {}, -- Screen information by screen ID
    memory = {}, -- Position memory state
    layouts = {}, -- Layout configurations
    app_switcher = {}, -- App switcher state
    pomodoro = {} -- Pomodoro timer state
}

-- Event subscribers
local _subscribers = {}

-- Helper for deep copying tables
local function _deepCopy(orig)
    local copy
    if type(orig) == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[_deepCopy(orig_key)] = _deepCopy(orig_value)
        end
        setmetatable(copy, _deepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

-- Helper for merging tables
local function _merge(target, source)
    for k, v in pairs(source) do
        if type(v) == "table" and type(target[k]) == "table" then
            _merge(target[k], v)
        else
            target[k] = v
        end
    end
    return target
end

-- Notify subscribers of state changes
local function _notifySubscribers(category, key, value, old_value)
    if not _subscribers[category] then
        return
    end

    for _, subscriber in ipairs(_subscribers[category]) do
        -- Try-catch to prevent subscriber errors from affecting state
        local success, err = pcall(function()
            subscriber(key, value, old_value)
        end)

        if not success then
            logger.error("State", "Subscriber error: %s", err)
        end
    end
end

-- Set a value in the state store with optional notification
function state.set(category, key, value, silent)
    if not category or not key then
        logger.error("State", "Cannot set state without category and key")
        return false
    end

    -- Ensure category exists
    if not _store[category] then
        _store[category] = {}
    end

    -- Store old value for notifications
    local old_value = nil
    if not silent then
        old_value = _deepCopy(_store[category][key])
    end

    -- Set the new value (deep copy to prevent external modification)
    _store[category][key] = _deepCopy(value)

    -- Notify subscribers unless silent
    if not silent then
        _notifySubscribers(category, key, value, old_value)
    end

    return true
end

-- Get a value from the state store
function state.get(category, key)
    if not category then
        logger.error("State", "Cannot get state without category")
        return nil
    end

    -- Return whole category if no key specified
    if not key then
        -- Return a deep copy to prevent direct modification
        return _deepCopy(_store[category])
    end

    -- Ensure category exists
    if not _store[category] then
        return nil
    end

    -- Return a deep copy to prevent direct modification
    return _deepCopy(_store[category][key])
end

-- Subscribe to changes in a category
function state.subscribe(category, callback)
    if not category or type(callback) ~= "function" then
        logger.error("State", "Invalid subscription: requires category and callback function")
        return false
    end

    if not _subscribers[category] then
        _subscribers[category] = {}
    end

    table.insert(_subscribers[category], callback)
    return true
end

-- Unsubscribe from changes in a category
function state.unsubscribe(category, callback)
    if not category or not _subscribers[category] then
        return false
    end

    for i, subscriber in ipairs(_subscribers[category]) do
        if subscriber == callback then
            table.remove(_subscribers[category], i)
            return true
        end
    end

    return false
end

-- Update a partial state (merge with existing)
function state.update(category, key, partial, silent)
    if not category or not key then
        logger.error("State", "Cannot update state without category and key")
        return false
    end

    -- Get existing state or initialize empty table
    local existing = state.get(category, key) or {}

    -- Merge partial update with existing state
    local updated = _merge(_deepCopy(existing), _deepCopy(partial))

    -- Set the updated state
    return state.set(category, key, updated, silent)
end

-- Remove a key from state
function state.remove(category, key, silent)
    if not category or not key then
        logger.error("State", "Cannot remove state without category and key")
        return false
    end

    -- Ensure category exists
    if not _store[category] then
        return false
    end

    -- Check if key exists
    if _store[category][key] == nil then
        return false
    end

    -- Store old value for notifications
    local old_value = nil
    if not silent then
        old_value = _deepCopy(_store[category][key])
    end

    -- Remove the key
    _store[category][key] = nil

    -- Notify subscribers unless silent
    if not silent then
        _notifySubscribers(category, key, nil, old_value)
    end

    return true
end

-- Clear all data in a category
function state.clear(category, silent)
    if not category then
        logger.error("State", "Cannot clear state without category")
        return false
    end

    -- Nothing to clear if category doesn't exist
    if not _store[category] then
        return true
    end

    -- Store old value for notifications
    local old_value = nil
    if not silent then
        old_value = _deepCopy(_store[category])
    end

    -- Clear the category
    _store[category] = {}

    -- Notify subscribers for each key unless silent
    if not silent and old_value then
        for key, value in pairs(old_value) do
            _notifySubscribers(category, key, nil, value)
        end
    end

    return true
end

-- Reset the entire state store
function state.reset(silent)
    for category, _ in pairs(_store) do
        state.clear(category, silent)
    end
    return true
end

-- Track window state (convenience function)
function state.trackWindow(win_id, window_state)
    return state.set("windows", tostring(win_id), window_state)
end

-- Get window state (convenience function)
function state.getWindowState(win_id)
    return state.get("windows", tostring(win_id))
end

-- Register a zone (convenience function)
function state.registerZone(zone)
    if not zone or not zone.id then
        logger.error("State", "Cannot register zone without ID")
        return false
    end

    return state.set("zones", zone.id, zone)
end

-- Get a zone by ID (convenience function)
function state.getZone(zone_id)
    return state.get("zones", zone_id)
end

-- Register a screen (convenience function)
function state.registerScreen(screen)
    if not screen or not screen:id() then
        logger.error("State", "Cannot register screen without ID")
        return false
    end

    local screen_id = tostring(screen:id())
    local screen_info = {
        id = screen_id,
        name = screen:name(),
        frame = screen:frame(),
        fullFrame = screen:fullFrame(),
        mode = state.get("screens", screen_id) and state.get("screens", screen_id).mode or nil
    }

    return state.set("screens", screen_id, screen_info)
end

-- Get a screen by ID (convenience function)
function state.getScreen(screen_id)
    return state.get("screens", tostring(screen_id))
end

-- Set screen mode (convenience function)
function state.setScreenMode(screen_id, mode)
    return state.update("screens", tostring(screen_id), {
        mode = mode
    })
end

-- Save window position memory (convenience function)
function state.saveWindowMemory(app_name, screen_id, position)
    if not app_name or not screen_id then
        logger.error("State", "Cannot save window memory without app name and screen ID")
        return false
    end

    -- Ensure memory category exists for this screen
    local memory_key = tostring(screen_id)
    local screen_memory = state.get("memory", memory_key) or {}

    -- Update memory for this app
    screen_memory[app_name] = _deepCopy(position)

    return state.set("memory", memory_key, screen_memory)
end

-- Get window position memory (convenience function)
function state.getWindowMemory(app_name, screen_id)
    if not app_name or not screen_id then
        logger.error("State", "Cannot get window memory without app name and screen ID")
        return nil
    end

    local memory_key = tostring(screen_id)
    local screen_memory = state.get("memory", memory_key)

    if not screen_memory then
        return nil
    end

    return screen_memory[app_name]
end

-- Create a snapshot of current state
function state.createSnapshot()
    return _deepCopy(_store)
end

-- Restore state from a snapshot
function state.restoreSnapshot(snapshot, silent)
    if type(snapshot) ~= "table" then
        logger.error("State", "Cannot restore from invalid snapshot")
        return false
    end

    -- Replace current state with snapshot
    for category, data in pairs(snapshot) do
        -- Clear existing data
        state.clear(category, true)

        -- Restore data from snapshot
        for key, value in pairs(data) do
            state.set(category, key, value, silent)
        end
    end

    return true
end

-- Export state to JSON (requires hs.json)
function state.exportJSON()
    local json = require("hs.json")
    return json.encode(_store)
end

-- Import state from JSON (requires hs.json)
function state.importJSON(json_string, silent)
    local json = require("hs.json")
    local success, data = pcall(json.decode, json_string)

    if not success or type(data) ~= "table" then
        logger.error("State", "Failed to import JSON: %s", data)
        return false
    end

    return state.restoreSnapshot(data, silent)
end

-- Initialize the state manager
function state.init()
    logger.info("State", "Initializing state management system")
    return state
end

return state
