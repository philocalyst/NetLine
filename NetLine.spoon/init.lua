-- NetLine Spoon
-- Displays a colored line at the top of the screen indicating network reachability status.

local obj = {}
obj.name = "NetLine"
obj.version = "0.2"
obj.author = "Philocalyst"
obj.homepage = "https://github.com/netline"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- Required modules
local canvas = require("hs.canvas")
local color = require("hs.drawing.color")
local logger = require("hs.logger").new(obj.name)
local network = require("hs.network")
local screen = require("hs.screen")
local settings = require("hs.settings")
local sound = require("hs.sound")
local utils = require("hs.fnutils")
local timer = require("hs.timer")
local inspect = require("hs.inspect")
local focus

-- ▰▰▰ Configuration ▰▰▰ --

-- Sensible defaults :)
local DEFAULTS = {
  targetHost = "1.1.1.1", -- This is the place that netline will ping out to. Defaults to an IP address here, Cloudfares, as it should be more reliable than a solitary hostname.
  screen = "all",         -- Which screen(s) should the bar be shown on? "all", "main", or part of name/UUID
  barHeight = 3,          -- How tall is the bar?
  barYOffset = 0,         -- How far bar is from the top (usually 0)
  horizontalPadding = 0,  -- Padding on the left/right edges (Corrected spelling)
  shadowSize = 3,         -- The size or blur of the bar shadow
  shadowOffsetY = -2,     -- Vertical offset of the shadow
  shadowColorAlpha = 0.8, -- Alpha for the shadow color (0.0 to 1.0)
  fadeDuration = 0.5,     -- Default fade in/out duration (seconds)
  colors = {
    reachable = color.definedCollections.hammerspoon.osx_green,
    unreachable = color.definedCollections.hammerspoon.osx_red,
    unknown = color.definedCollections.hammerspoon.osx_yellow
  },
  fadeSeconds = {      -- Time bar stays visible before fading (0 = stay visible)
    reachable = 5.0,
    unreachable = 0.0, -- Stay visible when unreachable
    unknown = 3.0
  },
  sounds = {
    enabled = false,
    reachable = "",   -- e.g., "Submarine", "Glass", or path to sound file
    unreachable = "", -- e.g., "Basso", "Funk"
    unknown = "",
    volume = 0.7      -- 0.0 to 1.0
  },
  logLevel = "info"   -- "verbose", "debug", "info", "warning", "error"
}

-- ▰▰▰ Internall state ▰▰▰ --
obj.statusCanvases = {}
obj.fadeTimers = {}
obj.reachabilityWatcher = nil
obj.screenWatcher = nil
obj.lastReachabilityStatus = "unknown" -- Store the last *displayed* status
obj.lastStatusInfo = nil               -- Store the full info used for the last update
obj.isRunning = false

-- ▰▰▰ Private helper functions ▰▰▰ --

-- Get a configuration value. If none are found, retreat to defaults.
local function _getConfig(key)
  local fullKey = obj.name .. "." .. key
  local userValue = settings.get(fullKey)

  if userValue ~= nil then
    -- logger.v("Using user setting for key:", key, "Value:", inspect(userValue))
    return userValue
  else
    local keys = {}
    for k in key:gmatch("[^%.]+") do table.insert(keys, k) end

    local defaultValue = DEFAULTS
    for i, k in ipairs(keys) do
      if type(defaultValue) == "table" and defaultValue[k] ~= nil then
        defaultValue = defaultValue[k]
      else
        logger.w("Default value not found for key path:", key, "(failed at segment", i, ":", k, ")")
        return nil
      end
    end
    -- logger.v("Using default setting for key:", key, "Value:", inspect(defaultValue))
    return defaultValue
  end
end

local function _setLogLevel()
  local levelStr = _getConfig("logLevel") or "warning"
  local levelMap = { verbose = 5, debug = 4, info = 3, warning = 2, error = 1 }
  local level = levelMap[levelStr:lower()] or 2 -- Default to warning
  logger.setLogLevel(level)
  logger.i("Log level set to:", levelStr, "(Level", level .. ")")
