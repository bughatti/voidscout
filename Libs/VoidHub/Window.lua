----------------------------------------------------------------------
-- VoidHub window: every Void addon in one window (built as the private VoidHubLab prototype 2026-11-24; moved
-- into the shared VoidHub 2026-11-25, the user: "voidhub is fine, just work it into how voidhub already is now").
-- Every Void addon carries it as Libs\VoidHub (Kit.lua: the first / newest copy runs). Opened by right-clicking
-- the VoidHub minimap button, /vhub, or the drawer (Other > VoidHub window).
--
-- What the user decided (memory project-voidhub-window):
--   * the window looks the same with 1 Void addon or 20 (within one game)
--   * every Void addon is listed; one you have shows its data, one you don't shows one screenshot
--     and how to get it
--   * tabs on top and on bottom (the left side belongs to the open addon: trees inside addons)
--   * grouped tabs ("fine with grouping, but I want to see a real mockup in game")
--   * built around retail and Forever: the hub sees which game and which addons you have, hides the
--     other game's addons, and turns addons on / off
-- Which tab row is which: the "Swap rows" button flips it (kept per character).
----------------------------------------------------------------------
local ns = _G.VoidHubWin
if not ns or ns.skip then return end   -- another Void addon's copy of VoidHub runs the window
local K = ns.Kit
local FOREVER = (select(4, GetBuildInfo()) or 0) < 100000
local GAME = FOREVER and "WoW Forever" or "Retail"

local A = K.A
local W, H = 1000, 640
local GROUP_ROW_H, ADDON_ROW_H, SECTION_ROW_H = 26, 30, 24
local Backdrop, Button, Tab = K.Box, K.Button, K.Tab

----------------------------------------------------------------------
-- Pages: each addon's real pages, drawn by the hub with the kit (Pages\*.lua).
--   ns.RegisterPage("VoidQuest", { available = fn, sections = { { key, label, build(host) -> panel } } })
-- A section's panel is built once, the first time it's opened, and kept (its scroll and search stay).
----------------------------------------------------------------------
ns.Pages = {}
function ns.RegisterPage(addon, def) ns.Pages[addon] = def end

