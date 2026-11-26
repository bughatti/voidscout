----------------------------------------------------------------------
-- VoidHub page for "Dungeons and raids" (WoW Forever): VoidDungeon's dungeon panel (the side of its map view).
--   left   every dungeon by level bracket ("You're in" on top), the one open is VoidDungeon's own current one
--   top    Quests / Loot / Path / Tips / Marks / Reserve / BoE
--   right  the same entries VoidDungeon lists for that tab (VoidDungeon.SideHub.Build), hovered and clicked by
--          VoidDungeon's own handlers (quest chains open, loot links / reserves, the way to a quest giver, marks)
-- The map itself (boss spots, the route) stays in the world map; picking a dungeon here picks it there too.
----------------------------------------------------------------------
local ns = _G.VoidHubWin
if not ns or ns.skip then return end   -- another Void addon's copy of VoidHub runs the window
local K = ns.Kit

local function J() return _G.VoidDungeon end
local function SH() local j = J(); return j and j.SideHub end
local P
local V = { tab = "Path" }

local function pickDefault()
    local j = J()
    if j.cur then return end
    local d = j.inside
    if not d then
        local lvl = UnitLevel("player") or 1
        for _, x in ipairs(j.dungeons or {}) do
            if (x.min or 0) <= lvl + 2 then d = x end   -- the highest one you can do (the list is by level)
        end
        d = d or (j.dungeons or {})[1]
    end
    if d then j:Show(d) end
end

local function Render(keep)
    if not (P and P:IsVisible()) then return end
    local j, H = J(), SH()
    if not (j and H) then return end
    pickDefault()
    -- left: the dungeons by level bracket
    local tree, bracket = {}, nil
    if j.inside then tree[#tree + 1] = { here = true, d = j.inside } end
    for _, d in ipairs(j.dungeons or {}) do
        local b = math.floor((d.min or 0) / 10) * 10
        if b ~= bracket then bracket = b; tree[#tree + 1] = { header = ("Level %d-%d"):format(b, b + 9) } end
        tree[#tree + 1] = { d = d }
    end
    P.tree:SetData(tree, true)
    -- top: the tab
    P.tabs:Select(V.tab)
    P.head:SetText(j.cur and ("|cff00c7ff%s|r  |cff8c8c9e%s|r"):format(j.cur.name, j.cur.lv or "") or "")
    local out = {}
    if j.cur then
        local ok, err = pcall(H.Build, V.tab, out)
        if not ok then out = { { text = "|cffff5555" .. tostring(err) .. "|r" } } end
    end
    P.list:SetData(out, keep)
end

local function Build(host)
    P = CreateFrame("Frame", nil, host)
    P:SetAllPoints()
    P.left = CreateFrame("Frame", nil, P)
    P.left:SetPoint("TOPLEFT", 8, -8); P.left:SetPoint("BOTTOMLEFT", 8, 8); P.left:SetWidth(230)
    K.Box(P.left, { 0.04, 0.04, 0.06, 1 }, K.EDGE)
    P.tree = K.List(P.left, 18, function(b)
        b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        b:GetHighlightTexture():SetVertexColor(K.A[1], K.A[2], K.A[3], 0.12)
        b.text = K.Text(b, "GameFontHighlightSmall"); b.text:SetPoint("LEFT", 2, 1); b.text:SetPoint("RIGHT", -40, 0); b.text:SetWordWrap(false)
        b.lv = K.Text(b, "GameFontDisableSmall"); b.lv:SetPoint("RIGHT", -2, 1)
        b:SetScript("OnClick", function(s) local it = s.item; if it and it.d then J():Show(it.d); P.list.off = 0; Render() end end)
    end, function(b, it)
        if it.header then
            b.text:SetText("|cffffd200" .. it.header .. "|r"); b.lv:SetText(""); b:EnableMouse(false)
            return
        end
        b:EnableMouse(true)
        local sel = J().cur == it.d
        local name = it.here and ("|cff33ff33You're in:|r " .. it.d.name) or it.d.name
        b.text:SetText((sel and "|cff00c7ff" or "|cffffffff") .. "  " .. name .. "|r")
        b.lv:SetText(it.d.lv or "")
    end)
    P.tree:SetPoint("TOPLEFT", 6, -6); P.tree:SetPoint("BOTTOMRIGHT", -4, 6)

    P.right = CreateFrame("Frame", nil, P)
    P.right:SetPoint("TOPLEFT", P.left, "TOPRIGHT", 12, 0); P.right:SetPoint("BOTTOMRIGHT", -8, 8)
    P.head = K.Text(P.right, "GameFontNormalLarge"); P.head:SetPoint("TOPLEFT", 2, -2)
    local defs = {}
    for _, t in ipairs(SH() and SH().TABS or {}) do defs[#defs + 1] = { t, t } end
    P.tabs = K.Segments(P.right, defs, 84, function(t) V.tab = t; P.list.off = 0; Render() end)
    if P.tabs[1] then P.tabs[1]:SetPoint("TOPLEFT", 0, -28) end
    P.list = K.List(P.right, 20, function(r)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        r:GetHighlightTexture():SetVertexColor(K.A[1], K.A[2], K.A[3], 0.10)
        r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(15, 15); r.icon:SetPoint("LEFT", 4, 0)
        r.prog = K.Text(r, "GameFontHighlightSmall"); r.prog:SetPoint("RIGHT", -6, 0); r.prog:SetJustifyH("RIGHT")
        r.title = K.Text(r, "GameFontHighlight"); r.title:SetWordWrap(false)
        r:SetScript("OnEnter", function(s) if s.e then SH().Enter(s) end end)
        r:SetScript("OnLeave", function() SH().Leave() end)
        r:SetScript("OnClick", function(s, button)
            if not s.e then return end
            SH().Click(s, button)
            C_Timer.After(0, function() Render(true) end)   -- a chain opened, a dungeon / map picked: redraw
        end)
    end, function(r, e)
        r.e = e
        r.title:ClearAllPoints()
        r.title:SetPoint("RIGHT", r.prog, "LEFT", -4, 0)
        if e.head then
            r.icon:Hide()
            r.title:SetPoint("LEFT", 6, 0)
            r.title:SetText("|cff00c7ff" .. e.head .. "|r")
            r.prog:SetText("")
            return
        end
        if e.icon then
            r.icon:SetTexture(e.icon); r.icon:Show()
            r.title:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
        else
            r.icon:Hide()
            r.title:SetPoint("LEFT", 6, 0)
        end
        r.title:SetText(e.text or "")
        r.title:SetTextColor(e.r or 1, e.g or 1, e.b or 1)
        r.prog:SetText(e.right or "")
    end)
    P.list:SetPoint("TOPLEFT", 0, -58); P.list:SetPoint("BOTTOMRIGHT", 0, 0)
    P:SetScript("OnShow", function() Render() end)
    -- VoidDungeon's own changes (a dungeon entered, a boss picked on the map, loot loaded): redraw while open
    J():OnChange(function(what)
        if not (P and P:IsVisible()) then return end
        if what == "select" and J().sel and V.tab ~= "Tips" then V.tab = "Loot" end
        Render(what ~= "dungeon" and what ~= "map")
    end)
    return P
end

ns.RegisterPage("VoidDungeon", {
    available = function() local j = J(); return j ~= nil and j.dungeons ~= nil and SH() ~= nil end,
    sections = { { key = "dungeons", label = "Dungeons", build = Build } },
})
