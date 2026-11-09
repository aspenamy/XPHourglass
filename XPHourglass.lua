-------------------------------------------------------------------------------
-- XP Hourglass
--
-- Lightweight leveling stats written onto Blizzard's own XP bar for World of
-- Warcraft: Forever. Nothing is replaced or hidden: the bar keeps its look,
-- its Edit Mode position and the reputation bar beside it. This file keeps
-- the numbers; Bar.lua draws them and Options.lua is the settings page.
--
-- How the numbers work:
--   * The clock only runs while you're logged in, and stops while you're AFK
--     (unless that's turned off), so a break doesn't drag your pace down.
--   * XP per hour is taken from the last 15 minutes of play by default, so it
--     follows what you're doing now. The session rate is in the tooltip.
--   * For the first 3 minutes of a session the rate counts at least 3 minutes,
--     so one quest turn-in right after logging in can't show a huge rate.
--   * Kills to level uses your last 10 kills and counts the double XP you get
--     while rested.
--   * The session survives a /reload or a quick relog (10 minutes).
-------------------------------------------------------------------------------

local ADDON_NAME, ns = ...

ns.TITLE = "XP Hourglass"

-- The stats that can go on the bar, in the order they're drawn within each
-- end. Each one's place is "left", "right" or "off".
ns.BAR_STATS = {
  { key = "pct",    place = "left",  label = "Percent through the level", example = "45.2%" },
  { key = "rested", place = "left",  label = "Rested XP",                 example = "30% rested" },
  { key = "rate",   place = "right", label = "XP per hour",               example = "12.3k xp/hr" },
  { key = "ttl",    place = "right", label = "Time to level",             example = "38m to level" },
  { key = "kills",  place = "right", label = "Kills to level",            example = "~14 kills" },
}

local DEFAULTS = {
  font         = "default", -- "default" is Blizzard's bar font, or a name from ns.FONTS / LibSharedMedia
  -- fontSize is filled in at load with the size of Blizzard's bar text
  outline      = "default", -- "default", "NONE", "OUTLINE" or "THICKOUTLINE"
  textInset    = 20,        -- pixels in from each end of the bar
  textY        = 0,         -- pixels up (or down, below 0) from the bar's middle
  questXP      = true,      -- shade XP from finished quests on the bar
  questColor   = { r = 1, g = 0.8, b = 0.2, a = 0.85 }, -- its color, and how see-through it is (a)
  tooltip         = true,   -- add the full stats to the XP bar tooltip
  levelUpChat     = true,   -- a chat line on level up
  pauseAFK        = true,   -- stop the clock while AFK
  window          = 15,     -- minutes of play the rate is taken from, 0 = whole session
}

ns.DEFAULT_QUEST_COLOR = DEFAULTS.questColor

local RESUME_SECONDS = 600   -- a session saved this recently is picked back up
local RATE_FLOOR     = 180   -- the rate counts at least this many seconds
local KILLS_KEPT     = 10    -- recent kills used for kills to level
local GAINS_KEPT     = 3600  -- seconds of XP gains kept, the longest window

local db, char
local session = { active = 0, xp = 0, levels = 0, gains = {}, kills = {} }
local last = {}       -- level, xp and max XP at the last check
local quests = { xp = 0, count = 0 }

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

function ns.Print(msg, ...)
  if select("#", ...) > 0 then msg = msg:format(...) end
  print("|cffe6c35cXP Hourglass|r: " .. msg)
end

function ns.Settings() return db end

-- 950, 12.3k, 1.25m
function ns.Short(n)
  n = n or 0
  if n >= 1e6 then return ("%.2fm"):format(n / 1e6) end
  if n >= 1e4 then return ("%.1fk"):format(n / 1e3) end
  if n >= 1e3 then return ("%.2fk"):format(n / 1e3) end
  return ("%d"):format(n)
end

-- <1m, 38m, 1h 05m, 2d 3h
function ns.Duration(s)
  if not s or s ~= s or s == math.huge or s < 0 then return "--" end
  s = math.floor(s)
  if s < 60 then return "<1m" end
  local m = math.floor(s / 60)
  if m < 60 then return m .. "m" end
  local h = math.floor(m / 60)
  m = m % 60
  if h < 24 then return ("%dh %02dm"):format(h, m) end
  return ("%dd %dh"):format(math.floor(h / 24), h % 24)
end

function ns.Number(n)
  return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

-- Bar.lua sets this. Called whenever the numbers change.
local function Changed()
  if ns.Redraw then ns.Redraw() end
end
ns.Changed = Changed

-------------------------------------------------------------------------------
-- XP gains and the rate
-------------------------------------------------------------------------------

local function AddGain(amount)
  session.xp = session.xp + amount
  local gains = session.gains
  gains[#gains + 1] = { session.active, amount }
  -- Drop gains older than the longest window.
  local cutoff = session.active - GAINS_KEPT
  if gains[1][1] < cutoff then
    local keep = {}
    for _, g in ipairs(gains) do
      if g[1] >= cutoff then keep[#keep + 1] = g end
    end
    session.gains = keep
  end
end

-- XP per hour over the last `minutes` of play, or the whole session for 0.
function ns.Rate(minutes)
  local active = session.active
  if minutes == nil then minutes = db.window end
  local sum, span
  if minutes == 0 then
    sum, span = session.xp, active
  else
    local window = minutes * 60
    local cutoff = active - window
    sum = 0
    for i = #session.gains, 1, -1 do
      local g = session.gains[i]
      if g[1] <= cutoff then break end
      sum = sum + g[2]
    end
    span = math.min(window, active)
  end
  if sum <= 0 then return 0 end
  return sum / math.max(span, RATE_FLOOR) * 3600
end

-------------------------------------------------------------------------------
-- Kills. Read from the "X dies, you gain N experience." chat line, built
-- from the game's own string so it works in every language.
-------------------------------------------------------------------------------

local killPattern
do
  local fmt = COMBATLOG_XPGAIN_FIRSTPERSON
  if type(fmt) == "string" then
    fmt = fmt:gsub("%%%d%$", "%%")                     -- %1$s -> %s
    fmt = fmt:gsub("[%.%(%)%[%]%+%-%*%?%^%$]", "%%%0") -- escape pattern characters
    fmt = fmt:gsub("%%s", "(.-)"):gsub("%%d", "(%%d+)")
    fmt = fmt:gsub("%%%.$", "")                        -- the rested and group bonus text follows the period
    killPattern = "^" .. fmt
  end
end

local function OnXPMessage(msg)
  if not killPattern or type(msg) ~= "string" then return end
  local a, b = msg:match(killPattern)
  local gain = tonumber(b) or tonumber(a)
  if not gain or gain <= 0 then return end
  -- While rested a kill is worth more. Keep the base value so kills to level
  -- can work out when the rested XP runs out.
  local stateID, _, multiplier = GetRestState()
  if stateID == 1 and (GetXPExhaustion() or 0) > 0 and multiplier and multiplier > 1 then
    gain = gain / multiplier
  end
  local kills = session.kills
  kills[#kills + 1] = gain
  if #kills > KILLS_KEPT then table.remove(kills, 1) end
end

-------------------------------------------------------------------------------
-- Quests ready to turn in
-------------------------------------------------------------------------------

local questScanPending = false

local function ScanQuests()
  questScanPending = false
  local xp, count = 0, 0
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and GetQuestLogRewardXP then
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
      local info = C_QuestLog.GetInfo(i)
      if info and not info.isHeader and info.questID and C_QuestLog.IsComplete(info.questID) then
        local ok, reward = pcall(GetQuestLogRewardXP, info.questID)
        if ok and type(reward) == "number" and reward > 0 then
          xp, count = xp + reward, count + 1
        end
      end
    end
  end
  if xp ~= quests.xp or count ~= quests.count then
    quests.xp, quests.count = xp, count
    Changed()
  end
end

-- QUEST_LOG_UPDATE fires in bursts, so scan once shortly after.
local function QueueQuestScan()
  if questScanPending then return end
  questScanPending = true
  C_Timer.After(0.5, ScanQuests)
end

-------------------------------------------------------------------------------
-- Level time and level ups
-------------------------------------------------------------------------------

local function StartLevel(level, partial)
  char.level = level
  char.levelTime = 0
  char.levelPartial = partial or nil
end

local function LevelUp(oldLevel, newLevel)
  char.history = char.history or {}
  local took, partial = char.levelTime or 0, char.levelPartial
  char.history[oldLevel] = { time = took, partial = partial }
  session.levels = session.levels + (newLevel - oldLevel)

  if db.levelUpChat then
    local line = ("Reached level %d. Level %d took %s"):format(newLevel, oldLevel, ns.Duration(took))
    if partial then
      line = line .. ", counted from when XP Hourglass started tracking it"
    end
    local rate = ns.Rate()
    if rate > 0 then
      line = line .. (" (%s XP an hour lately)"):format(ns.Short(rate))
    end
    ns.Print(line .. ".")
  end

  StartLevel(newLevel, newLevel - oldLevel > 1)
end

-------------------------------------------------------------------------------
-- Reading XP
-------------------------------------------------------------------------------

local function ReadXP()
  local level, cur, max = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
  if not last.level then
    last.level, last.xp, last.max = level, cur, max
    return
  end
  local gain = 0
  if level > last.level then
    -- Rest of the old level plus what's on the new one. Levels skipped in
    -- between (very rare) aren't counted.
    gain = (last.max - last.xp) + cur
    LevelUp(last.level, level)
  elseif level == last.level then
    if cur < last.xp then
      -- The XP has already reset for a level up the level number hasn't
      -- caught up with yet. Wait for the next update.
      return
    end
    gain = cur - last.xp
  end
  last.level, last.xp, last.max = level, cur, max
  if gain > 0 then AddGain(gain) end
  Changed()
end

-------------------------------------------------------------------------------
-- Everything the bar, tooltip and /xph show
-------------------------------------------------------------------------------

function ns.IsMaxLevel()
  if IsXPUserDisabled and IsXPUserDisabled() then return true end
  if GameRulesUtil and GameRulesUtil.IsPlayerAtEffectiveMaxLevel then
    local ok, maxed = pcall(GameRulesUtil.IsPlayerAtEffectiveMaxLevel)
    if ok and maxed then return true end
  end
  return (UnitXPMax("player") or 0) <= 0
end

function ns.GetStats()
  local s = {}
  s.level = UnitLevel("player")
  s.cur, s.max = UnitXP("player"), UnitXPMax("player")
  s.maxed = ns.IsMaxLevel()
  if s.max <= 0 then s.max = 1 end
  s.remaining = math.max(s.max - s.cur, 0)
  s.pct = s.cur / s.max * 100

  s.rested = GetXPExhaustion() or 0
  s.restedPct = s.rested / s.max * 100
  s.resting = IsResting()

  s.window = db.window
  s.rate = ns.Rate()
  s.sessionRate = ns.Rate(0)
  if s.rate > 0 then s.timeToLevel = s.remaining / s.rate * 3600 end

  -- Kills to level, counting double XP until the rested XP runs out.
  local n = #session.kills
  if n > 0 then
    local sum = 0
    for _, k in ipairs(session.kills) do sum = sum + k end
    local base = sum / n
    local stateID, _, multiplier = GetRestState()
    local bonus = (stateID == 1 and multiplier and multiplier > 1) and multiplier or 1
    s.killXP = base
    if bonus > 1 and s.rested > 0 then
      local restedPart = math.min(s.rested * bonus / (bonus - 1), s.remaining)
      s.kills = math.ceil(restedPart / (base * bonus))
      if restedPart < s.remaining then
        s.kills = s.kills + math.ceil((s.remaining - restedPart) / base)
      end
    else
      s.kills = math.ceil(s.remaining / base)
    end
  end

  s.questXP, s.questCount = quests.xp, quests.count

  s.levelTime = char.levelTime or 0
  s.levelPartial = char.levelPartial
  local prev = char.history and char.history[s.level - 1]
  if prev then s.lastLevelTime, s.lastLevelPartial = prev.time, prev.partial end

  s.sessionTime = session.active
  s.sessionXP = session.xp
  s.sessionLevels = session.levels
  s.paused = db.pauseAFK and UnitIsAFK("player")
  return s
end

function ns.ResetSession()
  session.active, session.xp, session.levels = 0, 0, 0
  session.gains, session.kills = {}, {}
  Changed()
end

-------------------------------------------------------------------------------
-- Saving the session across a /reload
-------------------------------------------------------------------------------

local function SaveSession()
  if not char then return end
  char.session = {
    savedAt = time(),
    active = session.active,
    xp = session.xp,
    levels = session.levels,
    gains = session.gains,
    kills = session.kills,
  }
end

local function RestoreSession()
  local saved = char.session
  char.session = nil
  if type(saved) ~= "table" or not saved.savedAt then return end
  if time() - saved.savedAt > RESUME_SECONDS then return end
  session.active = saved.active or 0
  session.xp = saved.xp or 0
  session.levels = saved.levels or 0
  session.gains = saved.gains or {}
  session.kills = saved.kills or {}
end

-------------------------------------------------------------------------------
-- The clock
-------------------------------------------------------------------------------

local ticks = 0
local function Tick()
  if db.pauseAFK and UnitIsAFK("player") then return end
  session.active = session.active + 1
  char.levelTime = (char.levelTime or 0) + 1
  ticks = ticks + 1
  -- The rate slides as time passes, so redraw now and then even with no XP.
  if ticks % 5 == 0 then Changed() end
end

-------------------------------------------------------------------------------
-- Startup and events
-------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local started = false

local function Start()
  if started then return end
  started = true

  local level, cur = UnitLevel("player"), UnitXP("player")
  if char.level ~= level then
    -- First run, or levels gained without the addon. Time on this level is
    -- only complete if we're seeing it from the very start.
    StartLevel(level, cur > 0)
  end
  RestoreSession()
  ReadXP()
  ScanQuests()

  C_Timer.NewTicker(1, Tick)
  frame:RegisterEvent("PLAYER_XP_UPDATE")
  frame:RegisterEvent("PLAYER_LEVEL_UP")
  frame:RegisterEvent("UPDATE_EXHAUSTION")
  frame:RegisterEvent("PLAYER_UPDATE_RESTING")
  frame:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
  frame:RegisterEvent("QUEST_LOG_UPDATE")
  frame:RegisterEvent("QUEST_TURNED_IN")
  frame:RegisterEvent("PLAYER_FLAGS_CHANGED")
  frame:RegisterEvent("PLAYER_LOGOUT")

  if ns.OnStart then ns.OnStart() end
  Changed()
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON_NAME then return end
    XPHourglassDB = XPHourglassDB or {}
    db = XPHourglassDB
    -- 0.1.0 had an on/off checkbox per stat.
    for old, key in pairs({ showPercent = "pct", showRested = "rested", showRate = "rate",
                            showTimeToLevel = "ttl", showKills = "kills" }) do
      if db[old] == false then db["place_" .. key] = "off" end
      db[old] = nil
    end
    -- The size of Blizzard's own bar text is the default text size.
    local size = _G.TextStatusBarText and select(2, TextStatusBarText:GetFont())
    ns.defaultFontSize = math.floor((size or 12) + 0.5)
    db.fontSize = db.fontSize or ns.defaultFontSize
    for k, v in pairs(DEFAULTS) do
      if db[k] == nil then
        if type(v) == "table" then
          local copy = {}
          for tk, tv in pairs(v) do copy[tk] = tv end
          v = copy
        end
        db[k] = v
      end
    end
    for _, stat in ipairs(ns.BAR_STATS) do
      db["place_" .. stat.key] = db["place_" .. stat.key] or stat.place
    end
    XPHourglassCharDB = XPHourglassCharDB or {}
    char = XPHourglassCharDB
    if ns.OnLoaded then ns.OnLoaded() end
  elseif event == "PLAYER_ENTERING_WORLD" then
    Start()
  elseif event == "PLAYER_XP_UPDATE" then
    ReadXP()
  elseif event == "PLAYER_LEVEL_UP" then
    -- The level number can lag the event a little.
    C_Timer.After(0.5, ReadXP)
  elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
    OnXPMessage(...)
  elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_TURNED_IN" then
    QueueQuestScan()
  elseif event == "PLAYER_FLAGS_CHANGED" then
    if ... == "player" then Changed() end
  elseif event == "PLAYER_LOGOUT" then
    SaveSession()
  else
    Changed()
  end
end)

-------------------------------------------------------------------------------
-- /xph
-------------------------------------------------------------------------------

SLASH_XPHOURGLASS1 = "/xph"
SLASH_XPHOURGLASS2 = "/hourglass"
SlashCmdList.XPHOURGLASS = function(input)
  local cmd = (input or ""):lower():match("^%s*(%S*)")
  if cmd == "config" or cmd == "options" or cmd == "settings" then
    if ns.OpenOptions then ns.OpenOptions() end
  elseif cmd == "reset" then
    ns.ResetSession()
    ns.Print("session reset. XP per hour and time to level start over.")
  elseif cmd == "help" then
    ns.Print("/xph shows your leveling stats in chat.")
    ns.Print("/xph config opens the settings.")
    ns.Print("/xph reset starts the session over.")
  else
    if not started then return end
    if ns.IsMaxLevel() then
      ns.Print("you're at max level, so there's nothing to track.")
      return
    end
    ns.Print("level %d", UnitLevel("player"))
    for _, line in ipairs(ns.StatLines(ns.GetStats())) do
      print(("  |cffffd200%s:|r %s"):format(line[1], line[2]))
    end
  end
end