end

-- Retrieve the corresponding hs color for various formats (string, hex, table)
local function _getColor(colorInput)
  local finalFallbackColor = { red = 0.5, green = 0.5, blue = 0.5, alpha = 1.0 } -- Gray

  if colorInput == nil then
    logger.w("getColor received nil input, using ultimate fallback.")
    return finalFallbackColor
  end

  local convertedColor = color.asRGB(colorInput)

  if convertedColor then
    if type(convertedColor.alpha) ~= "number" or convertedColor.alpha < 0 or convertedColor.alpha > 1 then
      convertedColor.alpha = 1.0
    end
    logger.v("Converted color input:", inspect(colorInput), "to:", inspect(convertedColor))
    return convertedColor
  else
    logger.w("Could not convert color input:", inspect(colorInput), "- using ultimate fallback.")
    return finalFallbackColor
  end
end


-- Retrieves sound from corresponding sound name
local function _getSound(soundName)
  if not soundName or soundName == "" or soundName:lower() == "none" then
    return nil
  end

  local s = sound.get(soundName)
  if s then
    local vol = tonumber(_getConfig("sounds.volume"))
    if type(vol) == "number" and vol >= 0 and vol <= 1 then
      s:volume(vol)
      logger.v("Loaded sound:", soundName, "with volume:", vol)
      return s
    else
      logger.w("Invalid sound volume configured:", inspect(vol), "- using default volume for sound:", soundName)
      s:volume(DEFAULTS.sounds.volume)
      return s
    end
  else
    logger.w("Could not find or load sound:", soundName)
    return nil
  end
end

-- Gets the target screens based on config
local function _getTargetScreens()
  local screenConfig = _getConfig("screen")
  local targetScreens = {}
  local allScreens = screen.allScreens()
  if not allScreens or #allScreens == 0 then
    logger.e("Failed to get screens from hs.screen.allScreens()")
    return {}
  end

  if not screenConfig or type(screenConfig) ~= "string" or screenConfig == "" then
    logger.w("Invalid 'screen' configuration value:", inspect(screenConfig), "- falling back to 'main'.")
    screenConfig = "main"
  end

  local configLower = screenConfig:lower()

  if configLower == "all" then
    logger.v("Targeting all screens.")
    return allScreens
  elseif configLower == "main" then -- Main is primary screen.
    local mainScreen = screen.mainScreen()
    if mainScreen then
      logger.v("Targeting main screen:", mainScreen:name() or mainScreen:getUUID() or mainScreen:id())
      table.insert(targetScreens, mainScreen)
    else
      logger.e("Could not get main screen, no screens will be targeted.")
    end
  else
    logger.v("Attempting to match screen config:", screenConfig)
    for _, s in ipairs(allScreens) do
      local screenName = s:name()
      local screenUUID = s:getUUID()
      local matched = false
      if screenName and screenName:lower():find(configLower, 1, true) then
        logger.v("Matched screen by name:", screenName)
        table.insert(targetScreens, s)
        matched = true
      elseif screenUUID and screenUUID:lower():find(configLower, 1, true) then
        logger.v("Matched screen by UUID:", screenUUID)
        table.insert(targetScreens, s)
        matched = true
      end
      if not matched then
        logger.v("Screen", (screenName or screenUUID or s:id()), "did not match config:", screenConfig)
      end
    end
  end

  if #targetScreens == 0 then
    logger.w("Screen config '" .. screenConfig .. "' matched no screens. Falling back to 'main'.")
    local mainScreen = screen.mainScreen()
    if mainScreen then table.insert(targetScreens, mainScreen) end
  end

  if #targetScreens == 0 then
    logger.e("Could not find any screens to target, even after fallback.")
  end

  return targetScreens
end

