--[[
  grid.lua - Grid management for window tiling

  This module provides utilities for creating and working with screen grids,
  which are used to position and size windows in a structured way.

  Usage:
    local grid = require("modules.tiler.grid")

    -- Create a grid for a screen
    local my_grid = grid.createGrid(screen, 3, 2)

    -- Get position for grid coordinates
    local position = grid.getPositionForCell(my_grid, "a1")
    local region = grid.getPositionForRegion(my_grid, "a1:b2")

    -- Convert string coordinates to numeric
    local col, row = grid.parseCoordinates("b3")

    -- Get a standardized grid for a screen
    local auto_grid = grid.getGridForScreen(screen)
]] local logger = require("core.logger")
local utils = require("core.utils")
local state = require("core.state")

local grid = {}

-- Define a table for column letter to number conversion
local COLUMN_TO_NUMBER = {
    a = 1,
    b = 2,
    c = 3,
    d = 4,
    e = 5,
    f = 6,
    g = 7,
    h = 8,
    i = 9,
    j = 10,
    k = 11,
    l = 12,
    m = 13,
    n = 14,
    o = 15
}

-- Define a table for number to column letter conversion
local NUMBER_TO_COLUMN = {"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o"}

-- Parses grid coordinates like "b3" into column and row numbers
function grid.parseCoordinates(coords)
    if type(coords) ~= "string" then
        logger.error("Grid", "Invalid coordinates: %s", tostring(coords))
        return nil, nil
    end

    -- Parse the string using regex: letter followed by number
    local col_char, row_num = coords:match("([a-z])([0-9]+)")

    if not col_char or not row_num then
        logger.error("Grid", "Invalid coordinate format: %s", coords)
        return nil, nil
    end

    -- Convert column letter to number (a=1, b=2, etc.)
    local col_num = COLUMN_TO_NUMBER[col_char:lower()]

    if not col_num then
        logger.error("Grid", "Invalid column letter: %s", col_char)
        return nil, nil
    end

    -- Convert row to number
    local row = tonumber(row_num)

    return col_num, row
end

-- Converts a column number to letter (1="a", 2="b", etc.)
function grid.columnToLetter(col_num)
    if type(col_num) ~= "number" or col_num < 1 or col_num > #NUMBER_TO_COLUMN then
        logger.error("Grid", "Invalid column number: %s", tostring(col_num))
        return "a"
    end

    return NUMBER_TO_COLUMN[col_num]
end

-- Parses a region like "a1:c3" into start/end coordinates
function grid.parseRegion(region_str)
    if type(region_str) ~= "string" then
        logger.error("Grid", "Invalid region: %s", tostring(region_str))
        return nil
    end

    -- Handle named positions
    if region_str == "full" then
        return {
            start_col = 1,
            start_row = 1,
            end_col = -1,
            end_row = -1
        }
    elseif region_str == "center" then
        return {
            start_col = 2,
            start_row = 2,
            end_col = -2,
            end_row = -2
        }
    elseif region_str == "left-half" then
        return {
            start_col = 1,
            start_row = 1,
            end_col = "50%",
            end_row = -1
        }
    elseif region_str == "right-half" then
        return {
            start_col = "50%",
            start_row = 1,
            end_col = -1,
            end_row = -1
        }
    elseif region_str == "top-half" then
        return {
            start_col = 1,
            start_row = 1,
            end_col = -1,
            end_row = "50%"
        }
    elseif region_str == "bottom-half" then
        return {
            start_col = 1,
            start_row = "50%",
            end_col = -1,
            end_row = -1
        }
    end

    -- Parse region with format "a1:c3" or just "a1" for a single cell
    local start_cell, end_cell = region_str:match("([a-z][0-9]+):?([a-z][0-9]*)")

    if not start_cell then
        logger.error("Grid", "Invalid region format: %s", region_str)
        return nil
    end

    -- If only one cell specified, use it for both start and end
    end_cell = end_cell or start_cell

    -- Parse start and end coordinates
    local start_col, start_row = grid.parseCoordinates(start_cell)
    local end_col, end_row = grid.parseCoordinates(end_cell)

    if not start_col or not start_row or not end_col or not end_row then
        return nil
    end

    return {
        start_col = start_col,
        start_row = start_row,
        end_col = end_col,
        end_row = end_row
    }
end

