----------------------------------------------------------------------
-- VoidHub kit: the ONE look every page in the hub is drawn with (the user, 2026-11-24: "i dont want to
-- hodge podge it"). Pages never use Blizzard's panel templates; they build from these pieces:
--   Box (pixel border), Button, Tab, Check, Search, Bar, List (scrolling rows, mouse wheel + thumb), Text
----------------------------------------------------------------------
-- Shared (2026-11-25, the user: "voidhub is fine, just work it into how voidhub already is now"): every Void addon
-- carries this folder as Libs\VoidHub (kept identical by tools/cmd/sync-libs, like VoidLib and VoidHubBundle).
-- The first copy to load runs the window; the others see _G.VoidHubWin and skip every file. A copy with a HIGHER
-- VERSION (a newer addon next to older ones) takes over, the way the drawer's QUICK_VERSION does.
local hostAddon = ...
-- WoW Forever only for now (2026-11-25 release): the retail pages aren't built yet, so on retail nothing loads and the
-- VoidHub button's right-click keeps its older panel (VoidHubBundle falls back when VoidHub_Toggle is missing).
if (select(4, GetBuildInfo()) or 0) >= 100000 then
    if _G.VoidHubWin then _G.VoidHubWin.skip = true end   -- this copy's other files skip too (Codex 11-25)
    return
end
local VERSION = 1
local cur = _G.VoidHubWin
if cur and (cur.version or 0) >= VERSION then cur.skip = true return end
_G.VoidHubWin = { version = VERSION, host = hostAddon, skip = false,
    path = "Interface\\AddOns\\" .. tostring(hostAddon) .. "\\Libs\\VoidHub\\" }
local ns = _G.VoidHubWin
local K = {}
ns.Kit = K

K.A = { 0, 0.78, 1 }                         -- the Void cyan
K.BG = { 0.04, 0.04, 0.07, 0.97 }            -- window
K.PANEL = { 0.06, 0.06, 0.09, 1 }            -- page area
K.ROW = { 0.08, 0.09, 0.12, 1 }              -- buttons, tabs
K.EDGE = { 0.22, 0.24, 0.29, 1 }             -- quiet border
K.GREY = "|cff8c8c9e"
local WHITE = "Interface\\Buttons\\WHITE8X8"

function K.PX()
    local s = UIParent and UIParent:GetEffectiveScale()
    if s and s > 0 and PixelUtil and PixelUtil.GetPixelToUIUnitFactor then return PixelUtil.GetPixelToUIUnitFactor() / s end
    return 1
end

-- a box with a 1-pixel border made of anchored textures (snapped to the pixel grid), recolorable
function K.Box(f, bg, edge)
    if not f._box then
        local px = K.PX() * 1.01
        local function tex(layer)
            local t = f:CreateTexture(nil, layer, nil, -8)
            t:SetTexture(WHITE)
            if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(true) end
            return t
        end
        local b = { bg = tex("BACKGROUND"), tex("BORDER"), tex("BORDER"), tex("BORDER"), tex("BORDER") }
        b.bg:SetPoint("TOPLEFT", px, -px); b.bg:SetPoint("BOTTOMRIGHT", -px, px)
        b[1]:SetPoint("TOPLEFT"); b[1]:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, -px)
        b[2]:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, px); b[2]:SetPoint("BOTTOMRIGHT")
        b[3]:SetPoint("TOPLEFT", 0, -px); b[3]:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", px, px)
        b[4]:SetPoint("TOPLEFT", f, "TOPRIGHT", -px, -px); b[4]:SetPoint("BOTTOMRIGHT", 0, px)
        f._box = b
    end
    K.Recolor(f, bg, edge)
    return f
end

function K.Recolor(f, bg, edge)
    local b = f._box
    if not b then return end
    if bg then b.bg:SetVertexColor(bg[1], bg[2], bg[3], bg[4] or 1) end
    if edge then for i = 1, 4 do b[i]:SetVertexColor(edge[1], edge[2], edge[3], edge[4] or 1) end end
end

