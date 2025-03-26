--[[
  events.lua - Centralized event system for Hammerspoon modules

  This module provides a simple event system that allows different parts
  of the application to subscribe to and emit events without direct dependencies.

  Usage:
    local events = require("core.events")

    -- Subscribe to an event
    events.on("window.moved", function(window_id, old_frame, new_frame)
      -- Handle window move
    end)

    -- Emit an event
    events.emit("window.moved", window_id, old_frame, new_frame)

    -- Unsubscribe from events
    local subscription = events.on("window.moved", myHandler)
    events.off(subscription)
]] local logger = require("core.logger")

local events = {
    _handlers = {},
    _next_id = 1
}

--- Subscribe to an event
-- @param event_name string The event to subscribe to
-- @param handler function The function to call when the event occurs
-- @return table Subscription object for unsubscribing
function events.on(event_name, handler)
    if type(event_name) ~= "string" or type(handler) ~= "function" then
        logger.error("Events", "Invalid subscription: requires event name and handler function")
        return nil
    end

    -- Ensure the event exists in the handlers table
    if not events._handlers[event_name] then
        events._handlers[event_name] = {}
    end

    -- Generate a unique ID for this subscription
    local subscription_id = events._next_id
    events._next_id = events._next_id + 1

    -- Create the subscription object
    local subscription = {
        id = subscription_id,
        event = event_name,
        handler = handler
    }

    -- Add to handlers
    events._handlers[event_name][subscription_id] = subscription

    logger.debug("Events", "Added subscription %d for event: %s", subscription_id, event_name)

    return subscription
end

--- Unsubscribe from an event
-- @param subscription table|number Subscription object or ID
-- @return boolean True if successfully unsubscribed
function events.off(subscription)
    -- Handle different types of subscription identifier
    local subscription_id
    local event_name

    if type(subscription) == "table" and subscription.id and subscription.event then
        subscription_id = subscription.id
        event_name = subscription.event
    elseif type(subscription) == "number" then
        subscription_id = subscription

        -- Find the event this subscription belongs to
        for evt, handlers in pairs(events._handlers) do
            if handlers[subscription_id] then
                event_name = evt
                break
            end
        end
    else
        logger.error("Events", "Invalid subscription object for removal")
        return false
    end

    -- If we couldn't find the event, fail
    if not event_name or not events._handlers[event_name] then
        logger.error("Events", "Cannot find event for subscription: %s", tostring(subscription_id))
        return false
    end

    -- Remove the subscription
    if events._handlers[event_name][subscription_id] then
        events._handlers[event_name][subscription_id] = nil
        logger.debug("Events", "Removed subscription %d for event: %s", subscription_id, event_name)
        return true
    end

    return false
end

--- Subscribe to an event once (automatically unsubscribes after first trigger)
-- @param event_name string The event to subscribe to
-- @param handler function The function to call when the event occurs
-- @return table Subscription object for unsubscribing
function events.once(event_name, handler)
    if type(event_name) ~= "string" or type(handler) ~= "function" then
        logger.error("Events", "Invalid subscription: requires event name and handler function")
        return nil
    end

    -- Create a wrapper that removes itself after execution
    local subscription
    local wrapper = function(...)
        -- Remove this subscription
        events.off({
            id = subscription.id,
            event = event_name
        })

        -- Call the original handler
        handler(...)
    end

    -- Create the actual subscription with the wrapper
    subscription = events.on(event_name, wrapper)

    return subscription
end

--- Emit an event
-- @param event_name string The event to emit
-- @param ... any Additional arguments to pass to handlers
-- @return number Number of handlers called
function events.emit(event_name, ...)
    if type(event_name) ~= "string" then
        logger.error("Events", "Invalid event name: %s", tostring(event_name))
        return 0
    end

    -- If no handlers for this event, return
    if not events._handlers[event_name] then
        return 0
    end

    local count = 0
    local args = {...} -- Capture arguments

    -- Call all handlers for this event
    for _, subscription in pairs(events._handlers[event_name]) do
        -- Call handler in protected mode to prevent one handler from breaking others
        local status, err = pcall(function()
            subscription.handler(unpack(args)) -- Use unpack instead of ... for compatibility
        end)

        if status then
            count = count + 1
        else
            logger.error("Events", "Error in handler for event %s: %s", event_name, err)
        end
    end

    return count
end

--- Get the count of subscribers for an event
-- @param event_name string The event to check
-- @return number Number of subscribers
function events.getSubscriberCount(event_name)
    if not event_name or not events._handlers[event_name] then
        return 0
    end

    local count = 0
    for _ in pairs(events._handlers[event_name]) do
        count = count + 1
    end

    return count
end

--- Remove all subscribers for an event
-- @param event_name string The event to clear
-- @return number Number of subscribers removed
function events.clearEvent(event_name)
    if not event_name or not events._handlers[event_name] then
        return 0
    end

    local count = events.getSubscriberCount(event_name)
    events._handlers[event_name] = {}

    logger.debug("Events", "Cleared %d subscribers for event: %s", count, event_name)

    return count
end

--- Remove all event subscribers
-- @return number Number of subscribers removed
function events.clearAll()
    local total = 0

    for event_name, _ in pairs(events._handlers) do
        total = total + events.clearEvent(event_name)
    end

    logger.debug("Events", "Cleared all events, removed %d total subscribers", total)

    return total
end

--- Get a list of all registered event names
-- @return table Array of event names
function events.getEventNames()
    local names = {}

    for event_name, _ in pairs(events._handlers) do
        table.insert(names, event_name)
    end

    return names
end

--- Initialize the events system
-- @return events module
function events.init()
    logger.info("Events", "Initializing event system")

    -- Define standard events
    events._standard_events = { -- Window events
    "window.created", "window.destroyed", "window.moved", "window.resized", "window.focused", "window.minimized",
    "window.unminimized", "window.hidden", "window.shown", -- Application events
    "application.launched", "application.terminated", "application.hidden", "application.shown",
    "application.activated", "application.deactivated", -- Screen events
    "screen.changed", "screen.added", "screen.removed", -- Tiler events
    "tiler.zone.created", "tiler.zone.destroyed", "tiler.window.added", "tiler.window.removed", "tiler.layout.applied",
    "tiler.layout.saved", -- System events
    "system.wakeup", "system.sleep", "system.screensaver.started", "system.screensaver.stopped",
    "system.volume.changed", "system.wifi.changed"}

    return events
end

return events
