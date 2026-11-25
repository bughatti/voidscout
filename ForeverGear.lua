-- VoidScout ForeverGear (WoW Forever only, TOC [AllowLoadGameType camelot]): item levels.
-- The user, 2026-11-18: retail VoidScout lets a leader see "their scores and how well they are
-- geared"; Forever's Group Finder carries no item level, so we measure it:
--   * yours: GetAverageItemLevel (equipped)
--   * others: one Blizzard inspect at a time (NotifyInspect -> INSPECT_READY ->
--     C_PaperDollInfo.GetInspectItemLevel), out of combat, never while Blizzard's inspect window
--     is open, for party members, your target and players you mouse over; each player at most
--     once per 10 minutes.
-- The numbers live in this session's cache; FightRecorder copies them into each saved fight
-- (raw.ilvl), so a known item level builds up from the runs you do.
-- API: VoidScout.ForeverGear.Get(key) -> ilvl, at   (key = "First-Surname")
--      VoidScout.ForeverGear.KeyOf(unit), .OnUpdate(fn(key)), .Want(unit)
if (select(4, GetBuildInfo()) or 0) >= 100000 then return end

local G = {}
VoidScout = VoidScout or {}
VoidScout.ForeverGear = G

local AGAIN = 600          -- inspect the same player again after 10 min at most
local TIMEOUT = 4          -- an inspect that never answers (out of range) is dropped
local RETRY = 60           -- an inspect that got nothing (too far away) is tried again after a minute
local tried = {}           -- key -> when we last asked

local cache = {}           -- key -> { ilvl, at }
local listeners = {}
local queue, queued, pending = {}, {}, nil
local ours = false        -- set only around our own NotifyInspect call
local othersUntil = 0     -- another addon / Blizzard started an inspect: stay out until then

-- someone else's inspect: don't start ours over it, and don't clear it when it answers
hooksecurefunc("NotifyInspect", function()
    if not ours then othersUntil = GetTime() + TIMEOUT end
end)

local function secret(v) return issecretvalue and issecretvalue(v) end

-- "Vede Tinkerline" -> "Vede-Tinkerline", the key VoidScout's scores use in Forever
function G.KeyOf(unit)
    if not (UnitExists(unit) and UnitIsPlayer(unit)) then return nil end
    local n = GetUnitName(unit, false)
    if type(n) ~= "string" or secret(n) or n == "" then return nil end
    return (n:gsub("%s+", "-"))
end

function G.Get(key)
    local c = key and cache[key]
    if c then return c.ilvl, c.at end
end

function G.OnUpdate(fn) listeners[#listeners + 1] = fn end

local function store(key, ilvl)
    if not key or type(ilvl) ~= "number" or secret(ilvl) or ilvl <= 0 then return end
    cache[key] = { ilvl = math.floor(ilvl + 0.5), at = time() }
    for _, fn in ipairs(listeners) do pcall(fn, key) end
end

local function mine()
    local _, equipped = GetAverageItemLevel()
    store(G.KeyOf("player"), equipped)
end

function G.Want(unit)
    if not UnitExists(unit) or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return end
    local key = G.KeyOf(unit)
    if not key then return end
    local c = cache[key]
    if c and time() - c.at < AGAIN then return end
    if tried[key] and time() - tried[key] < RETRY then return end
    local guid = UnitGUID(unit)
    if not guid or secret(guid) or queued[guid] or (pending and pending.guid == guid) then return end
    queued[guid] = true
    queue[#queue + 1] = { unit = unit, guid = guid, key = key }
end

local function pump()
    if pending and GetTime() - pending.t > TIMEOUT then pending = nil end
    if pending or #queue == 0 or InCombatLockdown() or GetTime() < othersUntil then return end
    if InspectFrame and InspectFrame:IsShown() then return end   -- the player is inspecting someone
    local q = table.remove(queue, 1)
    queued[q.guid] = nil
    local c = cache[q.key]
    if c and time() - c.at < AGAIN then return end            -- measured since it was queued
    -- a unit token like "mouseover" may point at someone else by now
    local now = UnitExists(q.unit) and UnitGUID(q.unit)
    if not now or secret(now) or now ~= q.guid or not CanInspect(q.unit) then return end
    pending = { unit = q.unit, guid = q.guid, key = q.key, t = GetTime() }
    tried[q.key] = time()
    ours = true
    NotifyInspect(q.unit)
    ours = false
end
C_Timer.NewTicker(1.5, pump)

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "GROUP_ROSTER_UPDATE",
    "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "INSPECT_READY" }) do
    ev:RegisterEvent(e)
end
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "INSPECT_READY" then
        if not pending or secret(arg1) or arg1 ~= pending.guid then return end
        local p = pending
        pending = nil
        -- the token may point at someone else by now: read through a unit that is still them
        local unit
        for _, u in ipairs({ p.unit, "target", "mouseover", "party1", "party2", "party3", "party4" }) do
            local g = UnitExists(u) and UnitGUID(u)
            if g and not secret(g) and g == p.guid then unit = u; break end
        end
        if unit then
            local ok, ilvl = pcall(C_PaperDollInfo.GetInspectItemLevel, unit)
            if ok then store(p.key, ilvl) end
        end
        if not (InspectFrame and InspectFrame:IsShown()) and GetTime() >= othersUntil then ClearInspectPlayer() end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_EQUIPMENT_CHANGED" then
        mine()
    elseif event == "GROUP_ROSTER_UPDATE" then
        for i = 1, 4 do G.Want("party" .. i) end
    elseif event == "PLAYER_TARGET_CHANGED" then
        G.Want("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        G.Want("mouseover")
    end
end)