function K.Text(parent, font, str)
    local s = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    s:SetJustifyH("LEFT")
    if str then s:SetText(str) end
    return s
end

function K.Button(parent, label, w, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or 90, 22)
    K.Box(b, K.ROW, { K.A[1], K.A[2], K.A[3], 0.55 })
    b.text = K.Text(b, "GameFontHighlightSmall", label)
    b.text:SetPoint("CENTER")
    if onClick then b:SetScript("OnClick", onClick) end
    b:SetScript("OnEnter", function(s) K.Recolor(s, nil, { K.A[1], K.A[2], K.A[3], 1 }) end)
    b:SetScript("OnLeave", function(s) K.Recolor(s, nil, { K.A[1], K.A[2], K.A[3], 0.55 }) end)
    function b:SetLabel(t) self.text:SetText(t) end
    return b
end

-- a tab: text (and an optional icon); selected = lit; note = small grey word after the text
function K.Tab(parent, h)
    local t = CreateFrame("Button", nil, parent)
    t:SetHeight(h)
    K.Box(t, K.ROW, K.EDGE)
    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetSize(h - 10, h - 10); t.icon:SetPoint("LEFT", 6, 0)
    t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    t.text = K.Text(t, "GameFontHighlightSmall")
    t.note = K.Text(t, "GameFontDisableSmall")
    t.note:SetPoint("LEFT", t.text, "RIGHT", 4, 0)
    function t:Set(label, icon, selected, dim, note)
        self.text:SetText(label)
        self.text:ClearAllPoints()
        if icon then self.icon:SetTexture(icon); self.icon:Show(); self.text:SetPoint("LEFT", self.icon, "RIGHT", 5, 0)
        else self.icon:Hide(); self.text:SetPoint("LEFT", 10, 0) end
        self.icon:SetDesaturated(dim and true or false); self.icon:SetAlpha(dim and 0.5 or 1)
        self.text:SetTextColor(dim and 0.55 or 1, dim and 0.55 or 1, dim and 0.6 or 1)
        self.note:SetText(note or "")
        self:SetWidth(math.max(64, (icon and (self:GetHeight() - 4) or 6) + self.text:GetStringWidth() + self.note:GetStringWidth() + 22))
        if selected then K.Recolor(self, { 0.04, 0.18, 0.24, 1 }, { K.A[1], K.A[2], K.A[3], 1 })
        else K.Recolor(self, K.ROW, K.EDGE) end
        self:Show()
    end
    return t
end

-- a check box: a small box with a cyan tick
function K.Check(parent, label, onClick)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(16, 16)
    K.Box(c, { 0.03, 0.03, 0.05, 1 }, K.EDGE)
    c.tick = c:CreateTexture(nil, "ARTWORK")
    c.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check"); c.tick:SetPoint("CENTER"); c.tick:SetSize(18, 18)
    c.tick:SetVertexColor(K.A[1], K.A[2], K.A[3])
    c.label = K.Text(c, "GameFontHighlightSmall", label)
    c.label:SetPoint("LEFT", c, "RIGHT", 6, 0)
    c:SetHitRectInsets(0, -(c.label:GetStringWidth() + 8), 0, 0)
    function c:SetChecked(v) self.checked = v and true or false; self.tick:SetShown(self.checked) end
    function c:GetChecked() return self.checked end
    c:SetScript("OnClick", function(s) s:SetChecked(not s.checked); if onClick then onClick(s, s.checked) end end)
    c:SetChecked(false)
    return c
end

