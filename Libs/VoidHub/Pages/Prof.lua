----------------------------------------------------------------------
-- VoidHub pages for "Professions":
--   VoidProf    one section per profession you have (WoW Forever): its next skill cap and the plan under it,
--               drawn by VoidProf's own builders (SkillCap:Build and the gathering / skinning / crafting plans and
--               vendor recipes under it; they keep their state on the frame they're given, so the hub's copy and
--               the VoidProf window don't touch each other), with the hub's buttons. Lockpicking (rogues) and the
--               recipe Cache, drawn by the hub. Left in VoidProf's window for now: Camping (one tab per addon) and
--               the profession helpers with a spell button (Cast Cooking Fire: locked in combat).
--   VoidGather  Skill-ups (where your next herb / ore points are, Go) and Settings (its settings window).
----------------------------------------------------------------------
local ns = _G.VoidHubWin
if not ns or ns.skip then return end   -- another Void addon's copy of VoidHub runs the window
local K = ns.Kit

local function VP() return _G.VoidProf end

-- VoidProf's builders call makeButton(parent, w, h, label, onClick[, spell]) and read btn._text
local function makeButton(parent, w, h, label, onClick)
    local b = K.Button(parent, label, w, onClick)
    b:SetHeight(h or 22)
    b._text = b.text
    return b
end