----------------------------------------------------------------------
-- The public Void addons (CurseForge's list: tools/cmd/upload-curseforge). games: f = Forever, r = retail.
-- Group = the VoidHub drawer's groups. Private addons are never listed.
----------------------------------------------------------------------
local GROUPS = { "Questing and travel", "Gear and gold", "Professions", "Combat", "Dungeons and raids", "PvP and groups", "Other" }
local ADDONS = {
    { name = "VoidQuest",      label = "Quests",        group = 1, games = "fr", cf = 1786400, icon = "Interface\\Icons\\INV_Misc_Book_08",
      desc = "Quest helper: what you can do now, a quest book of every quest, where each one starts and what it needs first." },
    { name = "VoidGPS",        label = "GPS",           group = 1, games = "fr", cf = 1789975, icon = "Interface\\Icons\\INV_Misc_Map_01",
      desc = "Type a place, an NPC or a service: a route along roads, flight paths, boats and zeppelins." },
    { name = "VoidMap",        label = "World map",     group = 1, games = "fr", cf = 1789971, icon = "Interface\\Icons\\INV_Misc_Map02",
      desc = "The world map in a Void window, your quests beside it." },
    { name = "VoidLayer",      label = "Layers",        group = 1, games = "f",  cf = 1794524, icon = "Interface\\Icons\\Spell_Arcane_PortalDalaran",
      desc = "See your layer, hop to another with one click, rares up on other layers." },
    { name = "VoidSweep",      label = "Map radar",     group = 1, games = "fr", cf = 1731000, icon = "Interface\\Icons\\INV_Misc_Spyglass_03",
      desc = "Rares, chests and campfires around you, seen by you and every Void player." },
    { name = "VoidGear",       label = "Gear",          group = 2, games = "fr", cf = 1774945, icon = "Interface\\Icons\\INV_Chest_Plate16",
      desc = "Your upgrades and where to get them." },
    { name = "VoidBags",       label = "Bags",          group = 2, games = "fr", cf = 1545029, icon = "Interface\\Icons\\INV_Misc_Bag_08",
      desc = "Bags that sort themselves, gold per hour, sell junk and repair in one click." },
    { name = "VoidAH",         label = "Auction House", group = 2, games = "fr", cf = 1545033, icon = "Interface\\Icons\\INV_Misc_Coin_01",
      desc = "A full Auction House: sell fast or for the best price, and warnings for bait listings." },
    { name = "VoidProf",       label = "Professions",   group = 3, games = "fr", cf = 1782704, icon = "Interface\\Icons\\Trade_BlackSmithing",
      desc = "The cheapest way to level a profession, from what your characters already have." },
    { name = "VoidGather",     label = "Gathering",     group = 3, games = "fr", cf = 1730949, icon = "Interface\\Icons\\Trade_Herbalism",
      desc = "Every ore, herb and skinning spot on your map, shared between players." },
    { name = "VoidBars",       label = "Action bars",   group = 4, games = "fr", cf = 1773764, icon = "Interface\\Icons\\INV_Misc_Gear_01",
      desc = "Action bars with smart Consumables, Travel and Professions bars." },
    { name = "VoidSequencer",  label = "Sequencer",     group = 4, games = "fr", cf = 1773743, icon = "Interface\\Icons\\Ability_Rogue_Sprint",
      desc = "One-button rotations for every spec." },
    { name = "VoidPlates",     label = "Nameplates",    group = 4, games = "fr", cf = 1766749, icon = "Interface\\Icons\\Ability_Hunter_MarkedForDeath",
      desc = "Clean nameplates: who is casting, what to kick." },
    { name = "VoidFrames",     label = "Party frames",  group = 4, games = "fr", cf = 1770185, icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing",
      desc = "Party and raid frames with click casting built in." },
    { name = "VoidDungeon",    label = "Dungeons",      group = 5, games = "f",  cf = 1794000, icon = "Interface\\Icons\\INV_Misc_Key_10",
      desc = "Every dungeon: maps, quests, boss loot and where the entrance is." },
    { name = "VoidCheatSheet", label = "Cheat sheets",  group = 5, games = "r",  cf = 1512422, icon = "Interface\\Icons\\INV_Scroll_03",
      desc = "Cheat sheets for every raid and Mythic+ dungeon, popping up on pull." },
    { name = "VoidRaidTools",  label = "Raid tools",    group = 5, games = "r",  cf = 1570320, icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
      desc = "Kick rotations, tank swaps and boss helpers." },
    { name = "VoidRaidToolsReader", label = "VRT reader", group = 5, games = "r", cf = 1570328, icon = "Interface\\Icons\\INV_Scroll_05",
      desc = "Records boss events so Raid tools' alerts know what really happens." },
    { name = "VoidPug",        label = "Pug tracker",   group = 5, games = "r",  cf = 1544051, icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
      desc = "Pug raid lockouts, and never lose a good pug leader." },
    { name = "VoidBounty",     label = "Bounties",      group = 6, games = "f",  cf = 1798589, icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
      desc = "World PvP: enemy players nearby, who killed you, and bounty writs." },
    { name = "VoidScout",      label = "Scout",         group = 6, games = "fr", cf = 1586298, icon = "Interface\\Icons\\INV_Misc_Spyglass_02",
      desc = "Player and group scores for the group finder." },
    { name = "VoidChat",       label = "Chat",          group = 7, games = "fr", cf = 1814123, icon = "Interface\\Icons\\INV_Letter_15",
      desc = "Chat, cleaned up." },
    { name = "VoidCalendar",   label = "Calendar",      group = 7, games = "fr", cf = 1553454, icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
      desc = "A calendar that shows every event in your own time zone." },
}

local function forThisGame(a) return a.games:find(FOREVER and "f" or "r", 1, true) ~= nil end

----------------------------------------------------------------------
-- What you have: on / off / turned on (reload) / turned off (reload) / load error / not installed
----------------------------------------------------------------------
local function me() return UnitGUID("player") end
local function call(fn, ...) if not fn then return nil end local ok, a, b = pcall(fn, ...) if ok then return a, b end end

local function State(a)
    if not (C_AddOns and call(C_AddOns.DoesAddOnExist, a.name)) then return "missing" end
    local loaded = call(C_AddOns.IsAddOnLoaded, a.name)
    local en = call(C_AddOns.GetAddOnEnableState, a.name, me()) or 0
    local enabled = en > ((Enum and Enum.AddOnEnableState and Enum.AddOnEnableState.None) or 0)
    if loaded then return enabled and "on" or "turning-off" end
    if call(C_AddOns.DoesAddOnHaveLoadError, a.name) then return "error" end
    return enabled and "turning-on" or "off"
end

local STATE_TEXT = {
    on = "|cff33ff33Running|r", off = "|cff8c8c9eTurned off|r", missing = "|cff8c8c9eNot installed|r",
    ["turning-on"] = "|cffffd200Turned on: reload to start it|r", ["turning-off"] = "|cffffd200Turned off: reload to stop it|r",
    error = "|cffff5555Failed to load|r",
}

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------
local win, view = nil, { group = 0, addon = nil }   -- group 0 = Start
-- per character, in the hub's own saved table (every Void addon's TOC lists VoidHubCharDB)
local function DB() VoidHubCharDB = VoidHubCharDB or {}; VoidHubCharDB.win = VoidHubCharDB.win or {}; return VoidHubCharDB.win end