-- a search box: hint text while empty, an x to clear, never keeps the keyboard (Enter / Esc / hide)
function K.Search(parent, w, hint, onChange)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(w, 22)
    e:SetAutoFocus(false)
    e:SetFontObject("GameFontHighlightSmall")
    e:SetTextInsets(22, 20, 0, 0)
    K.Box(e, { 0.03, 0.03, 0.05, 1 }, K.EDGE)
    local mag = e:CreateTexture(nil, "ARTWORK")
    mag:SetTexture("Interface\\Common\\UI-Searchbox-Icon"); mag:SetSize(14, 14); mag:SetPoint("LEFT", 5, -1)
    mag:SetVertexColor(0.6, 0.6, 0.65)
    e.hint = K.Text(e, "GameFontDisableSmall", hint)
    e.hint:SetPoint("LEFT", 22, 0)
    local x = CreateFrame("Button", nil, e)
    x:SetSize(16, 16); x:SetPoint("RIGHT", -3, 0)
    x.t = K.Text(x, "GameFontHighlightSmall", "x"); x.t:SetPoint("CENTER")
    x:SetScript("OnClick", function() e:SetText(""); e:ClearFocus() end)
    local function update()
        local t = e:GetText() or ""
        e.hint:SetShown(t == "" and not e:HasFocus())
        x:SetShown(t ~= "")
    end
    e:SetScript("OnEditFocusGained", function(s) K.Recolor(s, nil, { K.A[1], K.A[2], K.A[3], 0.9 }); update() end)
    e:SetScript("OnEditFocusLost", function(s) K.Recolor(s, nil, K.EDGE); update() end)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnHide", e.ClearFocus)
    e:SetScript("OnTextChanged", function(s)
        update()
        if onChange then onChange(strtrim(s:GetText() or "")) end
    end)
    update()
    return e
end

function K.Bar(parent, w, h)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetSize(w, h)
    bar:SetStatusBarTexture(WHITE)
    bar:SetStatusBarColor(K.A[1], K.A[2], K.A[3], 0.75)
    K.Box(bar, { 0.10, 0.10, 0.13, 0.9 }, { K.A[1], K.A[2], K.A[3], 0.35 })
    bar.text = K.Text(bar, "GameFontHighlightSmall"); bar.text:SetPoint("CENTER")
    function bar:Fill(done, total)
        self:SetMinMaxValues(0, math.max(1, total)); self:SetValue(done)
        self.text:SetText(("%d / %d"):format(done, total))
    end
    return bar
end

