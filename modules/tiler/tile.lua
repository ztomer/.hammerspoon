--[[
  tile.lua - Tile class for window positioning

  This module defines the Tile class which represents a window position
  with dimensions and optional metadata.

  Usage:
    local Tile = require("modules.tiler.tile")

    -- Create a new tile with position and size
    local tile = Tile.new(100, 200, 800, 600)

    -- Set a description for debugging/display
    tile:setDescription("Main editor area")

    -- Convert to a frame for use with Hammerspoon windows
    local frame = tile:toFrame()
    window:setFrame(frame)

    -- Check if a point is inside this tile
    if tile:containsPoint(x, y) then
      -- Point is inside tile
    end

    -- Calculate overlap with another tile or rect
    local overlap = tile:calculateOverlap(another_tile)
]] local logger = require("core.logger")
local utils = require("core.utils")

-- Define the Tile class
local Tile = {}
Tile.__index = Tile

--- Create a new tile with position and size
-- @param x number The x coordinate of the tile
-- @param y number The y coordinate of the tile
-- @param width number The width of the tile
-- @param height number The height of the tile
-- @param options table Optional settings for the tile
-- @return Tile The new tile instance
function Tile.new(x, y, width, height, options)
    local self = setmetatable({}, Tile)

    -- Validate input types
    if type(x) ~= "number" or type(y) ~= "number" or type(width) ~= "number" or type(height) ~= "number" then
        logger.error("Tile", "Invalid parameters for Tile creation")
        x, y, width, height = 0, 0, 0, 0
    end

    -- Core properties
    self.x = x
    self.y = y
    self.width = width
    self.height = height

    -- Optional metadata
    options = options or {}
    self.description = options.description
    self.id = options.id or utils.generateUUID()
    self.tags = options.tags or {}
    self.metadata = options.metadata or {}

    return self
end

--- Create a tile from various input formats
-- @param input table|string The input to convert to a tile
-- @return Tile The new tile instance
function Tile.from(input)
    if not input then
        logger.error("Tile", "Cannot create tile from nil input")
        return Tile.new(0, 0, 0, 0)
    end

    -- Handle string descriptions like "full", "center", etc.
    if type(input) == "string" then
        local screen = hs.screen.mainScreen()
        local frame = screen:frame()

        if input == "full" then
            return Tile.new(frame.x, frame.y, frame.w, frame.h, {
                description = "Full screen"
            })
        elseif input == "center" then
            return Tile.new(frame.x + frame.w / 4, frame.y + frame.h / 4, frame.w / 2, frame.h / 2, {
                description = "Center"
            })
        elseif input == "left-half" then
            return Tile.new(frame.x, frame.y, frame.w / 2, frame.h, {
                description = "Left half"
            })
        elseif input == "right-half" then
            return Tile.new(frame.x + frame.w / 2, frame.y, frame.w / 2, frame.h, {
                description = "Right half"
            })
        elseif input == "top-half" then
            return Tile.new(frame.x, frame.y, frame.w, frame.h / 2, {
                description = "Top half"
            })
        elseif input == "bottom-half" then
            return Tile.new(frame.x, frame.y + frame.h / 2, frame.w, frame.h / 2, {
                description = "Bottom half"
            })
        end

        logger.error("Tile", "Unknown tile descriptor: %s", input)
        return Tile.new(0, 0, 0, 0)
    end

    -- Handle table inputs with different formats
    if type(input) == "table" then
        -- hs.geometry.rect
        if input._geometry and input._type == "rect" then
            return Tile.new(input.x, input.y, input.w, input.h)
        end

        -- Table with x,y,w,h fields
        if input.x ~= nil and input.y ~= nil and (input.width ~= nil or input.w ~= nil) and
            (input.height ~= nil or input.h ~= nil) then
            return Tile.new(input.x, input.y, input.width or input.w, input.height or input.h, {
                description = input.description,
                id = input.id,
                tags = input.tags,
                metadata = input.metadata
            })
        end

        -- Array-style definition [x, y, width, height]
        if #input >= 4 and type(input[1]) == "number" then
            return Tile.new(input[1], input[2], input[3], input[4])
        end
    end

    -- Default case - empty tile
    logger.error("Tile", "Unsupported input format for Tile.from")
    return Tile.new(0, 0, 0, 0)
end

--- Create a copy of this tile
-- @return Tile A new tile with the same properties
function Tile:copy()
    return Tile.new(self.x, self.y, self.width, self.height, {
        description = self.description,
        id = self.id,
        tags = utils.deepCopy(self.tags),
        metadata = utils.deepCopy(self.metadata)
    })
end

--- Set a human-readable description for this tile
-- @param desc string The description text
-- @return Tile self (for method chaining)
function Tile:setDescription(desc)
    self.description = desc
    return self
end

--- Add a tag to this tile
-- @param tag string The tag to add
-- @return Tile self (for method chaining)
function Tile:addTag(tag)
    if type(tag) == "string" and not utils.tableContains(self.tags, tag) then
        table.insert(self.tags, tag)
    end
    return self
end

