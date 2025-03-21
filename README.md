# Zone Tiler for Hammerspoon

A powerful window management system that allows defining zones on the screen and cycling window sizes within those zones.

## Features

- **Grid-based Window Management**: Organize windows in a customizable grid layout
- **Screen-aware Layouts**: Automatically detects screen size and orientation to provide optimal layouts
- **Multiple Screen Support**: Seamlessly manage windows across multiple displays
- **Intuitive Keyboard Shortcuts**: Quickly position and resize windows with keyboard shortcuts
- **Customizable Configurations**: Easily tailor layouts to your specific needs
- **Cycle Through Positions**: Quickly cycle a window through different preset sizes
- **Window Margins**: Add configurable spacing between windows and screen edges
- **Window Focus Control**: Quickly focus and cycle through windows in specific zones
- **Smart Window Mapping**: Automatically detect and map existing windows to appropriate zones
- **Cross-Screen Focus Navigation**: Move focus between screens with keyboard shortcuts
- **Negative Coordinate Support**: Properly handle multi-monitor setups with negative screen coordinates
- **Robust State Tracking**: Maintain window positions even when rapidly switching between zones

## Installation

1. Install [Hammerspoon](https://www.hammerspoon.org/) if you haven't already
2. Download the `tiler.lua` file to your Hammerspoon configuration directory (`~/.hammerspoon/`)
3. Add the following to your `init.lua` file:

```lua
require "tiler"
```

## Default Keyboard Shortcuts

All default shortcuts use the modifier combination `Ctrl+Cmd` (can be customized).

### Basic Window Positioning

The keyboard layout maps directly to screen positions:

```
    y    u    i    o    p
    h    j    k    l    ;
    n    m    ,    .    /
```

Each key corresponds to a specific zone on the screen grid:

#### Left Side Keys (Left Side of Screen)
- `y`: Top-left region cycling: full height of left column → top-left cell
- `h`: Left side cycling: left two columns → left column → left three columns
- `n`: Bottom-left cycling: bottom-left cell → bottom half of left column

#### Middle Keys (Middle of Screen)
- `u`: Middle-top cycling: middle column → top half of middle column → top-middle cell
- `j`: Middle cycling: middle-right columns → middle column → middle cell
- `m`: Bottom-middle cycling: right-middle column → bottom half of middle column → bottom-middle cell

#### Right Side Keys (Right Side of Screen)
- `i`: Top-right cycling: right column → top half of right column → top-right cell
- `k`: Right side cycling: two rightmost columns → right column → middle-right cell
- `,`: Bottom-right cycling: bottom-right cell → bottom half of right column
- `o`: Top-right cycling: top-right cell → top-right two cells wide
- `l`: Right side cycling: right column → right two columns → right half
- `.`: Bottom-right cycling: bottom-right two cells wide → bottom-right cell

#### Special Positions
- `0`: Center cycling: center quarter → center two-thirds → full screen

### Window Movement Between Screens
- `Ctrl+Cmd+p`: Move current window to the next screen
- `Ctrl+Cmd+;`: Move current window to the previous screen

### Focus Management
- `Shift+Ctrl+Cmd+[zone key]`: Focus on windows in that zone (cycles through windows)
- `Shift+Ctrl+Cmd+p`: Move focus to next screen
- `Shift+Ctrl+Cmd+;`: Move focus to previous screen

## Screen-Specific Layouts

The tiler automatically detects your screen characteristics and applies the most appropriate layout:

- **Large Monitors (≥27")**: 4×3 grid (Dell U3223QE, etc.)
- **Medium Monitors (24-26")**: 3×3 grid
- **Standard Monitors (20-23")**: 3×2 grid
- **Small Monitors (<20")**: 2×2 grid
- **Portrait Monitors**: 1×3 grid for large (≥23") or 1×2 grid for smaller screens
- **MacBook Built-in Displays**: 2×2 grid

## Customization

### Basic Configuration

Here's a complete configuration example for your `init.lua`:

```lua
-- Define configuration for the tiler
local tiler_config = {
    debug = true,                  -- Enable debug logging
    modifier = {"ctrl", "cmd"},    -- Set default modifier keys
    focus_modifier = {"shift", "ctrl", "cmd"}, -- Modifier keys for focus commands

    -- Window margin settings
    margins = {
        enabled = true,            -- Enable margins between windows
        size = 8,                  -- Use 8 pixels for margins
        screen_edge = true         -- Apply margins to screen edges too
    },

    -- Focus settings
    flash_on_focus = true,         -- Visual flash when focusing windows

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
            }
        }
    },

    -- Screen-specific zone configurations
    zone_configs_by_screen = {
        ["LG IPS QHD"] = {
            -- Top section
            ["y"] = {"a1", "a1:a2"},

            -- Middle section
            ["h"] = {"a2", "a1:a3"},

            -- Bottom section
            ["n"] = {"a3", "a2:a3"},

            -- Center key
            ["0"] = {"a1:a3", "a2", "a1"}
        }
    }
}

-- Start tiler with the configuration
tiler.start(tiler_config)
```

### Custom Screen Layouts

You can define custom layouts for specific screens:

```lua
-- Define a custom layout for your monitor
tiler.layouts.custom["DELL U3223QE"] = { cols = 4, rows = 3 }
```

### Change Default Modifier Keys

```lua
-- Change the default modifier keys
tiler.config.modifier = {"ctrl", "alt"}
tiler.config.focus_modifier = {"shift", "ctrl", "alt"}
```

### Configure Window Margins

```lua
-- Configure window margins
tiler.config.margins = {
    enabled = true,     -- Turn margins on/off
    size = 10,          -- Margin size in pixels
    screen_edge = false -- Don't apply margins to screen edges
}
```

### Custom Zone Configurations

```lua
-- Customize the behavior of a specific key
tiler.configure_zone("y", { "a1:a2", "a1", "a1:a3" })
```

### Screen-Specific Zone Configurations

For different behaviors on different monitors:

```lua
-- Define custom zones for a portrait monitor
local portrait_zones = {
    ["y"] = {"a1", "a1:a2"},  -- Top section
    ["h"] = {"a2", "a1:a3"},  -- Middle section
    ["n"] = {"a3", "a2:a3"}   -- Bottom section
}

-- Apply to specific screen
tiler.zone_configs_by_screen = {
    ["LG IPS QHD"] = portrait_zones
}
```

## Grid Coordinate System

The tiler uses a grid coordinate system with alphabetic columns and numeric rows:

```
    a    b    c    d
  +----+----+----+----+
1 | a1 | b1 | c1 | d1 |
  +----+----+----+----+
2 | a2 | b2 | c2 | d2 |
  +----+----+----+----+
3 | a3 | b3 | c3 | d3 |
  +----+----+----+----+
```

You can define regions using:

1. String coordinates like `"a1"` (single cell) or `"a1:b2"` (rectangle from a1 to b2)
2. Named positions like `"center"`, `"left-half"`, `"top-half"`, etc.
3. Table coordinates like `{1,1,2,2}` for programmatic definitions

## Additional Features

### Window Mapping

The tiler automatically attempts to map existing windows to appropriate zones when it starts. You can also trigger this manually:

```lua
-- Manually map all existing windows to zones
hs.hotkey.bind({"ctrl", "cmd", "shift"}, "M", function()
    local count = tiler.map_existing_windows()
    hs.alert.show("Mapped " .. count .. " windows to zones")
end)
```

### Focus Control

The focus control feature allows you to quickly switch between windows in a particular zone or across screens:

- `Shift+Ctrl+Cmd+[zone key]` focuses on windows in that zone and cycles through them
- `Shift+Ctrl+Cmd+p` moves focus to the next screen
- `Shift+Ctrl+Cmd+;` moves focus to the previous screen

This makes it easy to navigate between applications without using the mouse, particularly in complex multi-screen setups.

## Troubleshooting

If windows are not positioning correctly:

1. **Enable Debug Mode**: Add `tiler.config.debug = true` to your `init.lua`
2. **Force Screen Detection**: Add a custom layout for your specific screen
3. **Reload Configuration**: Use `Cmd+Ctrl+Shift+R` if you've added the hot reload shortcut
4. **Check Multi-Monitor Setup**: For monitors with negative coordinates, ensure you're using the latest version with negative coordinate support
5. **Check State Tracking**: If windows don't cycle correctly when rapidly switching between zones, ensure you have the latest state tracking fixes

## Advanced Usage

### Hot Reload Configuration

Add this to your `init.lua` for quick reloading during customization:

```lua
hs.hotkey.bind({"ctrl", "cmd", "shift"}, "R", function()
    hs.reload()
    hs.alert.show("Config reloaded!")
end)
```

### Creating Custom Grid Layouts

For highly customized layouts, you can define your own grid system:

```lua
tiler.layouts.custom["My Special Monitor"] = {
    cols = 6,      -- 6 columns
    rows = 4,      -- 4 rows
    modifier = {"ctrl", "alt"}  -- Custom modifier keys
}
```

### Debug Helper Functions

For troubleshooting multi-monitor setups:

```lua
-- Helper function to display screen information
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "I", function()
    local output = {"Screen Information:"}

    for i, screen in ipairs(hs.screen.allScreens()) do
        local frame = screen:frame()
        local name = screen:name()

        table.insert(output, string.format("\nScreen %d: %s", i, name))
        table.insert(output, string.format("Frame: x=%.1f, y=%.1f, w=%.1f, h=%.1f",
                                         frame.x, frame.y, frame.w, frame.h))
    end

    hs.alert.show(table.concat(output, "\n"), 5)
end)
```

## Focus Zone Feature

The Focus Zone feature allows you to quickly switch between windows in a particular zone using keyboard shortcuts.

### Focus Zone Keyboard Shortcuts

By default, focusing on zone windows uses the `Shift+Ctrl+Cmd` modifier combined with the zone key:

- `Shift+Ctrl+Cmd+y`: Focus on windows in the top-left zone
- `Shift+Ctrl+Cmd+h`: Focus on windows in the left zone
- `Shift+Ctrl+Cmd+n`: Focus on windows in the bottom-left zone
- ... and so on for all zone keys

### Behavior

- Pressing a focus zone shortcut will switch to the topmost window in that zone
- If the currently focused window is already in that zone, it cycles to the next window
- When focusing, a brief highlight flash provides visual feedback (can be disabled)
- Focus is screen-specific: you only focus windows on your current screen

### Screen Focus Movement

The Screen Focus movement feature allows you to quickly move focus between screens:

- `Shift+Ctrl+Cmd+p`: Move focus to the next screen
- `Shift+Ctrl+Cmd+;`: Move focus to the previous screen

This complements the existing window movement functionality and makes it easy to work with multi-monitor setups.

### Configuration

You can customize the focus zone feature in your configuration:

```lua
local tiler_config = {
    -- Other settings...

    -- Focus zone settings
    focus_modifier = {"shift", "ctrl", "cmd"}, -- Modifier keys for focusing
    flash_on_focus = true,                     -- Flash window when focused
}
```

### Use Cases

The focus zone feature is particularly useful for:

- Quickly switching between related windows (e.g., between editor and terminal in a coding zone)
- Managing many windows arranged in specific zones
- Creating a workflow that combines window positioning and focus management
- Navigating across multiple monitors without using the mouse

## Planning

- [x] Focus on Zone keyboard shortcut (Switch to the topmost window in a zone and cycle through them)
- [x] Cross-screen focus navigation (Move focus between screens with keyboard shortcuts)
- [x] Smart window mapping (Automatically detect and map existing windows to appropriate zones)
- [ ] Application-aware layouts (Save preferred zones for specific applications)
- [ ] Automatically arrange windows based on predefined layouts
- [ ] Dynamic row and column resizing
- [ ] Zen mode (minimize all windows other than the active one)
- [ ] Automatic window resizing based on content
- [ ] Save and load window layouts
- [ ] Support for Mac spaces
- [ ] Window stacking within zones (keep multiple windows in a single zone and cycle through them)
- [ ] Grid visualization overlay (display the grid layout temporarily when positioning windows)
- [ ] Mouse-based zone selection (Shift+drag to select a custom zone)
- [ ] Zone presets (quickly switch between different zone layouts)

## Credits

Zone Tiler was created for use with [Hammerspoon](https://www.hammerspoon.org/)