-- VoidHub: the Start page, a "right now" dashboard. The user, 2026-11-24: "the start page is just a list of the
-- addons, i think we need more catchy than that", then on the first version: "i like the idea of the start page, but
-- it could be more and pop better". So: a hero band (portrait, class-coloured name, big level, XP bar with rested,
-- time to level, gold), then tiles with a big value, a colour stripe per kind, colour that means something
-- (durability green / yellow / red) and a hover glow. Click a tile = its page.
-- Cheap ("i dont want this to bloat the game"): built ONCE (the game can't free frames), refreshed on show and every
-- 5 s while on screen; closed, it costs nothing but one XP listener (for time to level). Every number is the game's
-- or the addon's own; nothing made up.
local ns = _G.VoidHubWin
if not ns or ns.skip then return end   -- another Void addon's copy of VoidHub runs the window
local K = ns.Kit

local TILE_W, TILE_H, GAP, COLS = 287, 56, 7, 3
local HERO_H, MOVE_H = 96, 50
local GOLD = "|cffffd200"
local GREY = "|cff8c8c9e"
local GREEN, YELLOW, RED = "|cff33ff66", "|cffffd200", "|cffff5555"
-- stripe colours by kind of tile
local KIND = {
    world = { 0.00, 0.78, 1.00 },   -- layers, rares
    quest = { 1.00, 0.82, 0.00 },
    gold  = { 1.00, 0.65, 0.10 },
    prof  = { 0.40, 0.90, 0.40 },
    gear  = { 0.70, 0.45, 1.00 },
    life  = { 0.95, 0.35, 0.35 },   -- repairs, bags, hearth
    rep   = { 0.30, 0.85, 0.85 },
}

local function loaded(name)
    local ok, v = pcall(C_AddOns.IsAddOnLoaded, name)
    return ok and v
end
local function money(c)
    if not c then return "?" end
    local b = _G.VoidBags
    if b and b.Income and b.Income.Money then local ok, s = pcall(b.Income.Money, c); if ok and s then return s end end
    return GetCoinTextureString and GetCoinTextureString(math.floor(c)) or tostring(c)
end
local function ago(sec)
    if sec < 90 then return ("%d s"):format(sec) end
    if sec < 5400 then return ("%d min"):format(math.floor(sec / 60)) end
    return ("%d h"):format(math.floor(sec / 3600))
end
local function span(sec)
    if sec < 3600 then return ("%d min"):format(math.max(1, math.floor(sec / 60 + 0.5))) end
    return ("%d h %02d min"):format(math.floor(sec / 3600), math.floor(sec % 3600 / 60))
end
local function big(n)
    if n >= 10000 then return ("%.1fk"):format(n / 1000) end
    return tostring(n)
end

----------------------------------------------------------------------
-- XP pace this session: one listener, only adds numbers (time to level)
----------------------------------------------------------------------
local xp = { t0 = nil, gained = 0, last = nil, lastMax = nil }
-- this session's wins (since login / reload): quests turned in, levels, gold
local sess = { quests = 0, levels = 0, money0 = nil }
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_XP_UPDATE")
    f:RegisterEvent("QUEST_TURNED_IN")
    f:RegisterEvent("PLAYER_LEVEL_UP")
    f:SetScript("OnEvent", function(_, e)
        if e == "QUEST_TURNED_IN" then sess.quests = sess.quests + 1 return end
        if e == "PLAYER_LEVEL_UP" then sess.levels = sess.levels + 1 return end
        if e == "PLAYER_ENTERING_WORLD" and not sess.money0 then sess.money0 = GetMoney() end
        local cur, max = UnitXP("player"), UnitXPMax("player")
        if e == "PLAYER_ENTERING_WORLD" or not xp.last then
            xp.t0 = xp.t0 or GetTime()
            xp.last, xp.lastMax = cur, max
            return
        end
        local d = cur - xp.last
        if d < 0 then d = (xp.lastMax - xp.last) + cur end   -- a level up in between
        xp.gained = xp.gained + math.max(0, d)
        xp.last, xp.lastMax = cur, max
    end)
end
local function timeToLevel()
    if not xp.t0 or xp.gained <= 0 then return nil end
    local el = GetTime() - xp.t0
    if el < 300 then return nil end   -- a pace only after 5 minutes of play
    local left = UnitXPMax("player") - UnitXP("player")
    return left / (xp.gained / el)
end

----------------------------------------------------------------------
-- The tiles: kind, title, icon, available() (its addon / data is there), value(), detail(), go
----------------------------------------------------------------------
local TILES = {}

TILES[#TILES + 1] = {
    kind = "world", title = "Layer", icon = "Interface\\Icons\\Spell_Arcane_PortalOrgrimmar",
    available = function() return _G.VoidLayerCore ~= nil end, go = { "VoidLayer", "layers" },
    value = function()
        local c = _G.VoidLayerCore
        local pair, zone = c:Here()
        if not zone then return GREY .. "No layers here|r" end
        if not pair then return GREY .. "Not known yet|r" end
        return GOLD .. c:Label(zone, pair) .. "|r"
    end,
    detail = function()
        local c = _G.VoidLayerCore
        local pair, zone = c:Here()
        if IsInGroup() and not IsInRaid() and c.MoveGroup then return "In a party: Move group takes everyone to a fresh one." end
        if not zone then return "Instances have no layers." end
        local others = 0
        for p in pairs(c:Counts(zone)) do if p ~= pair then others = others + 1 end end
        local online = c:Online() or 0
        if others == 0 then return ("%d Void players online. No other layer known here yet."):format(online) end
        return ("%d other layer%s with Void players here, %d online."):format(others, others == 1 and "" or "s", online)
    end,
}

TILES[#TILES + 1] = {
    kind = "world", title = "Rares", icon = "Interface\\Icons\\Ability_Hunter_MarkedForDeath",
    empty = function() local c = _G.VoidLayerCore; local _, z = c:Here(); return not z or #c:Rares(z) == 0 end,
    available = function() local c = _G.VoidLayerCore; return c ~= nil and c.Rares ~= nil end, go = { "VoidLayer", "layers" },
    value = function()
        local c = _G.VoidLayerCore
        local _, zone = c:Here()
        local n = zone and #c:Rares(zone) or 0
        if n == 0 then return GREY .. "None reported here|r" end
        return GOLD .. n .. "|r up in this zone"
    end,
    detail = function()
        local c = _G.VoidLayerCore
        local _, zone = c:Here()
        local r = zone and c:Rares(zone)[1]
        if not r then return "Void players share every rare they see." end
        return ("%s, %s, %s ago."):format(r.name or "?", r.same and "on your layer" or "on another layer", ago(r.age or 0))
    end,
}

local function questCounts()
    local done, all, names = 0, 0, {}
    for i = 1, (C_QuestLog.GetNumQuestLogEntries() or 0) do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and not info.isHidden then
            all = all + 1
            if info.questID and C_QuestLog.IsComplete(info.questID) then
                done = done + 1
                if #names < 2 then names[#names + 1] = info.title end
            end
        end
    end
    return done, all, names
end
TILES[#TILES + 1] = {
    kind = "quest", title = "Quests", icon = "Interface\\Icons\\INV_Misc_Book_08",
    available = function() return loaded("VoidQuest") end, go = { "VoidQuest", "book" },
    value = function()
        local done, all = questCounts()
        if done == 0 then return ("%d on the go"):format(all) end
        return GREEN .. done .. "|r ready to turn in"
    end,
    detail = function()
        local done, all, names = questCounts()
        if done == 0 then return "The Quest Book lists what you can still do here." end
        return table.concat(names, ", ") .. (done > #names and (" and %d more."):format(done - #names) or ".")
    end,
}

TILES[#TILES + 1] = {
    kind = "gold", title = "Gold", icon = "Interface\\Icons\\INV_Misc_Coin_02",
    -- after a reload the session starts over: no tile until there's a real rate (the hero shows your gold)
    empty = function()
        local I = _G.VoidBags.Income
        local s = I:Session()
        local r = I.Rate and I.Rate(s.worth or 0, s.active or 0)
        return not r or r <= 0 or (s.worth or 0) <= 0   -- "0c an hour" says nothing
    end,
    available = function() local b = _G.VoidBags; return b and b.Income and b.Income.Hub ~= nil end, go = { "VoidBags", "income" },
    value = function()
        local I = _G.VoidBags.Income
        local s = I:Session()
        local r = I.Rate and I.Rate(s.worth or 0, s.active or 0)
        if not r then return GREY .. "Session just started|r" end
        return GOLD .. money(r) .. "|r an hour"
    end,
    detail = function()
        local I = _G.VoidBags.Income
        local s = I:Session()
        local mins = I.Hub.Minutes and I.Hub.Minutes(s.active or 0) or 0
        return ("%s made in %d min (worth if you sell it all)."):format(money(s.worth or 0), mins)
    end,
}

-- the profession with the most room left that isn't maxed; a capped one (needs a trainer) first
local function profPick()
    local best
    for _, idx in pairs({ GetProfessions() }) do
        local name, _, rank, max = GetProfessionInfo(idx)
        if name and rank and max and max > 0 and rank < 300 then
            local capped = rank >= max
            local score = capped and -1 or (max - rank)
            if not best or score < best.score then best = { name = name, rank = rank, max = max, capped = capped, score = score } end
        end
    end
    return best
end
TILES[#TILES + 1] = {
    kind = "prof", title = "Professions", icon = "Interface\\Icons\\Trade_Engineering",
    available = function() return _G.VoidProf ~= nil and profPick() ~= nil end,
    go = function() local p = profPick(); return { "VoidProf", p and ("p:" .. p.name) or nil } end,
    value = function()
        local p = profPick()
        return ("%s %s%d|r / %d"):format(p.name, p.capped and YELLOW or GOLD, p.rank, p.max)
    end,
    detail = function()
        local p = profPick()
        if p.capped then return YELLOW .. "At its cap: train the next rank to keep going.|r" end
        return ("%d more to the next cap. The plan shows the cheapest way."):format(p.max - p.rank)
    end,
}

-- upgrades from quests you can still do (VoidGear works it out; at most once a minute, only while this is open)
local gearCache = { t = -999 }
local function gearCount()
    if GetTime() - gearCache.t < 60 then return gearCache.n end
    local g = _G.VoidGear
    local H = g and g.ForeverUI and g.ForeverUI.Hub
    if not (H and H.View) then return nil end
    local ok, lines = pcall(H.View, "quests")
    if not ok or type(lines) ~= "table" then return nil end
    local n, first = 0, nil
    for _, l in ipairs(lines) do if l.link then n = n + 1; first = first or l.link end end
    gearCache = { t = GetTime(), n = n, first = first }
    return n
end
TILES[#TILES + 1] = {
    kind = "gear", title = "Gear", icon = "Interface\\Icons\\INV_Chest_Chain_04",
    available = function() local g = _G.VoidGear; return g and g.ForeverUI and g.ForeverUI.Hub ~= nil end, go = { "VoidGear", "quests" },
    value = function()
        local n = gearCount()
        if not n then return GREY .. "Checking...|r" end
        if n == 0 then return GREY .. "No quest upgrades near your level|r" end
        return GREEN .. n .. "|r quest upgrade" .. (n == 1 and "" or "s")
    end,
    detail = function()
        local n = gearCount()
        if n and n > 0 and gearCache.first then return "Best: " .. gearCache.first end
        return "Dungeon drops are on the Gear page too."
    end,
}

-- repairs: the lowest piece you wear (the game's own numbers)
local function durability()
    local low, lowSlot
    for s = 1, 19 do
        local cur, max = GetInventoryItemDurability(s)
        if cur and max and max > 0 then
            local p = cur / max
            if not low or p < low then low, lowSlot = p, s end
        end
    end
    return low, lowSlot
end
TILES[#TILES + 1] = {
    kind = "life", title = "Repairs", icon = "Interface\\Icons\\Trade_BlackSmithing",
    empty = function() return (durability() or 1) >= 0.5 end,   -- a warning: only when it matters
    available = function() return durability() ~= nil end, go = { "VoidBags", "settings" },
    value = function()
        local p = durability()
        local pct = math.floor(p * 100 + 0.5)
        local col = pct >= 50 and GREEN or pct >= 25 and YELLOW or RED
        return ("Gear down to %s%d%%|r"):format(col, pct)
    end,
    detail = function()
        local p = durability()
        if p >= 0.5 then return "Fine for now." end
        if p >= 0.25 then return YELLOW .. "Repair at the next vendor.|r" end
        return RED .. "Repair soon: a broken piece gives no stats.|r"
    end,
}

-- bags: free slots
local function bagSpace()
    local free, total = 0, 0
    local C = C_Container
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local n = C and C.GetContainerNumSlots(bag) or 0
        total = total + n
        if n > 0 then free = free + (C.GetContainerNumFreeSlots(bag) or 0) end
    end
    return free, total
end
TILES[#TILES + 1] = {
    kind = "life", title = "Bags", icon = "Interface\\Icons\\INV_Misc_Bag_08",
    empty = function() return (bagSpace()) >= 10 end,   -- a warning: only when it matters
    available = function() local _, t = bagSpace(); return t > 0 and _G.VoidBags ~= nil end, go = { "VoidBags", "income" },
    value = function()
        local free, total = bagSpace()
        local col = free >= 10 and GREEN or free >= 4 and YELLOW or RED
        return ("%s%d|r free of %d"):format(col, free, total)
    end,
    detail = function()
        local free = bagSpace()
        if free < 4 then return RED .. "Almost full: sell or bank before the next pull.|r" end
        return "Gold per hour counts what you loot."
    end,
}

-- hearthstone: where, and ready or not
local HEARTH = 6948
TILES[#TILES + 1] = {
    kind = "life", title = "Hearth", icon = "Interface\\Icons\\INV_Misc_Rune_01",
    available = function() return GetBindLocation and GetBindLocation() ~= nil end, go = { "VoidGPS" },
    value = function() return GOLD .. (GetBindLocation() or "?") .. "|r" end,
    detail = function()
        local cd = C_Container and C_Container.GetItemCooldown
        local start, dur = 0, 0
        if cd then start, dur = cd(HEARTH) end
        local left = (start and start > 0 and dur and dur > 0) and (start + dur - GetTime()) or 0
        if left > 1 then return ("Ready in %s."):format(span(left)) end
        if C_Item and C_Item.GetItemCount and C_Item.GetItemCount(HEARTH) == 0 then return GREY .. "No Hearthstone in your bags.|r" end
        return GREEN .. "Ready.|r"
    end,
}

-- reputation: the faction you watch
local function watched()
    local R = C_Reputation
    local d = R and R.GetWatchedFactionData and R.GetWatchedFactionData()
    if not (d and d.name and d.name ~= "") then return nil end
    return d
end
TILES[#TILES + 1] = {
    kind = "rep", title = "Reputation", icon = "Interface\\Icons\\Achievement_Reputation_01",
    available = function() return watched() ~= nil end,
    value = function()
        local d = watched()
        local label = _G["FACTION_STANDING_LABEL" .. (d.reaction or 0)] or ""
        return ("%s  %s%s|r"):format(d.name, GOLD, label)
    end,
    detail = function()
        local d = watched()
        local lo, hi, cur = d.currentReactionThreshold or 0, d.nextReactionThreshold or 0, d.currentStanding or 0
        if hi <= lo then return "Maxed." end
        return ("%s / %s to the next standing."):format(big(cur - lo), big(hi - lo))
    end,
}

-- calendar: the next event (VoidCalendar's own list, the agenda's rules)
local function nextEvent()
    local C = _G.VoidCalendar
    if not (C and C.Events and C.Events.GetEvents and C_Calendar and C_Calendar.GetMonthInfo) then return nil end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return nil end
    local now = C_DateAndTime.GetCurrentCalendarTime()
    local cur = now and C_Calendar.GetMonthInfo(0)
    if not (cur and cur.month == now.month and cur.year == now.year) then return nil end   -- never moves the calendar's month
    local hide = C.GetDB and C:GetDB().hideBlizzEvents
    for off = 0, 1 do
        local mi = C_Calendar.GetMonthInfo(off)
        if mi then
            for d = (off == 0 and now.monthDay or 1), (mi.numDays or 30) do
                for _, e in ipairs(C.Events:GetEvents(off, d) or {}) do
                    local blizz = e.calendarType == "HOLIDAY" or e.calendarType == "SYSTEM" or e.calendarType == "RAID_LOCKOUT"
                    if not (hide and blizz) then return e, off, d end
                end
            end
        end
    end
end
TILES[#TILES + 1] = {
    kind = "quest", title = "Calendar", icon = "Interface\\Icons\\INV_Misc_Note_01",
    available = function() return _G.VoidCalendar ~= nil end, go = { "VoidCalendar" },
    value = function()
        local e = nextEvent()
        if not e then return GREY .. "Nothing coming up|r" end
        return GOLD .. (e.title or "An event") .. "|r"
    end,
    detail = function()
        local e, off, d = nextEvent()
        if not e then return "Guild events and holidays show here." end
        local now = C_DateAndTime.GetCurrentCalendarTime()
        local when = (off == 0 and d == now.monthDay) and "Today" or (off == 0 and d == now.monthDay + 1) and "Tomorrow"
            or ("On the %d%s"):format(d, (d == 1 or d == 21 or d == 31) and "st" or (d == 2 or d == 22) and "nd" or (d == 3 or d == 23) and "rd" or "th")
        local st = e.startTime
        if st and st.hour then when = when .. (" at %d:%02d"):format(st.hour, st.minute or 0) end
        return when .. "."
    end,
}

----------------------------------------------------------------------
-- Your next big move: the one thing worth doing now, with its payoff in numbers (the user: "it needs to excite
-- people"). First that applies wins. Each: { kind, icon, text, sub, button, go = function }
----------------------------------------------------------------------
local function readyXP()
    local n, total = 0, 0
    for i = 1, (C_QuestLog.GetNumQuestLogEntries() or 0) do
        local info = C_QuestLog.GetInfo(i)
        local q = info and not info.isHeader and info.questID
        if q and C_QuestLog.IsComplete(q) then
            n = n + 1
            local ok, x = pcall(GetQuestLogRewardXP, q)
            if ok and type(x) == "number" then total = total + x end
        end
    end
    return n, total
end
local MOVES = {
    -- a rare on YOUR layer in this zone, seen in the last 10 minutes
    function()
        local c = _G.VoidLayerCore
        if not (c and c.Rares) then return end
        local _, zone = c:Here()
        for _, r in ipairs(zone and c:Rares(zone) or {}) do
            -- alive only: a reported corpse isn't "go get it" (hp 0 = dead, as the Layers page shows it; Codex 11-25)
            if r.same and (r.age or 999) < 600 and (r.hp == nil or r.hp > 0) then
                return { kind = "world", icon = "Interface\\Icons\\Ability_Hunter_MarkedForDeath",
                    text = ("Rare up near you: %s%s|r"):format(GOLD, r.name or "?"),
                    sub = ("On your layer, seen %s ago%s. Go get it."):format(ago(r.age or 0),
                        (r.x and r.y and r.x > 0) and (" at %d, %d"):format(r.x / 10, r.y / 10) or ""),
                    button = "Show me", go = { "VoidLayer", "layers" } }
            end
        end
    end,
    -- quests ready: the XP waiting
    function()
        if not loaded("VoidQuest") then return end
        local n, total = readyXP()
        if n == 0 then return end
        local max = UnitXPMax("player") or 0
        local pct = (max > 0 and total > 0) and math.floor(total / max * 100 + 0.5) or nil
        return { kind = "quest", icon = "Interface\\Icons\\INV_Misc_Book_08",
            text = total > 0 and ("%s+%s XP|r waiting for you"):format(GREEN, big(total)) or ("%s%d quests|r ready to hand in"):format(GREEN, n),
            sub = ("Turn in %d quest%s%s."):format(n, n == 1 and "" or "s", pct and pct > 0 and (": %d%% of a level"):format(pct) or ""),
            button = "Show the way", go = { "VoidQuest", "route" } }
    end,
    -- a profession at its cap: a trainer away from more
    function()
        if not _G.VoidProf then return end
        local p = profPick()
        if not (p and p.capped) then return end
        return { kind = "prof", icon = "Interface\\Icons\\Trade_Engineering",
            text = ("%s is ready to %strain|r"):format(p.name, YELLOW),
            sub = ("You're at %d / %d: the next rank goes to %d."):format(p.rank, p.max, p.max + 75),
            button = "Where", go = { "VoidProf", "p:" .. p.name } }
    end,
    -- an upgrade waiting
    function()
        local n = gearCount()
        if not (n and n > 0 and gearCache.first) then return end
        return { kind = "gear", icon = "Interface\\Icons\\INV_Chest_Chain_04",
            text = ("Upgrade waiting: %s"):format(gearCache.first),
            sub = n > 1 and ("And %d more quest reward%s that beat what you wear."):format(n - 1, n == 2 and "" or "s") or "A quest reward that beats what you wear.",
            button = "See it", go = { "VoidGear", "quests" } }
    end,
    -- nothing pressing: new quests around you
    function()
        if not loaded("VoidQuest") then return end
        return { kind = "quest", icon = "Interface\\Icons\\INV_Misc_Map_01",
            text = ("Fresh quests in %s"):format(GOLD .. (GetRealZoneText and GetRealZoneText() or "this zone") .. "|r"),
            sub = "See what's left to pick up here, nearest first.",
            button = "Show me", go = { "VoidQuest", "zone" } }
    end,
}
local function nextMove()
    for _, fn in ipairs(MOVES) do
        local ok, m = pcall(fn)
        if ok and m then return m end
    end
end

----------------------------------------------------------------------
-- The page
----------------------------------------------------------------------
local D   -- the dashboard frame, built once
local function tileGo(t)
    local g = type(t.go) == "function" and t.go() or t.go
    if g then ns.Open(g[1], g[2]) end
end

local function RefreshHero()
    local H = D.hero
    pcall(SetPortraitTexture, H.portrait, "player")
    local name = UnitName("player") or ""
    local _, class = UnitClass("player")
    local cc = class and (C_ClassColor and C_ClassColor.GetClassColor(class) or RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
    H.name:SetText(cc and cc.WrapTextInColorCode and cc:WrapTextInColorCode(name) or name)
    H.level:SetText(UnitLevel("player") or "")
    local zone = GetRealZoneText and GetRealZoneText() or ""
    local sub = GetSubZoneText and GetSubZoneText() or ""
    H.where:SetText(GREY .. zone .. ((sub ~= "" and sub ~= zone) and ("  ·  " .. sub) or "") .. "|r")
    H.money:SetText(money(GetMoney()))
    -- this session's wins
    local wins = {}
    if xp.gained > 0 then wins[#wins + 1] = GREEN .. "+" .. big(xp.gained) .. "|r XP" end
    if sess.levels > 0 then wins[#wins + 1] = GREEN .. "+" .. sess.levels .. "|r level" .. (sess.levels == 1 and "" or "s") end
    if sess.quests > 0 then wins[#wins + 1] = GREEN .. sess.quests .. "|r quest" .. (sess.quests == 1 and "" or "s") end
    local dm = sess.money0 and (GetMoney() - sess.money0) or 0
    if dm > 0 then wins[#wins + 1] = "+" .. money(dm) end
    H.wins:SetText(#wins > 0 and (GREY .. "This session|r  " .. table.concat(wins, GREY .. "  ·  |r")) or (GREY .. "This session: just getting started|r"))
    -- the Void network, live
    local c = _G.VoidLayerCore
    if c and c.Online then
        local online = c:Online() or 0
        local rares = c.Rares and #c:Rares() or 0
        H.pulseText:SetText(("%s%d|r Void players online%s"):format(GREEN, online,
            rares > 0 and ("  ·  %s%d|r rare%s shared right now"):format(GOLD, rares, rares == 1 and "" or "s") or ""))
        H.pulse:Show(); H.pulseText:Show()
    else
        H.pulse:Hide(); H.pulseText:Hide()
    end
    -- XP
    local maxLevel = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or 60
    local cur, max = UnitXP("player"), UnitXPMax("player")
    if (UnitLevel("player") or 0) >= maxLevel or not max or max <= 0 then
        H.xp:SetMinMaxValues(0, 1); H.xp:SetValue(1); H.rest:SetMinMaxValues(0, 1); H.rest:SetValue(0)
        H.xpText:SetText("Max level")
        H.ttl:SetText("")
        return
    end
    local rested = GetXPExhaustion() or 0
    H.xp:SetMinMaxValues(0, max); H.xp:SetValue(cur)
    H.rest:SetMinMaxValues(0, max); H.rest:SetValue(math.min(max, cur + rested))
    H.xpText:SetText(("%s / %s XP  (%d%%)%s"):format(big(cur), big(max), math.floor(cur / max * 100),
        rested > 0 and ("   " .. "|cff6fb7ff+%s rested|r"):format(big(rested)) or ""))
    local t = timeToLevel()
    H.ttl:SetText(t and ("Level %d in about %s at this pace"):format((UnitLevel("player") or 0) + 1, GOLD .. span(t) .. "|r")
        or GREY .. "Time to level shows after a few minutes of play|r")
end

local function RefreshMove()
    local M = D.move
    local m = nextMove()
    M.def = m
    if not m then M:Hide() return end
    local c = KIND[m.kind] or KIND.world
    M.icon:SetTexture(m.icon)
    M.text:SetText(m.text)
    M.sub:SetText(m.sub or "")
    M.glow:SetVertexColor(c[1], c[2], c[3])
    M.stripe:SetColorTexture(c[1], c[2], c[3], 1)
    M.btn:SetLabel(m.button or "Go")
    M:Show()
end

local function Refresh()
    if not (D and D:IsVisible()) then return end
    pcall(RefreshHero)
    pcall(RefreshMove)
    -- which tiles have something to say now (an empty one steps aside: no "None reported here" filler)
    local show = {}
    for _, t in ipairs(TILES) do
        local ok, avail = pcall(t.available)
        if ok and avail then
            local okE, empty = true, false
            if t.empty then okE, empty = pcall(t.empty) end
            if not (okE and empty) then show[#show + 1] = t end
        end
    end
    -- the grid fills the page: widths from the page's real width (lined up with the hero band), heights from
    -- what's left below the next-move band; a short last row stretches across
    local n = #show
    local top = 14 + HERO_H + 8 + (D.move:IsShown() and (MOVE_H + 10) or 0)
    local W = math.max(300, (D:GetWidth() or 900) - 32)
    local rows = math.max(1, math.ceil(n / COLS))
    local availH = (D:GetHeight() or 500) - top - 14
    local th = math.floor(math.min(78, math.max(TILE_H, (availH - GAP * (rows - 1)) / rows)))
    local i = 0
    for _, t in ipairs(show) do
        do
            i = i + 1
            local row = math.floor((i - 1) / COLS)
            local inRow = (row == rows - 1) and (n - row * COLS) or COLS
            local col = (i - 1) % COLS
            local tw = math.floor((W - GAP * (inRow - 1)) / inRow)
            local b = D.tiles[i]
            b:SetSize(tw, th)
            b.value:SetWidth(tw - 74); b.detail:SetWidth(tw - 74)
            b.def = t
            local c = KIND[t.kind] or KIND.world
            b.stripe:SetColorTexture(c[1], c[2], c[3], 1)
            b.glow:SetColorTexture(c[1], c[2], c[3], 0.10)
            -- the stripe's colour fading out to the right; a flat faint tint where gradients aren't there
            local okG = b.wash.SetGradient and CreateColor and pcall(b.wash.SetGradient, b.wash, "HORIZONTAL",
                CreateColor(c[1], c[2], c[3], 0.16), CreateColor(c[1], c[2], c[3], 0))
            if not okG then b.wash:SetColorTexture(c[1], c[2], c[3], 0.06) end
            b.icon:SetTexture(t.icon)
            b.title:SetText(t.title:upper())
            b.title:SetTextColor(c[1], c[2], c[3])
            local ok1, v = pcall(t.value); b.value:SetText(ok1 and v or GREY .. "—|r")
            local ok2, d = pcall(t.detail); b.detail:SetText(ok2 and d or "")
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 16 + col * (tw + GAP), -top - row * (th + GAP))
            b:Show()
        end
    end
    for j = i + 1, #D.tiles do D.tiles[j]:Hide() end
end

local function MakeTile(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(TILE_W, TILE_H)
    K.Box(b, { 0.045, 0.06, 0.08, 1 }, { 0.16, 0.19, 0.24, 1 })
    b.stripe = b:CreateTexture(nil, "ARTWORK"); b.stripe:SetPoint("TOPLEFT", 1, -1); b.stripe:SetPoint("BOTTOMLEFT", 1, 1); b.stripe:SetWidth(3)
    -- a soft wash of the tile's colour from the left
    b.wash = b:CreateTexture(nil, "BACKGROUND", nil, 1); b.wash:SetPoint("TOPLEFT", 4, -1); b.wash:SetPoint("BOTTOMLEFT", 4, 1); b.wash:SetWidth(120)
    b.wash:SetTexture("Interface\\Buttons\\WHITE8X8")   -- coloured per tile in Refresh (a fade from the stripe)
    b.glow = b:CreateTexture(nil, "HIGHLIGHT"); b.glow:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(42, 42); b.icon:SetPoint("LEFT", 12, 0)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.iconEdge = b:CreateTexture(nil, "BORDER"); b.iconEdge:SetPoint("TOPLEFT", b.icon, -1, 1); b.iconEdge:SetPoint("BOTTOMRIGHT", b.icon, 1, -1)
    b.iconEdge:SetColorTexture(0, 0, 0, 1)
    b.title = K.Text(b, "GameFontNormalSmall"); b.title:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 10, 1)
    b.value = K.Text(b, "GameFontHighlightLarge"); b.value:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -2)
    b.value:SetWidth(TILE_W - 74); b.value:SetWordWrap(false); b.value:SetJustifyH("LEFT")
    b.detail = K.Text(b, "GameFontDisableSmall"); b.detail:SetPoint("TOPLEFT", b.value, "BOTTOMLEFT", 0, -2)
    b.detail:SetWidth(TILE_W - 74); b.detail:SetJustifyH("LEFT"); b.detail:SetWordWrap(true); b.detail:SetMaxLines(2)
    b:SetScript("OnClick", function(s) if s.def and s.def.go then tileGo(s.def) end end)
    b:SetScript("OnEnter", function(s)
        if not s.def then return end
        local c = KIND[s.def.kind] or KIND.world
        if s.Recolor then s:Recolor(nil, { c[1], c[2], c[3], 1 }) elseif K.Recolor then K.Recolor(s, nil, { c[1], c[2], c[3], 1 }) end
    end)
    b:SetScript("OnLeave", function(s)
        if s.Recolor then s:Recolor(nil, { 0.16, 0.19, 0.24, 1 }) elseif K.Recolor then K.Recolor(s, nil, { 0.16, 0.19, 0.24, 1 }) end
    end)
    b:Hide()
    return b
end

local function Build(parent)
    D = CreateFrame("Frame", nil, parent)
    D:SetAllPoints()
    -- hero band
    local H = CreateFrame("Frame", nil, D)
    D.hero = H
    H:SetPoint("TOPLEFT", 16, -14); H:SetPoint("TOPRIGHT", -16, -14); H:SetHeight(HERO_H)
    K.Box(H, { 0.03, 0.09, 0.13, 1 }, { 0.0, 0.55, 0.75, 0.9 })
    -- a glow from the portrait side that fades out (no hard edge)
    H.band = H:CreateTexture(nil, "BACKGROUND", nil, 1); H.band:SetPoint("TOPLEFT", 1, -1); H.band:SetPoint("BOTTOMLEFT", 1, 1); H.band:SetWidth(520)
    H.band:SetTexture("Interface\\Buttons\\WHITE8X8")
    if not (H.band.SetGradient and CreateColor and pcall(H.band.SetGradient, H.band, "HORIZONTAL",
            CreateColor(0, 0.78, 1, 0.16), CreateColor(0, 0.78, 1, 0))) then
        H.band:SetColorTexture(0, 0.78, 1, 0.05)
    end
    H.portrait = H:CreateTexture(nil, "ARTWORK"); H.portrait:SetSize(70, 70); H.portrait:SetPoint("LEFT", 12, 0)
    pcall(H.portrait.SetMask, H.portrait, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
    H.ring = H:CreateTexture(nil, "OVERLAY"); H.ring:SetSize(84, 84); H.ring:SetPoint("CENTER", H.portrait)
    H.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); H.ring:SetTexCoord(0, 0.6, 0, 0.6)
    -- the level as a badge on the ring's bottom edge
    H.lvlBadge = CreateFrame("Frame", nil, H)
    H.lvlBadge:SetSize(30, 20); H.lvlBadge:SetPoint("CENTER", H.portrait, "BOTTOM", 0, 2)
    H.lvlBadge:SetFrameLevel((H:GetFrameLevel() or 1) + 5)
    K.Box(H.lvlBadge, { 0.02, 0.03, 0.05, 1 }, { 1, 0.82, 0, 1 })
    H.level = K.Text(H.lvlBadge, "GameFontNormal"); H.level:SetPoint("CENTER", 0, 0)
    H.name = K.Text(H, "GameFontNormalHuge"); H.name:SetPoint("TOPLEFT", H.portrait, "TOPRIGHT", 16, -4)
    H.where = K.Text(H, "GameFontHighlight"); H.where:SetPoint("LEFT", H.name, "RIGHT", 12, -2)
    H.money = K.Text(H, "GameFontHighlightLarge"); H.money:SetPoint("TOPRIGHT", -16, -12)
    H.wins = K.Text(H, "GameFontHighlightSmall"); H.wins:SetPoint("TOPRIGHT", H.money, "BOTTOMRIGHT", 0, -8)
    H.wins:SetJustifyH("RIGHT")
    -- the network, live: a green dot that breathes (an animation: drawn by the game, no Lua per frame)
    H.pulseText = K.Text(H, "GameFontHighlightSmall"); H.pulseText:SetPoint("BOTTOMRIGHT", -16, 10)
    H.pulse = H:CreateTexture(nil, "OVERLAY"); H.pulse:SetSize(10, 10); H.pulse:SetPoint("RIGHT", H.pulseText, "LEFT", -7, 0)
    H.pulse:SetTexture("Interface\\FriendsFrame\\StatusIcon-Online")   -- the game's own round green "online" dot
    local ag = H.pulse:CreateAnimationGroup(); ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha"); a:SetFromAlpha(1); a:SetToAlpha(0.25); a:SetDuration(0.9); a:SetSmoothing("IN_OUT")
    H:SetScript("OnShow", function() ag:Play() end)
    H:SetScript("OnHide", function() ag:Stop() end)
    -- XP bar: rested underneath, XP on top
    H.rest = CreateFrame("StatusBar", nil, H)
    H.rest:SetPoint("TOPLEFT", H.portrait, "TOPRIGHT", 16, -38); H.rest:SetSize(430, 14)
    H.rest:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8"); H.rest:SetStatusBarColor(0.25, 0.45, 0.85, 0.55)
    H.rest.bg = H.rest:CreateTexture(nil, "BACKGROUND"); H.rest.bg:SetAllPoints(); H.rest.bg:SetColorTexture(0, 0, 0, 0.6)
    H.xp = CreateFrame("StatusBar", nil, H.rest)
    H.xp:SetAllPoints()
    H.xp:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8"); H.xp:SetStatusBarColor(0.58, 0.25, 0.95, 1)
    H.xpText = K.Text(H.xp, "GameFontHighlightSmall"); H.xpText:SetPoint("CENTER")
    H.ttl = K.Text(H, "GameFontHighlightSmall"); H.ttl:SetPoint("TOPLEFT", H.rest, "BOTTOMLEFT", 0, -5)
    -- your next big move: one band, a breathing glow, one button
    local M = CreateFrame("Button", nil, D)
    D.move = M
    M:SetPoint("TOPLEFT", H, "BOTTOMLEFT", 0, -8); M:SetPoint("TOPRIGHT", H, "BOTTOMRIGHT", 0, -8); M:SetHeight(MOVE_H)
    K.Box(M, { 0.05, 0.07, 0.05, 1 }, { 0.25, 0.30, 0.25, 1 })
    M.glow = M:CreateTexture(nil, "BACKGROUND", nil, 2); M.glow:SetPoint("TOPLEFT", 1, -1); M.glow:SetPoint("BOTTOMRIGHT", -1, 1)
    M.glow:SetTexture("Interface\\Buttons\\WHITE8X8"); M.glow:SetAlpha(0.10)
    local mg = M.glow:CreateAnimationGroup(); mg:SetLooping("BOUNCE")
    local ma = mg:CreateAnimation("Alpha"); ma:SetFromAlpha(0.06); ma:SetToAlpha(0.22); ma:SetDuration(1.2); ma:SetSmoothing("IN_OUT")
    M:SetScript("OnShow", function() mg:Play() end)
    M:SetScript("OnHide", function() mg:Stop() end)
    M.stripe = M:CreateTexture(nil, "ARTWORK"); M.stripe:SetPoint("TOPLEFT", 1, -1); M.stripe:SetPoint("BOTTOMLEFT", 1, 1); M.stripe:SetWidth(4)
    M.icon = M:CreateTexture(nil, "ARTWORK"); M.icon:SetSize(36, 36); M.icon:SetPoint("LEFT", 14, 0); M.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    M.label = K.Text(M, "GameFontNormalSmall", "YOUR NEXT MOVE"); M.label:SetPoint("TOPLEFT", M.icon, "TOPRIGHT", 12, 2)
    M.text = K.Text(M, "GameFontHighlightLarge"); M.text:SetPoint("LEFT", M.label, "RIGHT", 10, -1)
    M.sub = K.Text(M, "GameFontHighlightSmall"); M.sub:SetPoint("BOTTOMLEFT", M.icon, "BOTTOMRIGHT", 12, 0)
    M.btn = K.Button(M, "Go", 120, function() if M.def and M.def.go then tileGo(M.def) end end)
    M.btn:SetPoint("RIGHT", -12, 0)
    M:SetScript("OnClick", function() if M.def and M.def.go then tileGo(M.def) end end)
    -- tiles
    D.tiles = {}
    for i = 1, #TILES do D.tiles[i] = MakeTile(D) end
    D:SetScript("OnShow", Refresh)
    D.t = 0
    D:SetScript("OnUpdate", function(s, dt)   -- only runs while it's on screen
        s.t = s.t + dt
        if s.t >= 5 then s.t = 0; Refresh() end
    end)
    D:Hide()
end

-- the shell calls this for the Start group; returns the page frame (kept, never rebuilt)
function ns.StartDash(parent)
    if not D then Build(parent) end
    if D:GetParent() ~= parent then D:SetParent(parent); D:SetAllPoints() end
    D:Show()
    Refresh()
    return D
end
