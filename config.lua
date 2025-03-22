-- Configuration file for Hammerspoon settings
local config = {}

-- Key combinations
config.keys = {
    mash = {"ctrl", "cmd"},
    mash_app = {"shift", "ctrl"},
    mash_shift = {"shift", "ctrl", "cmd"},
    HYPER = {"shift", "ctrl", "alt", "cmd"}
}

-- Application shortcuts with direct lowercase mapping
config.appCuts = {
    q = 'BambuStudio',
    w = 'Whatsapp',
    e = 'Finder',
    r = 'Cronometer',
    t = 'iTerm',
    a = 'Notion',
    s = 'Notion Mail',
    d = 'Notion Calendar',
    f = 'Zen',
    g = 'Gmail',
    z = 'Nimble Commander',
    x = 'Claude',
    c = 'Arc',
    v = 'Visual Studio Code',
    b = 'Spotify'
}

config.hyperAppCuts = {
    q = 'IBKR Desktop',
    w = 'Weather',
    e = 'Clock',
    r = 'Discord',
    t = 'ChatGpt'
}

-- Pomodoro settings
config.pomodoro = {
    enable_color_bar = true,
    work_period_sec = 52 * 60, -- 52 minutes
    rest_period_sec = 17 * 60, -- 17 minutes
    indicator_height = 0.2, -- ratio from the height of the menubar (0..1)
    indicator_alpha = 0.3,
    indicator_in_all_spaces = true,
    color_time_remaining = hs.drawing.color.green,
    color_time_used = hs.drawing.color.red
}

-- Tiler settings
config.tiler = {
    debug = true, -- Enable debug logging
    modifier = {"ctrl", "cmd"}, -- Set default modifier keys
    focus_modifier = {"shift", "ctrl", "cmd"}, -- Default modifier for focus commands
    flash_on_focus = true,
    smart_placement = true, -- Enable smart placement of new windows

    -- Add window margin configuration
    margins = {
        enabled = true, -- Enable margins between windows
        size = 5, -- Use 5 pixels for margins (adjust as needed)
        screen_edge = true -- Apply margins to screen edges too
    },

    -- List of apps that need special window positioning handling
    problem_apps = {"Firefox", "Zen" -- Add other problematic apps here
    },

    -- Custom layouts for specific screens
    layouts = {
        custom = {
            ["DELL U3223QE"] = {
                cols = 4,
                rows = 3
            },
            ["LG IPS QHD"] = {
                cols = 1,
                rows = 3
            } -- 1×3 for portrait LG
        }
    },

    -- Default configurations for each zone key
    default_zone_configs = {
        -- Format: key = { array of grid coordinates to cycle through }

        -- Left side of keyboard - left side of screen
        ["y"] = {"a1:a2", "a1", "a1:b2"}, -- Top-left region with added a1:b2 (semi-quarter)
        ["h"] = {"a1:b3", "a1:a3", "a1:c3", "a2"}, -- Left side in various widths
        ["n"] = {"a3", "a2:a3", "a3:b3"}, -- Bottom-left with added a3:b3 (semi-quarter)
        ["u"] = {"b1:b3", "b1:b2", "b1"}, -- Middle column region variations
        ["j"] = {"b1:c3", "b1:b3", "b2", "b1:d4"}, -- Middle area variations
        ["m"] = {"b1:b3", "b2:c3", "b3"}, -- Right-middle column variations

        -- Right side of keyboard - right side of screen
        ["i"] = {"d1:d3", "d1:d2", "d1"}, -- Right column variations (mirrors "u")
        ["k"] = {"c1:d3", "c1:c3", "c2"}, -- Right side variations (mirrors "j")
        [","] = {"d1:d3", "d2:d3", "d3"}, -- Bottom-right corner/region (mirrors "m")
        ["o"] = {"c1:d1", "d1", "c1:d2"}, -- Top-right with added c1:d2 (semi-quarter) (mirrors "y")
        ["l"] = {"d1:d3", "c1:d3", "b1:d3", "d2"}, -- Right columns (mirrors "h")
        ["."] = {"d3", "d2:d3", "c3:d3"}, -- Bottom-right with added c2:d3 (semi-quarter)  (mirrors "n")

        -- Center key for center position
        ["0"] = {"b2:c2", "b1:c3", "a1:d3"}, -- Quarter, two-thirds, full screen

        -- Fallback for any key without specific config
        ["default"] = {"full", "center", "left-half", "right-half", "top-half", "bottom-half"}
    },

    -- Custom zone configs for portrait mode
    portrait_zones = {
        -- Top section
        ["y"] = {"a1", "a1:a2"}, -- Top cell, and top two cells

        -- Middle section
        ["h"] = {"a2", "a1:a3"}, -- Middle cell, and entire column

        -- Bottom section
        ["n"] = {"a3", "a2:a3"}, -- Bottom cell, and bottom two cells

        -- Disable other zones by setting them to empty tables
        ["u"] = {},
        ["j"] = {},
        ["m"] = {},
        ["i"] = {},
        ["k"] = {},
        [","] = {},
        ["o"] = {},
        ["l"] = {},
        ["."] = {},

        -- Center key still works for full-screen
        ["0"] = {"a1:a3", "a2", "a1"} -- Full column, middle, top
    }
}

return config
