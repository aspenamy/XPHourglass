-------------------------------------------------------------------------------
-- The XP bar: text at both ends of Blizzard's bar, shading for quest XP, and
-- extra lines in the bar's tooltip.
--
-- Blizzard's status bar manager has two containers (the XP bar can sit in
-- either, next to a watched reputation), and each has its own copy of the XP
-- bar. Both get an overlay; only the one on screen is ever visible. The
-- overlays are children of the bars, so they move, fade and hide with them
-- and follow Edit Mode. Nothing on Blizzard's frames is changed.
--
-- The text sits at the left and right ends by default. Stats can also go in
-- the middle, where they make way for Blizzard's own "XP 1,234 / 5,678" text
-- while you hover the bar. Where each stat goes, and the text's font, size,
-- outline and position, are set on the settings page.
-------------------------------------------------------------------------------

local ADDON_NAME, ns = ...

local overlays = {}
local attached = {}
local SEP = "   |cff9d9d9d\194\183|r   "   -- a grey middle dot
-- Frame levels above the bar's container, enough to clear its segment lines.
local TEXT_LEVEL = 20

-------------------------------------------------------------------------------
-- Lines for the tooltip and /xph
-------------------------------------------------------------------------------

local function WindowLabel(minutes)
  if minutes == 0 then return "this session" end
  return ("last %d min"):format(minutes)
end

