-- Configuration file for Hammerspoon settings
local config = {}

-- Key combinations
config.keys = {
    mash = {"ctrl", "cmd"},
    mash_app = {"shift", "ctrl"},
    mash_shift = {"shift", "ctrl", "cmd"},
    HYPER = {"shift", "ctrl", "alt", "cmd"}
}

-- Application switcher settings
config.app_switcher = {
    -- Apps that need menu-based hiding
    hide_workaround_apps = {'Arc'},

    -- Apps that require exact mapping between launch name and display name
    special_app_mappings = {
        ["bambustudio"] = "bambu studio" -- Launch name → Display name
    },

    -- Ambiguous app pairs that should not be considered matching
    ambiguous_apps = {{'notion', 'notion calendar'}, {'notion', 'notion mail'}}
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
    t = 'ChatGpt',
    a = 'KeePassXC'
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

    -- Screen detection configuration
    screen_detection = {
        -- Special screen name patterns and their preferred layouts
        patterns = {
            ["DELL.*U32"] = {
                cols = 4,
                rows = 3
            }, -- Dell 32-inch monitors
            ["LG.*QHD"] = {
                cols = 1,
                rows = 3
            }, -- LG QHD in portrait mode
            ["Built[-]?in"] = {
                cols = 2,
                rows = 2
            }, -- MacBook built-in displays
            ["Color LCD"] = {
                cols = 2,
                rows = 2
            }, -- MacBook displays
            ["internal"] = {
                cols = 2,
                rows = 2
            }, -- Internal displays
            ["MacBook"] = {
                cols = 2,
                rows = 2
            } -- MacBook displays
        },

        -- Size-based layouts (screen diagonal in inches)
        sizes = {
            large = {
                min = 27,
                layout = "4x3"
            }, -- 27" and larger - 4x3 grid
            medium = {
                min = 24,
                max = 26.9,
                layout = "3x3"
            }, -- 24-26" - 3x3 grid
            standard = {
                min = 20,
                max = 23.9,
                layout = "3x2"
            }, -- 20-23" - 3x2 grid
            small = {
                max = 19.9,
                layout = "2x2"
            } -- Under 20" - 2x2 grid
        },

        -- Portrait mode layouts
        portrait = {
            large = {
                min = 23,
                layout = "1x3"
            }, -- 23" and larger in portrait - 1x3 grid
            small = {
                max = 22.9,
                layout = "1x2"
            } -- Under 23" in portrait - 1x2 grid
        }
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
