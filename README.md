# Hammerspoon Tiler - Refactored

A modular, maintainable window management system for macOS using Hammerspoon.

## Features

- **Grid-based Window Management**: Organize windows in customizable grid layouts
- **Screen-aware Layouts**: Automatically detects screen properties for optimal layouts
- **Multiple Screen Support**: Seamless management across displays with position memory
- **Application Switching**: Quick hotkeys for launching and toggling applications
- **Pomodoro Timer**: Built-in productivity timer with visual feedback
- **Window Memory**: Remembers window positions between app launches
- **Layout Presets**: Save and restore entire workspace configurations
- **Zone System**: Organize screens into zones with multiple tile configurations
- **Event System**: Decoupled components with event-based communication

## Project Structure

```
~/.hammerspoon/
├── init.lua                 # Main initialization file
├── config.lua               # Central configuration
├── core/                    # Core functionality
│   ├── logger.lua           # Unified logging system
│   ├── state.lua            # Centralized state management
│   ├── events.lua           # Event system
│   └── utils.lua            # Shared utility functions
├── modules/                 # Feature modules
│   ├── tiler/               # Window tiling functionality
│   │   ├── init.lua         # Main tiler API
│   │   ├── grid.lua         # Grid management
│   │   ├── tile.lua         # Tile class
│   │   ├── zone.lua         # Zone class
│   │   └── layout.lua       # Layout management
│   ├── app_switcher.lua     # Application switching
│   └── pomodoor.lua         # Pomodoro timer
```

## Installation

1. Install [Hammerspoon](https://www.hammerspoon.org/)
2. Clone this repository to `~/.hammerspoon/`
3. Restart Hammerspoon

## Quick Start Guide

The refactored tiler provides a clean API for window management:

```lua
-- In your init.lua
local tiler = require("modules.tiler")
tiler.init(config.tiler)

-- Moving windows
tiler.moveToZone("center")    -- Move current window to center zone
tiler.moveToNextScreen()      -- Move window to next screen

-- Managing layouts
tiler.saveCurrentLayout("coding")  -- Save current window arrangement
tiler.applyLayout("coding")        -- Apply a saved layout

-- Working with screens
tiler.focusNextScreen()       -- Focus on next screen
```

## Architecture Overview

The refactored system uses several architectural patterns:

1. **Object-Oriented Design**: Classes like Tile and Zone encapsulate behavior
2. **Centralized State Management**: All state stored in one location
3. **Event-Based Communication**: Decoupled components using events
4. **Method Chaining**: Fluent interfaces for configuration
5. **Separation of Concerns**: Clear module responsibilities

## Key Components

### Core Modules

- **logger.lua**: Unified logging with levels and file output
- **state.lua**: Centralized state storage with change notifications
- **events.lua**: Event subscription and publishing
- **utils.lua**: Shared utility functions

### Tiler Modules

- **grid.lua**: Screen grid management with margin support
- **tile.lua**: Window position representation
- **zone.lua**: Screen regions with multiple tile configurations
- **layout.lua**: Save and restore window arrangements

## Default Keyboard Shortcuts

Refer to your `config.lua` file for specific keyboard shortcuts. The defaults are:

### Window Management (Ctrl+Cmd)

The keyboard layout maps directly to screen positions:

```
    y    u    i    o    p
    h    j    k    l    ;
    n    m    ,    .    /
```

### Window Movement

- `Ctrl+Cmd+p`: Move current window to next screen
- `Ctrl+Cmd+;`: Move current window to previous screen

### Focus Management

- `Shift+Ctrl+Cmd+[zone key]`: Focus on windows in that zone
- `Shift+Ctrl+Cmd+p`: Move focus to next screen
- `Shift+Ctrl+Cmd+;`: Move focus to previous screen

### App Switching (Shift+Ctrl)

- `Shift+Ctrl+[key]`: Launch or toggle application
- `Shift+Ctrl+/`: Display help with keyboard shortcuts

### Pomodoro Timer

- `Ctrl+Cmd+9`: Start pomodoro timer
- `Ctrl+Cmd+0`: Pause/reset pomodoro timer
- `Shift+Ctrl+Cmd+0`: Reset work count

## Configuration

All configuration is done through `config.lua`. The tiler section includes:

```lua
config.tiler = {
    debug = true,
    modifier = {"ctrl", "cmd"},
    focus_modifier = {"shift", "ctrl", "cmd"},

    -- Margins between windows
    margins = {
        enabled = true,
        size = 5,
        screen_edge = true
    },

    -- Apps that need special handling
    problem_apps = {"Firefox", "Zen"},

    -- Screen detection configuration
    screen_detection = { ... },

    -- Custom layouts for screens
    layouts = { ... },

    -- Window memory settings
    window_memory = { ... }
}
```

## Extending the Tiler

The modular design makes it easy to extend the tiler with new features:

1. **Custom Zones**: Create specialized zones with `tiler.defineZone()`
2. **Event Handlers**: Subscribe to events with `events.on()`
3. **Layout Presets**: Define layouts with `Layout.define()`

## Troubleshooting

1. **Enable Debug Mode**: Press `Ctrl+Cmd+Shift+D` to toggle debug mode
2. **Check Console**: Open Hammerspoon Console to view detailed logs
3. **Reload Config**: Use `Shift+Ctrl+Cmd+R` to reload configuration
4. **Reset State**: Delete `~/.hammerspoon/tiler.json` to reset window memory