-- a scrolling list of rows: rows are made as the height needs them (make(row)), filled from data
-- (fill(row, item, index)); mouse wheel, a slim thumb you can drag
function K.List(parent, rowH, make, fill)
    local L = CreateFrame("Frame", nil, parent)
    L.rows, L.data, L.off, L.rowH = {}, {}, 0, rowH
    L:EnableMouseWheel(true)
    L.track = CreateFrame("Frame", nil, L)
    L.track:SetPoint("TOPRIGHT"); L.track:SetPoint("BOTTOMRIGHT"); L.track:SetWidth(5)
    local tbg = L.track:CreateTexture(nil, "BACKGROUND"); tbg:SetAllPoints(); tbg:SetColorTexture(1, 1, 1, 0.05)
    L.thumb = CreateFrame("Button", nil, L.track)
    L.thumb:SetWidth(5)
    local th = L.thumb:CreateTexture(nil, "ARTWORK"); th:SetAllPoints(); th:SetColorTexture(K.A[1], K.A[2], K.A[3], 0.55)

    function L:Visible() return math.max(1, math.floor((self:GetHeight() or 0) / rowH)) end
    function L:MaxOff() return math.max(0, #self.data - self:Visible()) end
    function L:Refresh()
        local n = self:Visible()
        self.off = math.max(0, math.min(self.off, self:MaxOff()))
        for i = 1, n do
            local r = self.rows[i]
            if not r then
                r = CreateFrame("Button", nil, self)
                r:SetHeight(rowH)
                r:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
                r:SetPoint("RIGHT", self, "RIGHT", -9, 0)
                make(r)
                self.rows[i] = r
            end
            local it = self.data[self.off + i]
            if it ~= nil then r.item = it; fill(r, it, self.off + i); r:Show() else r.item = nil; r:Hide() end
        end
        for i = n + 1, #self.rows do self.rows[i]:Hide() end
        -- the thumb
        local total, trackH = #self.data, self.track:GetHeight() or 0
        if total <= n or trackH <= 0 then self.track:Hide() return end
        self.track:Show()
        local h = math.max(16, trackH * n / total)
        self.thumb:SetHeight(h)
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("TOP", self.track, "TOP", 0, -(trackH - h) * (self.off / self:MaxOff()))
    end
    function L:SetData(d, keepOffset)
        self.data = d or {}
        if not keepOffset then self.off = 0 end
        self:Refresh()
    end
    L:SetScript("OnMouseWheel", function(s, delta) s.off = s.off - delta * 3; s:Refresh() end)
    L:SetScript("OnSizeChanged", function(s) s:Refresh() end)
    -- drag the thumb
    L.thumb:SetScript("OnMouseDown", function(s)
        local _, y = GetCursorPosition()
        s.dragY, s.dragOff = y / (s:GetEffectiveScale() or 1), L.off
        s:SetScript("OnUpdate", function(t)
            if not IsMouseButtonDown("LeftButton") then t:SetScript("OnUpdate", nil) return end
            local _, cy = GetCursorPosition()
            cy = cy / (t:GetEffectiveScale() or 1)
            local trackH = L.track:GetHeight() - t:GetHeight()
            if trackH <= 0 then return end
            local new = t.dragOff + math.floor((t.dragY - cy) / trackH * L:MaxOff() + 0.5)
            if new ~= L.off then L.off = new; L:Refresh() end
        end)
    end)
    return L
end

-- a row of toggle buttons where one is on (filters): defs = { { key, label } }, onPick(key)
function K.Segments(parent, defs, w, onPick)
    local S = { buttons = {} }
    local prev
    for _, d in ipairs(defs) do
        local b = K.Button(parent, d[2], w)
        b.key, b.label = d[1], d[2]
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) end
        b:SetScript("OnClick", function() onPick(d[1]) end)
        S.buttons[d[1]] = b
        S[#S + 1] = b
        prev = b
    end
    function S:Select(key)
        for k, b in pairs(self.buttons) do
            if k == key then K.Recolor(b, { 0.04, 0.18, 0.24, 1 }, { K.A[1], K.A[2], K.A[3], 1 })
            else K.Recolor(b, K.ROW, { K.A[1], K.A[2], K.A[3], 0.55 }) end
            b:SetScript("OnLeave", function(s)
                if s.key == key then K.Recolor(s, nil, { K.A[1], K.A[2], K.A[3], 1 })
                else K.Recolor(s, nil, { K.A[1], K.A[2], K.A[3], 0.55 }) end
            end)
        end
    end
    return S
end

-- a slider: label + value above a thin bar with a thumb; drag it, click on the bar, or mouse wheel.
-- fmt(v) -> the value's text; get() / set(v) read and write the setting
function K.Slider(parent, w, label, minv, maxv, step, fmt, get, set)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(w, 30)
    s.label = K.Text(s, "GameFontHighlightSmall"); s.label:SetPoint("TOPLEFT", 0, 0)
    s.track = CreateFrame("Button", nil, s)
    s.track:SetPoint("BOTTOMLEFT", 0, 2); s.track:SetPoint("BOTTOMRIGHT", 0, 2); s.track:SetHeight(8)
    K.Box(s.track, { 0.03, 0.03, 0.05, 1 }, K.EDGE)
    s.fill = s.track:CreateTexture(nil, "ARTWORK"); s.fill:SetTexture(WHITE)
    s.fill:SetVertexColor(K.A[1], K.A[2], K.A[3], 0.55); s.fill:SetPoint("TOPLEFT", 1, -1); s.fill:SetPoint("BOTTOMLEFT", 1, 1)
    s.thumb = s.track:CreateTexture(nil, "OVERLAY"); s.thumb:SetTexture(WHITE)
    s.thumb:SetVertexColor(1, 1, 1, 0.9); s.thumb:SetSize(4, 12)
    local function clamp(v)
        v = math.floor((v - minv) / step + 0.5) * step + minv
        return math.max(minv, math.min(maxv, v))
    end
    function s:Show_(v)
        local p = (v - minv) / (maxv - minv)
        local tw = self.track:GetWidth() or w
        self.fill:SetWidth(math.max(1, (tw - 2) * p))
        self.thumb:ClearAllPoints(); self.thumb:SetPoint("CENTER", self.track, "LEFT", tw * p, 0)
        self.label:SetText(("%s: |cff55ff55%s|r"):format(label, fmt and fmt(v) or tostring(v)))
    end
    function s:Sync() self:Show_(get() or minv) end
    local function fromCursor()
        local x = GetCursorPosition() / (s.track:GetEffectiveScale() or 1)
        local left, tw = s.track:GetLeft() or 0, s.track:GetWidth() or w
        local v = clamp(minv + (x - left) / tw * (maxv - minv))
        if v ~= get() then set(v) end
        s:Show_(v)
    end
    s.track:SetScript("OnMouseDown", function(t)
        fromCursor()
        t:SetScript("OnUpdate", function(u)
            if not IsMouseButtonDown("LeftButton") then u:SetScript("OnUpdate", nil) return end
            fromCursor()
        end)
    end)
    s.track:EnableMouseWheel(true)
    s.track:SetScript("OnMouseWheel", function(_, d)
        local v = clamp((get() or minv) + d * step)
        set(v); s:Show_(v)
    end)
    s:SetScript("OnSizeChanged", function(f) f:Sync() end)
    return s
end

-- a choice: label, then one button per option, the chosen one lit. opts = { { val, text } }
function K.Choice(parent, label, opts, get, set)
    local c = CreateFrame("Frame", nil, parent)
    c:SetHeight(22)
    c.label = K.Text(c, "GameFontHighlightSmall", label); c.label:SetPoint("LEFT", 0, 0)
    local defs = {}
    for _, o in ipairs(opts) do defs[#defs + 1] = { o[1], o[2] } end
    c.seg = K.Segments(c, defs, 56, function(v) set(v); c:Sync() end)
    c.seg[1]:SetPoint("LEFT", 110, 0)
    function c:Sync() self.seg:Select(get()) end
    c:SetWidth(110 + #opts * 60)
    return c
end

-- a settings page: blocks laid out in columns (a block never splits). blocks = { { title = "...", items = {
--   { "check", label, get, set, tip }, { "choice", label, opts, get, set }, { "slider", label, min, max, step, fmt, get, set },
--   { "note", text } } }. Returns the page; page:Sync() re-reads every value (call it on show: settings change elsewhere too).
function K.SettingsPage(parent, blocks, colW)
    -- blocks go into as many columns as fit, each into the shortest one; taller than the page scrolls
    local outer = CreateFrame("ScrollFrame", nil, parent)
    outer:SetAllPoints()
    local page = CreateFrame("Frame", nil, outer)
    outer:SetScrollChild(page)
    outer.syncs = {}
    page.syncs = outer.syncs
    colW = colW or 340
    local W = parent:GetWidth() or 0
    if W < 300 then W = 960 end
    page:SetSize(W, 10)
    outer:SetScript("OnSizeChanged", function(s, w) if w and w > 0 then page:SetWidth(w) end end)
    outer:EnableMouseWheel(true)
    outer:SetScript("OnMouseWheel", function(s, d)
        local max = math.max(0, page:GetHeight() - s:GetHeight())
        s:SetVerticalScroll(math.max(0, math.min(max, s:GetVerticalScroll() - d * 40)))
    end)
    local function tipOn(f, title, body)
        if not body then return end
        f:HookScript("OnEnter", function(s)
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:AddLine(title)
            GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true); GameTooltip:Show()
        end)
        f:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local function heightOf(b)
        local h = 26
        for _, it in ipairs(b.items) do
            h = h + ((it[1] == "slider") and 38 or (it[1] == "note") and (it.h or 30) or (it[1] == "button") and 28
                or (it[1] == "number") and 26 or 24)
        end
        return h + 10
    end
    local ncols = math.max(1, math.floor((W - 16) / (colW + 24)))
    local colY = {}
    for c = 1, ncols do colY[c] = -12 end
    for _, b in ipairs(blocks) do
        local _ = heightOf(b)
        local col = 1
        for c = 2, ncols do if colY[c] > colY[col] then col = c end end
        local x, y = 16 + (col - 1) * (colW + 24), colY[col]
        local hd = K.Text(page, "GameFontNormal", "|cff00c7ff" .. b.title .. "|r")
        hd:SetPoint("TOPLEFT", x, y)
        local ln = page:CreateTexture(nil, "ARTWORK"); ln:SetTexture(WHITE)
        ln:SetVertexColor(K.A[1], K.A[2], K.A[3], 0.35); ln:SetPoint("TOPLEFT", hd, "BOTTOMLEFT", 0, -3); ln:SetSize(colW, 1)
        y = y - 26
        for _, it in ipairs(b.items) do
            local kind = it[1]
            if kind == "check" then
                local get, set = it[3], it[4]
                local cb = K.Check(page, it[2], function(_, on) set(on) end)
                cb:SetPoint("TOPLEFT", x + (it.indent and 16 or 0), y - 3)
                tipOn(cb, it[2], it[5])
                page.syncs[#page.syncs + 1] = function() cb:SetChecked(get() and true or false) end
                y = y - 24
            elseif kind == "choice" then
                local ch = K.Choice(page, it[2], it[3], it[4], it[5])
                ch:SetPoint("TOPLEFT", x, y)
                page.syncs[#page.syncs + 1] = function() ch:Sync() end
                y = y - 24
            elseif kind == "slider" then
                local sl = K.Slider(page, math.min(260, colW - 20), it[2], it[3], it[4], it[5], it[6], it[7], it[8])
                sl:SetPoint("TOPLEFT", x, y - 2)
                page.syncs[#page.syncs + 1] = function() sl:Sync() end
                y = y - 38
            elseif kind == "note" then
                local n = K.Text(page, "GameFontDisableSmall", it[2]); n:SetPoint("TOPLEFT", x, y - 2); n:SetWidth(colW)
                y = y - (it.h or 30)
            elseif kind == "number" then   -- { "number", label, get, set, tip }: a small box, saved on Enter
                local lbl = K.Text(page, "GameFontHighlightSmall", it[2]); lbl:SetPoint("TOPLEFT", x, y - 5)
                local e = CreateFrame("EditBox", nil, page)
                e:SetSize(64, 20); e:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
                e:SetAutoFocus(false); e:SetNumeric(true); e:SetFontObject("GameFontHighlightSmall"); e:SetTextInsets(6, 6, 0, 0)
                K.Box(e, { 0.03, 0.03, 0.05, 1 }, K.EDGE)
                local get, set = it[3], it[4]
                e:SetScript("OnEnterPressed", function(s) set(tonumber(s:GetText()) or 0); s:ClearFocus() end)
                e:SetScript("OnEscapePressed", function(s) s:SetText(tostring(get() or 0)); s:ClearFocus() end)
                e:SetScript("OnEditFocusLost", function(s) s:SetText(tostring(get() or 0)) end)
                e:SetScript("OnHide", e.ClearFocus)
                tipOn(e, it[2], it[5])
                page.syncs[#page.syncs + 1] = function() e:SetText(tostring(get() or 0)) end
                y = y - 26
            elseif kind == "button" then   -- { "button", label, onClick, tip }
                local b = K.Button(page, it[2], math.max(120, #it[2] * 7 + 24), it[3])
                b:SetPoint("TOPLEFT", x, y - 2)
                if it[4] then
                    b:HookScript("OnEnter", function(s)
                        GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:AddLine(it[2])
                        GameTooltip:AddLine(it[4], 0.8, 0.8, 0.8, true); GameTooltip:Show()
                    end)
                    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
                end
                y = y - 28
            elseif kind == "dropdown" then   -- { "dropdown", label, options() -> { {value, label} }, get, set, tip }
                local lbl = K.Text(page, "GameFontHighlightSmall", it[2]); lbl:SetPoint("TOPLEFT", x, y - 5)
                local optsFn, get, set = it[3], it[4], it[5]
                local function labelOf(v)
                    for _, o in ipairs(optsFn() or {}) do if o.value == v then return o.label or o.text or tostring(v) end end
                    return tostring(v or "")
                end
                local b = K.Button(page, "", 160, nil)
                b.text:SetWidth(150); b.text:SetWordWrap(false)   -- a long choice stays inside the button
                if lbl:GetStringWidth() > colW - 176 then   -- a long label: the dropdown goes under it
                    lbl:SetWidth(colW); lbl:SetWordWrap(true)
                    b:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -4)
                    y = y - (lbl:GetStringHeight() or 14) - 4
                else
                    b:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
                end
                b:SetScript("OnClick", function(s)
                    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
                    MenuUtil.CreateContextMenu(s, function(_, root)
                        for _, o in ipairs(optsFn() or {}) do
                            root:CreateRadio(o.label or o.text or tostring(o.value), function() return get() == o.value end,
                                function() set(o.value); s:SetLabel(labelOf(o.value)) end)
                        end
                    end)
                end)
                tipOn(b, it[2], it[6])
                page.syncs[#page.syncs + 1] = function() b:SetLabel(labelOf(get())) end
                y = y - 26
            end
        end
        colY[col] = y - 10
    end
    local low = 0
    for c = 1, ncols do low = math.min(low, colY[c]) end
    page:SetHeight(-low + 10)
    function outer:Sync() for _, fn in ipairs(self.syncs) do pcall(fn) end end
    outer:SetScript("OnShow", function(p) p:Sync() end)
    return outer
end

-- An addon's own Blizzard Options category (Esc > Options > AddOns > name), read back from Blizzard's settings
-- registry as blocks for K.SettingsPage: its check boxes, sliders, dropdowns and buttons, with the addon's own
-- labels, tooltips, getters and setters (nothing re-declared, nothing changed in the addon). A section header
-- starts a new block; long runs are cut into blocks of `per` items.
-- a category by its name: walk the list (Settings.GetCategory wants the category's ID on WoW Forever, a number,
-- so a name found nothing; seen 2026-11-24)
-- Shift-click a link into chat. 12.x: ChatFrameUtil.InsertLink; ChatEdit_InsertLink only lives in Blizzard's
-- deprecated-API addon, which a player can have off (Codex 2026-11-25)
function K.InsertLink(link)
    local fn = (ChatFrameUtil and ChatFrameUtil.InsertLink) or _G.ChatEdit_InsertLink
    if fn and link then return fn(link) end
end

function K.SettingsCategory(name)
    if not (SettingsPanel and SettingsPanel.GetAllCategories) then return nil end
    for _, c in ipairs(SettingsPanel:GetAllCategories() or {}) do
        if c.GetName and c:GetName() == name then return c end
    end
end

function K.FromBlizzardSettings(categoryName, firstTitle, per)
    per = per or 14
    local cat = K.SettingsCategory(categoryName)
    local layout = cat and SettingsPanel and SettingsPanel.GetLayout and SettingsPanel:GetLayout(cat)
    local inits = layout and layout.GetInitializers and layout:GetInitializers()
    if not inits then return nil end
    local blocks, cur = {}, nil
    local function newBlock(title) cur = { title = title, items = {} }; blocks[#blocks + 1] = cur end
    newBlock(firstTitle or "Settings")
    local function tipOf(t) if type(t) == "function" then local ok, v = pcall(t); return ok and v or nil end return t end
    for _, init in ipairs(inits) do
        local d = init.GetData and init:GetData() or init.data or {}
        local s = d.setting
        if #cur.items >= per then newBlock(cur.title:gsub(" %(more%)$", "") .. " (more)") end
        if s and s.GetValue and s.SetValue then
            local name = s.GetName and s:GetName() or "?"
            local get = function() return s:GetValue() end
            local set = function(v) s:SetValue(v) end
            local o = d.options
            if type(o) == "table" and o.minValue and o.maxValue then
                local step = (o.steps and o.steps > 0) and (o.maxValue - o.minValue) / o.steps or 1
                local fmt = function(v)
                    if o.maxValue <= 1 then return ("%d%%"):format(math.floor(v * 100 + 0.5)) end
                    return (step < 1) and ("%.2f"):format(v) or ("%d"):format(math.floor(v + 0.5))
                end
                cur.items[#cur.items + 1] = { "slider", name, o.minValue, o.maxValue, step, fmt, get, set }
            elseif type(o) == "function" then
                cur.items[#cur.items + 1] = { "dropdown", name, function() local ok, v = pcall(o); return ok and v or {} end, get, set, tipOf(d.tooltip) }
            elseif type(s:GetValue()) == "boolean" then
                cur.items[#cur.items + 1] = { "check", name, get, set, tipOf(d.tooltip) }
            end
        elseif d.buttonClick then
            cur.items[#cur.items + 1] = { "button", d.name or d.buttonText or "?", function() d.buttonClick() end, tipOf(d.tooltip) }
        elseif d.name and not d.setting then
            newBlock(d.name)   -- a section header
        end
    end
    local out = {}
    for _, b in ipairs(blocks) do if #b.items > 0 then out[#out + 1] = b end end
    return out
end

-- An addon's hand-drawn Blizzard Options panel (a canvas category, e.g. VoidSequencer's rotation editor), shown inside
-- a hub page: the hub parents the addon's own frame into the page while the page is open, exactly as Blizzard's
-- Options window does when it shows that category (SettingsPanelMixin:DisplayLayout); opening it in Blizzard's
-- Options later takes it back the same way. Its own OnShow refreshes it. Returns the holder, or nil (no such canvas).
function K.CanvasPage(host, categoryName)
    local cat = K.SettingsCategory(categoryName)
    local layout = cat and SettingsPanel and SettingsPanel.GetLayout and SettingsPanel:GetLayout(cat)
    local isCanvas = layout and layout.GetLayoutType and SettingsLayoutMixin and SettingsLayoutMixin.LayoutType
        and layout:GetLayoutType() == SettingsLayoutMixin.LayoutType.Canvas
    local frame = isCanvas and layout.GetFrame and layout:GetFrame()
    if not frame then return nil end
    local holder = CreateFrame("Frame", nil, host)
    holder:SetAllPoints()
    local function attach(h)
        frame:SetParent(h)
        frame:ClearAllPoints()
        frame:SetAllPoints(h)
        frame:Show()
        local fn = frame.OnRefresh or frame.refresh
        if type(fn) == "function" then pcall(fn, frame) end
    end
    -- opened in a fight: attach when it ends, if the page is still up (Codex 11-25: it stayed blank)
    local wait = CreateFrame("Frame")
    wait:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if holder:IsVisible() and not InCombatLockdown() then attach(holder) end
    end)
    holder:SetScript("OnShow", function(h)
        if InCombatLockdown() then wait:RegisterEvent("PLAYER_REGEN_ENABLED") return end
        attach(h)
    end)
    return holder
end

----------------------------------------------------------------------
-- Events only while a panel is on screen (the user, 2026-11-24: "i dont want this to bloat the game ... even
-- with lower end computers"). Registered when the panel shows, all dropped when it hides (hiding the hub
-- hides every page), so a closed hub listens to nothing. A burst = one fn() `delay` s later, only if the
-- panel is still up; delay 0 = fn(event, ...) at once. Pages redraw on show, so nothing missed while hidden.
----------------------------------------------------------------------
function K.LiveEvents(panel, events, fn, delay)
    local ev = CreateFrame("Frame")
    local queued
    ev:SetScript("OnEvent", function(_, e, ...)
        if delay == 0 then fn(e, ...) return end
        if queued then return end
        queued = true
        C_Timer.After(delay or 0.5, function()
            queued = false
            if panel:IsVisible() then fn() end
        end)
    end)
    local function on() for _, e in ipairs(events) do pcall(ev.RegisterEvent, ev, e) end end
    panel:HookScript("OnShow", on)
    panel:HookScript("OnHide", function() ev:UnregisterAllEvents() end)
    if panel:IsVisible() then on() end
    return ev
end