-- Create a grid for a screen with specified dimensions
function grid.createGrid(screen, cols, rows, options)
    if not screen then
        logger.error("Grid", "Cannot create grid without screen")
        return nil
    end

    options = options or {}

    -- Get the screen frame
    local frame = screen:frame()

    -- Create grid object
    local grid_obj = {
        screen_id = screen:id(),
        screen_name = screen:name(),
        cols = cols,
        rows = rows,
        frame = {
            x = frame.x,
            y = frame.y,
            w = frame.w,
            h = frame.h
        },
        margins = options.margins or {
            enabled = false,
            size = 0,
            screen_edge = false
        },
        cell_width = frame.w / cols,
        cell_height = frame.h / rows,
        id = options.id or (screen:name() .. "_" .. cols .. "x" .. rows)
    }

    -- Store the grid in state
    state.set("grids", grid_obj.id, grid_obj)

    logger.debug("Grid", "Created %dx%d grid for screen %s", cols, rows, screen:name())

    return grid_obj
end

-- Get a position for a single cell in the grid
function grid.getPositionForCell(grid_obj, cell_or_col, row)
    if not grid_obj then
        logger.error("Grid", "Invalid grid")
        return nil
    end

    local col, row_num

    -- Handle different parameter formats
    if type(cell_or_col) == "string" and not row then
        -- String format like "a1"
        col, row_num = grid.parseCoordinates(cell_or_col)
    elseif type(cell_or_col) == "number" and type(row) == "number" then
        -- Numeric format with separate col and row
        col, row_num = cell_or_col, row
    else
        logger.error("Grid", "Invalid cell specification")
        return nil
    end

    -- Validate coordinates
    if not col or not row_num or col < 1 or col > grid_obj.cols or row_num < 1 or row_num > grid_obj.rows then
        logger.error("Grid", "Cell coordinates out of bounds: col=%s, row=%s (grid is %dx%d)", tostring(col),
            tostring(row_num), grid_obj.cols, grid_obj.rows)
        return nil
    end

    -- Calculate base position without margins
    local x = grid_obj.frame.x + (col - 1) * grid_obj.cell_width
    local y = grid_obj.frame.y + (row_num - 1) * grid_obj.cell_height
    local w = grid_obj.cell_width
    local h = grid_obj.cell_height

    -- Apply margins if enabled
    if grid_obj.margins.enabled then
        local margin_size = grid_obj.margins.size

        -- Apply screen edge margins if enabled
        if grid_obj.margins.screen_edge then
            -- Left edge
            if col == 1 then
                x = x + margin_size
                w = w - margin_size
            end

            -- Top edge
            if row_num == 1 then
                y = y + margin_size
                h = h - margin_size
            end

            -- Right edge
            if col == grid_obj.cols then
                w = w - margin_size
            end

            -- Bottom edge
            if row_num == grid_obj.rows then
                h = h - margin_size
            end
        end

        -- Apply internal margins between cells
        -- Only subtract from width if this isn't the rightmost column
        if col < grid_obj.cols then
            w = w - margin_size
        end

        -- Only subtract from height if this isn't the bottom row
        if row_num < grid_obj.rows then
            h = h - margin_size
        end

        -- Add margin to x position if not in the leftmost column
        if col > 1 and not grid_obj.margins.screen_edge then
            x = x + margin_size
            w = w - margin_size
        end

        -- Add margin to y position if not in the top row
        if row_num > 1 and not grid_obj.margins.screen_edge then
            y = y + margin_size
            h = h - margin_size
        end
    end

    -- Ensure the position stays within screen bounds
    if x + w > grid_obj.frame.x + grid_obj.frame.w then
        w = (grid_obj.frame.x + grid_obj.frame.w) - x
    end

    if y + h > grid_obj.frame.y + grid_obj.frame.h then
        h = (grid_obj.frame.y + grid_obj.frame.h) - y
    end

    -- Return position with human-readable description
    return {
        x = x,
        y = y,
        w = w,
        h = h,
        description = grid.columnToLetter(col) .. row_num
    }
end

