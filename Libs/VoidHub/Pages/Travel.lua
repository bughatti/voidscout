----------------------------------------------------------------------
-- VoidHub pages for the rest of "Questing and travel":
--   VoidGPS    Find: a full-page search (VoidGPS's own S:Find), every result a row, click = the same route
--              the search box starts; empty = your recent places. Settings: its three switches.
--   VoidMap    Settings: the settings window (same M:Config keys, same map calls)
--   VoidSweep  Settings: the map button's menu (what shows on the map, completed, minimap, crowd sync,
--              campfires, the players-here box)
-- Data and actions come from each addon (VoidGPS.SearchModule.Hub, VoidMap.Hub, VoidSweepHub).
----------------------------------------------------------------------
local ns = _G.VoidHubWin
if not ns or ns.skip then return end   -- another Void addon's copy of VoidHub runs the window
local K = ns.Kit

----------------------------------------------------------------------
-- VoidGPS
----------------------------------------------------------------------
local function GS() local g = _G.VoidGPS; return g and g.SearchModule end
local GP

local function GpsRender()
    if not (GP and GP:IsVisible()) then return end
    local S = GS()
    if not (S and S.Hub) then return end
    local q = GP.query or ""
    local ok, res = pcall(S.Find, S, q)
    res = ok and res or {}
    GP.title:SetText(q == "" and ("Recent places  |cff888888%d|r"):format(#res) or ("Results for \"%s\"  |cff888888%d|r"):format(q, #res))
    GP.empty:SetShown(#res == 0)
    GP.empty:SetText(q == "" and "No recent places yet: search for a place, an NPC, a service (bank, flight master, repair), a zone or an item."
        or "Nothing found. Try a shorter word: an NPC's name, a service (mailbox, innkeeper, trainer), a zone, or coordinates (52 40).")
    GP.list:SetData(res)
end

local function GpsBuild(host)
    GP = CreateFrame("Frame", nil, host)
    GP:SetAllPoints()
    GP.search = K.Search(GP, 460, "Where to? A name, a service (bank, repair, flight master), a zone, an item, 52 40...", function(t)
        GP.query = t
        -- search once typing pauses (VoidGPS's own rule: a search per keystroke lagged the screen)
        GP.tok = (GP.tok or 0) + 1
        local tok = GP.tok
        C_Timer.After(InCombatLockdown() and 0.35 or 0.15, function() if tok == GP.tok then GpsRender() end end)
    end)
    GP.search:SetPoint("TOPLEFT", 16, -12)
    GP.search:SetScript("OnEnterPressed", function(e)
        e:ClearFocus()
        -- search now for what's typed (the pause-to-search timer may not have run yet: Codex 11-25)
        GP.tok = (GP.tok or 0) + 1
        GpsRender()
        local first = GP.list.data[1]
        if first then GS().Hub.Go(first) end
    end)
    GP.title = K.Text(GP, "GameFontNormal"); GP.title:SetPoint("TOPLEFT", GP.search, "BOTTOMLEFT", 0, -14)
    GP.empty = K.Text(GP, "GameFontDisableSmall"); GP.empty:SetPoint("TOPLEFT", GP.title, "BOTTOMLEFT", 2, -10); GP.empty:SetWidth(700)
    GP.list = K.List(GP, 34, function(r)
        r:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        r:GetHighlightTexture():SetVertexColor(K.A[1], K.A[2], K.A[3], 0.12)
        r.name = K.Text(r, "GameFontHighlight"); r.name:SetPoint("TOPLEFT", 8, -4); r.name:SetPoint("RIGHT", -8, 0); r.name:SetWordWrap(false)
        r.sub = K.Text(r, "GameFontDisableSmall"); r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3); r.sub:SetPoint("RIGHT", -8, 0); r.sub:SetWordWrap(false)
        r:SetScript("OnClick", function(s) if s.item then GS().Hub.Go(s.item) end end)
    end, function(r, e)
        local H = GS().Hub
        local bits = {}
        if e.sub and e.sub ~= "" then bits[#bits + 1] = e.sub end
        local where = e.map and H.MapName(e.map) or nil
        if where and e.kind ~= "zone" and e.kind ~= "coords" then bits[#bits + 1] = where end
        if e.dist then bits[#bits + 1] = H.Yards(e.dist) .. " yd" end
        r.name:SetText(e.kind == "rare" and ("|cffff6060" .. e.name .. "|r") or e.name)
        r.sub:SetText(table.concat(bits, " · "))
    end)
    GP.list:SetPoint("TOPLEFT", GP.title, "BOTTOMLEFT", -2, -8); GP.list:SetPoint("BOTTOMRIGHT", -12, 30)
    GP.hint = K.Text(GP, "GameFontDisableSmall", "Click a result (or Enter for the first): VoidGPS shows the way, along roads, flight paths, boats and zeppelins.")
    GP.hint:SetPoint("BOTTOMLEFT", 16, 10)
    GP:SetScript("OnShow", GpsRender)
    return GP
end

local function GpsSettings(host)
    local G = _G.VoidGPS
    return K.SettingsPage(host, {
        { title = "VoidGPS", items = {
            { "check", "Rare alerts", function() return VoidGPSDB and VoidGPSDB.rareAlerts ~= false end,
              function(on) G:SetRareAlerts(on); if GS() and GS().PaintRares then GS():PaintRares() end end,
              "A sound and \"<name> is up!\" when any rare shows on a nameplate, your target or your mouseover." },
            { "check", "Search box on screen", function() local S = GS(); return S and S:Docked() end,
              function(on) local S = GS(); if S then S:SetDocked(on) end end,
              "Keep VoidGPS's search box on screen (drag it where you like). Off: it opens when you need it." },
            { "check", "Flight paths on the map", function() return VoidGPSDB and VoidGPSDB.flightPins ~= false end,
              function(on) if G.SetFlightPins then G:SetFlightPins(on) end end,
              "Every flight master of your faction on the world map: green = you have it, yellow = not yet. Click one to get a route there." },
        } },
    }, 380)
end

ns.RegisterPage("VoidGPS", {
    available = function() local S = GS(); return S ~= nil and S.Hub ~= nil end,
    sections = {
        { key = "find", label = "Find", build = GpsBuild },
        { key = "settings", label = "Settings", build = GpsSettings },
    },
})

----------------------------------------------------------------------
-- VoidMap: its settings window
----------------------------------------------------------------------
local function MH() local m = _G.VoidMap; return m and m.Hub end

local function MapSettings(host)
    local H = MH()
    local function c() return H.Config() end
    local function flip(k) return function() return c()[k] end, function(on) c()[k] = on; H.Apply() end end
    local function pick(k) return function() return c()[k] end, function(v) c()[k] = v; H.Apply() end end
    local scaleG, scaleS = pick("scale")
    local alphaG, alphaS = pick("mapAlpha")
    local page = K.SettingsPage(host, {
        { title = "Window", items = {
            { "check", "Move the map by dragging its title bar", function() return c().movable end, function(on) c().movable = on; H.Apply() end, "Drag the title bar to put the map anywhere; drag the corner at the bottom right to size it." },
            { "check", "Quest list beside the map", function() return c().questPanel end, function() H.ToggleQuests() end,
              "Your quests, the ones on the map you're looking at first. Also the Quests button on the map." },
        } },
        { title = "Look", items = {
            { "choice", "Scale", { { 0.8, "80%" }, { 0.9, "90%" }, { 1.0, "100%" }, { 1.15, "115%" }, { 1.3, "130%" } }, scaleG, scaleS },
            { "choice", "Map opacity", { { 0.5, "50%" }, { 0.7, "70%" }, { 0.85, "85%" }, { 1.0, "100%" } }, alphaG, alphaS },
            { "check", "Fade the map while you move (Blizzard's setting)", function() return GetCVarBool("mapFade") end,
              function(on) SetCVar("mapFade", on and "1" or "0") end,
              "Blizzard's own fade: the map turns see-through while you walk and comes back when you stop or point at it." },
            { "check", "Coordinates at the bottom (you and the cursor)", flip("coords") },
        } },
        { title = "Trails (for VoidGPS)", items = {
            { "check", "Record where I walk", function() return c().trails end, function(on) c().trails = on; H.Apply() end,
              "Saves the paths you walk and ride (not flying, taxis, boats or instances), for every character. VoidGPS will route along them, around mountains and cliffs. Stays on this computer." },
            { "note", "Settings are per character." },
        } },
    }, 420)
    local reset = K.Button(page, "Default spot and size", 170, function() H.ResetGeo() end)
    reset:SetPoint("BOTTOMLEFT", 16, 14)
    reset:SetScript("OnEnter", function(s)
        K.Recolor(s, nil, { K.A[1], K.A[2], K.A[3], 1 })
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:AddLine("Default spot and size")
        GameTooltip:AddLine("Puts the map back in the middle of the screen at its starting size.", 0.8, 0.8, 0.8, true); GameTooltip:Show()
    end)
    reset:SetScript("OnLeave", function(s) K.Recolor(s, nil, { K.A[1], K.A[2], K.A[3], 0.55 }); GameTooltip:Hide() end)
    return page
end

ns.RegisterPage("VoidMap", {
    available = function() return MH() ~= nil end,
    sections = { { key = "settings", label = "Settings", build = MapSettings } },
})

----------------------------------------------------------------------
-- VoidSweep: the map button's menu
----------------------------------------------------------------------
local function SH() return _G.VoidSweepHub end

local function SweepSettings(host)
    local H = SH()
    local function cfg() return H.Config() end
    local show = {}
    for _, cat in ipairs(H.CATS) do
        local col = H.Color(cat.key)
        local sw = ("|TInterface\\Buttons\\WHITE8X8:10:10:0:0:8:8:0:8:0:8:%d:%d:%d|t  "):format(
            math.floor(col[1] * 255), math.floor(col[2] * 255), math.floor(col[3] * 255))
        if cat.live and H.FireIcon() then sw = ("|T%s:12:12:0:0:64:64:5:59:5:59|t  "):format(H.FireIcon()) end
        show[#show + 1] = { "check", sw .. cat.label, function() return cfg().show[cat.key] ~= false end,
            function(on) cfg().show[cat.key] = on; H.RefreshPins() end }
    end
    if H.Forever then
        show[#show + 1] = { "check", "Possible spots (where a chest or supply can appear)", function() return cfg().chestSpots == true end,
            function() H.ToggleSpots() end, "WoW Forever: chests are seen by players (no game markers there). Bright = seen in the last 15 min (by you or a Void player)." }
    end
    local more = {
        { "check", "Show completed", function() return cfg().showCompleted end, function(on) cfg().showCompleted = on; H.RefreshPins() end },
        { "check", "Minimap pins", function() return cfg().showMinimap end, function(on) cfg().showMinimap = on end },
        { "check", "Crowd sync", function() return cfg().sync end, function(on) cfg().sync = on; H.RefreshPins(); H.CountNow() end,
          "Share what you find with other Void players and see theirs." },
    }
    if H.CampNet() and H.Forever then
        more[#more + 1] = { "check", "Share campfires I'm at", function() return cfg().campNet ~= false end, function(on) cfg().campNet = on end }
        more[#more + 1] = { "check", "Campfire popup (a buff NEW for me, in my zone)", function() return cfg().campAlert ~= false end, function(on) cfg().campAlert = on end }
    end
    if _G.VoidPresence then
        more[#more + 1] = { "check", "Players-here box", function() return VoidPresence:IsShown() end, function(on) VoidPresence:SetShown(on) end }
    end
    return K.SettingsPage(host, {
        { title = "Show on map", items = show },
        { title = "More", items = more },
    }, 380)
end

ns.RegisterPage("VoidSweep", {
    available = function() return SH() ~= nil end,
    sections = { { key = "settings", label = "Settings", build = SweepSettings } },
})