function ns.StatLines(s)
  local lines = {}
  local function Add(label, value) lines[#lines + 1] = { label, value } end

  if s.timeToLevel then
    Add("Time to level", ns.Duration(s.timeToLevel))
  else
    Add("Time to level", "|cff9d9d9dneeds some XP first|r")
  end
  if s.rate > 0 then
    Add("XP per hour", ("%s (%s)"):format(ns.Short(s.rate), WindowLabel(s.window)))
  end
  if s.window ~= 0 and s.sessionRate > 0 then
    Add("Session pace", ns.Short(s.sessionRate) .. " an hour")
  end
  Add("XP to level", ("%s (%.1f%%)"):format(ns.Number(s.remaining), 100 - s.pct))

  if s.rested > 0 then
    Add("Rested", ("%s (%.0f%% of a level)"):format(ns.Number(s.rested), s.restedPct))
  elseif s.resting then
    Add("Rested", "none yet, builds while you're here")
  end

  if s.kills then
    Add("Kills to level", ("about %d (%s XP each)"):format(s.kills, ns.Short(s.killXP)))
  end
  if s.questCount > 0 then
    Add("Quests ready to turn in", ("%d for %s XP (%.0f%% of a level)")
      :format(s.questCount, ns.Number(s.questXP), s.questXP / s.max * 100))
  end

  Add("Time on this level", ns.Duration(s.levelTime) .. (s.levelPartial and "+" or ""))
  if s.lastLevelTime then
    Add("Last level took", ns.Duration(s.lastLevelTime) .. (s.lastLevelPartial and "+" or ""))
  end

  local sessionText = ("%s played, %s XP"):format(ns.Duration(s.sessionTime), ns.Short(s.sessionXP))
  if s.sessionLevels > 0 then
    sessionText = sessionText .. (", %d level%s"):format(s.sessionLevels, s.sessionLevels == 1 and "" or "s")
  end
  Add("This session", sessionText)

  if s.paused then
    Add("Clock", "|cffff8040paused while you're AFK|r")
  end
  return lines
end

-------------------------------------------------------------------------------
-- Fonts
-------------------------------------------------------------------------------

-- Fonts every client has. Fonts other addons share through LibSharedMedia
-- are offered too, when one of them is installed.
ns.FONTS = {
  { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
  { name = "Arial Narrow",  path = "Fonts\\ARIALN.TTF" },
  { name = "Skurri",        path = "Fonts\\SKURRI.TTF" },
  { name = "Morpheus",      path = "Fonts\\MORPHEUS.TTF" },
}

function ns.SharedMedia()
  return LibStub and LibStub("LibSharedMedia-3.0", true)
end

local function FontPath(name)
  for _, font in ipairs(ns.FONTS) do
    if font.name == name then return font.path end
  end
  local media = ns.SharedMedia()
  return media and media:IsValid("font", name) and media:Fetch("font", name) or nil
end

-- The quest shading is the chosen color with a soft gradient: brighter along
-- the top edge and a little deeper along the bottom, like the bar's own fill.
local function ApplyQuestColor(o)
  local c = ns.Settings().questColor
  -- Lightening mixes toward white, so the top edge keeps the same hue.
  local function Lighter(f)
    return CreateColor(c.r + (1 - c.r) * f, c.g + (1 - c.g) * f, c.b + (1 - c.b) * f, c.a)
  end
  local function Darker(f)
    return CreateColor(c.r * f, c.g * f, c.b * f, c.a)
  end
  if o.quest.SetGradient and CreateColor then
    o.quest:SetColorTexture(1, 1, 1, 1)
    o.quest:SetGradient("VERTICAL", Darker(0.75), Lighter(0.3))
  else
    o.quest:SetColorTexture(c.r, c.g, c.b, c.a)
  end
end

local function ApplyStyle(o)
  local db = ns.Settings()
  local basePath, _, baseFlags = o.baseFont:GetFont()
  local path = db.font ~= "default" and FontPath(db.font) or basePath
  local flags = db.outline == "default" and (baseFlags or "") or (db.outline == "NONE" and "" or db.outline)
  for _, text in ipairs({ o.left, o.center, o.right }) do
    -- A font that can't be loaded (an addon removed, say) falls back to Blizzard's.
    if not text:SetFont(path, db.fontSize, flags) then
      text:SetFont(basePath, db.fontSize, flags)
    end
  end
  o.left:ClearAllPoints()
  o.left:SetPoint("LEFT", o.textFrame, "LEFT", db.textInset, db.textY)
  o.right:ClearAllPoints()
  o.right:SetPoint("RIGHT", o.textFrame, "RIGHT", -db.textInset, db.textY)
  o.center:ClearAllPoints()
  o.center:SetPoint("CENTER", o.textFrame, "CENTER", 0, db.textY)
  ApplyQuestColor(o)
end

function ns.Restyle()
  for _, o in ipairs(overlays) do ApplyStyle(o) end
  ns.Redraw()
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------

local STAT_TEXT = {
  pct = function(s) return ("%.1f%%"):format(s.pct) end,
  rested = function(s)
    if s.rested > 0 then return ("|cff6fa8ff%.0f%% rested|r"):format(s.restedPct) end
  end,
  rate = function(s) return (s.rate > 0 and ns.Short(s.rate) or "--") .. " xp/hr" end,
  ttl = function(s) return (s.timeToLevel and ns.Duration(s.timeToLevel) or "--") .. " to level" end,
  kills = function(s)
    if s.kills then return ("~%d kills"):format(s.kills) end
  end,
}

local function BarTexts(s, db)
  local sides = { left = {}, center = {}, right = {} }
  for _, stat in ipairs(ns.BAR_STATS) do
    local side = sides[db["place_" .. stat.key]]
    local text = side and STAT_TEXT[stat.key](s)
    if text then side[#side + 1] = text end
  end
  if s.paused then table.insert(sides.right, "|cffff8040paused|r") end
  return table.concat(sides.left, SEP), table.concat(sides.center, SEP), table.concat(sides.right, SEP)
end

local function DrawQuestShade(o, s, db)
  local width = o:GetWidth()
  if not db.questXP or s.questXP <= 0 or s.remaining <= 0 or not width or width <= 0 then
    o.quest:Hide()
    return
  end
  local x = width * s.cur / s.max
  local w = width * math.min(s.questXP, s.remaining) / s.max
  o.quest:ClearAllPoints()
  o.quest:SetPoint("TOPLEFT", o, "TOPLEFT", x, 0)
  o.quest:SetPoint("BOTTOMLEFT", o, "BOTTOMLEFT", x, 0)
  o.quest:SetWidth(math.max(w, 1))
  o.quest:Show()
end

function ns.Redraw()
  if #overlays == 0 then return end
  local db = ns.Settings()
  local s = ns.GetStats()
  local left, center, right = "", "", ""
  if not s.maxed then left, center, right = BarTexts(s, db) end
  for _, o in ipairs(overlays) do
    o.left:SetText(left)
    o.center:SetText(center)
    o.right:SetText(right)
    if s.maxed then o.quest:Hide() else DrawQuestShade(o, s, db) end
  end
end

-------------------------------------------------------------------------------
-- Tooltip
-------------------------------------------------------------------------------

local function OnBarEnter()
  local db = ns.Settings()
  if not db.tooltip or ns.IsMaxLevel() then return end
  local tooltip = GameTooltip
  -- Blizzard shows its XP and rested tooltip on the same hover. Add to it,
  -- or start one if it didn't.
  if tooltip:IsShown() then
    tooltip:AddLine(" ")
  else
    GameTooltip_SetDefaultAnchor(tooltip, UIParent)
  end
  tooltip:AddLine(ns.TITLE, 0.9, 0.76, 0.36)
  for _, line in ipairs(ns.StatLines(ns.GetStats())) do
    tooltip:AddDoubleLine(line[1], line[2], 1, 0.82, 0, 1, 1, 1)
  end
  tooltip:Show()
end

-------------------------------------------------------------------------------
-- Finding Blizzard's XP bars
-------------------------------------------------------------------------------

-- Edit Mode and the bar manager can change the container's frame level, so
-- this is redone whenever the bar is shown.
local function RaiseText(o)
  o.textFrame:SetFrameLevel(o.container:GetFrameLevel() + TEXT_LEVEL)
end

-- Blizzard's "XP 1,234 / 5,678" text uses the middle of the bar while you
-- hover it, or all the time with Interface > Display > Show XP text on. The
-- center text steps aside whenever Blizzard's is showing.
local function UpdateCenter(o)
  local blizzardText = o.bar.OverlayFrame and o.bar.OverlayFrame.Text
  o.center:SetShown(not (blizzardText and blizzardText:IsShown()))
end

local function CreateOverlay(bar)
  local statusBar = bar.StatusBar or bar

  local o = CreateFrame("Frame", nil, bar)
  o:SetAllPoints(statusBar)
  o:SetFrameLevel(statusBar:GetFrameLevel() + 2)

  o.quest = o:CreateTexture(nil, "ARTWORK")
  o.quest:Hide()

  -- The text has to sit above the bar's frame art and the segment lines,
  -- which belong to the container around the bar and are drawn a strata
  -- higher than the bar, like Blizzard's own bar text.
  local textFrame = CreateFrame("Frame", nil, o)
  textFrame:SetAllPoints(o)
  textFrame:SetFrameStrata("MEDIUM")
  o.textFrame = textFrame
  o.container = bar:GetParent()
  RaiseText(o)

  -- Blizzard's own bar text font: its shadow and color are kept, and its
  -- face, size and outline are what "default" means in the settings.
  o.baseFont = _G.TextStatusBarText or GameFontHighlightSmall
  o.left = textFrame:CreateFontString(nil, "OVERLAY")
  o.left:SetFontObject(o.baseFont)
  o.left:SetJustifyH("LEFT")
  o.right = textFrame:CreateFontString(nil, "OVERLAY")
  o.right:SetFontObject(o.baseFont)
  o.right:SetJustifyH("RIGHT")
  o.center = textFrame:CreateFontString(nil, "OVERLAY")
  o.center:SetFontObject(o.baseFont)
  o.center:SetJustifyH("CENTER")
  o.bar = bar
  ApplyStyle(o)

  o:SetScript("OnSizeChanged", function() ns.Redraw() end)
  bar:HookScript("OnEnter", function()
    UpdateCenter(o)
    OnBarEnter()
  end)
  bar:HookScript("OnLeave", function() UpdateCenter(o) end)
  bar:HookScript("OnShow", function()
    RaiseText(o)
    UpdateCenter(o)
    ns.Redraw()
  end)
  -- Also catches the Show XP text option being switched on or off.
  if type(bar.UpdateTextVisibility) == "function" then
    hooksecurefunc(bar, "UpdateTextVisibility", function() UpdateCenter(o) end)
  end
  UpdateCenter(o)

  overlays[#overlays + 1] = o
end

local function Attach()
  local manager = _G.StatusTrackingBarManager
  local bars = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
  if not (manager and manager.barContainers and bars and bars.Experience) then return false end
  local found = false
  for _, container in ipairs(manager.barContainers) do
    local bar = container.bars and container.bars[bars.Experience]
    if bar and not attached[bar] then
      attached[bar] = true
      CreateOverlay(bar)
    end
    found = found or bar ~= nil
  end
  return found
end

function ns.OnStart()
  if not Attach() then
    ns.Print("couldn't find Blizzard's XP bar (another addon may have replaced it). "
      .. "Type /xph to see your stats in chat.")
  end
  ns.Redraw()
end