-- Process a region with flexible coordinate handling
local function processRegion(grid_obj, region)
    local start_col, start_row, end_col, end_row

    -- Process region to get actual cell coordinates
    start_col = region.start_col
    start_row = region.start_row
    end_col = region.end_col
    end_row = region.end_row

    -- Handle special values for region bounds

    -- Percentage-based positioning
    if type(start_col) == "string" and start_col:match("(%d+)%%") then
        local percent = tonumber(start_col:match("(%d+)"))
        start_col = math.max(1, math.ceil(grid_obj.cols * percent / 100))
    end

    if type(start_row) == "string" and start_row:match("(%d+)%%") then
        local percent = tonumber(start_row:match("(%d+)"))
        start_row = math.max(1, math.ceil(grid_obj.rows * percent / 100))
    end

    if type(end_col) == "string" and end_col:match("(%d+)%%") then
        local percent = tonumber(end_col:match("(%d+)"))
        end_col = math.min(grid_obj.cols, math.floor(grid_obj.cols * percent / 100))
    end

    if type(end_row) == "string" and end_row:match("(%d+)%%") then
        local percent = tonumber(end_row:match("(%d+)"))
        end_row = math.min(grid_obj.rows, math.floor(grid_obj.rows * percent / 100))
    end

    -- Negative indexing (from the end)
    if type(end_col) == "number" and end_col < 0 then
        end_col = grid_obj.cols + end_col + 1
    end

    if type(end_row) == "number" and end_row < 0 then
        end_row = grid_obj.rows + end_row + 1
    end

    -- Ensure bounds
    start_col = math.max(1, math.min(start_col, grid_obj.cols))
    start_row = math.max(1, math.min(start_row, grid_obj.rows))
    end_col = math.max(1, math.min(end_col, grid_obj.cols))
    end_row = math.max(1, math.min(end_row, grid_obj.rows))

    -- Ensure start <= end
    if start_col > end_col then
        start_col, end_col = end_col, start_col
    end

    if start_row > end_row then
        start_row, end_row = end_row, start_row
    end

    return start_col, start_row, end_col, end_row
end

-- Get a position for a region in the grid
function grid.getPositionForRegion(grid_obj, region_spec)
    if not grid_obj then
        logger.error("Grid", "Invalid grid")
        return nil
    end

    local region

    -- Handle different parameter formats
    if type(region_spec) == "string" then
        -- String format like "a1:c3" or named position like "center"
        region = grid.parseRegion(region_spec)
        if not region then
            return nil
        end
    elseif type(region_spec) == "table" then
        -- Table format with start_col, start_row, end_col, end_row
        region = region_spec
    else
        logger.error("Grid", "Invalid region specification")
        return nil
    end

    -- Process the region to get actual coordinates
    local start_col, start_row, end_col, end_row = processRegion(grid_obj, region)

    -- Create a description for this region
    local description
    if start_col == end_col and start_row == end_row then
        -- Single cell
        description = grid.columnToLetter(start_col) .. start_row
    else
        -- Region
        description = grid.columnToLetter(start_col) .. start_row .. ":" .. grid.columnToLetter(end_col) .. end_row
    end

    -- For single cell, use getPositionForCell
    if start_col == end_col and start_row == end_row then
        return grid.getPositionForCell(grid_obj, start_col, start_row)
    end

    -- Calculate the starting position of the region
    local x = grid_obj.frame.x + (start_col - 1) * grid_obj.cell_width
    local y = grid_obj.frame.y + (start_row - 1) * grid_obj.cell_height

    -- Calculate width and height of the region
    local width = (end_col - start_col + 1) * grid_obj.cell_width
    local height = (end_row - start_row + 1) * grid_obj.cell_height

    -- Apply margins if enabled
    if grid_obj.margins.enabled then
        local margin_size = grid_obj.margins.size

        -- Apply screen edge margins
        if grid_obj.margins.screen_edge then
            -- Left edge
            if start_col == 1 then
                x = x + margin_size
                width = width - margin_size
            end

            -- Top edge
            if start_row == 1 then
                y = y + margin_size
                height = height - margin_size
            end

            -- Right edge
            if end_col == grid_obj.cols then
                width = width - margin_size
            end

            -- Bottom edge
            if end_row == grid_obj.rows then
                height = height - margin_size
            end
        end

        -- Apply internal margin adjustments
        if start_col > 1 and not grid_obj.margins.screen_edge then
            x = x + margin_size
            width = width - margin_size
        end

        if start_row > 1 and not grid_obj.margins.screen_edge then
            y = y + margin_size
            height = height - margin_size
        end

        -- Internal margins between cells are already accounted for in cell width/height

        -- Remove internal margins that would be doubled
        local internal_cols = end_col - start_col
        local internal_rows = end_row - start_row

        if internal_cols > 0 then
            width = width - (internal_cols * margin_size)
        end

        if internal_rows > 0 then
            height = height - (internal_rows * margin_size)
        end
    end

    -- Ensure the position stays within screen bounds
    if x + width > grid_obj.frame.x + grid_obj.frame.w then
        width = (grid_obj.frame.x + grid_obj.frame.w) - x
    end

    if y + height > grid_obj.frame.y + grid_obj.frame.h then
        height = (grid_obj.frame.y + grid_obj.frame.h) - y
    end

    return {
        x = x,
        y = y,
        w = width,
        h = height,
        description = description
    }
