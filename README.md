# NetLine Spoon for Hammerspoon

[![Hammerspoon version](https://badgen.net/badge/hammerspoon/1.0/yellow)](https://www.hammerspoon.org/)
[![Lua version](https://badgen.net/badge/Lua/5.4)](https://www.lua.org/)

## Overview

NetLine is a Hammerspoon Spoon that displays a colored status line at the top of your screen(s) indicating network reachability status. It provides visual feedback on your network connectivity without requiring constant attention to a menubar icon.

### Features

- **Visual Network Status:** Shows a colored line at the top of your screen that indicates network status
- **Multi-screen Support:** Display on all screens, main screen only, or specific screens
- **Customizable Appearance:** Configure colors, height, position, and shadow effects
- **Sound Alerts:** Optional audio notifications for status changes
- **Focus Mode Integration:** Can respect Do Not Disturb/Focus modes for sound alerts
- **Automatic Fading:** Configure status line to automatically fade after specified duration

## Installation

### Method 1: Using Hammerspoon's Spoon Manager
```lua
hs.loadSpoon("SpoonInstall")
spoon.SpoonInstall:andUse("NetLine")
```

### Method 2: Manual Installation
1. Download the NetLine.spoon zip file from [GitHub](https://github.com/netline/releases)
2. Unzip the file
3. Double-click the NetLine.spoon file to install it to your Hammerspoon Spoons directory

## Quick Start

Add this to your `init.lua` file:

```lua
hs.loadSpoon("NetLine")
spoon.NetLine:start()
```

## Configuration

NetLine can be configured through Hammerspoon's settings system. Here's a full example with all available options:

```lua
-- Load NetLine
hs.loadSpoon("NetLine")

-- Configure (Optional - these are all default values)
hs.settings.set("NetLine.targetHost", "1.1.1.1")
hs.settings.set("NetLine.screen", "all")        -- "all", "main", or part of screen name/UUID
hs.settings.set("NetLine.barHeight", 3)         -- Height in pixels
hs.settings.set("NetLine.barYOffset", 0)        -- Distance from top of screen
hs.settings.set("NetLine.horizontalPadding", 0) -- Padding on left/right edges
hs.settings.set("NetLine.shadowSize", 3)        -- Shadow blur radius
hs.settings.set("NetLine.shadowOffsetY", -2)    -- Shadow vertical offset
hs.settings.set("NetLine.shadowColorAlpha", 0.8) -- Shadow transparency (0.0-1.0)
hs.settings.set("NetLine.fadeDuration", 0.5)    -- Animation duration in seconds

-- Status colors (can be any hs.drawing.color format)
hs.settings.set("NetLine.colors.reachable", hs.drawing.color.definedCollections.hammerspoon.osx_green)
hs.settings.set("NetLine.colors.unreachable", hs.drawing.color.definedCollections.hammerspoon.osx_red)
hs.settings.set("NetLine.colors.unknown", hs.drawing.color.definedCollections.hammerspoon.osx_yellow)

-- How long to show the bar before fading (0 = stay visible)
hs.settings.set("NetLine.fadeSeconds.reachable", 5.0)
hs.settings.set("NetLine.fadeSeconds.unreachable", 0.0) -- Stay visible when unreachable
hs.settings.set("NetLine.fadeSeconds.unknown", 3.0)

-- Sound alerts
hs.settings.set("NetLine.sounds.enabled", false)
hs.settings.set("NetLine.sounds.reachable", "Glass")   -- System sound name or file path
hs.settings.set("NetLine.sounds.unreachable", "Basso") -- System sound name or file path
hs.settings.set("NetLine.sounds.unknown", "")          -- Empty string for no sound
hs.settings.set("NetLine.sounds.volume", 0.7)          -- 0.0 to 1.0

-- Logging level: "verbose", "debug", "info", "warning", "error"
hs.settings.set("NetLine.logLevel", "info")

-- Start NetLine
spoon.NetLine:start()
```

### Configuration Options Explained

#### Network Settings
- `targetHost`: IP address or hostname to monitor for reachability (default: "1.1.1.1")

#### Display Settings
- `screen`: Which screen(s) to display the status line on:
  - `"all"`: Display on all screens
  - `"main"`: Display only on the primary screen
  - `"partial name"`: Display on screens whose name or UUID contains this string
- `barHeight`: Height of the status line in pixels (default: 3)
- `barYOffset`: Distance from the top edge of the screen (default: 0)
- `horizontalPadding`: Distance from left/right screen edges (default: 0)
- `shadowSize`: Size of the shadow effect (default: 3, 0 disables shadow)
- `shadowOffsetY`: Vertical offset of the shadow (default: -2)
- `shadowColorAlpha`: Transparency of the shadow (default: 0.8)
- `fadeDuration`: Animation duration when showing/hiding the bar (default: 0.5)

#### Status Colors
- `colors.reachable`: Color when network is reachable (default: macOS green)
- `colors.unreachable`: Color when network is unreachable (default: macOS red)
- `colors.unknown`: Color when network status is unknown (default: macOS yellow)

#### Duration Settings
- `fadeSeconds.reachable`: How long to display the bar when network becomes reachable (default: 5.0 seconds)
- `fadeSeconds.unreachable`: How long to display the bar when network becomes unreachable (default: 0.0 - stay visible)
- `fadeSeconds.unknown`: How long to display the bar when network status is unknown (default: 3.0 seconds)

#### Sound Alerts
- `sounds.enabled`: Master switch for sound notifications (default: false)
- `sounds.reachable`: Sound to play when network becomes reachable (default: "")
- `sounds.unreachable`: Sound to play when network becomes unreachable (default: "")
- `sounds.unknown`: Sound to play when network status is unknown (default: "")
- `sounds.volume`: Volume level for sound alerts (default: 0.7)

#### Logging
- `logLevel`: Detail level for logs: "verbose", "debug", "info", "warning", "error" (default: "info")

## Methods

NetLine provides the following methods:

### spoon.NetLine:start()
Starts the network monitoring and displays the status line.

```lua
spoon.NetLine:start()
```

### spoon.NetLine:stop()
Stops monitoring and removes the status line.

```lua
spoon.NetLine:stop()
```

### spoon.NetLine:status()
Returns a table with information about the current status.

```lua
local status = spoon.NetLine:status()
hs.inspect(status)
```

The status table includes:
- `running`: Boolean indicating if NetLine is active
- `lastDisplayedStatus`: Most recent status ("reachable", "unreachable", "unknown")
- `targetHost`: Current host being monitored
- `watcherActive`: Whether the reachability watcher is active
- `currentReachabilityFlags`: Current network flags
- `activeCanvases`: Information about displayed status lines

## Example Configurations

### Minimal Setup

```lua
hs.loadSpoon("NetLine")
spoon.NetLine:start()
```

### Multiple Monitors with Custom Colors

```lua
hs.loadSpoon("NetLine")
hs.settings.set("NetLine.screen", "all")
hs.settings.set("NetLine.colors.reachable", {green=0.4, blue=0.9, alpha=0.7})
hs.settings.set("NetLine.colors.unreachable", {red=0.9, alpha=0.9})
spoon.NetLine:start()
```

### Sound Notifications

```lua
hs.loadSpoon("NetLine")
hs.settings.set("NetLine.sounds.enabled", true)
hs.settings.set("NetLine.sounds.reachable", "Glass")
hs.settings.set("NetLine.sounds.unreachable", "Basso")
hs.settings.set("NetLine.sounds.volume", 0.5)
spoon.NetLine:start()
```

### Status Line Customization

```lua
hs.loadSpoon("NetLine")
hs.settings.set("NetLine.barHeight", 5)
hs.settings.set("NetLine.shadowSize", 8)
hs.settings.set("NetLine.shadowOffsetY", -4)
hs.settings.set("NetLine.horizontalPadding", 100) -- Inset from edges
spoon.NetLine:start()
```

## Requirements

NetLine requires the following Hammerspoon modules:

- `hs.canvas`
- `hs.drawing.color`
- `hs.logger`
- `hs.network`
- `hs.screen`
- `hs.settings`
- `hs.sound`
- `hs.fnutils`
- `hs.timer`
- `hs.inspect`

The `hs.focus` module is used if available (for DND detection) but is optional.

## Troubleshooting

### The status line doesn't appear
- Check that Hammerspoon has accessibility permissions in System Preferences
- Try increasing the `barHeight` setting
- Check your log console for errors (Console.app, filter for "Hammerspoon")

### The status doesn't update correctly
- Try changing the `targetHost` to a reliable server (like "1.1.1.1" or "8.8.8.8")
- Restart Hammerspoon

### Sounds don't play
- Verify that `sounds.enabled` is set to `true`
- Check that the sound names are valid system sounds
- Make sure your system volume is not muted

## License

NetLine is released under the [MIT License](https://opensource.org/licenses/MIT).

## Changelog

### 0.2
- Added multi-screen support
- Added sound alerts
- Added customizable shadow effects
- Added Focus Mode (DND) detection for sounds
- Improved error handling and logging

### 0.1
- Initial release

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request on the [GitHub repository](https://github.com/netline).