local function _drawOnScreen(screenObj, barColor, hideAfter, statusSound)
  -- Validate the input
  if not screenObj or type(screenObj.id) ~= "function" then
    logger.e("_drawOnScreen: Invalid screen object received:", inspect(screenObj)); return
  end
  if not barColor or type(barColor) ~= "table" or not barColor.red then
    logger.e("_drawOnScreen: Invalid barColor received:", inspect(barColor)); return
  end

  local screenID = screenObj:id()
  local screenName = screenObj:name() or screenObj:getUUID() or tostring(screenID) -- ONLY for logging
  local screenFrame = screenObj:fullFrame()
  if not screenFrame then
    logger.e("_drawOnScreen: Could not get frame for screen", screenName); return
  end

  logger.v(string.format("Drawing on screen %s (ID: %d): Color=%s, HideAfter=%.2f",
    screenName, screenID, inspect(barColor), hideAfter or -1))

  -- Cancel existing fade timer if there is one for an instant reset
  if obj.fadeTimers[screenID] then
    logger.v("Cancelling existing fade timer for screen", screenID)
    obj.fadeTimers[screenID]:stop()
    obj.fadeTimers[screenID] = nil
  end

  -- Get the display properties from the config
  local barHeight = tonumber(_getConfig("barHeight")) or DEFAULTS.barHeight
  local barYOffset = tonumber(_getConfig("barYOffset")) or DEFAULTS.barYOffset
  local horizontalPadding = tonumber(_getConfig("horizontalPadding")) or DEFAULTS
      .horizontalPadding -- Corrected spelling
  local shadowSize = tonumber(_getConfig("shadowSize")) or DEFAULTS.shadowSize
  local shadowOffsetY = tonumber(_getConfig("shadowOffsetY")) or DEFAULTS.shadowOffsetY
  local shadowColorAlpha = tonumber(_getConfig("shadowColorAlpha")) or DEFAULTS.shadowColorAlpha
  local fadeDuration = tonumber(_getConfig("fadeDuration")) or DEFAULTS.fadeDuration

  -- Bound checks for shadow alpha
  shadowColorAlpha = math.max(0, math.min(1, shadowColorAlpha))

  local screenX = screenFrame.x
  local screenY = screenFrame.y -- Top of the screen
  local screenWidth = screenFrame.w

  -- Hide existing canvas IF it exists
  if obj.statusCanvases[screenID] then
    logger.v("Deleting existing canvas before drawing new one for screen", screenID)
    obj.statusCanvases[screenID]:delete()
    obj.statusCanvases[screenID] = nil -- Clear reference
  end

  local canvasHeight = math.max(barHeight, math.abs(barYOffset)) + shadowSize + math.abs(shadowOffsetY)
  local canvasX = screenX + horizontalPadding               -- Simulating padding with shift
  local canvasY = screenY +
      barYOffset                                            -- Assumes the top here
  local canvasWidth = screenWidth - (horizontalPadding * 2) -- Double to account for the left shift.
  local barWidth = canvasWidth

  -- Create a new canvas
  local initialRect = { x = canvasX, y = canvasY, w = canvasWidth, h = canvasHeight } -- Use calculated frame
  local c = canvas.new(initialRect)
  if not c then
    logger.e("Failed to create canvas for screen", screenName); return
  end

  -- ▰▰▰ Canvas behavior options ▰▰▰ --
  c:level(canvas.windowLevels.status) -- Status level (makes sense!)
  c:behavior({ "canJoinAllSpaces", "stationary", "ignoresCycle", "fullScreenDisallowsTiling" })
  c:mouseCallback(nil)                -- Disable mouse interaction, meant to be uninteractable.

  -- Store canvas reference
  obj.statusCanvases[screenID] = c
  logger.v("Created new canvas for screen", screenName)

  -- Create status bar in canvas
  local barFrameInCanvas = {
    x = 0, -- Draw from the very left of the canvas frame
    y = 0, -- Draw from the very top of the canvas frame (Y offset handled by canvas position)
    h = barHeight,
    w = barWidth
  }

  -- Define shadow properties using validated alpha
  local shadowColor = {
    red = barColor.red,
    green = barColor.green,
    blue = barColor.blue,
    alpha = shadowColorAlpha
  }

  c:replaceElements({
    {
      type = "rectangle",
      id = "netBar",
      frame = barFrameInCanvas,
      fillColor = barColor,
      withShadow = (shadowSize > 0), -- Only add shadow if size > 0
      shadow = {
        color = shadowColor,
        blurRadius = shadowSize,
        offset = { w = 0, h = shadowOffsetY }
      }
    }
  })

  c:show(fadeDuration) -- Make visible
  logger.v("Showing canvas with fade duration:", fadeDuration)


  -- Play sound
  if statusSound and _getConfig("sounds.enabled") then
    local playSound = true
    if not focus then
      pcall(function() focus = require("hs.focus") end)
      if not focus then
        logger.w("hs.focus module not available. Cannot check DND. Playing sound.")
      end
    end

    if focus and focus.focused then
      local isFocused, focusErr = pcall(focus.focused)
      if focusErr then
        logger.w("Error calling hs.focus.focused():", focusErr, "- Playing sound anyway.")
      elseif isFocused then
        logger.i("Sound suppressed due to Focus Mode (DND)")
        playSound = false
      end
    elseif focus and not focus.focused then
      logger.w("hs.focus module loaded, but focused() function not found (macOS version?). Skipping DND check.")
    end

    if playSound then
      logger.v("Playing sound:", inspect(statusSound))
      local ok, err = pcall(function() statusSound:play() end)
      if not ok then
        logger.e("Error playing sound:", err)
      end
    end
  end

  -- Set hide timer if specified
  if hideAfter and type(hideAfter) == "number" and hideAfter > 0 then
    logger.v(string.format("Setting fade timer for screen %s: %.2f seconds", screenName, hideAfter))
    obj.fadeTimers[screenID] = timer.doAfter(hideAfter, function()
      logger.v("Fade timer triggered for screen", screenName)
      local currentCanvas = obj.statusCanvases[screenID] -- Get current ref
      if currentCanvas then
        currentCanvas:hide(fadeDuration)
      end
      obj.fadeTimers[screenID] = nil
    end)
  elseif hideAfter == 0 then
    logger.v("hideAfter is 0, bar will remain visible for screen", screenName)
  else
    logger.v("hideAfter is not set or not positive, bar will remain visible for screen", screenName)
  end