end

-- Convert a position table to a hs.geometry.rect
function grid.positionToRect(position)
    if not position then
        return nil
    end

    return hs.geometry.rect(position.x, position.y, position.w, position.h)
end

-- Get an appropriate grid for a screen based on its properties
function grid.getGridForScreen(screen, config)
    if not screen then
        logger.error("Grid", "Cannot create grid without screen")
        return nil
    end

    config = config or {}

    -- Check if we already have a grid for this screen
    local screen_id = screen:id()
    local existing_grids = state.get("grids")

    if existing_grids then
        for _, grid_obj in pairs(existing_grids) do
            if grid_obj.screen_id == screen_id then
                logger.debug("Grid", "Using existing grid for screen %s: %dx%d", screen:name(), grid_obj.cols,
                    grid_obj.rows)
                return grid_obj
            end
        end
    end

    -- No existing grid, determine best grid based on screen properties
    local screen_name = screen:name()
    local screen_frame = screen:frame()
    local is_portrait = screen_frame.h > screen_frame.w

    -- Determine grid dimensions
    local cols, rows

    -- 1. Check for explicit configuration
    if config.custom_screens and config.custom_screens[screen_name] then
        local custom_config = config.custom_screens[screen_name]
        cols = custom_config.grid and custom_config.grid.cols
        rows = custom_config.grid and custom_config.grid.rows

        if cols and rows then
            logger.debug("Grid", "Using custom config for screen %s: %dx%d", screen_name, cols, rows)
            return grid.createGrid(screen, cols, rows, {
                margins = config.margins,
                id = screen_name .. "_custom"
            })
        end
    end

    -- 2. Check for pattern match in screen name
    if config.screen_detection and config.screen_detection.patterns then
        for pattern, layout in pairs(config.screen_detection.patterns) do
            if screen_name:match(pattern) then
                if type(layout) == "table" then
                    cols = layout.cols
                    rows = layout.rows
                elseif type(layout) == "string" then
                    -- Parse string like "4x3"
                    cols, rows = layout:match("(%d+)x(%d+)")
                    cols = tonumber(cols)
                    rows = tonumber(rows)
                end

                if cols and rows then
                    logger.debug("Grid", "Using pattern match for screen %s: %dx%d", screen_name, cols, rows)
                    return grid.createGrid(screen, cols, rows, {
                        margins = config.margins,
                        id = screen_name .. "_" .. pattern
                    })
                end
            end
        end
    end

    -- 3. Try to extract screen size from name
    local size_match = screen_name:match("(%d+)[%s%-]?inch")

    if size_match then
        local screen_size = tonumber(size_match)
        logger.debug("Grid", "Extracted screen size from name: %s inches", screen_size)

        if is_portrait then
            -- Portrait mode layouts
            if config.screen_detection and config.screen_detection.portrait then
                for _, size_config in pairs(config.screen_detection.portrait) do
                    local matches = false
                    if size_config.min and size_config.max then
                        matches = screen_size >= size_config.min and screen_size <= size_config.max
                    elseif size_config.min then
                        matches = screen_size >= size_config.min
                    elseif size_config.max then
                        matches = screen_size <= size_config.max
                    end

                    if matches and size_config.layout then
                        if type(size_config.layout) == "string" then
                            -- Parse string like "1x3"
                            cols, rows = size_config.layout:match("(%d+)x(%d+)")
                            cols = tonumber(cols)
                            rows = tonumber(rows)
                        elseif type(size_config.layout) == "table" then
                            cols = size_config.layout.cols
                            rows = size_config.layout.rows
                        end

                        if cols and rows then
                            logger.debug("Grid", "Using portrait size-based layout: %dx%d", cols, rows)
                            return grid.createGrid(screen, cols, rows, {
                                margins = config.margins,
                                id = screen_name .. "_portrait_" .. screen_size
                            })
                        end
                    end
                end
            end

            -- Default portrait layouts if no match
            if screen_frame.w >= 1440 or screen_frame.h >= 2560 then
                logger.debug("Grid", "High-resolution portrait screen - using 1x3 layout")
                return grid.createGrid(screen, 1, 3, {
                    margins = config.margins,
                    id = screen_name .. "_portrait_hires"
                })
            else
                logger.debug("Grid", "Standard portrait screen - using 1x2 layout")
                return grid.createGrid(screen, 1, 2, {
                    margins = config.margins,
                    id = screen_name .. "_portrait_standard"
                })
            end
        else
            -- Landscape mode layouts based on size
            if config.screen_detection and config.screen_detection.sizes then
                for _, size_config in pairs(config.screen_detection.sizes) do
                    local matches = false
                    if size_config.min and size_config.max then
                        matches = screen_size >= size_config.min and screen_size <= size_config.max
                    elseif size_config.min then
                        matches = screen_size >= size_config.min
                    elseif size_config.max then
                        matches = screen_size <= size_config.max
                    end

                    if matches and size_config.layout then
                        if type(size_config.layout) == "string" then
                            -- Parse string like "4x3"
                            cols, rows = size_config.layout:match("(%d+)x(%d+)")
                            cols = tonumber(cols)
                            rows = tonumber(rows)
                        elseif type(size_config.layout) == "table" then
                            cols = size_config.layout.cols
                            rows = size_config.layout.rows
                        end

                        if cols and rows then
                            logger.debug("Grid", "Using size-based layout: %dx%d", cols, rows)
                            return grid.createGrid(screen, cols, rows, {
                                margins = config.margins,
                                id = screen_name .. "_size_" .. screen_size
                            })
                        end
                    end
                end
            end
        end
    end

    -- 4. Resolution-based fallback
    if is_portrait then
        if screen_frame.w >= 1440 or screen_frame.h >= 2560 then
            logger.debug("Grid", "High-resolution portrait screen - using 1x3 layout")
            return grid.createGrid(screen, 1, 3, {
                margins = config.margins,
                id = screen_name .. "_portrait_hires"
            })
        else
            logger.debug("Grid", "Standard portrait screen - using 1x2 layout")
            return grid.createGrid(screen, 1, 2, {
                margins = config.margins,
                id = screen_name .. "_portrait_standard"
            })
        end
    else
        -- Landscape orientation
        local aspect_ratio = screen_frame.w / screen_frame.h
        local is_ultrawide = aspect_ratio > 2.0

        if screen_frame.w >= 3840 or screen_frame.h >= 2160 then
            logger.debug("Grid", "Detected 4K or higher resolution - using 4x3 layout")
            return grid.createGrid(screen, 4, 3, {
                margins = config.margins,
                id = screen_name .. "_4k"
            })
        elseif screen_frame.w >= 3440 or is_ultrawide then
            logger.debug("Grid", "Detected ultrawide monitor - using 4x2 layout")
            return grid.createGrid(screen, 4, 2, {
                margins = config.margins,
                id = screen_name .. "_ultrawide"
            })
        elseif screen_frame.w >= 2560 or screen_frame.h >= 1440 then
            logger.debug("Grid", "Detected 1440p resolution - using 3x3 layout")
            return grid.createGrid(screen, 3, 3, {
                margins = config.margins,
                id = screen_name .. "_1440p"
            })
        elseif screen_frame.w >= 1920 or screen_frame.h >= 1080 then
            logger.debug("Grid", "Detected 1080p resolution - using 3x2 layout")
            return grid.createGrid(screen, 3, 2, {
                margins = config.margins,
                id = screen_name .. "_1080p"
            })
        else
            logger.debug("Grid", "Detected smaller resolution - using 2x2 layout")
            return grid.createGrid(screen, 2, 2, {
                margins = config.margins,
                id = screen_name .. "_small"
            })
        end
    end
end

-- Initialize grids for all screens
function grid.initForAllScreens(config)
    logger.info("Grid", "Initializing grids for all screens")

    local screens = hs.screen.allScreens()
    local grids = {}

    for _, screen in ipairs(screens) do
        local grid_obj = grid.getGridForScreen(screen, config)
        if grid_obj then
            grids[screen:id()] = grid_obj
        end
    end

    return grids
end

return grid