local function professions()
    local names, have = {}, {}
    local raw = GetProfessions and { GetProfessions() } or {}
    for i = 1, 8 do
        local idx = raw[i]
        if idx then
            local name = GetProfessionInfo(idx)
            if name and not have[name] then names[#names + 1] = name; have[name] = true end
        end
    end
    -- Poisons (rogues): not in GetProfessions on the laptop's character, but it is on the PC's (two Poisons
    -- tabs, 2026-11-24); SkillCap finds it by its skill line, so add it only when missing
    local S = VP() and VP().SkillCap
    local all = S and S:Professions() or {}
    if all.Poisons and not have.Poisons then names[#names + 1] = "Poisons" end
    return names
end

local profPanels = {}
local function header(P)
    local rank, max
    for _, idx in pairs({ GetProfessions() }) do
        local name, _, r, m = GetProfessionInfo(idx)
        if name == P.prof then rank, max = r, m end
    end
    local line = rank and ("Skill %d / %d"):format(rank, max or 0) or ""
    local cache = VP():ProfCache()[P.prof]
    if cache and (cache.learnedCount or 0) > 0 then
        local mins = cache.lastSync and math.max(0, math.floor((time() - cache.lastSync) / 60)) or 0
        line = line .. ("   |cff888888·   %d recipes   ·   synced %dm ago|r"):format(cache.learnedCount, mins)
    end
    P.sub:SetText(line)
end
local function profRefresh(P)
    if not (P and P:IsVisible()) then return end
    header(P)
    VP().SkillCap:Refresh(P)
end

local function ProfBuild(prof)
    return function(host)
        local P = CreateFrame("Frame", nil, host)
        P:SetAllPoints()
        P.prof = prof
        P.title = K.Text(P, "GameFontNormalLarge", "|cff00c7ff" .. prof .. "|r"); P.title:SetPoint("TOPLEFT", 14, -10)
        P.sub = K.Text(P, "GameFontHighlightSmall"); P.sub:SetPoint("TOPLEFT", 14, -32)
        VP().SkillCap:Build(P, prof, -56, makeButton)
        P:SetScript("OnShow", function(s)
            -- bags, banks and prices change while it's closed: the plan is worked out again (VoidProf's own rule)
            if VP().LevelUI and VP().LevelUI.Invalidate then VP().LevelUI:Invalidate() end
            profRefresh(s)
        end)
        -- skill-ups, levels and a book landing in your bags: followed while it's open (batched)
        K.LiveEvents(P, { "SKILL_LINES_CHANGED", "PLAYER_LEVEL_UP", "BAG_UPDATE_DELAYED", "CHAT_MSG_SKILL" }, function() profRefresh(P) end, 1)
        profPanels[#profPanels + 1] = P
        return P
    end
end

-- Lockpicking (rogues): the route, green where it gives points now
local LPP
local function LockRender()
    if not (LPP and LPP:IsVisible()) then return end
    local LP = VP().Lockpick
    local skill, max = LP:Skill()
    if skill then
        LPP.head:SetText(("Lockpicking |cffffd200%d|r%s"):format(skill, max and ("/" .. max) or ""))
        LPP.sub:SetText("Green: gives you points now. Click a line for a waypoint. Max goes up 5 per level (Pick Lock).")
    else
        LPP.head:SetText("Lockpicking")
        LPP.sub:SetText("Your skill shows after your next Lockpicking point. Click a line for a waypoint.")
    end
    LPP.skill = skill
    local first
    for i, step in ipairs(LP.ROUTE) do if not first and LP:State(step, skill) == "now" then first = i end end
    LPP.list:SetData(LP.ROUTE, LPP.placed)
    if first and not LPP.placed then LPP.placed = true; LPP.list.off = math.max(0, first - 2); LPP.list:Refresh() end
end

local function LockBuild(host)
    LPP = CreateFrame("Frame", nil, host)
    LPP:SetAllPoints()
    LPP.head = K.Text(LPP, "GameFontNormalLarge"); LPP.head:SetPoint("TOPLEFT", 14, -10)
    LPP.sub = K.Text(LPP, "GameFontDisableSmall"); LPP.sub:SetPoint("TOPLEFT", 14, -32)
    LPP.list = K.List(LPP, 34, function(r)
        r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
        r:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        r:GetHighlightTexture():SetVertexColor(K.A[1], K.A[2], K.A[3], 0.10)
        r.top = K.Text(r, "GameFontHighlight"); r.top:SetPoint("TOPLEFT", 8, -3); r.top:SetPoint("RIGHT", -8, 0); r.top:SetWordWrap(false)
        r.where = K.Text(r, "GameFontHighlightSmall"); r.where:SetPoint("TOPLEFT", r.top, "BOTTOMLEFT", 0, -2); r.where:SetPoint("RIGHT", -8, 0); r.where:SetWordWrap(false)
        r:SetScript("OnClick", function(s) local LP = VP().Lockpick; if s.item and LP.Hub then LP.Hub.Go(s.item) end end)
        r:SetScript("OnEnter", function(s)
            local step, LP = s.item, VP().Lockpick
            if not step then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:AddLine(("%s  (needs Lockpicking %d)"):format(step[3], step[1]), 1, 1, 1)
            GameTooltip:AddLine(step[6], 0.85, 0.85, 0.85, true)
            if step[4] then
                local n = #LP.SpotsOf(step[3], step[1], step[4])
                GameTooltip:AddLine(("%d spots in %s. Click for a waypoint to the nearest."):format(n, LP.Hub.ZONE[step[4]] or "the zone"), 0.5, 0.8, 1, true)
            end
            local top = LP:LearnedTop(step[1])
            if top then GameTooltip:AddLine(("Your last point from these came at %d."):format(top), 0.6, 1, 0.6) end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end, function(r, step)
        local LP = VP().Lockpick
        local st = LP:State(step, LPP.skill)
        local side = UnitFactionGroup("player") == "Alliance" and "A" or "H"
        local other = step[5] and step[5] ~= side
        local where = step[4] and LP.Hub.ZONE[step[4]] or "Blackrock Depths"
        r.top:SetText(("%s|cff%s%d-%d|r  %s  |cff8a8a94%s|r"):format(st == "now" and "|cff33ff33>|r " or "  ",
            st == "now" and "33ff33" or st == "done" and "6a6a72" or "ffd200", step[1], step[2],
            st == "done" and ("|cff6a6a72" .. step[3] .. "|r") or step[3], where .. (other and " (other faction)" or "")))
        r.where:SetText(step[6])
        r.where:SetTextColor(st == "done" and 0.42 or 0.72, st == "done" and 0.42 or 0.72, st == "done" and 0.46 or 0.78)
        r.bg:SetColorTexture(st == "now" and 0.2 or 1, 1, st == "now" and 0.2 or 1, st == "now" and 0.08 or 0.03)
    end)
    LPP.list:SetPoint("TOPLEFT", 8, -54); LPP.list:SetPoint("BOTTOMRIGHT", -12, 10)
    LPP:SetScript("OnShow", LockRender)
    K.LiveEvents(LPP, { "CHAT_MSG_SKILL", "SKILL_LINES_CHANGED" }, LockRender)
    return LPP
end

-- the recipe cache
local CP
local function CacheRender()
    if not (CP and CP:IsVisible()) then return end
    local lines, n = {}, 0
    for prof, data in pairs(VP():ProfCache()) do
        n = n + 1
        local mins = data.lastSync and math.max(0, math.floor((time() - data.lastSync) / 60)) or 0
        lines[#lines + 1] = ("|cffffd200%s|r  %d recipes, skill %d/%d  |cff888888(synced %dm ago)|r"):format(
            prof, data.learnedCount or 0, data.skillRank or 0, data.skillMaxRank or 0, mins)
    end
    table.sort(lines)
    CP.text:SetText(n == 0 and "|cffff8800No professions cached yet.|r Open any profession window to fill it." or table.concat(lines, "\n"))
end
local function CacheBuild(host)
    CP = CreateFrame("Frame", nil, host)
    CP:SetAllPoints()
    local t = K.Text(CP, "GameFontNormalLarge", "|cff00c7ffRecipe cache|r"); t:SetPoint("TOPLEFT", 14, -10)
    local s = K.Text(CP, "GameFontDisableSmall", "It updates by itself whenever you open a profession window."); s:SetPoint("TOPLEFT", 14, -32)
    local b = K.Button(CP, "Sync now (re-snapshot)", 180, function() VP():CaptureTradeSkillSnapshot(); CacheRender() end)
    b:SetPoint("TOPLEFT", 14, -56)
    CP.text = K.Text(CP, "GameFontHighlight"); CP.text:SetPoint("TOPLEFT", 14, -92); CP.text:SetWidth(700); CP.text:SetSpacing(4)
    CP:SetScript("OnShow", CacheRender)
    return CP
end

-- Camping: every profession's camp items around the burning campfire, as VoidProf's Camping tab shows them, built
-- from VoidProf's own pieces (VoidProf.Camping.Hub: icon buttons with its tooltip and click, the moving fire, paint)
local CMP
local function CampRender()
    if not (CMP and CMP:IsVisible()) then return end
    local C = VP().Camping
    local H = C.Hub
    if not CMP.preloaded then
        CMP.preloaded = true
        for prof in pairs(H.LINE) do
            for _, e in ipairs(C:Items(prof)) do
                H.Preload(e.made); H.Preload(e.book)
                for _, m in ipairs(e.mats) do H.Preload(m[1]) end
            end
        end
    end
    local fires, other = {}, {}
    for _, e in ipairs(C:Items("Cooking")) do
        if e.name:find("Campfire", 1, true) then fires[#fires + 1] = e else other[#other + 1] = e end
    end
    H.Paint(CMP.base, "Cooking", fires[1], 1)
    H.Paint(CMP.l2, "Cooking", fires[2], 2)
    H.Paint(CMP.l3, "Cooking", fires[3], 3)
    local lit = fires[1] and C.HasItem("Cooking", fires[1])
    CMP.label:SetText(("|cff%s%s|r  |cffaaaaaalevel 1|r"):format(lit and "ffd200" or "9a9aa6", fires[1] and fires[1].name or "Campfire"))
    for prof, s in pairs(CMP.slots) do
        local items = prof == "Cooking" and other or C:Items(prof)
        local byTier = {}
        for _, e in ipairs(items) do local t = C.TierOf(e); byTier[t] = byTier[t] or e end
        local first = byTier[1] or items[1]
        local firstLevel = first and C.TierOf(first) or 1
        H.Paint(s.main, prof, first, firstLevel)
        H.Paint(s.t2, prof, firstLevel < 2 and byTier[2] or nil, 2)
        H.Paint(s.t3, prof, firstLevel < 3 and byTier[3] or nil, 3)
        local got = first and C.HasItem(prof, first)
        s.name:SetText(("|cff%s%s|r"):format(got and "ffffff" or "8a8a94", first and first.name or prof))
    end
end

local function CampBuild(host)
    CMP = CreateFrame("Frame", nil, host)
    CMP:SetAllPoints()
    local C = VP().Camping
    local H = C.Hub
    local w, h = host:GetWidth() or 0, host:GetHeight() or 0
    local cx, cy = (w > 300) and math.floor(w / 2) or 490, -((h > 200) and math.floor(h / 2) - 10 or 230)
    CMP.base = H.IconButton(CMP, 52)
    CMP.base:SetPoint("CENTER", CMP, "TOPLEFT", cx, cy)
    local fire = H.MakeFire(CMP)
    fire:SetPoint("BOTTOM", CMP.base, "CENTER", 0, -6)
    fire:SetFrameLevel(CMP.base:GetFrameLevel() + 3)
    CMP.label = K.Text(CMP, "GameFontNormal"); CMP.label:SetPoint("TOP", CMP.base, "BOTTOM", 0, -3)
    CMP.l2, CMP.l3 = H.IconButton(CMP, 24), H.IconButton(CMP, 24)
    CMP.l2:SetPoint("TOPRIGHT", CMP.label, "BOTTOM", -3, -3)
    CMP.l3:SetPoint("TOPLEFT", CMP.label, "BOTTOM", 3, -3)
    CMP.slots = {}
    for i, prof in ipairs(C.RING) do
        local ang = (i - 1) / #C.RING * 2 * math.pi - math.pi / 2
        local s = CreateFrame("Frame", nil, CMP)
        s:SetSize(110, 70)
        s:SetPoint("CENTER", CMP, "TOPLEFT", cx + 330 * math.cos(ang), (cy + 5) - 175 * math.sin(ang))
        local b = H.IconButton(s, 34); b:SetPoint("TOP", 0, 0)
        local name = K.Text(s, "GameFontHighlightSmall"); name:SetPoint("TOP", b, "BOTTOM", 0, -2); name:SetWidth(110)
        name:SetJustifyH("CENTER"); name:SetWordWrap(false)
        local t2, t3 = H.IconButton(s, 18), H.IconButton(s, 18)
        t2:SetPoint("TOPRIGHT", name, "BOTTOM", -2, -2); t3:SetPoint("TOPLEFT", name, "BOTTOM", 2, -2)
        CMP.slots[prof] = { main = b, name = name, t2 = t2, t3 = t3 }
    end
    local hint = K.Text(CMP, "GameFontDisableSmall", "Grey: you don't have it yet. Under each: its level 2 and 3. Hover for what it takes; click a boss drop for the way.")
    hint:SetPoint("BOTTOM", CMP, "BOTTOM", 0, 6)
    CMP:SetScript("OnShow", CampRender)
    K.LiveEvents(CMP, { "NEW_RECIPE_LEARNED", "LEARNED_SPELL_IN_SKILL_LINE", "BAG_UPDATE_DELAYED" }, CampRender)
    return CMP
end

ns.RegisterPage("VoidProf", {
    -- WoW Forever: the skill-cap pages (retail's knowledge trees aren't moved yet)
    available = function() local p = VP(); return p ~= nil and p.SkillCap ~= nil and p.ProfCache ~= nil end,
    sections = function()
        local out = {}
        for _, name in ipairs(professions()) do out[#out + 1] = { key = "p:" .. name, label = name, build = ProfBuild(name) } end
        local LP = VP().Lockpick
        local CM = VP().Camping
        if CM and CM.Hub and CM.RING then out[#out + 1] = { key = "camping", label = "Camping", build = CampBuild } end
        if LP and LP.IsRogue() and LP.Hub then out[#out + 1] = { key = "lockpick", label = "Lockpicking", build = LockBuild } end
        out[#out + 1] = { key = "cache", label = "Cache", build = CacheBuild }
        return out
    end,
})

----------------------------------------------------------------------
-- VoidGather
----------------------------------------------------------------------
local function VG() return _G.VoidGather end
local SKP

local function SkillRender()
    if not (SKP and SKP:IsVisible()) then return end
    local G = VG()
    local any = false
    for _, r in ipairs(SKP.rows) do
        local line = G.Skill and G.Skill:Summary(r.kind)
        if line then
            any = true
            r.fs:SetText(line)
            r.go:SetShown(G.Skill:BestSpots(r.kind, 1)[1] ~= nil)
            r:Show()
        else
            r:Hide()
        end
    end
    SKP.none:SetShown(not any)
end

local function SkillBuild(host)
    SKP = CreateFrame("Frame", nil, host)
    SKP:SetAllPoints()
    local t = K.Text(SKP, "GameFontNormalLarge", "|cff00c7ffSkill-ups|r"); t:SetPoint("TOPLEFT", 14, -10)
    local s = K.Text(SKP, "GameFontDisableSmall", "Where your next Herbalism and Mining points are. Orange always gives a point, yellow usually.")
    s:SetPoint("TOPLEFT", 14, -32)
    SKP.rows = {}
    for i, k in ipairs({ "herb", "mining" }) do
        local r = CreateFrame("Frame", nil, SKP)
        r:SetPoint("TOPLEFT", 14, -60 - (i - 1) * 64); r:SetPoint("RIGHT", -14, 0); r:SetHeight(58)
        r.kind = k
        r.go = K.Button(r, "Go to the best spot", 150, function() VG().Skill:GoBest(k) end)
        r.go:SetPoint("TOPRIGHT", 0, 0)
        r.go:SetScript("OnEnter", function(b)
            local spot = VG().Skill:BestSpots(k, 1)[1]
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT"); GameTooltip:AddLine("Waypoint to the best spot")
            GameTooltip:AddLine(spot and VG().Skill:SpotText(spot) or "No known spot that gives you skill yet.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        r.go:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r.fs = K.Text(r, "GameFontHighlight"); r.fs:SetPoint("TOPLEFT", 0, -2); r.fs:SetPoint("RIGHT", r.go, "LEFT", -12, 0)
        r.fs:SetSpacing(3)
        SKP.rows[i] = r
    end
    SKP.none = K.Text(SKP, "GameFontDisableSmall", "No Herbalism or Mining that still levels on this character.")
    SKP.none:SetPoint("TOPLEFT", 14, -64)
    SKP:SetScript("OnShow", SkillRender)
    K.LiveEvents(SKP, { "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL" }, SkillRender)
    return SKP
end

local function GatherSettings(host)
    local G = VG()
    local cfg = function() return G:Config() end
    local function flag(k, after) return function() return cfg()[k] end, function(on) cfg()[k] = on; if after then after() end end end
    local refresh = function() G:Refresh() end
    local kinds = {}
    for _, k in ipairs(G.KIND_ORDER) do
        local def = G.KINDS[k]
        kinds[#kinds + 1] = { "check", ("|T%s:14:14:0:0:64:64:6:58:6:58|t  %s"):format(def.icon, def.label),
            function() return cfg().show[k] ~= false end, function(on) cfg().show[k] = on; G:Refresh() end }
    end
    local g1, s1 = flag("skillOnly", refresh)
    local g2, s2 = flag("onlyMine", refresh)
    local g3, s3 = flag("showWorld", refresh)
    local g4, s4 = flag("showMinimap", refresh)
    local g5, s5 = flag("autoTrack", function() G.Tracking:Apply() end)
    local g6, s6 = flag("share", function() G.Sync:Apply() end)
    local g7, s7 = flag("craftTips")
    local gathering = {
        { "check", "Auto-switch Find Minerals / Find Herbs", g5, s5, "For miner-herbalists: flips between the two trackers while you move, out of combat." },
        { "choice", "Switch every", { { 3, "3 s" }, { 5, "5 s" }, { 8, "8 s" }, { 10, "10 s" } },
          function() return cfg().autoTrackSecs or 5 end, function(v) cfg().autoTrackSecs = v; G.Tracking:Apply() end },
        { "check", "Share spots with other players", g6, s6, "Send your new spots to other VoidGather players and receive theirs." },
        { "check", "Earnings box on screen", function() return cfg().showEarn end, function(on) G.Earn:SetShown(on) end,
          "What your gathering is worth this session and per hour. Hover it for details." },
        { "check", "Item tooltips: what materials are worth crafted", g7, s7,
          "Hover a herb, ore, leather or cooking ingredient: its sell price, and what each piece is worth turned into a potion, mulch, ingot and so on." },
    }
    if _G.VoidPresence then
        gathering[#gathering + 1] = { "check", "Players-here box", function() return VoidPresence:IsShown() end, function(on) VoidPresence:SetShown(on) end,
            "How many other players in your zone run VoidGather (and VoidSweep), counted over the sharing channel." }
    end
    return K.SettingsPage(host, {
        { title = "Show on map", items = kinds },
        { title = "Pins", items = {
            { "check", "Only nodes that give skill", g1, s1, "Hide herb and ore pins that no longer give you skill (grey)." },
            { "check", "Only my professions", g2, s2, "Hide spots for professions you don't have. Lumber always shows." },
            { "check", "World map dots", g3, s3 },
            { "check", "Minimap pins", g4, s4 },
            { "choice", "Minimap pin size", { { 9, "Small" }, { 11, "Medium" }, { 13, "Large" } },
              function() return cfg().mmPinSize or 11 end, function(v) cfg().mmPinSize = v end },
            { "choice", "Pin opacity", { { 0.5, "50%" }, { 0.7, "70%" }, { 1, "100%" } },
              function() return cfg().mmAlpha or 0.7 end, function(v) cfg().mmAlpha = v end },
        } },
        { title = "Gathering", items = gathering },
        { title = "Gathering HUD", items = {
            { "check", "Show the HUD", function() return cfg().hud end, function(on) G.HUD:SetShown(on) end,
              "Your minimap, big and see-through in front of you and turning with you: the game's herb and ore dots plus VoidGather's spots. Switches outside combat." },
            { "choice", "Size", { { 0.5, "Small" }, { 0.7, "Medium" }, { 0.9, "Large" } },
              function() return cfg().hudSize or 0.7 end, function(v) cfg().hudSize = v; G.HUD:Refresh() end },
            { "choice", "Map underneath", { { 0, "Off" }, { 0.15, "Faint" }, { 0.35, "Light" } },
              function() return cfg().hudTerrain or 0 end, function(v) cfg().hudTerrain = v; G.HUD:Refresh() end },
            { "button", "Move / lock the HUD", function() G.HUD:ToggleMove() end, "Unlocks it so you can drag it; click again to lock. Locked, it lets your clicks through." },
        } },
    }, 300)
end

ns.RegisterPage("VoidGather", {
    available = function() local g = VG(); return g ~= nil and g.Config ~= nil and g.KINDS ~= nil end,
    sections = {
        { key = "skill", label = "Skill-ups", build = SkillBuild, available = function() return VG().Skill ~= nil end },
        { key = "settings", label = "Settings", build = GatherSettings },
    },
})