end

-- Update status line on relevant screens based on statusInfo
local function _updateBar(statusInfo)
  if not statusInfo or not statusInfo.status then
    logger.e("_updateBar called with invalid statusInfo:", inspect(statusInfo))
    return
  end
  local status = statusInfo.status -- "reachable", "unreachable", "unknown"

  logger.i(string.format("Updating status bar display: Status=%s", status))
  obj.lastStatusInfo = statusInfo -- Store for screen changes

  -- Get configuration for this new status
  local barColor = _getColor(_getConfig("colors." .. status) or DEFAULTS.colors.unknown)
  local hideAfter = _getConfig("fadeSeconds." .. status)
  local statusSoundName = _getConfig("sounds." .. status)
  local statusSound = nil
  if _getConfig("sounds.enabled") then
    statusSound = _getSound(statusSoundName)
  end
  local fadeDuration = tonumber(_getConfig("fadeDuration")) or DEFAULTS.fadeDuration

  -- Determine which screens to draw on
  local targetScreens = _getTargetScreens()
  if #targetScreens == 0 then
    logger.w("No target screens found for drawing. Nothing to update.")
    return
  end

  local targetScreenIDs = {}
  for _, s in ipairs(targetScreens) do
    targetScreenIDs[s:id()] = true -- Create a set for quick lookup
    _drawOnScreen(s, barColor, hideAfter, statusSound)
  end

  -- Clean up bars on screens that are no longer targeted
  for screenID, canvasObj in pairs(obj.statusCanvases) do
    if not targetScreenIDs[screenID] then
      logger.i("Hiding bar on now untargeted screen:", screenID)
      if obj.fadeTimers[screenID] then
        obj.fadeTimers[screenID]:stop()
        obj.fadeTimers[screenID] = nil
      end
      if canvasObj and type(canvasObj.alpha) == "function" then
        -- Fade out using alpha animation, then delete
        canvasObj:alpha(0, fadeDuration, function()
          if obj.statusCanvases[screenID] == canvasObj then -- Check if it still exists and wasn't replaced
            logger.v("Deleting untargeted canvas for screen", screenID)
            canvasObj:delete()
            obj.statusCanvases[screenID] = nil
          end
        end)
      else
        obj.statusCanvases[screenID] = nil -- Remove reference if canvas invalid
      end
    end
  end
