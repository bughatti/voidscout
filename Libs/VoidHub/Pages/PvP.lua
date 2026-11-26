----------------------------------------------------------------------
-- VoidHub pages for "PvP and groups" (WoW Forever):
--   VoidBounty  its window's pages: Sightings, Blood debts, Most wanted (and with bounties on: My hunts, Ledger, Hall),
--               the "coming soon" page and Settings. Lists come from VoidBounty's own builders (VoidBountyHub.Items),
--               their buttons (Track, Unmark, Writ...) do what they do there. The Board of wanted posters stays in
--               VoidBounty's window (only while bounties are on).
--   VoidScout   Players: everyone in your recorded fights (you first), and the card for the one you pick (the same
--               numbers as VoidScout's card: VoidScout.ForeverCard.Lookup). Data sharing: allow / local only.
----------------------------------------------------------------------
local ns = _G.VoidHubWin
if not ns or ns.skip then return end   -- another Void addon's copy of VoidHub runs the window
local K = ns.Kit

----------------------------------------------------------------------
-- VoidBounty
----------------------------------------------------------------------
local function BH() return _G.VoidBountyHub end
local bountyPanels = {}

local function BountyRender(P)
    if not (P and P:IsVisible()) then return end
    local H = BH()
    P.net:SetText(H.Net() .. "     " .. H.Danger())
    local ok, items = pcall(H.Items[P.kind])
    if not ok then items = { { text = "|cffff5555" .. tostring(items) .. "|r" } } end
    P.list:SetData(items or {}, true)
end

local function BountyList(kind)
    return function(host)
        local P = CreateFrame("Frame", nil, host)
        P:SetAllPoints()
        P.kind = kind
        P.net = K.Text(P, "GameFontDisableSmall"); P.net:SetPoint("TOPLEFT", 16, -10); P.net:SetPoint("RIGHT", -16, 0)
        P.list = K.List(P, 22, function(r)
            r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
            r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 4, 0)
            r.text = K.Text(r, "GameFontHighlight"); r.text:SetWordWrap(false)
            r.btn = {}
            for i = 1, 3 do
                local b = K.Button(r, "", 60, nil)
                b:SetHeight(18)
                if i == 1 then b:SetPoint("RIGHT", -2, 0) else b:SetPoint("RIGHT", r.btn[i - 1], "LEFT", -4, 0) end
                b:HookScript("OnEnter", function(s)
                    if not s.tipText then return end
                    GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:AddLine(s.label or ""); GameTooltip:AddLine(s.tipText, 0.8, 0.8, 0.8, true); GameTooltip:Show()
                end)
                b:HookScript("OnLeave", function() GameTooltip:Hide() end)
                r.btn[i] = b
            end
            r:SetScript("OnEnter", function(s)
                local it = s.item
                if it and it.tip then GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); it.tip(GameTooltip); GameTooltip:Show() end
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end, function(r, it, i)
            if it.head then
                r.bg:SetColorTexture(K.A[1], K.A[2], K.A[3], 0.10)
                r.icon:Hide()
                r.text:ClearAllPoints(); r.text:SetPoint("LEFT", 6, 0)
                r.text:SetText("|cff00c7ff" .. (it.text or "") .. "|r")
            else
                r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.035 or 0)
                r.text:ClearAllPoints()
                if it.cls ~= nil then BH().ClassIcon(r.icon, it.cls); r.icon:Show(); r.text:SetPoint("LEFT", 24, 0)
                else r.icon:Hide(); r.text:SetPoint("LEFT", 6, 0) end
                r.text:SetText(it.text or "")
            end
            local used = 0
            for k, b in ipairs(r.btn) do
                local spec = it.buttons and it.buttons[k]
                if spec then
                    b:SetLabel(spec[1]); b:SetWidth(spec[4] or 60)
                    b.label, b.tipText = spec[1], spec[3]
                    b:SetScript("OnClick", function() spec[2](); BountyRender(P) end)
                    b:SetEnabled(spec[5] ~= false); b:SetAlpha(spec[5] == false and 0.45 or 1)
                    b:Show()
                    used = used + (spec[4] or 60) + 4
                else
                    b:Hide()
                end
            end
            r.text:SetPoint("RIGHT", r, "RIGHT", -(used + 8), 0)
        end)
        P.list:SetPoint("TOPLEFT", 8, -32); P.list:SetPoint("BOTTOMRIGHT", -12, 10)
        P:SetScript("OnShow", BountyRender)
        bountyPanels[#bountyPanels + 1] = P
        return P
    end
end

local function SoonBuild(host)
    local P = CreateFrame("Frame", nil, host)
    P:SetAllPoints()
    local h = K.Text(P, "GameFontNormalLarge", "|cff00c7ffBounties: coming soon|r"); h:SetPoint("TOPLEFT", 16, -12)
    local t = K.Text(P, "GameFontHighlight"); t:SetPoint("TOPLEFT", 16, -42); t:SetWidth(720); t:SetSpacing(4)
    t:SetText("Being tested now, and switched on in an update once it's solid:\n\n"
        .. "|cffffd27aWanted posters|r  A writ on a player who killed you, shown to every VoidBounty player of your side.\n\n"
        .. "|cffffd27aHunting|r  Take a writ, get the killing blow outside cities and battlegrounds. Your own combat log is the proof.\n\n"
        .. "|cffffd27aTribute|r  The reward is basic vendor goods the poster buys and trades to you (food, potions, ammo, reagents). Never gold.\n\n"
        .. "|cffffd27aStanding|r  Settle your writs to climb: Collector, Hunter, Executioner. Leave one unpaid and you're Burned.\n\n"
        .. "|cff999999Everything else works today: the nearby warning, Blood debts, Sightings, tracking and Most wanted. "
        .. "The players who kill you now will still be on your list when bounties arrive.|r")
    return P
end

local function BountySettings(host)
    local H = BH()
    local items = {}
    for _, o in ipairs(H.Options()) do
        local key, label, tip, defOn, shared = o[1], o[2], o[3], o[4], o[5]
        local get, set
        if shared then
            get, set = function() return shared.On() end, function(on) shared.Set(on) end
        else
            get = function() local v = H.Char()[key]; if defOn then return v ~= false end return v and true or false end
            set = function(on)
                H.Char()[key] = on
                if key == "autolog" and on then H.LogState() end
                H.RenderAlert()
            end
        end
        items[#items + 1] = { "check", label, get, set, tip }
    end
    return K.SettingsPage(host, {
        { title = "Settings (this character)", items = items },
        { title = "Try it", items = {
            { "button", "Test the warning", function() H.Test() end, "A made-up Marked enemy \"Test Dummy\" near you for 25 seconds." },
            { "button", "Mark my target", function() H.MarkTarget() end, "Puts the enemy player you have targeted on your Blood debts list: the warning goes red when they're near." },
            { "note", "Enemy players are seen from nameplates, your target and your mouse, in the open world (battlegrounds hide who players are). Whoever kills you goes on Blood debts by itself. Other VoidBounty players of your side share what they see.", h = 70 },
        } },
    }, 420)
end

local BOUNTY_LABEL = { sightings = "Sightings", debts = "Blood debts", hall = "Most wanted", hunts = "My hunts", ledger = "Ledger" }
ns.RegisterPage("VoidBounty", {
    available = function() return BH() ~= nil end,
    sections = function()
        local out, H = {}, BH()
        for _, n in ipairs(H.NAV()) do
            local id, label = n[1], n[2]
            if H.Items[id] then out[#out + 1] = { key = id, label = label or BOUNTY_LABEL[id], build = BountyList(id) }
            elseif id == "soon" then out[#out + 1] = { key = "soon", label = label, build = SoonBuild }
            elseif id == "settings" then out[#out + 1] = { key = "settings", label = label, build = BountySettings } end
        end
        return out
    end,
})

-- VoidBounty's own change signal (a sighting, a death, a share; "tick" at most every 5 s), like its window
do
    local hooked, lastTick = false, 0
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        local H = BH()
        if hooked or not (H and H.OnChange) then return end
        hooked = true
        H.OnChange(function(what)
            if what == "tick" then
                if GetTime() - lastTick < 5 then return end
                lastTick = GetTime()
            end
            for _, P in ipairs(bountyPanels) do if P:IsVisible() then BountyRender(P) end end
        end)
    end)
end

----------------------------------------------------------------------
-- VoidScout
----------------------------------------------------------------------
local function VC() local v = _G.VoidScout; return v and v.ForeverCard end
local AXES = { "Damage", "Interrupts", "Dispels", "Avoidance", "Activity", "Survival", "Teamwork" }
local TIPS = {
    Damage = "more damage: no gaps, cooldowns on the boss", Interrupts = "kick more: watch enemy casts",
    Dispels = "dispel more: watch your party's debuffs", Avoidance = "take less avoidable damage: step out of it",
    Activity = "fewer pauses between casts", Survival = "die less: defensives, potions, bandages", Teamwork = "use your group utility",
}
-- VoidScout's own score colours (its card's)
local function colorFor(s) local C = VC(); if C and C.ColorFor then return C.ColorFor(s) end return 0.5, 0.5, 0.5 end
local function ago(t)
    if not t or t <= 0 then return "?" end
    local s = time() - t
    if s < 3600 then return math.max(1, math.floor(s / 60)) .. "m ago" end
    if s < 86400 then return math.floor(s / 3600) .. "h ago" end
    return math.floor(s / 86400) .. "d ago"
end
local SP
local function myKey() return VoidScoutDB and VoidScoutDB.me and VoidScoutDB.me.key end

local function cardLines(d, isMe)
    local L = {}
    local function add(l, r, c) L[#L + 1] = { l = l, r = r or "", c = c } end
    local cc = d.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[d.class]
    local hex = cc and ("|cff%02x%02x%02x"):format(math.floor(cc.r * 255), math.floor(cc.g * 255), math.floor(cc.b * 255)) or "|cffffffff"
    L[#L + 1] = { big = true, l = hex .. d.name .. "|r" }
    local meta = {}
    if d.fights > 0 then meta[#meta + 1] = d.fights .. " boss fight" .. (d.fights == 1 and "" or "s") end
    if not isMe and (d.runsWithMe or 0) > 0 then meta[#meta + 1] = "ran with you " .. d.runsWithMe .. "x" end
    if not isMe and d.lastSeen then meta[#meta + 1] = "last " .. ago(d.lastSeen) end
    add("|cff999999" .. (#meta > 0 and table.concat(meta, "  ·  ") or "Not in your recorded fights yet") .. "|r")
    L[#L + 1] = { head = "Score" }
    local r, g, b = colorFor(d.overall)
    add("VoidScout Score", d.overall and tostring(d.overall) or "-", { r, g, b })
    if d.commitment then add("Commitment", d.commitment .. "%", { colorFor(d.commitment) }) end
    local any = false
    for _, a in ipairs(AXES) do
        local v = d.axes[a]
        if v then
            if not any then L[#L + 1] = { head = "By part" }; any = true end
            add("   " .. a, tostring(v), { colorFor(v) })
        end
    end
    L[#L + 1] = { head = "Gear and fights" }
    add("Item level", d.ilvl and (d.ilvl .. (d.ilvlFrom == "inspect" and ("  (inspected " .. ago(d.ilvlAt) .. ")") or ("  (in a fight " .. ago(d.ilvlAt) .. ")")))
        or (isMe and "-" or "- (shows when they're near you)"), { 1, 1, 1 })
    if d.dps then add("Average DPS", tostring(d.dps), { 1, 1, 1 }) end
    if d.fights > 0 then add("Died in", ("%d of %d fights"):format(d.deaths, d.fights), { 1, 1, 1 }) end
    if isMe then
        local weak = {}
        for _, a in ipairs(AXES) do if d.axes[a] and d.axes[a] < 75 then weak[#weak + 1] = a end end
        table.sort(weak, function(x, z) return d.axes[x] < d.axes[z] end)
        if #weak > 0 then
            L[#L + 1] = { head = "Work on" }
            for k = 1, math.min(2, #weak) do add(TIPS[weak[k]]) end
        end
    end
    return L
end

local function ScoutRender()
    if not (SP and SP:IsVisible()) then return end
    local C = VC()
    local me = myKey() or (UnitName("player"))
    local people = { { key = me, me = true } }
    local scores = VoidScoutDB and VoidScoutDB.scores or {}
    local list = {}
    for key, rec in pairs(scores) do
        if key ~= me then
            local n, last = 0, 0
            for _, f in ipairs(rec.fights or {}) do n = n + 1; if (f.timestamp or 0) > last then last = f.timestamp end end
            if n > 0 then list[#list + 1] = { key = key, n = n, last = last } end
        end
    end
    table.sort(list, function(a, b) return a.last > b.last end)
    for _, x in ipairs(list) do people[#people + 1] = x end
    SP.people:SetData(people, true)
    SP.sel = SP.sel or me
    local d = C.Lookup(SP.sel)
    SP.card:SetData(d and cardLines(d, SP.sel == me) or { { l = "|cff999999No fights recorded for " .. tostring(SP.sel):gsub("%-", " ") .. " yet: run a dungeon with VoidScout on.|r" } }, false)
end

local function ScoutBuild(host)
    SP = CreateFrame("Frame", nil, host)
    SP:SetAllPoints()
    local left = CreateFrame("Frame", nil, SP)
    left:SetPoint("TOPLEFT", 8, -8); left:SetPoint("BOTTOMLEFT", 8, 8); left:SetWidth(240)
    K.Box(left, { 0.04, 0.04, 0.06, 1 }, K.EDGE)
    SP.people = K.List(left, 20, function(b)
        b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        b:GetHighlightTexture():SetVertexColor(K.A[1], K.A[2], K.A[3], 0.12)
        b.text = K.Text(b, "GameFontHighlightSmall"); b.text:SetPoint("LEFT", 4, 0); b.text:SetPoint("RIGHT", -60, 0); b.text:SetWordWrap(false)
        b.n = K.Text(b, "GameFontDisableSmall"); b.n:SetPoint("RIGHT", -4, 0)
        b:SetScript("OnClick", function(s) SP.sel = s.item.key; ScoutRender() end)
    end, function(b, p)
        local sel = SP.sel == p.key
        b.text:SetText((sel and "|cff00c7ff" or "|cffffffff") .. (p.me and "You" or tostring(p.key):gsub("%-", " ")) .. "|r")
        b.n:SetText(p.n and (p.n .. " fight" .. (p.n == 1 and "" or "s")) or "")
    end)
    SP.people:SetPoint("TOPLEFT", 6, -6); SP.people:SetPoint("BOTTOMRIGHT", -4, 6)
    SP.card = K.List(SP, 22, function(r)
        r.l = K.Text(r, "GameFontHighlight"); r.l:SetPoint("LEFT", 6, 0)
        r.r = K.Text(r, "GameFontNormal"); r.r:SetPoint("LEFT", 230, 0)
    end, function(r, x)
        if x.head then
            r.l:SetFontObject("GameFontNormal"); r.l:SetText("|cff00c7ff" .. x.head .. "|r"); r.r:SetText("")
        else
            r.l:SetFontObject(x.big and "GameFontNormalLarge" or "GameFontHighlight")
            r.l:SetText(x.l or ""); r.r:SetText(x.r or "")
            local c = x.c
            if c then r.r:SetTextColor(c[1], c[2], c[3]) else r.r:SetTextColor(1, 0.82, 0) end
        end
    end)
    SP.card:SetPoint("TOPLEFT", left, "TOPRIGHT", 16, -4); SP.card:SetPoint("BOTTOMRIGHT", -12, 10)
    SP:SetScript("OnShow", ScoutRender)
    return SP
end

local function ScoutSharing(host)
    local P = CreateFrame("Frame", nil, host)
    P:SetAllPoints()
    local h = K.Text(P, "GameFontNormalLarge", "|cff00c7ffData sharing|r"); h:SetPoint("TOPLEFT", 16, -12)
    P.status = K.Text(P, "GameFontHighlight"); P.status:SetPoint("TOPLEFT", 16, -42); P.status:SetWidth(720)
    local t = K.Text(P, "GameFontDisableSmall", "VoidScout's scores come from your own fights. Allowed: fight summaries and the players you meet are kept and the VoidScout program uploads them to voidscout.io, anonymously, for everyone's percentiles. Local only: the addon still works from what it ships with, but keeps and uploads nothing new.")
    t:SetPoint("TOPLEFT", 16, -70); t:SetWidth(720); t:SetSpacing(3)
    local function paint()
        local on = VoidScout_IsUploadAllowed and VoidScout_IsUploadAllowed()
        P.status:SetText("Right now: " .. (on and "|cff33ff33uploads allowed|r" or "|cffffd200local only (nothing uploaded)|r"))
    end
    local a = K.Button(P, "Allow uploads", 130, function() if VoidScout_SetConsent_OptIn then VoidScout_SetConsent_OptIn() end; paint() end)
    a:SetPoint("TOPLEFT", 16, -124)
    local l = K.Button(P, "Local only", 130, function() if VoidScout_SetConsent_OptOut then VoidScout_SetConsent_OptOut() end; paint() end)
    l:SetPoint("LEFT", a, "RIGHT", 8, 0)
    local d = K.Button(P, "What gets uploaded...", 170, function() if VoidScout_ShowConsentDialog then VoidScout_ShowConsentDialog() end end)
    d:SetPoint("LEFT", l, "RIGHT", 8, 0)
    P:SetScript("OnShow", paint)
    return P
end

ns.RegisterPage("VoidScout", {
    available = function() return VC() ~= nil and VC().Lookup ~= nil end,
    sections = {
        { key = "players", label = "Players", build = ScoutBuild },
        { key = "sharing", label = "Data sharing", build = ScoutSharing },
    },
})
