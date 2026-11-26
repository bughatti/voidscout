----------------------------------------------------------------------
-- VoidHub page: VoidQuest > Quest Book (WoW Forever).
-- The same quests as VoidQuest's own Quest Book window: everything comes from VoidQuest.Book.Hub
-- (the book's own Build / Classify / search / sort), only the drawing is the hub's.
--   left   the categories (Summary, zones per continent with done / total, Rewards: Bags)
--   top    Only what I can use, the search, the filter (All / Can do / In log / Later / Done)
--   right  the quests: status, [level] title, zone and what's needed first, reward icons
-- Old window stays as it is while we check the two show the same (the user, 2026-11-24).
----------------------------------------------------------------------
local ns = _G.VoidHubWin
if not ns or ns.skip then return end   -- another Void addon's copy of VoidHub runs the window
local K = ns.Kit

local function VQ() return _G.VoidQuest end
local function HB() local q = VQ(); return q and q.Book and q.Book.Hub end
local function FZ() local q = VQ(); return q and q.Forever end
local function safe(fn, ...) if not fn then return nil end local ok, a, b, c = pcall(fn, ...) if ok then return a, b, c end end

local CAT_W, CAT_ROW, ROW_H, MAX_ICONS = 210, 18, 30, 6
local STATUS_ICON = {
    done = "Interface\\RaidFrame\\ReadyCheck-Ready",
    log = "Interface\\GossipFrame\\ActiveQuestIcon",
    can = "Interface\\GossipFrame\\AvailableQuestIcon",
    later = "Interface\\GossipFrame\\AvailableQuestIcon",
}
local STATUS_TEXT = { done = "|cff66ff66done|r", log = "|cffffd200in your log|r", can = "|cffffffffcan do now|r",
    later = "|cff888888later|r" }

-- the page's own view (separate from the old book's, so using one never changes the other)
local V = { cat = "summary", query = nil, filter = "all" }
local P   -- the panel

local function usable() return not (VQ() and VQ().Get and VQ():Get("bookUsableOnly") == false) end