--- Check if this tile has a specific tag
-- @param tag string The tag to check for
-- @return boolean True if the tile has the tag
function Tile:hasTag(tag)
    return utils.tableContains(self.tags, tag)
end

--- Set a metadata value
-- @param key string The metadata key
-- @param value any The value to store
-- @return Tile self (for method chaining)
function Tile:setMetadata(key, value)
    if type(key) == "string" then
        self.metadata[key] = value
    end
    return self
end

--- Get a metadata value
-- @param key string The metadata key
-- @param default any The default value if key not found
-- @return any The metadata value or default
function Tile:getMetadata(key, default)
    if self.metadata[key] ~= nil then
        return self.metadata[key]
    end
    return default
end

--- Convert this tile to a string for logging
-- @return string A string representation of this tile
function Tile:toString()
    local desc = self.description and (" - " .. self.description) or ""
    return string.format("Tile(x=%.1f, y=%.1f, w=%.1f, h=%.1f%s)", self.x, self.y, self.width, self.height, desc)
end

--- Get the area of this tile
-- @return number The area in pixels
function Tile:getArea()
    return self.width * self.height
end

--- Check if a point is inside this tile
-- @param x number|table The x coordinate or a point table {x,y}
-- @param y number The y coordinate (optional if x is a table)
-- @return boolean True if the point is inside the tile
function Tile:containsPoint(x, y)
    -- Handle point as table
    if type(x) == "table" and x.x ~= nil and x.y ~= nil then
        y = x.y
        x = x.x
    end

    if type(x) ~= "number" or type(y) ~= "number" then
        return false
    end

    return x >= self.x and x <= self.x + self.width and y >= self.y and y <= self.y + self.height
end

--- Get the center point of this tile
-- @return table {x,y} The center coordinates
function Tile:getCenter()
    return {
        x = self.x + self.width / 2,
        y = self.y + self.height / 2
    }
end

--- Calculate the distance from a point to this tile's center
-- @param x number|table The x coordinate or a point table {x,y}
-- @param y number The y coordinate (optional if x is a table)
-- @return number The distance in pixels
function Tile:distanceFromCenter(x, y)
    -- Handle point as table
    if type(x) == "table" and x.x ~= nil and x.y ~= nil then
        y = x.y
        x = x.x
    end

    if type(x) ~= "number" or type(y) ~= "number" then
        return math.huge
    end

    local center = self:getCenter()
    return math.sqrt((center.x - x) ^ 2 + (center.y - y) ^ 2)
end

--- Calculate the overlap with another tile or rect
-- @param other Tile|table The other tile or rect to compare with
-- @return number The area of overlap in pixels
function Tile:calculateOverlap(other)
    if not other then
        return 0
    end

    -- Extract coordinates from the other object
    local other_x, other_y, other_width, other_height

    if type(other) == "table" then
        if other.x ~= nil and other.y ~= nil then
            other_x = other.x
            other_y = other.y
            other_width = other.width or other.w or 0
            other_height = other.height or other.h or 0
        else
            return 0
        end
    end

    -- Calculate intersection
    local x_overlap = math.max(0, math.min(self.x + self.width, other_x + other_width) - math.max(self.x, other_x))

    local y_overlap = math.max(0, math.min(self.y + self.height, other_y + other_height) - math.max(self.y, other_y))

    -- Return overlap area
    return x_overlap * y_overlap
end

--- Calculate the overlap percentage with another tile
-- @param other Tile|table The other tile or rect to compare with
-- @return number The percentage of this tile that overlaps with other (0-1)
function Tile:calculateOverlapPercentage(other)
    local overlap_area = self:calculateOverlap(other)
    local this_area = self:getArea()

    if this_area <= 0 then
        return 0
    end

    return overlap_area / this_area
end

--- Check if this tile is approximately the same as another
-- @param other Tile|table The other tile to compare with
-- @param tolerance number The maximum difference to consider equal (default: 5)
-- @return boolean True if tiles are approximately equal
function Tile:approximatelyEquals(other, tolerance)
    if not other then
        return false
    end

    tolerance = tolerance or 5

    -- Extract coordinates from the other object
    local other_x, other_y, other_width, other_height

    if type(other) == "table" then
        if other.x ~= nil and other.y ~= nil then
            other_x = other.x
            other_y = other.y
            other_width = other.width or other.w or 0
            other_height = other.height or other.h or 0
        else
            return false
        end
    end

    -- Check if all coordinates are within tolerance
    return math.abs(self.x - other_x) <= tolerance and math.abs(self.y - other_y) <= tolerance and
               math.abs(self.width - other_width) <= tolerance and math.abs(self.height - other_height) <= tolerance
end

--- Convert to a hs.geometry.rect for use with Hammerspoon
-- @return hs.geometry.rect A Hammerspoon rect
function Tile:toFrame()
    return hs.geometry.rect(self.x, self.y, self.width, self.height)
end

--- Convert to a table with x,y,w,h fields
-- @return table A table with x,y,w,h fields
function Tile:toTable()
    return {
        x = self.x,
        y = self.y,
        w = self.width,
        h = self.height,
        description = self.description,
        id = self.id
    }
