-------------------------------------------------------------------------------
-- Settings page: Options > AddOns > Hourglass
-------------------------------------------------------------------------------

local ADDON_NAME, ns = ...

local optionsCategory

local function BuildOptionsPage()
  if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then
    return
  end
  local db = ns.Settings()
  local category, layout = Settings.RegisterVerticalLayoutCategory(ns.TITLE)
  optionsCategory = category

  local function AddHeader(text)
    if CreateSettingsListSectionHeaderInitializer and layout then
      pcall(function() layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text)) end)
    end
  end

  local function Register(key, label, default)
    local setting = Settings.RegisterAddOnSetting(category, "XPHourglass_" .. key, key, db, type(default), label, default)
    setting:SetValueChangedCallback(function() ns.Restyle() end)
    return setting
  end

  local function Checkbox(key, label, default, tooltip)
    Settings.CreateCheckbox(category, Register(key, label, default), tooltip)
  end

  local function Dropdown(key, label, default, choices, tooltip)
    local setting = Register(key, label, default)
    local function GetOptions()
      local container = Settings.CreateControlTextContainer()
      for _, choice in ipairs(type(choices) == "function" and choices() or choices) do
        container:Add(choice[1], choice[2])
      end
      return container:GetData()
    end
    Settings.CreateDropdown(category, setting, GetOptions, tooltip)
  end

  local function Slider(key, label, default, min, max, tooltip, format)
    if not (Settings.CreateSlider and Settings.CreateSliderOptions) then return end
    local options = Settings.CreateSliderOptions(min, max, 1)
    if MinimalSliderWithSteppersMixin and options.SetLabelFormatter then
      options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, format)
    end
    Settings.CreateSlider(category, Register(key, label, default), options, tooltip)
  end

  AddHeader("On the XP bar")
  local places = { { "left", "Left end" }, { "center", "Center" }, { "right", "Right end" }, { "off", "Hidden" } }
  for _, stat in ipairs(ns.BAR_STATS) do
    Dropdown("place_" .. stat.key, stat.label, stat.place, places,
      ("Where on the XP bar it shows, like %s, or Hidden to keep it to the tooltip. "
        .. "Stats in the same place keep the order of this list. Center text makes way for Blizzard's "
        .. "own XP numbers while you hover the bar."):format(stat.example))
  end
  Checkbox("questXP", "Shade XP from finished quests", true,
    "Shades the part of the bar that your finished quests will fill once you turn them in.")
  if CreateSettingsButtonInitializer and layout and ColorPickerFrame then
    pcall(function()
      layout:AddInitializer(CreateSettingsButtonInitializer(
        "Quest shading color", "Choose", ns.PickQuestColor,
        "Opens the color picker for the quest shading. The opacity slider sets how much of the bar shows through.", true))
      layout:AddInitializer(CreateSettingsButtonInitializer(
        "", "Reset color", function()
          ns.SetQuestColor(ns.DEFAULT_QUEST_COLOR)
        end, "Puts the quest shading back to the default gold.", true))
    end)
  end

  AddHeader("Text")
  Dropdown("font", "Font", "default", function()
    local choices = { { "default", "Blizzard's bar font" } }
    for _, font in ipairs(ns.FONTS) do choices[#choices + 1] = { font.name, font.name } end
    local media = ns.SharedMedia()
    if media then
      for _, name in ipairs(media:List("font")) do
        local builtIn = false
        for _, font in ipairs(ns.FONTS) do builtIn = builtIn or font.name == name end
        if not builtIn then choices[#choices + 1] = { name, name } end
      end
    end
    return choices
  end, "The font for the text on the bar. Fonts shared by other addons through LibSharedMedia are listed too.")
  Slider("fontSize", "Size", ns.defaultFontSize or 12, 8, 20,
    "How big the text on the bar is.", function(value) return tostring(value) end)
  Dropdown("outline", "Outline", "default", {
    { "default", "Blizzard's" }, { "NONE", "None" }, { "OUTLINE", "Thin" }, { "THICKOUTLINE", "Thick" },
  }, "An outline keeps the text readable over a bright bar.")
  Slider("textInset", "Distance from the ends", 20, 0, 150,
    "How far in from each end of the XP bar the text sits, in pixels.",
    function(value) return value .. " px" end)
  Slider("textY", "Up and down", 0, -10, 10,
    "Moves the text up or down on the bar, a pixel at a time.",
    function(value) return (value > 0 and "+" or "") .. value end)

  AddHeader("Pace")
  do
    local setting = Register("window", "XP per hour from", 15)
    local function GetOptions()
      local container = Settings.CreateControlTextContainer()
      for _, minutes in ipairs({ 5, 15, 30, 60 }) do
        container:Add(minutes, ("The last %d minutes"):format(minutes))
      end
      container:Add(0, "The whole session")
      return container:GetData()
    end
    Settings.CreateDropdown(category, setting, GetOptions,
      "How much recent play the XP per hour and time to level are worked out from. A short time follows what "
        .. "you're doing right now, and the whole session is steadier.")
  end
  Checkbox("pauseAFK", "Pause the clock while AFK", true,
    "Stops counting time while you're away, so a break doesn't pull your XP per hour down. "
      .. "Time on the level stops too.")

  AddHeader("Other")
  Checkbox("tooltip", "Add stats to the XP bar tooltip", true,
    "Hovering the XP bar adds time to level, kills, quests ready to turn in, time on the level and the session.")
  Checkbox("levelUpChat", "Say how long the level took", true,
    "Prints a line in chat when you level up with how long the level took.")

  if CreateSettingsButtonInitializer and layout then
    pcall(function()
      layout:AddInitializer(CreateSettingsButtonInitializer(
        "Session", "Reset", function()
          ns.ResetSession()
          ns.Print("session reset. XP per hour and time to level start over.")
        end, "Starts the session over, so XP per hour and time to level forget everything so far. "
          .. "Time on the level is kept.", true))
    end)
  end

  Settings.RegisterAddOnCategory(category)
end

-------------------------------------------------------------------------------
-- Quest shading color
-------------------------------------------------------------------------------

function ns.SetQuestColor(c)
  -- Always a fresh table, so the default is never changed by accident.
  ns.Settings().questColor = { r = c.r, g = c.g, b = c.b, a = c.a }
  ns.Restyle()
end

function ns.PickQuestColor()
  local before = ns.Settings().questColor
  local function Picked()
    local r, g, b = ColorPickerFrame:GetColorRGB()
    local a = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or before.a
    ns.SetQuestColor({ r = r, g = g, b = b, a = a })
  end
  local info = {
    r = before.r, g = before.g, b = before.b,
    opacity = before.a, hasOpacity = true,
    swatchFunc = Picked, opacityFunc = Picked,
    cancelFunc = function() ns.SetQuestColor(before) end,
  }
  if ColorPickerFrame.SetupColorPickerAndShow then
    ColorPickerFrame:SetupColorPickerAndShow(info)
  end
end

function ns.OpenOptions()
  if optionsCategory and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(optionsCategory:GetID())
  else
    ns.Print("the settings page isn't available, so use the /xph commands instead.")
  end
end

ns.OnLoaded = BuildOptionsPage