end

-- Handle network reachability changes from the watcher
local function _handleReachabilityChange(flags)
  logger.v("Reachability callback triggered. Raw Flags:", flags)

  if type(flags) ~= "number" then
    logger.e("Invalid flags received in _handleReachabilityChange:", inspect(flags), "- Assuming unreachable.")
    flags = 0
  end

  local isReachable = (flags & network.reachability.flags.reachable) > 0
  local connectionRequired = (flags & network.reachability.flags.connectionRequired) > 0
  local interventionRequired = (flags & network.reachability.flags.interventionRequired) > 0
  local transientConnection = (flags & network.reachability.flags.transientConnection) > 0

  local newStatus = "unreachable"
  if isReachable then
    newStatus = "reachable"
  end

  logger.v(string.format(
    "Interpreted Flags: Reachable=%s, ConnRequired=%s, InterventionReq=%s, Transient=%s -> NewStatus=%s",
    tostring(isReachable), tostring(connectionRequired), tostring(interventionRequired), tostring(transientConnection),
    newStatus))

  if newStatus ~= obj.lastReachabilityStatus then
    logger.i(string.format("Reachability Status Change Detected: %s -> %s", obj.lastReachabilityStatus, newStatus))
    obj.lastReachabilityStatus = newStatus
    _updateBar({ status = newStatus, flags = flags })
  else
    logger.v("Reachability status unchanged (" .. newStatus .. "), no visual update needed.")
  end
end

-- Handle screen layout changes
local function _handleScreenChange()
  logger.i("Screen configuration changed. Re-evaluating bar display.")
  local lastStatusToRedraw = obj.lastStatusInfo

  logger.v("Cleaning up existing canvases and timers before redraw...")
  for screenID, c in pairs(obj.statusCanvases) do
    if obj.fadeTimers[screenID] then
      obj.fadeTimers[screenID]:stop()
      logger.v("Stopped fade timer for screen", screenID)
    end
    if c and type(c.delete) == "function" then
      c:delete()
      logger.v("Deleted canvas for screen", screenID)
    end
  end
  obj.statusCanvases = {}
  obj.fadeTimers = {}
  logger.v("Screen change cleanup complete.")

  if obj.isRunning and lastStatusToRedraw then
    logger.i("Redrawing last known status on new screen layout:", inspect(lastStatusToRedraw))
    timer.doAfter(0.5, function()
      if obj.isRunning then
        _updateBar(lastStatusToRedraw)
      else
        logger.i("Spoon stopped during screen change delay, not redrawing.")
      end
    end)
  elseif not obj.isRunning then
    logger.i("Spoon is not running, not redrawing after screen change.")
  else
    logger.i("No previous status known, not redrawing after screen change.")
  end
end

-- ▰▰▰ Public Methods ▰▰▰ --

function obj:init()
  _setLogLevel()
  logger.i(obj.name .. " version " .. obj.version .. " initialized.")
end