end

--- Adjust this tile by the given delta values
-- @param dx number X adjustment (can be nil to leave unchanged)
-- @param dy number Y adjustment (can be nil to leave unchanged)
-- @param dw number Width adjustment (can be nil to leave unchanged)
-- @param dh number Height adjustment (can be nil to leave unchanged)
-- @return Tile self (for method chaining)
function Tile:adjust(dx, dy, dw, dh)
    if type(dx) == "number" then
        self.x = self.x + dx
    end
    if type(dy) == "number" then
        self.y = self.y + dy
    end
    if type(dw) == "number" then
        self.width = self.width + dw
    end
    if type(dh) == "number" then
        self.height = self.height + dh
    end
    return self
end

--- Constrain this tile to fit within a rect
-- @param rect Tile|table The rect to constrain within
-- @return Tile self (for method chaining)
function Tile:constrainTo(rect)
    if not rect then
        return self
    end

    -- Extract coordinates from the rect
    local rect_x, rect_y, rect_width, rect_height

    if type(rect) == "table" then
        if rect.x ~= nil and rect.y ~= nil then
            rect_x = rect.x
            rect_y = rect.y
            rect_width = rect.width or rect.w or 0
            rect_height = rect.height or rect.h or 0
        else
            return self
        end
    end

    -- Constrain width and height
    if self.x + self.width > rect_x + rect_width then
        self.width = (rect_x + rect_width) - self.x
    end

    if self.y + self.height > rect_y + rect_height then
        self.height = (rect_y + rect_height) - self.y
    end

    -- Ensure positive dimensions
    self.width = math.max(1, self.width)
    self.height = math.max(1, self.height)

    return self
end

--- Expand or contract this tile by a margin value
-- @param margin number The margin to apply (positive to expand, negative to contract)
-- @return Tile self (for method chaining)
function Tile:applyMargin(margin)
    if type(margin) ~= "number" then
        return self
    end

    self.x = self.x - margin
    self.y = self.y - margin
    self.width = self.width + (margin * 2)
    self.height = self.height + (margin * 2)

    -- Ensure positive dimensions
    self.width = math.max(1, self.width)
    self.height = math.max(1, self.height)

    return self
end

--- Resize this tile to match a specific aspect ratio
-- @param aspect_ratio number The desired width/height ratio
-- @param preserve string What to preserve: "width", "height", "area" or "center"
-- @return Tile self (for method chaining)
function Tile:setAspectRatio(aspect_ratio, preserve)
    if type(aspect_ratio) ~= "number" or aspect_ratio <= 0 then
        return self
    end

    preserve = preserve or "center"

    local current_ratio = self.width / self.height
    local center = self:getCenter()

    if current_ratio == aspect_ratio then
        -- Already at desired ratio
        return self
    end

    if preserve == "width" then
        -- Adjust height to match ratio
        local new_height = self.width / aspect_ratio
        local height_delta = new_height - self.height

        if preserve == "center" then
            self.y = self.y - (height_delta / 2)
        end

        self.height = new_height
    elseif preserve == "height" then
        -- Adjust width to match ratio
        local new_width = self.height * aspect_ratio
        local width_delta = new_width - self.width

        if preserve == "center" then
            self.x = self.x - (width_delta / 2)
        end

        self.width = new_width
    elseif preserve == "area" then
        -- Preserve area while changing ratio
        local area = self:getArea()
        local new_height = math.sqrt(area / aspect_ratio)
        local new_width = area / new_height

        -- Center the new dimensions over the old center
        self.x = center.x - (new_width / 2)
        self.y = center.y - (new_height / 2)
        self.width = new_width
        self.height = new_height
    else -- default to "center"
        -- Preserve center point and adjust dimensions
        local new_height, new_width

        if current_ratio > aspect_ratio then
            -- Current is wider, adjust width
            new_width = self.height * aspect_ratio
            new_height = self.height
        else
            -- Current is taller, adjust height
            new_height = self.width / aspect_ratio
            new_width = self.width
        end

        self.x = center.x - (new_width / 2)
        self.y = center.y - (new_height / 2)
        self.width = new_width
        self.height = new_height
    end

    return self
end

--- Apply frame to a window with retry for problematic applications
-- @param window hs.window The window to apply the frame to
-- @param options table Options for applying the frame
-- @return boolean True if successful
function Tile:applyToWindow(window, options)
    if not window then
        logger.error("Tile", "Cannot apply tile to nil window")
        return false
    end

    options = options or {}

    -- Get app name for special handling
    local app_name = nil
    if window:application() then
        app_name = window:application():name()
    end

    -- Apply frame using utility function
    return utils.applyFrameWithRetry(window, self:toFrame(), {
        max_attempts = options.max_attempts or 3,
        delay = options.delay or 0.1,
        animation_duration = options.animation_duration,
        is_problem_app = options.is_problem_app or
            (options.problem_apps and app_name and utils.tableContains(options.problem_apps, app_name))
    })
end

return Tile