----------------------------------------------------------------------
-- rows
----------------------------------------------------------------------
local function MakeCat(b)
    b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    b:GetHighlightTexture():SetVertexColor(K.A[1], K.A[2], K.A[3], 0.12)
    b.text = K.Text(b, "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 2, 1); b.text:SetPoint("RIGHT", -46, 0); b.text:SetWordWrap(false)
    b.count = K.Text(b, "GameFontDisableSmall"); b.count:SetPoint("RIGHT", -2, 1)
    b.bar = CreateFrame("StatusBar", nil, b)
    b.bar:SetPoint("BOTTOMLEFT", 10, 1); b.bar:SetPoint("BOTTOMRIGHT", -2, 1); b.bar:SetHeight(2)
    b.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    b.bar:SetStatusBarColor(K.A[1], K.A[2], K.A[3], 0.7)
    b:SetScript("OnClick", function(s)
        local c = s.item
        if not (c and c.key) then return end
        V.cat = c.key
        if V.query then P.search:SetText("") end   -- clears the search (and redraws)
        P.Render(true)
    end)
end

local function FillCat(b, c)
    local H = HB()
    if c.header then
        b.text:SetText("|cffffd200" .. c.header .. "|r"); b.count:SetText(""); b.bar:Hide()
        b:EnableMouse(false)
        return
    end
    b:EnableMouse(true)
    local sel = (not V.query) and V.cat == c.key
    b.text:SetText((sel and "|cff00c7ff" or "|cffffffff") .. "  " .. c.label .. "|r")
    if c.list and H then
        local cc = H.Counts(c.list)
        b.count:SetText(("%d/%d"):format(cc.done, cc.all))
        b.bar:SetMinMaxValues(0, math.max(1, cc.all)); b.bar:SetValue(cc.done); b.bar:Show()
    else
        b.count:SetText(""); b.bar:Hide()
    end
end

local function MakeRow(row)
    row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    row:GetHighlightTexture():SetVertexColor(K.A[1], K.A[2], K.A[3], 0.10)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18); row.icon:SetPoint("LEFT", 4, 0)
    row.title = K.Text(row, "GameFontNormal")
    row.title:SetPoint("TOPLEFT", 28, -3); row.title:SetPoint("RIGHT", -(MAX_ICONS * 22 + 10), 0); row.title:SetWordWrap(false)
    row.sub = K.Text(row, "GameFontDisableSmall")
    row.sub:SetPoint("BOTTOMLEFT", 28, 3); row.sub:SetPoint("RIGHT", -(MAX_ICONS * 22 + 10), 0); row.sub:SetWordWrap(false)
    row.items = {}
    for k = 1, MAX_ICONS do
        local b = CreateFrame("Button", nil, row)
        b:SetSize(20, 20)
        b:SetPoint("RIGHT", row, "RIGHT", -4 - (MAX_ICONS - k) * 22, 0)
        b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetAllPoints(); b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b:SetScript("OnEnter", function(s)
            if not s.id then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(s.id); GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function(s)
            local H = HB()
            local link = s.id and H and H.ItemLinkOf(s.id)
            if not link then return end
            if IsModifiedClick("CHATLINK") then K.InsertLink(link)
            elseif IsModifiedClick("DRESSUP") then DressUpItemLink(link) end
        end)
        row.items[k] = b
    end
    row:SetScript("OnClick", function(s)
        local e, q = s.item, VQ()
        if not (e and q) then return end
        if e.drop then
            local H = HB()
            local link = IsModifiedClick("CHATLINK") and H and H.ItemLinkOf(e.item)
            if link then K.InsertLink(link) elseif q.Book.GoDrop then q.Book.GoDrop(e) end
        elseif e.vendor then
            if VoidGPS and VoidGPS.Goods then VoidGPS.Goods:GoVendor(e.v, e.name) end
        elseif e.id and FZ() then
            FZ():Go(e.id)
        end
    end)
    row:SetScript("OnEnter", function(s)
        local e = s.item
        if not e or e.header then return end
        if e.drop then
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(e.item)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(("Drops in %s (%s)"):format(e.dungeon, e.lv or "?"), 0.6, 1, 0.6)
            GameTooltip:AddLine(e.bosses > 1 and ("from " .. table.concat(e.names, ", ")) or ("from " .. e.boss), 1, 1, 1, true)
            GameTooltip:AddLine("Click: the way to the dungeon entrance · Shift-click: link it", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        elseif e.vendor then
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(e.item)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Sold by " .. e.v.name, 0.6, 1, 0.6)
            GameTooltip:AddLine("Click: the way to the vendor (VoidGPS)", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        elseif FZ() and FZ().QuestTooltip then
            FZ().QuestTooltip(s, e.id)
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function setIcons(row, ids)
    for k = 1, MAX_ICONS do
        local b, id = row.items[k], ids[k]
        if id then
            b.id = id
            b.tex:SetTexture(safe(C_Item.GetItemIconByID, id) or 134400)
            b:Show()
        else
            b.id = nil; b:Hide()
        end
    end
end

local function FillRow(row, e)
    local H, F, q = HB(), FZ(), VQ()
    if e.header then
        row.icon:Hide(); setIcons(row, {})
        row.title:SetText("|cffffd200" .. e.header .. "|r"); row.sub:SetText("")
        return
    end
    row.icon:Show()
    if e.drop then
        local icon = safe(C_Item.GetItemIconByID, e.item) or 134400
        row.icon:SetTexture(icon); row.icon:SetDesaturated(e.status == "later")
        local qc = e.q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[e.q]
        local hex = (qc and qc.hex) or "|cffffffff"
        local lv = (e.need or 0) > 0 and ((e.est and "[~%d] " or "[%d] "):format(e.need)) or ""
        row.title:SetText((e.status == "later" and "|cff999999" or "|cffffffff") .. lv .. "|r" .. hex .. (e.name or ("item " .. e.item)) .. "|r")
        local bits = { ("%s, %s (%s)"):format(e.boss, e.dungeon, e.lv or "?") }
        local p = e.pct or 0
        if p > 0 then bits[#bits + 1] = (p >= 10 and ("%d%%"):format(math.floor(p + 0.5)) or ("%.1f%%"):format(p):gsub("%.0%%", "%%")) end
        if e.bosses > 1 then bits[#bits + 1] = ("+%d more boss%s"):format(e.bosses - 1, e.bosses > 2 and "es" or "") end
        if e.status == "later" then bits[#bits + 1] = STATUS_TEXT.later end
        local J = q and q.Book.VD and q.Book.VD()
        if not (J and J.EntranceOf and J:EntranceOf(e.dungeon)) then bits[#bits + 1] = "|cff888888entrance not known yet|r" end
        row.sub:SetText(table.concat(bits, "  ·  "))
        setIcons(row, { e.item })
        return
    end
    if e.vendor then
        row.icon:SetTexture(safe(C_Item.GetItemIconByID, e.item) or 134400); row.icon:SetDesaturated(false)
        local kind = e.family ~= 0 and (" |cff88ccff" .. H.BagKind(e.family) .. "|r") or ""
        row.title:SetText(("|cffffffff%s|r  |cff66ff66%d slots|r%s"):format(e.name, e.slots, kind))
        local coin = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or _G.GetCoinTextureString
        row.sub:SetText(("Sold by %s%s%s"):format(e.v.name, e.v.yards and (" (%d yd)"):format(e.v.yards) or "",
            (e.buy and e.buy > 0 and coin) and ("  " .. coin(e.buy)) or ""))
        setIcons(row, {})
        return
    end
    local st = e.status or H.Classify(e)
    local ready = st == "log" and safe(C_QuestLog.IsComplete, e.id) and true or false
    row.icon:SetTexture(STATUS_ICON[st])
    row.icon:SetDesaturated(st == "later" or e.low or (st == "log" and not ready))
    local color = (st == "done" or st == "later") and "|cff999999" or st == "log" and "|cffffd200" or "|cffffffff"
    local lv = (e.level or 0) > 0 and ("[" .. e.level .. "] ") or (e.est and ("[~" .. e.est .. "] ")) or ""
    local bag = e.bag and ("  |cff66ff66%d-slot %s|r"):format(e.bag[1], e.bag[2] ~= 0 and H.BagKind(e.bag[2]) or "bag") or ""
    row.title:SetText(color .. lv .. e.title .. "|r" .. bag)
    local bits = { e.zone, ready and "|cffffd200ready to turn in|r" or STATUS_TEXT[st] }
    if e.low then bits[#bits + 1] = "|cff888888low level|r" end
    if F and F.RewardPickOne and F:RewardPickOne(e.id) then bits[#bits + 1] = "pick one reward" end
    if (st == "can" or st == "later") and F then
        local ids
        if st == "later" and F.ChainSteps then local _; _, ids = F:ChainSteps(e.id) end
        local n = ids and #ids or 0
        if n > 0 then bits[#bits + 1] = ("|cffff8040%d quest%s first|r"):format(n, n > 1 and "s" or "") end
        local from = F.FromText and F:FromText(e.id)
        local tail = " in " .. (e.zone or "")
        if from and from:sub(-#tail) == tail then from = from:sub(1, -#tail - 1) end
        if from and from ~= "" and from ~= tail:sub(2) then bits[#bits + 1] = from end
    end
    row.sub:SetText(table.concat(bits, "  ·  "))
    -- rewards: bags first; when searching, the rewards that match first
    local ids, bags = {}, (q and q.ForeverBags) or {}
    local terms = V.query and H.Terms(V.query)
    local front = 0
    for tok in (e.ids or ""):gmatch("%d+") do
        local id = tonumber(tok)
        local hit = terms and q.Book.ItemMatches(id, terms, e.names and e.names[id])
        if hit or (not terms and bags[id]) then front = front + 1; table.insert(ids, front, id) else ids[#ids + 1] = id end
    end
    setIcons(row, ids)
end

----------------------------------------------------------------------
-- drawing
----------------------------------------------------------------------
local function Render(resetScroll)
    if not (P and P:IsVisible()) then return end
    local H, F = HB(), FZ()
    if not (H and F) then return end
    local cats = H.Categories()
    local list, title, isSummary, vendorBags, dl = H.List(V.cat, V.query, usable())
    -- counts + filter (dungeon drops count as can do / later)
    local c = H.Counts(list)
    for _, d in ipairs(dl or {}) do
        local st = H.DropStatus(d)
        c.all, c[st] = c.all + 1, (c[st] or 0) + 1
    end
    for key, b in pairs(P.filters.buttons) do b:SetLabel(("%s (%d)"):format(b.label, c[key] or 0)) end
    P.filters:Select(V.filter)
    local shown = {}
    for _, e in ipairs(list) do
        if V.filter == "all" or e.status == V.filter then shown[#shown + 1] = e end
    end
    H.SortList(shown)
    if isSummary then
        local me = UnitLevel("player") or 1
        local near = {}
        for _, e in ipairs(shown) do
            if e.status == "log" or (e.level or 0) == 0 or math.abs((e.level or 0) - me) <= 6 then near[#near + 1] = e end
        end
        shown = near
    end
    if vendorBags and V.filter ~= "done" and F.VendorBags then
        local vb = F:VendorBags()
        if #vb > 0 then
            shown[#shown + 1] = { header = "Bags you can buy (normal bags biggest first, then reagent bags)" }
            for _, v in ipairs(vb) do shown[#shown + 1] = v end
        end
    end
    local nQuests, nDrops = #shown, 0
    if dl then
        local ds = {}
        for _, d in ipairs(dl) do if V.filter == "all" or d.status == V.filter then ds[#ds + 1] = d end end
        nDrops = #ds
        if nDrops > 0 then
            H.SortDrops(ds)
            shown[#shown + 1] = { header = ("Dungeon drops (%d)  |cff888888click one for the way to the dungeon|r"):format(nDrops) }
            for _, d in ipairs(ds) do shown[#shown + 1] = d end
        end
        P.listTitle:SetText(("%s  |cff888888%d quests · %d dungeon drops|r"):format(title, nQuests, nDrops))
    else
        P.listTitle:SetText(("%s  |cff888888%d|r"):format(title, #shown))
    end

    -- summary block
    local sum = isSummary and not V.query
    P.summary:SetShown(sum)
    if sum then
        local all, _, zoneCont = H.All()
        local tot = H.Counts(all)
        P.sumAll:Fill(tot.done, tot.all)
        for cont, bar in pairs(P.sumCont) do
            local d, t = 0, 0
            for _, e in ipairs(all) do
                if (zoneCont[e.zone] or false) == cont then t = t + 1; if e.status == "done" then d = d + 1 end end
            end
            bar:Fill(d, t)
        end
        P.sumText:SetText(("|cffffffff%d|r can do now  ·  |cffffd200%d|r in your log  ·  |cff888888%d|r later  ·  |cff66ff66%d|r done")
            :format(tot.can, tot.log, tot.later, tot.done))
    end
    P.listTitle:ClearAllPoints()
    P.listTitle:SetPoint("TOPLEFT", P.right, "TOPLEFT", 2, sum and -122 or -36)
    P.list:ClearAllPoints()
    P.list:SetPoint("TOPLEFT", P.listTitle, "BOTTOMLEFT", -2, -6)
    P.list:SetPoint("BOTTOMRIGHT", P.right, "BOTTOMRIGHT", 0, 0)
    P.list:SetData(shown, not resetScroll)
    P.cats:SetData(cats, true)
end

-- quest levels come from the server a few at a time while the page is open (like the book does)
local loader
local function StartLoader()
    if loader then return end
    local H, F = HB(), FZ()
    if not (H and F) then return end
    local all = H.All()
    local queue, pos = {}, 1
    for _, e in ipairs(all) do
        if (e.level or 0) == 0 and (e.status or H.Classify(e)) ~= "done" then queue[#queue + 1] = e end
    end
    if #queue == 0 then return end
    loader = C_Timer.NewTicker(0.25, function()
        if not (P and P:IsVisible()) or pos > #queue then
            if loader then loader:Cancel(); loader = nil end
            return
        end
        for _ = 1, 10 do
            local e = queue[pos]
            if not e then break end
            F:Level(e.id)
            pos = pos + 1
        end
    end)
end

-- redraw as levels arrive and quests are taken / turned in (once per burst)
local pending
local function Redraw()
    if pending or not (P and P:IsVisible()) then return end
    pending = true
    C_Timer.After(0.5, function() pending = nil; Render() end)
end
local QUEST_EVENTS = { "QUEST_DATA_LOAD_RESULT", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_LEVEL_UP",
    "QUEST_LOG_UPDATE", "GET_ITEM_INFO_RECEIVED" }
local stale
-- only while the Book page is open (K.LiveEvents); closed, it's marked stale and catches up on show
local function onQuestEvent(e, qid)
    local H = HB()
    if not (H and P) then return end
    if e == "QUEST_DATA_LOAD_RESULT" then
        local _, byId = H.All()
        local x = qid and byId[qid]
        if x then x.status = nil; Redraw() end
        return
    end
    if e == "QUEST_LOG_UPDATE" or e == "GET_ITEM_INFO_RECEIVED" then Redraw() return end
    if P:IsVisible() then
        for _, x in ipairs((H.All())) do x.status = nil end
        Redraw()
    else
        stale = true
    end
end

----------------------------------------------------------------------
-- the panel
----------------------------------------------------------------------
local function Build(host)
    P = CreateFrame("Frame", nil, host)
    P:SetAllPoints()
    P.Render = Render

    -- left: categories
    P.left = CreateFrame("Frame", nil, P)
    P.left:SetPoint("TOPLEFT", 8, -8); P.left:SetPoint("BOTTOMLEFT", 8, 8); P.left:SetWidth(CAT_W)
    K.Box(P.left, { 0.04, 0.04, 0.06, 1 }, K.EDGE)
    P.cats = K.List(P.left, CAT_ROW, MakeCat, FillCat)
    P.cats:SetPoint("TOPLEFT", 6, -6); P.cats:SetPoint("BOTTOMRIGHT", -4, 6)

    -- right: tools, summary, list
    P.right = CreateFrame("Frame", nil, P)
    P.right:SetPoint("TOPLEFT", P.left, "TOPRIGHT", 12, 0); P.right:SetPoint("BOTTOMRIGHT", -8, 8)
    P.filters = K.Segments(P.right, { { "all", "All" }, { "can", "Can do" }, { "log", "In log" }, { "later", "Later" }, { "done", "Done" } },
        92, function(key) V.filter = key; Render(true) end)
    P.filters[1]:SetPoint("TOPLEFT", 0, 0)
    P.search = K.Search(P.right, 250, "Search quests, rewards or dungeon loot", function(t)
        V.query = (#t >= 2) and t or nil
        Render(true)
    end)
    P.search:SetPoint("TOPRIGHT", 0, 0)
    P.usable = K.Check(P.right, "Only what I can use", function(_, on)
        if VQ() and VQ().Set then VQ():Set("bookUsableOnly", on) end
        Render(true)
    end)
    P.usable:SetPoint("TOPLEFT", P.search, "BOTTOMLEFT", 2, -8)   -- under the search (the filters fill the row)
    P.usable:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Only what I can use")
        GameTooltip:AddLine("When searching, count only rewards and dungeon drops your class can wear or wield (armor type, weapon skills, dual wield).", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    P.usable:SetScript("OnLeave", function() GameTooltip:Hide() end)

    P.summary = CreateFrame("Frame", nil, P.right)
    P.summary:SetPoint("TOPLEFT", 0, -34); P.summary:SetPoint("RIGHT"); P.summary:SetHeight(80)
    local function label(text, y) local l = K.Text(P.summary, "GameFontHighlight", text); l:SetPoint("TOPLEFT", 0, y) end
    label("All quests you can do", 0)
    P.sumAll = K.Bar(P.summary, 300, 14); P.sumAll:SetPoint("TOPLEFT", 170, 0)
    P.sumCont = {}
    local H = HB()
    label("Kalimdor", -20)
    P.sumCont[H and H.KALIMDOR or 1414] = K.Bar(P.summary, 300, 14); P.sumCont[H and H.KALIMDOR or 1414]:SetPoint("TOPLEFT", 170, -20)
    label("Eastern Kingdoms", -40)
    P.sumCont[H and H.EASTERN or 1415] = K.Bar(P.summary, 300, 14); P.sumCont[H and H.EASTERN or 1415]:SetPoint("TOPLEFT", 170, -40)
    P.sumText = K.Text(P.summary, "GameFontHighlightSmall"); P.sumText:SetPoint("TOPLEFT", 0, -64)

    P.listTitle = K.Text(P.right, "GameFontNormal")
    P.list = K.List(P.right, ROW_H, MakeRow, FillRow)

    P:SetScript("OnShow", function()
        P.usable:SetChecked(usable())
        local h = HB()
        if stale and h then stale = nil; for _, x in ipairs((h.All())) do x.status = nil end end
        Render()
        StartLoader()
    end)
    K.LiveEvents(P, QUEST_EVENTS, onQuestEvent, 0)
    P:HookScript("OnHide", function() stale = true end)
    return P
end

----------------------------------------------------------------------
-- Zone quests: VoidQuest's zone list (ForeverZone's window), same data: F:Zones / F:ZoneList
--   left: Here, then every zone with done / total; right: the zone's quests (in log, open with a
--   known start first, later, done), "Hide done & later" (VoidQuest's own setting)
----------------------------------------------------------------------
local FLAG_TEXT = { d = "daily", w = "weekly", r = "repeatable", D = "dungeon", R = "raid", E = "elite", P = "PvP" }
local Z = { zone = nil }   -- nil = the zone you're in
local ZP

local function ZoneRender()
    if not (ZP and ZP:IsVisible()) then return end
    local F = FZ()
    if not F then return end
    local here = F:PlayerZone()
    local zone = Z.zone or here or "?"
    local cats = { { here = true, label = "Here" .. (here and (": " .. here) or "") } }
    for _, z in ipairs(F:Zones()) do cats[#cats + 1] = z end
    ZP.cats:SetData(cats, true)
    local all = F:ZoneList(zone)
    local hide = VQ():Get("foreverHideDone") == true
    ZP.hide:SetChecked(hide)
    local list, done, known = {}, 0, 0
    for _, e in ipairs(all) do
        if e.status == "done" then done = done + 1 end
        if e.spot and e.status == "open" then known = known + 1 end
        if not (hide and (e.status == "done" or e.status == "later")) then list[#list + 1] = e end
    end
    ZP.title:SetText(("%s  |cff888888%d / %d done · %d starts known|r"):format(zone, done, #all, known))
    ZP.list:SetData(list, true)
end

local function ZoneBuild(host)
    ZP = CreateFrame("Frame", nil, host)
    ZP:SetAllPoints()
    ZP.left = CreateFrame("Frame", nil, ZP)
    ZP.left:SetPoint("TOPLEFT", 8, -8); ZP.left:SetPoint("BOTTOMLEFT", 8, 8); ZP.left:SetWidth(CAT_W)
    K.Box(ZP.left, { 0.04, 0.04, 0.06, 1 }, K.EDGE)
    ZP.cats = K.List(ZP.left, CAT_ROW, function(b)
        b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        b:GetHighlightTexture():SetVertexColor(K.A[1], K.A[2], K.A[3], 0.12)
        b.text = K.Text(b, "GameFontHighlightSmall"); b.text:SetPoint("LEFT", 2, 1); b.text:SetPoint("RIGHT", -46, 0); b.text:SetWordWrap(false)
        b.count = K.Text(b, "GameFontDisableSmall"); b.count:SetPoint("RIGHT", -2, 1)
        b:SetScript("OnClick", function(s)
            Z.zone = (not s.item.here) and s.item.zone or nil
            ZP.list.off = 0
            ZoneRender()
        end)
    end, function(b, z)
        local sel = (z.here and Z.zone == nil) or (not z.here and Z.zone == z.zone)
        b.text:SetText((sel and "|cff00c7ff" or (z.here and "|cffffd200" or "|cffffffff")) .. "  " .. (z.label or z.zone) .. "|r")
        b.count:SetText(z.total and ("%d/%d"):format(z.done, z.total) or "")
    end)
    ZP.cats:SetPoint("TOPLEFT", 6, -6); ZP.cats:SetPoint("BOTTOMRIGHT", -4, 6)

    ZP.right = CreateFrame("Frame", nil, ZP)
    ZP.right:SetPoint("TOPLEFT", ZP.left, "TOPRIGHT", 12, 0); ZP.right:SetPoint("BOTTOMRIGHT", -8, 8)
    ZP.title = K.Text(ZP.right, "GameFontNormal"); ZP.title:SetPoint("TOPLEFT", 2, -4)
    ZP.hide = K.Check(ZP.right, "Hide done & later", function(_, on) VQ():Set("foreverHideDone", on); ZoneRender() end)
    ZP.hide:SetPoint("TOPRIGHT", -130, -2)
    ZP.list = K.List(ZP.right, 20, function(row)
        row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        row:GetHighlightTexture():SetVertexColor(K.A[1], K.A[2], K.A[3], 0.10)
        row.text = K.Text(row, "GameFontHighlight"); row.text:SetPoint("LEFT", 4, 0); row.text:SetPoint("RIGHT", -80, 0); row.text:SetWordWrap(false)
        row.right = K.Text(row, "GameFontDisableSmall"); row.right:SetPoint("RIGHT", -4, 0)
        row:SetScript("OnClick", function(s) if s.item and FZ() then FZ():Go(s.item.id) end end)
        row:SetScript("OnEnter", function(s) if s.item and FZ() and FZ().QuestTooltip then FZ().QuestTooltip(s, s.item.id) end end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end, function(row, e)
        local lv = (e.level or 0) > 0 and ("[" .. e.level .. "] ") or ""
        local tag = ""
        for c in (e.flags or ""):gmatch("[dwDRP]") do tag = tag .. " |cff88ccff(" .. FLAG_TEXT[c] .. ")|r" end
        local color = (e.status == "done" or e.status == "later") and "|cff777777" or e.status == "log" and "|cffffd200" or "|cffffffff"
        local star = (e.important and VQ().Chains and VQ().Chains.STAR) or ""
        row.text:SetText(star .. color .. lv .. e.title .. "|r" .. tag)
        row.right:SetText(e.status == "done" and "done" or e.status == "log" and "in log"
            or e.status == "later" and "later" or e.spot and "|cff88ccffpin|r" or "")
    end)
    ZP.list:SetPoint("TOPLEFT", 0, -28); ZP.list:SetPoint("BOTTOMRIGHT", 0, 0)
    ZP:SetScript("OnShow", ZoneRender)
    -- quests taken / done and zone changes while the page stays open (only while it's shown; Codex 11-25)
    if K.LiveEvents then
        K.LiveEvents(ZP, { "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "ZONE_CHANGED_NEW_AREA" }, ZoneRender, 1)
    end
    return ZP
end

----------------------------------------------------------------------
-- Route: VoidQuest's route planner (RoutePlan.lua), same plan: VQ.Route:Build()
----------------------------------------------------------------------
local RP
local function mins(sec)
    local m = math.floor(sec / 60 + 0.5)
    if m >= 60 then return ("%d h %d min"):format(math.floor(m / 60), m % 60) end
    return ("%d min"):format(math.max(1, m))
end
local function zoneName(map) local i = map and safe(C_Map.GetMapInfo, map); return i and i.name or "?" end
local function num(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n) end

-- a step: track the quest and let VoidGPS guide you there (the route window's own click)
local function goStep(st)
    if not st then return end
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID and safe(C_QuestLog.GetLogIndexForQuestID, st.q.qid) then
        if C_QuestLog.AddQuestWatch then pcall(C_QuestLog.AddQuestWatch, st.q.qid) end
        pcall(C_SuperTrack.SetSuperTrackedQuestID, st.q.qid)
    end
    if VoidGPS and VoidGPS.RouteTo then
        VoidGPS:RouteTo({ name = st.kind == "turnin" and (st.who or st.q.title) or st.q.title,
            sub = (st.kind == "turnin" and ("turn in " .. st.q.title)) or (st.kind == "explore" and "discover") or "quest",
            map = st.map, x = st.x, y = st.y })
    end
end

local RouteDraw
local function RouteRender(force)
    if not (RP and RP:IsVisible()) then return end
    local q = VQ()
    if not (q and q.Route) then return end
    -- the kept plan, as VoidQuest changes it while you play (P:Apply): shown as it is, nothing planned again (the
    -- user: "static should be static and changes get refreshed"); "Plan again" = from scratch
    if q.Route.lastPlan and force ~= true then RouteDraw(q, q.Route.lastPlan) return end
    -- planned a few ms a frame (VoidQuest RoutePlan.lua, perf pass 2026-11-24: one plan froze the game 1.7 s)
    if q.Route.BuildAsync then
        if not q.Route.lastPlan then RP.summary:SetText("|cffffd200Planning your route...|r"); RP.list:SetData({}); RP.foot:SetText("") end
        q.Route:BuildAsync(function(plan, why) if RP:IsVisible() then RouteDraw(q, plan, why) end end)
        return
    end
    local ok, plan, why = pcall(q.Route.Build, q.Route)
    if not ok then why, plan = tostring(plan), nil end
    RouteDraw(q, plan, why)
end
RouteDraw = function(q, plan, why)
    if not plan then RP.summary:SetText("|cffff8040" .. (why or "No plan") .. "|r"); RP.list:SetData({}); RP.foot:SetText(""); return end
    if #plan.steps == 0 then
        RP.summary:SetText("Nothing to plan: no quests you can do solo with a known place.")
    else
        local per = plan.sec > 0 and math.floor(plan.xp * 3600 / plan.sec / 100 + 0.5) * 100 or 0
        local np = (plan.picks or 0) + (plan.follows or 0)
        local picks = (np > 0 and (" + %d to pick up"):format(np) or "")
            .. ((plan.explores or 0) > 0 and (" + %d area%s to discover"):format(plan.explores, plan.explores == 1 and "" or "s") or "")
        RP.summary:SetText(("|cffffd200%d quests%s|r · about %s (%s on the way) · %s XP · ~%s XP/hour"):format(
            plan.quests, picks, mins(plan.sec), mins(plan.travel), num(plan.xp), num(per)))
    end
    local rows, lastZone = {}, nil
    for n, st in ipairs(plan.steps) do
        local z = zoneName(st.map)
        local tag = (q.Guide and q.Guide.LevelTag) and q.Guide.LevelTag(st.q.qid) or ""
        local who = st.who and (" |cff999999(" .. (st.guessed and "probably " or "") .. st.who .. ")|r") or ""
        local verb = (st.kind == "explore" and ("|cff88ccffDiscover|r " .. st.q.title .. " |cff999999(Explore " .. (st.q.zone or "") .. ")|r"))
            or (st.kind == "turnin" and ("|cff55ff55Turn in|r " .. tag .. st.q.title .. who))
            or (st.kind == "pickup" and ("|cffffd200Pick up|r " .. (st.q.follow and "|cff88ccff(next in chain)|r " or "") .. tag .. st.q.title .. who))
            or ("Do " .. tag .. st.q.title .. (st.what and (": " .. st.what) or "") .. (" |cff999999~%s|r"):format(mins(st.work)))
        local way = st.travel > 20 and ("|cff88ccff[%s%s]|r "):format(z ~= lastZone and (z .. ", ") or "", mins(st.travel)) or ""
        rows[#rows + 1] = { st = st, text = ("%d. %s%s"):format(n, way, verb) }
        lastZone = z
    end
    RP.list:SetData(rows)
    local foot, sk = {}, plan.skipped
    if #sk.group > 0 then foot[#foot + 1] = "|cffff8040Bring a group:|r " .. table.concat(sk.group, ", ") end
    if #sk.here > 0 then foot[#foot + 1] = "|cffffd200Here, left out:|r " .. table.concat(sk.here, ", ") end
    if #sk.pvp > 0 then foot[#foot + 1] = "|cffff5050PvP:|r " .. table.concat(sk.pvp, ", ") end
    if #sk.unknown > 0 then foot[#foot + 1] = "|cffaaaaaaNo known place yet:|r " .. table.concat(sk.unknown, ", ") end
    if #sk.grey > 0 then foot[#foot + 1] = "|cff999999Grey, left out:|r " .. table.concat(sk.grey, ", ") end
    if not (VoidGPS and VoidGPS.TravelTime) then foot[#foot + 1] = "|cffaaaaaaWith VoidGPS the way between stops counts flight paths and zeppelins.|r" end
    RP.foot:SetText(table.concat(foot, "\n"))
end

-- plan again when the log changes while the Route page is open (the route window's own rule: right away for a
-- quest taken / turned in / dropped, at most every 30 s for progress)
local rq, lastProgress = false, 0
local ROUTE_EVENTS = { "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "TAXIMAP_CLOSED", "PLAYER_LEVEL_UP" }
local function onRouteEvent(e)
    if not (RP and RP:IsVisible()) or rq then return end
    if e == "QUEST_LOG_UPDATE" then
        if GetTime() - lastProgress < 30 then return end
        lastProgress = GetTime()
    end
    rq = true
    C_Timer.After(1, function() rq = false; RouteRender() end)
end

local function RouteBuild(host)
    RP = CreateFrame("Frame", nil, host)
    RP:SetAllPoints()
    RP.summary = K.Text(RP, "GameFontHighlight"); RP.summary:SetPoint("TOPLEFT", 16, -12); RP.summary:SetPoint("RIGHT", -120, 0)
    RP.again = K.Button(RP, "Plan again", 90, function() RouteRender(true) end)   -- from scratch
    RP.again:SetPoint("TOPRIGHT", -12, -8)
    RP.foot = K.Text(RP, "GameFontHighlightSmall"); RP.foot:SetPoint("BOTTOMLEFT", 16, 30); RP.foot:SetPoint("RIGHT", -16, 0)
    RP.foot:SetJustifyV("BOTTOM"); RP.foot:SetMaxLines(6)
    RP.hint = K.Text(RP, "GameFontDisableSmall", "Click a step: the way there (VoidGPS) and the quest is tracked. Plans again when your quest log changes.")
    RP.hint:SetPoint("BOTTOMLEFT", 16, 10)
    RP.list = K.List(RP, 20, function(row)
        row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        row:GetHighlightTexture():SetVertexColor(K.A[1], K.A[2], K.A[3], 0.10)
        row.text = K.Text(row, "GameFontHighlight"); row.text:SetPoint("LEFT", 4, 0); row.text:SetPoint("RIGHT", -4, 0); row.text:SetWordWrap(false)
        row:SetScript("OnClick", function(s) if s.item then goStep(s.item.st) end end)
        row:SetScript("OnEnter", function(s)
            local st = s.item and s.item.st
            if not st then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:AddLine(st.q.title, 1, 0.82, 0)
            if st.kind == "explore" then
                GameTooltip:AddLine("Discover this area: it counts toward Explore " .. (st.q.zone or "") .. ", and Explore Azeroth is a Legacy point. It's on your way.", 1, 1, 1, true)
            elseif st.kind == "pickup" then
                GameTooltip:AddLine("Pick up" .. (st.who and (" from " .. st.who) or "") .. ": on your way, worth the detour", 1, 1, 1, true)
            elseif st.kind == "turnin" then
                GameTooltip:AddLine("Turn in" .. (st.who and (" to " .. st.who) or ""), 1, 1, 1)
                if st.guessed then GameTooltip:AddLine("Where it's handed in isn't known yet: most quests go back to whoever gave them.", .7, .7, .7, true) end
            else
                local qt = VQ().QuestTime
                GameTooltip:AddLine(("Do it: about %s%s"):format(mins(st.work),
                    (qt and qt:Minutes(st.q.qid)) and " (players' time)" or " (a guess from what's left)"), 1, 1, 1)
            end
            GameTooltip:AddLine(zoneName(st.map) .. (st.travel > 20 and (" · ~%s to get there"):format(mins(st.travel)) or ""), .53, .8, 1)
            GameTooltip:AddLine("Click: guide me there (VoidGPS) and track the quest", .6, .6, .6)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end, function(row, it) row.text:SetText(it.text) end)
    RP.list:SetPoint("TOPLEFT", RP.summary, "BOTTOMLEFT", -4, -10)
    RP.list:SetPoint("BOTTOMRIGHT", RP.foot, "TOPRIGHT", 0, 8)
    RP:SetScript("OnShow", function() RouteRender() end)
    K.LiveEvents(RP, ROUTE_EVENTS, function(e) onRouteEvent(e) end, 0)
    return RP
end


----------------------------------------------------------------------
-- Settings: VoidQuest's settings (Settings.lua), the same keys through VQ:Get / VQ:Set. Only what does
-- something on this game: the campaign / zone-guide buttons (retail) stay out on Forever.
----------------------------------------------------------------------
local function SettingsBuild(host)
    local q = VQ()
    local function key(k) return function() return q:Get(k) end, function(v) q:Set(k, v) end end
    local function check(label, k, tip, indent)
        local g, s = key(k)
        return { "check", label, g, s, tip, indent = indent }
    end
    local pct = function(v) return ("%.0f%%"):format(v * 100) end
    local guidance = {
        check("Set map waypoint", "setWaypoint"),
        check("Native objective ring (super-track)", "superTrack", "Use Blizzard's objective-area blob + tracking arrow for in-progress quests."),
        check("Objective ring on the world map", "showRing", "Draw a green circle on the world map where the current step happens -- the quest giver, the objective area, or the turn-in."),
        check("Highlight needed quest givers", "giverPins", "Light-blue halo on the world map (under Blizzard's !) and minimap for the quest givers in your scope: the Density tier plus the chain the guide follows."),
    }
    if q.MobLoot then guidance[#guidance + 1] = check("Whose loot on mob tooltips", "mobLoot", "A line on a mob's tooltip: yours, your group's (and the loot rule), someone else's, or free. On a corpse: whether you can loot it.") end
    if q.MobAtlas then guidance[#guidance + 1] = check("Record the mobs you see", "mobAtlas", "Keeps every mob you see or kill: name, level, where, and your kills. Stays on your computer. Used to check quest data.") end
    do
        local g, s = key(q.ForeverQuests and "foreverDensity" or "density")
        guidance[#guidance + 1] = { "choice", "Density", { { "min", "Min" }, { "mid", "Mid" }, { "max", "Max" } }, g, s }
    end
    local general = {
        check("Show minimap button", "minimapShow"),
        check("Show quest levels", "questLevels", "Puts the quest's level in front of its name on the panel's quest lines: [30], [30D] for a dungeon quest, [30R] raid, [30+] elite."),
        check("Announce auto-actions in chat", "announceActions", "Print a line each time VoidQuest auto-accepts or turns in a quest."),
    }
    local share = {}
    if q.Share then
        share = {
            check("Share quest givers with other players", "share", "WoW Forever has no quest markers on the map. When you find a quest giver, VoidQuest tells a few other VoidQuest players online where it is (by hidden addon whisper), and learns the ones they find. Sent: the quest, the NPC and its spot, only after you've left that map. A spot is used once two players agree on it."),
            check("Let VoidQuest players on your quest ask you to group", "groupAsks", "Another VoidQuest player in your zone on the same quest can ask you to group: a pop-up with their name, level and class, Accept or No thanks. Only when you're solo, out of combat and outside instances, at most once every 3 minutes."),
            check("Say when VoidQuest players here share your quests", "groupArrival", "Arriving in a zone, one chat line when other VoidQuest players there are on your quests, at most once per zone every 30 minutes."),
            check("Say when someone in chat is on your elite quests", "questLfgAlert", "When a chat line names one of your elite quests, one chat line with their name to click and whisper. At most once per player and quest every 10 minutes."),
        }
        local LH = rawget(_G, "VoidLayerHelp")
        if LH and rawget(_G, "VoidLayerCore") then share[#share + 1] = { "check", LH.LABEL, LH.On, LH.Set, LH.TIP } end
    end
    local blocks = {
        { title = "Hands-free (auto)", items = {
            check("Master hands-free", "auto", "Turn all auto actions on/off. When off, VoidQuest only guides -- you accept/turn in yourself."),
            check("Auto-accept quests", "autoAccept", nil, true),
            check("Auto turn-in quests", "autoTurnIn", nil, true),
            check("Auto-claim single rewards", "autoReward", "Automatically take the reward when there's only one. Choice rewards always pause below.", true),
            check("Pause on reward choice", "pauseOnChoice", "Stop so you pick which reward when a quest offers a choice of items.", true),
            check("Also handle non-campaign quests", "autoAllQuests", "Auto-accept and turn in EVERY quest you talk to an NPC about. Reward choices still pause. Off by default -- it will also grab dailies and side quests.", true),
        } },
        { title = "Guidance", items = guidance },
        { title = "Guide panel", items = {
            check("Show objective text", "showObjective"),
            check("Show zone summary line", "showZoneSummary"),
            check("Lock panel position", "lockPanel"),
            { "slider", "Scale", 0.7, 1.6, 0.05, pct, key("panelScale") },
            { "slider", "Opacity", 0.1, 1.0, 0.05, pct, key("panelOpacity") },
            { "slider", "Height", 120, 800, 10, function(v) return ("%d"):format(v) end, key("panelHeight") },
        } },
        { title = "General", items = general },
    }
    if #share > 0 then blocks[#blocks + 1] = { title = "Other players", items = share } end
    return K.SettingsPage(host, blocks, 300)
end

ns.RegisterPage("VoidQuest", {
    -- only on WoW Forever with a VoidQuest that has the hub hooks
    available = function() return HB() ~= nil and FZ() ~= nil end,
    sections = {
        { key = "book", label = "Quest Book", build = Build },
        { key = "zone", label = "Zone quests", build = ZoneBuild },
        { key = "route", label = "Route", build = RouteBuild },
        { key = "settings", label = "Settings", build = SettingsBuild },
    },
})