local Render   -- forward

local function Build()
    local f = CreateFrame("Frame", "VoidHubWindowFrame", UIParent, "BackdropTemplate")
    f:SetSize(W, H)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    Backdrop(f, { 0.04, 0.04, 0.07, 0.97 }, { A[1], A[2], A[3], 0.7 })
    local p = DB().pos
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("CENTER") end
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local pt, _, rel, x, y = s:GetPoint()
        DB().pos = { pt, rel, x, y }
    end)
    tinsert(UISpecialFrames, "VoidHubWindowFrame")   -- Esc closes it

    -- title bar
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 12, -10)
    f.title:SetText("|cff00c7ffVoid|rHub  |cff8c8c9e" .. GAME .. "|r")
    -- close: a drawn cross centred in its box (the user: the "x" letter "not proportional to the box its in")
    local close = Button(f, "", 22, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)
    close.lines = {}
    for i, deg in ipairs({ 45, -45 }) do
        local l = close:CreateTexture(nil, "OVERLAY")
        l:SetTexture("Interface\\Buttons\\WHITE8X8")
        l:SetSize(13, 2)   -- whole pixels: sharp lines
        l:SetPoint("CENTER")
        l:SetRotation(math.rad(deg))
        l:SetVertexColor(0.85, 0.85, 0.9)
        close.lines[i] = l
    end
    close:HookScript("OnEnter", function(s) for _, l in ipairs(s.lines) do l:SetVertexColor(1, 1, 1) end end)
    close:HookScript("OnLeave", function(s) for _, l in ipairs(s.lines) do l:SetVertexColor(0.85, 0.85, 0.9) end end)
    f.swap = Button(f, "Swap tab rows", 110, function()
        DB().swap = not DB().swap
        Render()
    end)
    f.swap:SetPoint("TOPRIGHT", -36, -8)   -- left of the x
    f.swap:SetScript("OnEnter", function(s)
        K.Recolor(s, nil, { A[1], A[2], A[3], 1 })
        GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Try it the other way round")
        GameTooltip:AddLine("Groups on top and addons at the bottom, or the reverse.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    f.swap:SetScript("OnLeave", function(s) K.Recolor(s, nil, { A[1], A[2], A[3], 0.55 }); GameTooltip:Hide() end)

    f.groupTabs, f.addonTabs = {}, {}
    f.content = CreateFrame("Frame", nil, f, "BackdropTemplate")
    Backdrop(f.content, { 0.06, 0.06, 0.09, 1 }, { 0.20, 0.22, 0.26, 1 })
    f.pieces = {}   -- content pieces, rebuilt per render
    f:Hide()
    f:SetScript("OnShow", function() Render() end)
    -- an addon turned on / off elsewhere (the game's AddOns list) shows when you come back
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(s) if s:IsShown() then Render() end end)
    return f
end

-- content helpers: everything in the content area is redrawn on each render. WoW never frees a frame or a font
-- string, so they're POOLED (Codex 2026-11-25: making new ones on every render grew without end): each kind of
-- piece is made once and handed out again, in order, on the next render; the caller sets everything it needs.
local function piece(obj) win.pieces[#win.pieces + 1] = obj; return obj end
local pools, used = {}, {}
local function reuse(kind, make)
    local p = pools[kind]
    if not p then p = {}; pools[kind] = p end
    local i = (used[kind] or 0) + 1
    used[kind] = i
    local o = p[i]
    if not o then o = make(); p[i] = o end
    o:ClearAllPoints()
    o:Show()
    return piece(o)
end
local function clear()
    for _, o in ipairs(win.pieces) do o:Hide() end
    wipe(win.pieces)
    wipe(used)
end
local function text(parent, str, font, x, y, w, anchor)
    font = font or "GameFontHighlight"
    local s = reuse("fs:" .. tostring(parent) .. ":" .. font, function() return parent:CreateFontString(nil, "OVERLAY", font) end)
    s:SetPoint(anchor or "TOPLEFT", x, y)
    s:SetWidth(w or 0)
    s:SetJustifyH(anchor and anchor:find("RIGHT") and "RIGHT" or "LEFT")
    s:SetText(str)
    return s
end

local function groupsHere()
    local out = {}
    for gi, name in ipairs(GROUPS) do
        local list = {}
        for _, a in ipairs(ADDONS) do if a.group == gi and forThisGame(a) then list[#list + 1] = a end end
        if #list > 0 then out[#out + 1] = { index = gi, name = name, addons = list } end
    end
    return out
end

local copyBox
local function ShowLink(a)
    if not copyBox then
        copyBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
        copyBox:SetAutoFocus(false)
        copyBox:SetSize(340, 22)
        copyBox:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
        copyBox:SetScript("OnTextChanged", function(s, user) if user then s:SetText(s.url or "") ; s:HighlightText() end end)
    end
    copyBox.url = "https://www.curseforge.com/projects/" .. a.cf
    copyBox:SetText(copyBox.url)
    return copyBox
end

-- addons with a screenshot in Shots/ (2026-11-25, captured on the laptop's Forever + the CurseForge page shots)
local SHOTS = {}
for _, n in ipairs({ "VoidAH", "VoidBags", "VoidBars", "VoidBounty", "VoidCalendar", "VoidChat", "VoidCheatSheet",
    "VoidDungeon", "VoidFrames", "VoidGather", "VoidGear", "VoidGPS", "VoidLayer", "VoidMap", "VoidPlates", "VoidProf",
    "VoidQuest", "VoidRaidTools", "VoidScout", "VoidSequencer", "VoidSweep" }) do SHOTS[n] = true end

-- an addon you don't have: one screenshot, what it does, how to get it
local function MissingPage(c, a)
    -- laid out from the bottom up so it fits whatever height the page has: button, then what it does,
    -- and the screenshot fills the rest
    local get = reuse("btn:get", function() return Button(c, "How to get it", 120, nil) end)
    get:SetPoint("BOTTOMLEFT", 20, 14)
    local desc = reuse("fs:desc", function() return c:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end)
    desc:SetPoint("BOTTOMLEFT", get, "TOPLEFT", 0, 10)
    desc:SetWidth(W - 80); desc:SetJustifyH("LEFT"); desc:SetText(a.desc)
    local shot = reuse("shot", function()
        local f = CreateFrame("Frame", nil, c, "BackdropTemplate")
        Backdrop(f, { 0.03, 0.03, 0.05, 1 }, { 0.35, 0.37, 0.42, 1 })
        return f
    end)
    shot:SetPoint("TOPLEFT", 20, -16)
    shot:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -20, 14 + 26 + 10 + desc:GetStringHeight() + 12)
    shot:SetScript("OnSizeChanged", nil)
    if SHOTS[a.name] then
        -- the addon at work (Shots/<name>.blp, 512x256 = 2:1, made by tools/cmd/png2blp; half size since every addon carries them): as big as the box allows
        -- while keeping its shape, centred
        local img = reuse("shotimg", function() return shot:CreateTexture(nil, "ARTWORK") end)
        img:SetTexture(ns.path .. "Shots\\" .. a.name)   -- inside whichever Void addon runs the window
        local function size()
            local bw, bh = shot:GetWidth() - 8, shot:GetHeight() - 8
            if bw <= 0 or bh <= 0 then return end
            local w = math.min(bw, bh * 2)
            img:SetSize(w, w / 2)
        end
        img:SetPoint("CENTER")
        size()
        shot:SetScript("OnSizeChanged", size)
    else
        local ic = reuse("shoticon", function() return shot:CreateTexture(nil, "ARTWORK") end)
        ic:SetSize(64, 64); ic:SetPoint("CENTER", 0, 20)
        ic:SetTexture(a.icon); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92); ic:SetAlpha(0.35)
        text(shot, "|cff8c8c9eone screenshot of " .. a.name .. " goes here|r", "GameFontNormal", 0, -40, nil, "CENTER")
    end
    get:SetScript("OnClick", function()
        local box = ShowLink(a)
        box:ClearAllPoints(); box:SetPoint("LEFT", get, "RIGHT", 14, 0); box:Show()
        box:SetFocus(); box:HighlightText()
        piece(box)
        local hint = reuse("fs:gethint", function() return c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") end)
        hint:SetPoint("LEFT", box, "RIGHT", 10, 0)
        hint:SetText("|cff8c8c9eCtrl+C, then search CurseForge for " .. a.name .. "|r")
    end)
end

local function Reload()
    if InCombatLockdown() then print("|cff00c7ffVoidHub|r: after combat."); return end
    ReloadUI()
end

-- an addon you have: its pages (the ones moved into the hub so far) as a row of section tabs at the
-- top of the page, then "About" (version, state, its quick switches, turn it on / off)
local AboutBody
local function HavePage(c, a, st)
    local def = st == "on" and ns.Pages[a.name] or nil
    if def and def.available and not def.available() then def = nil end
    local secs = {}
    if def then
        -- sections can come from a function (VoidProf: one per profession this character has)
        local list = type(def.sections) == "function" and def.sections() or def.sections
        for _, s in ipairs(list) do
            -- a section can need more than the page (an older version of the addon without its hook)
            if not s.available or s.available() then secs[#secs + 1] = s end
        end
    end
    secs[#secs + 1] = { key = "about", label = "About" }
    local db = DB()
    db.sec = db.sec or {}
    local cur = db.sec[a.name]
    local found
    for _, s in ipairs(secs) do if s.key == cur then found = s end end
    found = found or secs[1]
    local x = 8
    for _, s in ipairs(secs) do
        local t = reuse("sectab", function() return Tab(c, SECTION_ROW_H) end)
        t:SetPoint("TOPLEFT", x, -8)
        t:Set(s.label, nil, s == found)
        t:SetScript("OnClick", function() db.sec[a.name] = s.key; Render() end)
        x = x + t:GetWidth() + 4
    end
    if found.key == "about" then AboutBody(c, a, st, def) return end
    -- a real page: its panel is built once and kept
    win.hosts = win.hosts or {}
    local hk = a.name .. ":" .. found.key
    local host = win.hosts[hk]
    if not host then
        host = CreateFrame("Frame", nil, c)
        host:Hide()   -- built hidden, then shown: the page's OnShow runs (draws it) on the very first open
        host:SetPoint("TOPLEFT", 0, -(8 + SECTION_ROW_H + 2))
        host:SetPoint("BOTTOMRIGHT")
        win.hosts[hk] = host
        local ok, err = pcall(found.build, host)
        if not ok then
            host.err = K.Text(host, "GameFontHighlight", "|cffff5555This page failed to build:|r " .. tostring(err))
            host.err:SetPoint("TOPLEFT", 20, -20); host.err:SetWidth(W - 80)
        end
    end
    piece(host)
    host:Show()
end

AboutBody = function(c, a, st, def)
    local ver = call(C_AddOns.GetAddOnMetadata, a.name, "Version") or "?"
    text(c, ("%s   |cff8c8c9eversion %s|r   %s"):format(a.label, ver, STATE_TEXT[st] or st), "GameFontNormalLarge", 20, -48)
    text(c, "|cff8c8c9e" .. a.desc .. "|r", "GameFontHighlight", 20, -74, W - 80)
    if not def then
        text(c, "|cff8c8c9eIt has no pages in this window: its own window and settings open from its button.|r",
            "GameFontHighlightSmall", 20, -96, W - 80)
    end
    -- its quick switches from the VoidHub drawer: real, they work
    local y, any = -124, false
    for _, e in ipairs(_G.VoidHubToggles or {}) do
        if type(e) == "table" and type(e.id) == "string" and e.id:match("^([%w]+)%.") == a.name and e.get and e.set then
            if not any then text(c, "Quick switches:", "GameFontNormal", 20, y); y = y - 22; any = true end
            -- pooled: the check is made once with a click that runs whatever switch it shows now (cb.entry)
            local cb = reuse("check", function()
                return K.Check(c, "", function(s, on)
                    local en = s.entry
                    if not en then return end
                    if en.noCombat and InCombatLockdown() then s:SetChecked(not on) return end
                    pcall(en.set, on)
                end)
            end)
            cb.entry = e
            cb.label:SetText(e.label)
            cb:SetHitRectInsets(0, -(cb.label:GetStringWidth() + 8), 0, 0)
            cb:SetPoint("TOPLEFT", 22, y)
            local ok, v = pcall(e.get); cb:SetChecked(ok and v and true or false)
            y = y - 22
        end
    end
    -- on / off for this character (the manager part): pinned to the page's bottom edge, whatever its height
    local function bottomNote(b, msg)
        local fs = reuse("fs:bottomnote", function() return c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") end)
        fs:SetPoint("LEFT", b, "RIGHT", 10, 0)
        fs:SetText(msg)
    end
    -- pooled buttons: made once per label, the click set for this addon each time
    local function button(label, w, fn)
        local b = reuse("btn:" .. label, function() return Button(c, label, w, nil) end)
        b:SetScript("OnClick", fn)
        return b
    end
    if st == "on" then
        local b = button("Turn off", 100, function()
            if InCombatLockdown() then print("|cff00c7ffVoidHub|r: after combat."); return end
            call(C_AddOns.DisableAddOn, a.name, me()); Render()
        end)
        b:SetPoint("BOTTOMLEFT", 20, 14)
        bottomNote(b, "|cff8c8c9efor this character, from the next reload|r")
    elseif st == "off" or st == "error" then
        local b = button("Turn on", 100, function()
            if InCombatLockdown() then print("|cff00c7ffVoidHub|r: after combat."); return end
            call(C_AddOns.EnableAddOn, a.name, me()); Render()
        end)
        b:SetPoint("BOTTOMLEFT", 20, 14)
        bottomNote(b, "|cff8c8c9eturned off for this character: turn it on, then reload|r")
    elseif st == "turning-on" or st == "turning-off" then
        local b = button("Reload now", 100, Reload)
        b:SetPoint("BOTTOMLEFT", 20, 14)
        local u = button("Undo", 70, function()
            if st == "turning-on" then call(C_AddOns.DisableAddOn, a.name, me()) else call(C_AddOns.EnableAddOn, a.name, me()) end
            Render()
        end)
        u:SetPoint("LEFT", b, "RIGHT", 8, 0)
    end
end

-- the Start page: the "right now" dashboard (Pages\Start.lua), built once and kept; the old tile list below
-- only if that file is missing
local function StartPage(c)
    if ns.StartDash then piece(ns.StartDash(c)) return end
    local have, all = 0, 0
    for _, a in ipairs(ADDONS) do
        if forThisGame(a) then all = all + 1; if State(a) == "on" then have = have + 1 end end
    end
    text(c, "|cff00c7ffVoid|rHub", "GameFontNormalHuge", 20, -20)
    text(c, ("You run %d of the %d Void addons for %s on this character."):format(have, all, GAME), "GameFontHighlight", 20, -56)
    text(c, "|cff8c8c9e(placeholder: the Start page that grabs attention is still to design)|r", "GameFontHighlightSmall", 20, -78)
    -- every addon as a tile: lit = you have it; click = its page
    local col, x0, y0, tw, th = 0, 20, -110, 200, 46
    for _, g in ipairs(groupsHere()) do
        for _, a in ipairs(g.addons) do
            local st = State(a)
            local t = piece(CreateFrame("Button", nil, c, "BackdropTemplate"))
            t:SetSize(tw, th)
            t:SetPoint("TOPLEFT", x0 + (col % 4) * (tw + 8), y0 - math.floor(col / 4) * (th + 8))
            local lit = st == "on"
            Backdrop(t, lit and { 0.05, 0.14, 0.18, 1 } or { 0.07, 0.07, 0.09, 1 }, lit and { A[1], A[2], A[3], 0.8 } or { 0.25, 0.27, 0.32, 1 })
            local ic = t:CreateTexture(nil, "ARTWORK")
            ic:SetSize(32, 32); ic:SetPoint("LEFT", 7, 0); ic:SetTexture(a.icon); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            ic:SetDesaturated(not lit); ic:SetAlpha(lit and 1 or 0.45)
            local n = t:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            n:SetPoint("TOPLEFT", ic, "TOPRIGHT", 8, -2); n:SetText(a.label)
            if not lit then n:SetTextColor(0.6, 0.6, 0.65) end
            local s = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            s:SetPoint("TOPLEFT", n, "BOTTOMLEFT", 0, -2); s:SetText(STATE_TEXT[st] or st)
            t:SetScript("OnClick", function() view.group, view.addon = g.index, a.name; Render() end)
            col = col + 1
        end
    end
end

Render = function()
    if not (win and win:IsShown()) then return end
    clear()
    local groups = groupsHere()
    -- which row is which (Swap tab rows): default groups at the bottom, the group's addons on top
    local swap = DB().swap
    local topH = swap and GROUP_ROW_H or ADDON_ROW_H
    local botH = swap and ADDON_ROW_H or GROUP_ROW_H
    local topY, botY = -40, 10
    win.content:ClearAllPoints()
    win.content:SetPoint("TOPLEFT", 10, topY - topH - 6)
    win.content:SetPoint("BOTTOMRIGHT", -10, botY + botH + 6)

    -- group tabs: Start + every group with an addon for this game
    for _, t in ipairs(win.groupTabs) do t:Hide() end
    local gx = 10
    local function gtab(i, label, idx)
        local t = win.groupTabs[i] or Tab(win, GROUP_ROW_H)
        win.groupTabs[i] = t
        t:SetHeight(GROUP_ROW_H)
        t:Set(label, nil, view.group == idx)
        t:ClearAllPoints()
        if swap then t:SetPoint("TOPLEFT", gx, topY) else t:SetPoint("BOTTOMLEFT", gx, botY) end
        t:SetScript("OnClick", function()
            view.group = idx
            -- a group opens on its first addon you have, else its first addon
            view.addon = nil
            for _, g in ipairs(groups) do
                if g.index == idx then
                    for _, a in ipairs(g.addons) do if State(a) == "on" then view.addon = a.name; break end end
                    view.addon = view.addon or (g.addons[1] and g.addons[1].name)
                end
            end
            Render()
        end)
        gx = gx + t:GetWidth() + 4
    end
    gtab(1, "Start", 0)
    for i, g in ipairs(groups) do gtab(i + 1, g.name, g.index) end

    -- addon tabs of the open group
    for _, t in ipairs(win.addonTabs) do t:Hide() end
    local open
    if view.group ~= 0 then
        local ax = 10
        for _, g in ipairs(groups) do
            if g.index == view.group then
                for i, a in ipairs(g.addons) do
                    local st = State(a)
                    local t = win.addonTabs[i] or Tab(win, ADDON_ROW_H)
                    win.addonTabs[i] = t
                    t:SetHeight(ADDON_ROW_H)
                    local note = (st == "missing" and "get it") or ((st == "off" or st == "error") and "off")
                        or ((st == "turning-on" or st == "turning-off") and "reload") or nil
                    t:Set(a.label, a.icon, view.addon == a.name, st ~= "on", note)
                    t:ClearAllPoints()
                    if swap then t:SetPoint("BOTTOMLEFT", ax, botY) else t:SetPoint("TOPLEFT", ax, topY) end
                    t:SetScript("OnClick", function() view.addon = a.name; Render() end)
                    ax = ax + t:GetWidth() + 4
                    if view.addon == a.name then open = a end
                end
            end
        end
    end

    local c = win.content
    if view.group == 0 or not open then
        StartPage(c)
    else
        local st = State(open)
        if st == "missing" then MissingPage(c, open) else HavePage(c, open, st) end
    end
end

----------------------------------------------------------------------
-- Opening it: a switch in the VoidHub drawer (Other), no typing
----------------------------------------------------------------------
local function Toggle(on)
    win = win or Build()
    if on == nil then on = not win:IsShown() end
    win:SetShown(on)
end
ns.Toggle = Toggle
VoidHub_Toggle = Toggle   -- the hub button (VoidHubBundle) and /vhub open it with this

-- straight to one addon's page and section (pages link to each other with it; testing from a short /run:
-- VoidHub_Open("VoidQuest", "route"))
function ns.Open(addon, section)
    Toggle(true)
    for _, a in ipairs(ADDONS) do
        if a.name == addon then view.group, view.addon = a.group, a.name end
    end
    if section then DB().sec = DB().sec or {}; DB().sec[addon] = section end
    Render()
end
VoidHub_Open = ns.Open

-- in the drawer too (Other), once: a newer copy taking over replaces the entry instead of adding a second
VoidHubToggles = VoidHubToggles or {}
do
    local entry = { id = "VoidHub.window", group = "Other", label = "VoidHub window",
        tip = "Every Void addon in one window: its pages, settings and lookups. Also: right-click the VoidHub button, or /vhub.",
        noCombat = false,
        get = function() return win ~= nil and win:IsShown() end,
        set = function(on) Toggle(on) end }
    local at
    for i, e in ipairs(VoidHubToggles) do if e.id == entry.id then at = i end end
    if at then VoidHubToggles[at] = entry else table.insert(VoidHubToggles, entry) end
end