function obj:start()
  if obj.isRunning then
    logger.w("Already running.")
    return self
  end
  logger.i("Starting " .. obj.name .. "...")
  _setLogLevel()

  local targetHost = _getConfig("targetHost")
  if not targetHost or type(targetHost) ~= "string" or targetHost == "" then
    logger.e("Cannot start: Invalid or missing 'targetHost' configuration.")
    return self
  end

  if not network or not network.reachability then
    logger.e("Cannot start: hs.network.reachability module not available.")
    return self
  end

  logger.i("Creating reachability watcher for host:", targetHost)
  if obj.reachabilityWatcher then obj.reachabilityWatcher:stop() end

  local watcher, err = network.reachability.forHostName(targetHost)
  if not watcher then
    logger.e("Failed to create reachability watcher for host:", targetHost, "Error:", err)
    return self
  end
  obj.reachabilityWatcher = watcher

  obj.reachabilityWatcher:setCallback(function(reachObj, flags)
    _handleReachabilityChange(flags)
  end)

  if not obj.reachabilityWatcher:start() then
    logger.e("Failed to start reachability watcher for host:", targetHost)
    obj.reachabilityWatcher = nil
    return self
  end
  logger.v("Reachability watcher started for", targetHost)

  if not screen or not screen.watcher then
    logger.w("Cannot start screen watcher: hs.screen.watcher module not available.")
  else
    if obj.screenWatcher then obj.screenWatcher:stop() end
    obj.screenWatcher = screen.watcher.new(_handleScreenChange):start()
    if obj.screenWatcher then
      logger.v("Screen watcher started.")
    else
      logger.e("Failed to create or start screen watcher.")
    end
  end

  obj.isRunning = true
  obj.lastReachabilityStatus = "unknown"
  obj.lastStatusInfo = { status = "unknown" }
  _updateBar(obj.lastStatusInfo) -- Show initial "unknown" bar

  timer.doAfter(1.0, function()
    if obj.reachabilityWatcher and obj.isRunning then
      local initialFlags, flagsErr = obj.reachabilityWatcher:status()
      if initialFlags then
        logger.i("Performing initial reachability check. Flags:", initialFlags)
        _handleReachabilityChange(initialFlags)
      else
        logger.e("Error getting initial reachability status:", flagsErr, "- Status remains unknown.")
      end
    elseif not obj.isRunning then
      logger.i("Spoon stopped before initial check could run.")
    else
      logger.w("Reachability watcher not available for initial check.")
    end
  end)

  logger.i(obj.name .. " started successfully.")
  return self
end

function obj:stop()
  if not obj.isRunning then
    logger.w("Not running.")
    return self
  end
  logger.i("Stopping " .. obj.name .. "...")

  if obj.reachabilityWatcher then
    obj.reachabilityWatcher:stop()
    obj.reachabilityWatcher = nil
    logger.v("Reachability watcher stopped.")
  end

  if obj.screenWatcher then
    obj.screenWatcher:stop()
    obj.screenWatcher = nil
    logger.v("Screen watcher stopped.")
  end

  logger.v("Cleaning up visuals...")
  _handleScreenChange() -- Clears canvases and timers

  obj.isRunning = false
  obj.lastReachabilityStatus = "unknown"
  obj.lastStatusInfo = nil

  logger.i(obj.name .. " stopped.")
  return self
end

function obj:status()
  local watcherStatus = "inactive"
  local currentFlags = nil
  if obj.reachabilityWatcher then
    watcherStatus = "active"
    pcall(function() currentFlags = obj.reachabilityWatcher:status() end)
  end

  return {
    running = obj.isRunning,
    lastDisplayedStatus = obj.lastReachabilityStatus,
    targetHost = _getConfig("targetHost"),
    watcherActive = (watcherStatus == "active"),
    currentReachabilityFlags = currentFlags,
    activeCanvases = utils.map(obj.statusCanvases, function(_, _) return true end)
  }
end

return obj
