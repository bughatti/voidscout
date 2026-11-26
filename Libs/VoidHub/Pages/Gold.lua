----------------------------------------------------------------------
-- VoidHub pages for "Gear and gold":
--   VoidGear  Your gear / Dungeon upgrades / Quest upgrades (WoW Forever): VoidGear's Forever panel, the same
--             lines from VoidGear.ForeverUI.Hub.View(kind)
--   VoidBags  Gold per hour (this session, best zones, recent sessions: VoidBags.Income + its Hub store) and
--             Settings (VoidBags' settings window). The bag window itself stays: its item buttons lock in combat.
--   VoidAH    Prices: the "Auction House, from your last visit" window (VoidUI.AH's price data, shopping list).
--             The Auction House window itself stays at the AH.
----------------------------------------------------------------------
local ns = _G.VoidHubWin
if not ns or ns.skip then return end   -- another Void addon's copy of VoidHub runs the window
local K = ns.Kit

local function rowList(parent, h, make, fill)
    local L = K.List(parent, h, function(r)
        r:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        r:GetHighlightTexture():SetVertexColor(K.A[1], K.A[2], K.A[3], 0.10)
        make(r)
    end, fill)
    return L
end

----------------------------------------------------------------------
-- VoidGear
----------------------------------------------------------------------
local function GH() local g = _G.VoidGear; return g and g.ForeverUI and g.ForeverUI.Hub end
local gearPanels = {}

local function GearRender(P)
    if not (P and P:IsVisible()) then return end
    local H = GH()
    if not H then return end
    local ok, lines, head, note = pcall(H.View, P.kind)
    if not ok then lines, head, note = { { text = "|cffff5555" .. tostring(lines) .. "|r" } }, "", "" end
    P.head:SetText(head or "")
    P.note:SetText(note or "")
    P.list:SetData(lines or {}, true)
end

local function GearBuild(kind)
    return function(host)
        local P = CreateFrame("Frame", nil, host)
        P:SetAllPoints()
        P.kind = kind
        P.head = K.Text(P, "GameFontHighlight"); P.head:SetPoint("TOPLEFT", 16, -12); P.head:SetPoint("RIGHT", -16, 0)
        P.note = K.Text(P, "GameFontDisableSmall"); P.note:SetPoint("TOPLEFT", P.head, "BOTTOMLEFT", 0, -6); P.note:SetPoint("RIGHT", -16, 0)
        P.list = rowList(P, 22, function(r)
            r.text = K.Text(r, "GameFontHighlight"); r.text:SetPoint("LEFT", 6, 0); r.text:SetPoint("RIGHT", -6, 0); r.text:SetWordWrap(false)
            r:SetScript("OnEnter", function(s)
                local l = s.item
                if not (l and l.link) then return end
                GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(l.link)
                if l.hint then GameTooltip:AddLine(l.hint, 0, 0.78, 1, true) end
                GameTooltip:Show()
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r:SetScript("OnClick", function(s)
                local l = s.item
                if not l then return end
                if IsModifiedClick("CHATLINK") and l.link then K.InsertLink(l.link) return end
                local vq = _G.VoidQuest
                if l.qid and vq and vq.Forever and vq.Forever.Go then vq.Forever:Go(l.qid) end
            end)
        end, function(r, l) r.text:SetText(l.text or "") end)
        P.list:SetPoint("TOPLEFT", P.note, "BOTTOMLEFT", -6, -10); P.list:SetPoint("BOTTOMRIGHT", -12, 10)
        P:SetScript("OnShow", GearRender)
        -- item data arriving / gear or level changing: redraw while it's open (batched; none while closed)
        local queued
        K.LiveEvents(P, { "GET_ITEM_INFO_RECEIVED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "QUEST_TURNED_IN", "QUEST_DATA_LOAD_RESULT" }, function(e)
            if queued then return end
            local H = GH()
            if e == "GET_ITEM_INFO_RECEIVED" and not (H and H.Loading()) then return end
            queued = true
            C_Timer.After(0.6, function() queued = false; if P:IsVisible() then GearRender(P) end end)
        end, 0)
        gearPanels[#gearPanels + 1] = P
        return P
    end
end

ns.RegisterPage("VoidGear", {
    available = function() return GH() ~= nil end,
    sections = {
        { key = "gear", label = "Your gear", build = GearBuild("gear") },
        { key = "dungeons", label = "Dungeon upgrades", build = GearBuild("dungeons") },
        { key = "quests", label = "Quest upgrades", build = GearBuild("quests") },
    },
})

----------------------------------------------------------------------
-- VoidBags: Gold per hour
----------------------------------------------------------------------
local function INC() local b = _G.VoidBags; return b and b.Income end
local IP

local function IncomeRender()
    if not (IP and IP:IsVisible()) then return end
    local I = INC()
    if not (I and I.Hub) then return end
    local H, M = I.Hub, I.Money
    local s = I:Session()
    -- this session
    local lines = {}
    if s.worth <= 0 and s.active <= 0 then
        lines[1] = "|cff8c8c9eNothing earned yet. Loot, coin and quest rewards count from here.|r"
    else
        local rw, rc = I.Rate(s.worth, s.active), I.Rate(s.cash, s.active)
        lines[#lines + 1] = ("Worth if you sell it all   |cffffffff%s|r%s"):format(M(s.worth), rw and ("  |cff33ff33(%s/hr)|r"):format(M(rw)) or "")
        lines[#lines + 1] = ("Cash: coin + vendor price  |cffffffff%s|r%s"):format(M(s.cash), rc and ("  (%s/hr)"):format(M(rc)) or "")
        lines[#lines + 1] = ("Time playing  |cffffffff%d min|r"):format(H.Minutes(s.active))
        local srcs = {}
        for _, d in ipairs(I.SOURCES or {}) do if (s.src[d.key] or 0) > 0 then srcs[#srcs + 1] = d end end
        table.sort(srcs, function(a, b) return s.src[a.key] > s.src[b.key] end)
        if #srcs > 0 then
            lines[#lines + 1] = " "
            for _, d in ipairs(srcs) do lines[#lines + 1] = ("%s  |cffffffff%s|r"):format(d.label, M(s.src[d.key])) end
        end
        if (s.listed or 0) > 0 then
            lines[#lines + 1] = " "
            lines[#lines + 1] = ("|cff8c8c9e%s of it is priced from listings: not seen selling yet.|r"):format(M(s.listed))
        end
    end
    IP.session:SetText(table.concat(lines, "\n"))
    -- what it came from (items)
    local items = {}
    for id, row in pairs(s.items or {}) do if row.w > 0 then items[#items + 1] = { id = id, row = row } end end
    table.sort(items, function(a, b) return a.row.w > b.row.w end)
    IP.items:SetData(items, true)
    -- best zones
    local zones = {}
    for m, z in pairs(H.Store().zones) do
        local rate = I.Rate(z.v, z.a)
        if rate and z.a >= 600 and z.v > 0 then zones[#zones + 1] = { m = m, rate = rate, z = z } end
    end
    table.sort(zones, function(a, b) return a.rate > b.rate end)
    IP.zones:SetData(zones, true)
    IP.zonesEmpty:SetShown(#zones == 0)
    -- recent sessions
    I:Session()
    IP.sessions:SetData(H.Store().sessions, true)
    IP.sessionsEmpty:SetShown(#H.Store().sessions == 0)
    IP.box:SetLabel(I:Shown() and "Hide the box" or "Show the box")
end

local function IncomeBuild(host)
    IP = CreateFrame("Frame", nil, host)
    IP:SetAllPoints()
    local h1 = K.Text(IP, "GameFontNormal", "This session"); h1:SetPoint("TOPLEFT", 16, -12)
    IP.session = K.Text(IP, "GameFontHighlight"); IP.session:SetPoint("TOPLEFT", h1, "BOTTOMLEFT", 0, -8); IP.session:SetWidth(330)
    IP.session:SetSpacing(3)
    local h2 = K.Text(IP, "GameFontNormal", "What it came from"); h2:SetPoint("TOPLEFT", 16, -210)
    IP.items = rowList(IP, 20, function(r)
        r.text = K.Text(r, "GameFontHighlightSmall"); r.text:SetPoint("LEFT", 4, 0); r.text:SetPoint("RIGHT", -110, 0); r.text:SetWordWrap(false)
        r.val = K.Text(r, "GameFontHighlightSmall"); r.val:SetPoint("RIGHT", -4, 0)
        r:SetScript("OnEnter", function(s) if s.item then GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(s.item.id); GameTooltip:Show() end end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end, function(r, it)
        local I = INC()
        r.text:SetText(("%s x%d"):format(it.row.link or ("item " .. it.id), it.row.n or 1))
        r.val:SetText(I.Money(it.row.w) .. "  " .. (I.Hub.How[it.row.how] or ""))
    end)
    IP.items:SetPoint("TOPLEFT", h2, "BOTTOMLEFT", -4, -6); IP.items:SetPoint("BOTTOMLEFT", 12, 44); IP.items:SetWidth(360)

    local h3 = K.Text(IP, "GameFontNormal", "Best gold per hour by zone  |cff888888(this character, 10+ min)|r"); h3:SetPoint("TOPLEFT", 410, -12)
    IP.zones = rowList(IP, 20, function(r)
        r.a = K.Text(r, "GameFontHighlight"); r.a:SetPoint("LEFT", 4, 0); r.a:SetWidth(170); r.a:SetWordWrap(false)
        r.b = K.Text(r, "GameFontHighlight"); r.b:SetPoint("LEFT", r.a, "RIGHT", 6, 0); r.b:SetWidth(110)
        r.c = K.Text(r, "GameFontDisableSmall"); r.c:SetPoint("LEFT", r.b, "RIGHT", 6, 0); r.c:SetPoint("RIGHT", -4, 0); r.c:SetWordWrap(false)
    end, function(r, z)
        local I = INC()
        local topK, topV
        for k, v in pairs(z.z.src or {}) do if not topV or v > topV then topK, topV = k, v end end
        r.a:SetText(I.Hub.MapName(z.m))
        r.b:SetText(I.Money(z.rate) .. "/hr")
        r.c:SetText(("%d min%s"):format(I.Hub.Minutes(z.z.a), topK and (", mostly " .. (I.Hub.SourceLabel[topK] or topK):lower()) or ""))
    end)
    IP.zones:SetPoint("TOPLEFT", h3, "BOTTOMLEFT", -4, -6); IP.zones:SetPoint("RIGHT", -12, 0); IP.zones:SetHeight(20 * 8)
    IP.zonesEmpty = K.Text(IP, "GameFontDisableSmall", "No zone has 10 minutes of play with income yet."); IP.zonesEmpty:SetPoint("TOPLEFT", h3, "BOTTOMLEFT", 0, -8)

    local h4 = K.Text(IP, "GameFontNormal", "Recent sessions"); h4:SetPoint("TOPLEFT", IP.zones, "BOTTOMLEFT", 4, -12)
    IP.sessions = rowList(IP, 20, function(r)
        r.a = K.Text(r, "GameFontHighlightSmall"); r.a:SetPoint("LEFT", 4, 0); r.a:SetWidth(110)
        r.b = K.Text(r, "GameFontHighlight"); r.b:SetPoint("LEFT", r.a, "RIGHT", 6, 0); r.b:SetWidth(180)
        r.c = K.Text(r, "GameFontDisableSmall"); r.c:SetPoint("LEFT", r.b, "RIGHT", 6, 0); r.c:SetPoint("RIGHT", -4, 0); r.c:SetWordWrap(false)
    end, function(r, s)
        local I = INC()
        local rate = I.Rate(s.worth, s.active)
        r.a:SetText(date("%b %d %H:%M", s.start))
        r.b:SetText(I.Money(s.worth) .. (rate and ("  (" .. I.Money(rate) .. "/hr)") or ""))
        r.c:SetText(("%d min, %s"):format(I.Hub.Minutes(s.active), I.Hub.MapName(s.map)))
    end)
    IP.sessions:SetPoint("TOPLEFT", h4, "BOTTOMLEFT", -4, -6); IP.sessions:SetPoint("BOTTOMRIGHT", -12, 44)
    IP.sessionsEmpty = K.Text(IP, "GameFontDisableSmall", "No finished sessions yet: one ends with \"Start a new session\", or 30 minutes after you last earned anything.")
    IP.sessionsEmpty:SetPoint("TOPLEFT", h4, "BOTTOMLEFT", 0, -8); IP.sessionsEmpty:SetWidth(560)

    local new = K.Button(IP, "Start a new session", 150, function() INC():Reset(); IncomeRender() end)
    new:SetPoint("BOTTOMLEFT", 16, 12)
    IP.box = K.Button(IP, "Show the box", 120, function() local I = INC(); I:SetShown(not I:Shown()); IncomeRender() end)
    IP.box:SetPoint("LEFT", new, "RIGHT", 8, 0)
    IP:SetScript("OnShow", IncomeRender)
    IP.t = 0
    IP:SetScript("OnUpdate", function(s, dt) s.t = s.t + dt; if s.t >= 2 then s.t = 0; IncomeRender() end end)
    return IP
end

local function BagsSettings(host)
    local VB = _G.VoidBags
    local function cfg(k) return function() return VB:GetConfig(k) end, function(v) VoidBagsDB.config[k] = v end end
    local function check(label, k, tip) local g, s = cfg(k); return { "check", label, g, s, tip } end
    local capG, capS = cfg("repairCostCap")
    local I = INC()
    local items = {
        check("Auto-sell junk at vendor", "autoSellJunk", "Sell grey-quality items automatically when a vendor opens."),
        check("Auto-repair gear at vendor", "autoRepair", "Repair all gear automatically when you visit a repair vendor."),
        check("Use guild bank for repairs", "useGuildRepair", "Try guild bank funds first; fall back to your gold if unavailable."),
        { "number", "Personal repair cap (gold, 0 = none)", capG, capS, "Never auto-repair for more than this; press Enter to save." },
        { "button", "Repair now", function() VB:DoAutoRepair() end, "At a repair vendor." },
        { "button", "Sell junk", function() VB:DoSellJunk() end, "At a vendor." },
    }
    if I then items[#items + 1] = { "check", "Gold per hour box on screen", function() return I:Shown() end, function(on) I:SetShown(on) end } end
    return K.SettingsPage(host, {
        { title = "Vendor", items = items },
        { title = "Item markers", items = {
            { "note", "|cff00ff00L|r  Learnable: appearance / recipe / mount / pet / toy", h = 18 },
            { "note", "|cff00ff00C|r  Craftable: a material for a profession you know", h = 18 },
            { "note", "|cff00ff00T|r  Trash: vendor junk, sell for gold", h = 18 },
            { "note", "|cff00ff00^|r  Upgrade: higher item level than what you wear", h = 18 },
            { "note", "|cff00ff00$|r  Value: worth more on the Auction House than at a vendor", h = 18 },
        } },
    }, 360)
end

----------------------------------------------------------------------
-- VoidBags: your bank, the warband bank and other characters' banks, as they were when last opened (its bank
-- viewer, read-only): same saved data (VoidBagsDB.characters[..].bank / .warband), merged stacks, grouped by item type
-- (recipes first), search by name. Shift-click links an item.
----------------------------------------------------------------------
local BV
local BANK_ORDER = { [9] = 1, [7] = 2, [0] = 3, [5] = 4, [3] = 5, [4] = 6, [2] = 7, [1] = 8, [12] = 9, [15] = 10 }
local ICON = 34

local function bankAgo(t)
    if not t then return "never" end
    local s = time() - t
    if s < 3600 then return math.max(1, math.floor(s / 60)) .. " min ago" end
    if s < 86400 then return math.floor(s / 3600) .. " h ago" end
    return math.floor(s / 86400) .. " days ago"
end

local function BankRender()
    if not (BV and BV:IsVisible()) then return end
    local VB = _G.VoidBags
    local me = VB:GetPlayerKey()
    -- left: the banks there are
    local srcs = { { key = nil, label = "Your bank" } }
    if VoidBagsDB and VoidBagsDB.warband then srcs[#srcs + 1] = { key = "warband", label = "Warband bank" } end
    local others = {}
    for key, data in pairs(VoidBagsDB and VoidBagsDB.characters or {}) do
        if key ~= me and data.bank and #data.bank > 0 then others[#others + 1] = { key = key, label = VB:CharacterLabel(key, data) } end
    end
    table.sort(others, function(a, b) return a.label < b.label end)
    if #others > 0 then srcs[#srcs + 1] = { header = "Other characters" } end
    for _, o in ipairs(others) do srcs[#srcs + 1] = o end
    BV.srcs:SetData(srcs, true)
    -- right: the chosen one
    local items, when, label
    if BV.which == "warband" then
        local w = VoidBagsDB and VoidBagsDB.warband
        items, when, label = w and w.items or {}, w and w.timestamp, "Warband bank"
    else
        local key = BV.which or me
        local rec = VoidBagsDB and VoidBagsDB.characters and VoidBagsDB.characters[key]
        local name = rec and VB:CharacterLabel(key, rec) or "?"
        items, when, label = rec and rec.bank or {}, rec and rec.bankTime, (name:match("^[^-]+") or name) .. "'s bank"
    end
    BV.title:SetText(("|cff00c7ff%s|r  |cff8c8c9e%s|r"):format(label, when and ("as of " .. bankAgo(when)) or "bank not seen yet: open it once on this character"))
    local q = (BV.q or ""):lower()
    local merged, order = {}, {}
    for _, it in ipairs(items) do
        if it.id then
            local name = it.name or C_Item.GetItemNameByID(it.id) or ""
            if q == "" or name:lower():find(q, 1, true) then
                local m = merged[it.id]
                if not m then m = { id = it.id, link = it.link, name = name, quality = it.quality, count = 0 }; merged[it.id] = m; order[#order + 1] = m end
                m.count = m.count + (it.count or 1)
            end
        end
    end
    local groups, gorder = {}, {}
    for _, m in ipairs(order) do
        local classID = select(6, C_Item.GetItemInfoInstant(m.id)) or 99
        local g = groups[classID]
        if not g then g = { id = classID, name = C_Item.GetItemClassInfo(classID) or "Other", list = {} }; groups[classID] = g; gorder[#gorder + 1] = g end
        table.insert(g.list, m)
    end
    table.sort(gorder, function(a, b) return (BANK_ORDER[a.id] or 50) < (BANK_ORDER[b.id] or 50) end)
    local per = math.max(4, math.floor(((BV.grid:GetWidth() or 600) - 12) / (ICON + 4)))
    local rows = {}
    for _, g in ipairs(gorder) do
        rows[#rows + 1] = { head = ("%s |cff8c8c9e(%d)|r"):format(g.name, #g.list) }
        table.sort(g.list, function(a, b) return a.name < b.name end)
        for i = 1, #g.list, per do
            local r = {}
            for k = i, math.min(#g.list, i + per - 1) do r[#r + 1] = g.list[k] end
            rows[#rows + 1] = { icons = r }
        end
    end
    BV.grid:SetData(rows, true)
    BV.empty:SetShown(#rows == 0)
    BV.empty:SetText(when and (q ~= "" and "Nothing matches." or "Empty.") or "Not seen yet: open this bank once at a banker and VoidBags remembers it.")
end

local function BankBuild(host)
    BV = CreateFrame("Frame", nil, host)
    BV:SetAllPoints()
    local left = CreateFrame("Frame", nil, BV)
    left:SetPoint("TOPLEFT", 8, -8); left:SetPoint("BOTTOMLEFT", 8, 8); left:SetWidth(210)
    K.Box(left, { 0.04, 0.04, 0.06, 1 }, K.EDGE)
    BV.srcs = K.List(left, 20, function(b)
        b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        b:GetHighlightTexture():SetVertexColor(K.A[1], K.A[2], K.A[3], 0.12)
        b.text = K.Text(b, "GameFontHighlightSmall"); b.text:SetPoint("LEFT", 4, 0); b.text:SetPoint("RIGHT", -4, 0); b.text:SetWordWrap(false)
        b:SetScript("OnClick", function(s) if s.item and not s.item.header then BV.which = s.item.key; BV.grid.off = 0; BankRender() end end)
    end, function(b, s)
        if s.header then b.text:SetText("|cffffd200" .. s.header .. "|r"); b:EnableMouse(false) return end
        b:EnableMouse(true)
        b.text:SetText((BV.which == s.key and "|cff00c7ff" or "|cffffffff") .. s.label .. "|r")
    end)
    BV.srcs:SetPoint("TOPLEFT", 6, -6); BV.srcs:SetPoint("BOTTOMRIGHT", -4, 6)
    BV.title = K.Text(BV, "GameFontNormalLarge"); BV.title:SetPoint("TOPLEFT", left, "TOPRIGHT", 14, -4)
    BV.search = K.Search(BV, 200, "Search", function(t) BV.q = t; BankRender() end)
    BV.search:SetPoint("TOPRIGHT", -12, -8)
    BV.grid = K.List(BV, ICON + 4, function(r)
        r.head = K.Text(r, "GameFontNormal"); r.head:SetPoint("LEFT", 2, 0)
        r.btns = {}
    end, function(r, row)
        for _, b in ipairs(r.btns) do b:Hide() end
        if row.head then r.head:SetText("|cff00c7ff" .. row.head .. "|r"); r.head:Show() return end
        r.head:Hide()
        for i, m in ipairs(row.icons) do
            local b = r.btns[i]
            if not b then
                b = CreateFrame("Button", nil, r)
                b:SetSize(ICON, ICON)
                b.border = b:CreateTexture(nil, "BACKGROUND"); b.border:SetPoint("TOPLEFT", -1, 1); b.border:SetPoint("BOTTOMRIGHT", 1, -1)
                b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints()
                b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal"); b.count:SetPoint("BOTTOMRIGHT", -2, 2)
                b:SetScript("OnEnter", function(s)
                    if not s.d then return end
                    GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
                    if s.d.link then GameTooltip:SetHyperlink(s.d.link) else GameTooltip:SetItemByID(s.d.id) end
                    GameTooltip:Show()
                end)
                b:SetScript("OnLeave", function() GameTooltip:Hide() end)
                b:SetScript("OnClick", function(s) if s.d and s.d.link and IsModifiedClick("CHATLINK") then K.InsertLink(s.d.link) end end)
                r.btns[i] = b
            end
            b.d = m
            b:SetPoint("LEFT", (i - 1) * (ICON + 4) + 2, 0)
            b.icon:SetTexture(C_Item.GetItemIconByID(m.id))
            b.count:SetText(m.count > 1 and m.count or "")
            local c = m.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[m.quality]
            if c and m.quality >= 2 then b.border:SetColorTexture(c.r, c.g, c.b, 0.7) else b.border:SetColorTexture(0, 0, 0, 0) end
            b:Show()
        end
    end)
    BV.grid:SetPoint("TOPLEFT", left, "TOPRIGHT", 12, -36); BV.grid:SetPoint("BOTTOMRIGHT", -12, 26)
    BV.empty = K.Text(BV, "GameFontDisableSmall"); BV.empty:SetPoint("TOPLEFT", BV.grid, "TOPLEFT", 4, -6)
    local foot = K.Text(BV, "GameFontDisableSmall", "Read-only, as it was the last time you opened it. Shift-click links an item.")
    foot:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 14, 6)
    BV:SetScript("OnShow", BankRender)
    return BV
end

ns.RegisterPage("VoidBags", {
    available = function() return _G.VoidBags ~= nil and _G.VoidBags.GetConfig ~= nil end,
    sections = {
        { key = "income", label = "Gold per hour", build = IncomeBuild, available = function() local I = INC(); return I and I.Hub end },
        { key = "bank", label = "Bank and alts", build = BankBuild,
          available = function() local v = _G.VoidBags; return v and v.GetPlayerKey and v.CharacterLabel end },
        { key = "settings", label = "Settings", build = BagsSettings },
    },
})

----------------------------------------------------------------------
-- VoidAH: prices from your last visit (Anywhere.lua's window)
----------------------------------------------------------------------
local function AH() local a = _G.VoidUI and _G.VoidUI.AH; return (a and a.AllPrices) and a or nil end
local CATS = { { "All" }, { "Trade Goods", 7 }, { "Consumables", 0 }, { "Recipes", 9 }, { "Armor", 4 }, { "Weapons", 2 }, { "Other", "other" } }
local KNOWN_CLASS = { [7] = true, [0] = true, [9] = true, [4] = true, [2] = true }
local AP
local st = { cat = 1, sort = "name", desc = false, onlyList = false, q = "" }

local function money(c) return (_G.VoidUI and VoidUI.FormatMoney) and VoidUI:FormatMoney(c) or tostring(c) end
local function ago(t)
    if not t or t <= 0 then return "?" end
    local s = time() - t
    if s < 3600 then return math.max(1, math.floor(s / 60)) .. "m" end
    if s < 86400 then return math.floor(s / 3600) .. "h" end
    return math.floor(s / 86400) .. "d"
end

local function PricesRender(keep)
    if not (AP and AP:IsVisible()) then return end
    local a = AH()
    local db = a and a:AllPrices() or {}
    local q = (st.q or ""):lower()
    local want = CATS[st.cat][2]
    local out, nameless, newest = {}, 0, 0
    for key, e in pairs(db) do
        local id = tonumber(key)
        if id and type(e) == "table" and (e.m or 0) > 0 then
            if (e.t or 0) > newest then newest = e.t end
            local name = e.nm or C_Item.GetItemNameByID(id)
            if not name then nameless = nameless + 1 end
            local ok = name and (q == "" or name:lower():find(q, 1, true))
            if ok and want ~= nil then
                local classID = select(6, C_Item.GetItemInfoInstant(id))
                if want == "other" then ok = not KNOWN_CLASS[classID] else ok = classID == want end
            end
            if ok and st.onlyList then ok = a.ShoppingIndex and a:ShoppingIndex(id) end
            if ok then out[#out + 1] = { id = id, name = name, m = e.m, t = e.t or 0, q = e.q, n = e.n } end
        end
    end
    local k, desc = st.sort, st.desc
    table.sort(out, function(x, y)
        local u, v = x[k], y[k]
        if k == "name" then u, v = x.name:lower(), y.name:lower() end
        if u == v or u == nil or v == nil then
            if (u == nil) ~= (v == nil) then return v == nil end
            if x.name ~= y.name then return x.name < y.name end
            return x.id < y.id
        end
        if desc then return u > v end
        return u < v
    end)
    AP.cats:Select(st.cat)
    K.Recolor(AP.only, st.onlyList and { 0.04, 0.18, 0.24, 1 } or K.ROW, nil)
    AP.list:SetData(out, keep)
    AP.sum:SetText(a and ("%d items  ·  last price seen %s ago  ·  read-only: buy at the Auction House%s"):format(#out, ago(newest),
        nameless > 0 and ("  ·  |cff888888%d more next time (names still loading)|r"):format(nameless) or "")
        or "No prices yet: open the Auction House once with VoidAH.")
end

local function PricesBuild(host)
    AP = CreateFrame("Frame", nil, host)
    AP:SetAllPoints()
    AP.search = K.Search(AP, 240, "Search items", function(t) st.q = t; PricesRender() end)
    AP.search:SetPoint("TOPLEFT", 16, -12)
    AP.only = K.Button(AP, "My list only", 100, function() st.onlyList = not st.onlyList; PricesRender() end)
    AP.only:SetPoint("LEFT", AP.search, "RIGHT", 10, 0)
    local defs = {}
    for i, c in ipairs(CATS) do defs[i] = { i, c[1] } end
    AP.cats = K.Segments(AP, defs, 96, function(i) st.cat = i; PricesRender() end)
    AP.cats[1]:SetPoint("TOPLEFT", 16, -42)
    -- column headers: click to sort
    local function head(label, key, x, w, justify)
        local h = CreateFrame("Button", nil, AP)
        h:SetSize(w, 16); h:SetPoint("TOPLEFT", x, -74)
        h.t = K.Text(h, "GameFontNormalSmall", label); h.t:SetAllPoints(); h.t:SetJustifyH(justify or "LEFT")
        h:SetScript("OnClick", function()
            if st.sort == key then st.desc = not st.desc else st.sort, st.desc = key, key ~= "name" end
            PricesRender()
        end)
    end
    head("Item", "name", 44, 300)
    head("Price", "m", 360, 140, "RIGHT")
    head("Listed", "q", 510, 100, "RIGHT")
    head("Seen", "t", 620, 60, "RIGHT")
    AP.list = rowList(AP, 22, function(r)
        r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 8, 0)
        r.name = K.Text(r, "GameFontHighlight"); r.name:SetPoint("LEFT", 30, 0); r.name:SetWidth(300); r.name:SetWordWrap(false)
        r.price = K.Text(r, "GameFontHighlight"); r.price:SetPoint("RIGHT", r, "LEFT", 488, 0); r.price:SetJustifyH("RIGHT")
        r.listed = K.Text(r, "GameFontHighlightSmall"); r.listed:SetPoint("RIGHT", r, "LEFT", 598, 0); r.listed:SetJustifyH("RIGHT")
        r.age = K.Text(r, "GameFontHighlightSmall"); r.age:SetPoint("RIGHT", r, "LEFT", 668, 0); r.age:SetJustifyH("RIGHT")
        r.add = K.Button(r, "+ List", 70, function(b)
            local d, a = b:GetParent().item, AH()
            if d and a then a:ToggleShopping(d.id, d.name); PricesRender(true) end
        end)
        r.add:SetPoint("RIGHT", -4, 0)
        r:SetScript("OnClick", function(s)
            if s.item and IsModifiedClick("CHATLINK") then
                local _, link = C_Item.GetItemInfo(s.item.id)
                if link then K.InsertLink(link) end
            end
        end)
        r:SetScript("OnEnter", function(s)
            local d, a = s.item, AH()
            if not (d and a) then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(d.id)
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("|cff00c7ffVoidAH|r lowest buyout", money(d.m), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("seen", ago(d.t) .. " ago", 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
            local mean = a:GetMarketMean(d.id, 7)
            if mean and mean > 0 then GameTooltip:AddDoubleLine("7-day average", money(math.floor(mean)), 0.8, 0.8, 0.8, 1, 1, 1) end
            if d.q then GameTooltip:AddDoubleLine("listed", d.n and ("%d in %d auctions"):format(d.q, d.n) or tostring(d.q), 0.8, 0.8, 0.8, 1, 1, 1) end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end, function(r, d)
        local a = AH()
        local q = C_Item.GetItemQualityByID(d.id)
        local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        r.icon:SetTexture(C_Item.GetItemIconByID(d.id))
        r.name:SetText((c and c.hex or "|cffffffff") .. d.name .. "|r")
        local mean = a and a:GetMarketMean(d.id, 7)
        local arrow = ""
        if mean and mean > 0 then
            if d.m < mean * 0.9 then arrow = " |cff33ff33v|r" elseif d.m > mean * 1.1 then arrow = " |cffff5555^|r" end
        end
        r.price:SetText(money(d.m) .. arrow)
        r.listed:SetText(d.q and (d.n and ("%d in %d"):format(d.q, d.n) or tostring(d.q)) or "|cff666666-|r")
        r.age:SetText(ago(d.t))
        local on = a and a.ShoppingIndex and a:ShoppingIndex(d.id)
        r.add:SetLabel(on and "|cff33ff33On list|r" or "+ List")
    end)
    AP.list:SetPoint("TOPLEFT", 12, -94); AP.list:SetPoint("BOTTOMRIGHT", -12, 30)
    AP.sum = K.Text(AP, "GameFontDisableSmall"); AP.sum:SetPoint("BOTTOMLEFT", 16, 10)
    AP:SetScript("OnShow", function() PricesRender() end)
    return AP
end

ns.RegisterPage("VoidAH", {
    available = function() return AH() ~= nil end,
    sections = { { key = "prices", label = "Prices (last visit)", build = PricesBuild } },
})
