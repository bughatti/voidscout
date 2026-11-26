----------------------------------------------------------------------
-- VoidHub pages for "Combat": what these addons put in Blizzard's Options (Esc > Options > AddOns) shows here,
-- read back from Blizzard's settings registry (K.FromBlizzardSettings): the same check boxes, sliders, dropdowns
-- and buttons with the addons' own labels, tooltips and settings. The bars, frames and plates themselves stay on
-- screen where you play.
--   VoidBars, VoidPlates, VoidFrames: their Options category.
--   VoidSequencer: its own page (Pages/Seq.lua).
----------------------------------------------------------------------
local ns = _G.VoidHubWin
if not ns or ns.skip then return end   -- another Void addon's copy of VoidHub runs the window
local K = ns.Kit

local function hasCategory(name)
    return K.SettingsCategory(name) ~= nil
end

local function fromOptions(name, firstTitle)
    return function(host)
        local blocks = K.FromBlizzardSettings(name, firstTitle)
        if not blocks or #blocks == 0 then
            local t = K.Text(host, "GameFontDisableSmall", name .. "'s options aren't registered yet: open this page again after loading in.")
            t:SetPoint("TOPLEFT", 16, -16)
            return t
        end
        return K.SettingsPage(host, blocks, 290)
    end
end

----------------------------------------------------------------------
-- VoidBars: each bar's own settings (its per-bar window: on / off, fade, buttons, per row, size, spacing, when it
-- shows), applied by VoidBars' own code (VoidBars.BarSettingsHub). Out of combat: changes wait for the fight to end.
----------------------------------------------------------------------
local function VB() return _G.VoidBars end
local BP

local function BarsRender()
    if not (BP and BP:IsVisible()) then return end
    local V = VB()
    BP.list:SetData(V.bars or {}, true)
    local bar = BP.bar or (V.bars or {})[1]
    BP.bar = bar
    if not bar then return end
    local def, cfg = bar.def, V:BarConfig(bar.def.key)
    BP.title:SetText("|cff00c7ff" .. (def.label or def.key) .. "|r")
    BP.enabled:SetChecked(cfg.enabled and true or false)
    BP.fade:SetChecked(cfg.fade and true or false)
    local smart = def.kind == "smart"
    local fixed = def.kind == "pet" or def.kind == "stance" or def.kind == "markers"
    local n = #bar.buttons
    BP.loading = true
    BP.num:SetShown(not smart and not fixed)
    if smart then
        BP.vals = { num = n, cols = cfg.cols or 12, size = cfg.size or 36, spacing = cfg.spacing or 3 }
    else
        local cols, spacing, size = V.BarSettingsHub.Shape(cfg, bar)
        BP.vals = { num = math.min(cfg.num or n, n), cols = cols, size = size, spacing = spacing }
    end
    BP.maxButtons = n
    for _, s in ipairs({ BP.num, BP.cols, BP.size, BP.spacing }) do s:Sync() end
    BP.loading = false
    BP.rule:Select(cfg.show or "always")
    local custom = (cfg.show or "always") == "custom"
    BP.custom:SetShown(custom); BP.customHint:SetShown(custom)
    if not BP.custom:HasFocus() then BP.custom:SetText(cfg.showCustom or "") end
end

local function BarsBuild(host)
    BP = CreateFrame("Frame", nil, host)
    BP:SetAllPoints()
    local left = CreateFrame("Frame", nil, BP)
    left:SetPoint("TOPLEFT", 8, -8); left:SetPoint("BOTTOMLEFT", 8, 8); left:SetWidth(200)
    K.Box(left, { 0.04, 0.04, 0.06, 1 }, K.EDGE)
    BP.list = K.List(left, 20, function(b)
        b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        b:GetHighlightTexture():SetVertexColor(K.A[1], K.A[2], K.A[3], 0.12)
        b.text = K.Text(b, "GameFontHighlightSmall"); b.text:SetPoint("LEFT", 4, 0); b.text:SetPoint("RIGHT", -4, 0); b.text:SetWordWrap(false)
        b:SetScript("OnClick", function(s) BP.bar = s.item; BarsRender() end)
    end, function(b, bar)
        local on = VB():BarConfig(bar.def.key).enabled
        b.text:SetText((BP.bar == bar and "|cff00c7ff" or (on and "|cffffffff" or "|cff8c8c9e")) .. (bar.def.label or bar.def.key) .. "|r")
    end)
    BP.list:SetPoint("TOPLEFT", 6, -6); BP.list:SetPoint("BOTTOMRIGHT", -4, 6)

    local x = 230
    BP.title = K.Text(BP, "GameFontNormalLarge"); BP.title:SetPoint("TOPLEFT", x, -12)
    BP.enabled = K.Check(BP, "Show this bar", function(_, on) VB().BarSettingsHub.SetEnabled(BP.bar, on); BarsRender() end)
    BP.enabled:SetPoint("TOPLEFT", x, -44)
    BP.fade = K.Check(BP, "Fade out of combat (back on mouseover)", function(_, on) VB().BarSettingsHub.SetFade(BP.bar, on) end)
    BP.fade:SetPoint("TOPLEFT", x, -68)
    -- the sliders apply once a drag settles, on the bar they were changed on (the window's own rule)
    local pending = {}
    local function slider(field, label, lo, hi, y)
        local s = K.Slider(BP, 300, label, lo, hi, 1, function(v) return tostring(math.floor(v + 0.5)) end,
            function() return BP.vals and BP.vals[field] or lo end,
            function(v)
                if BP.loading or not BP.bar then return end
                if field == "num" or field == "cols" then v = math.min(v, BP.maxButtons or hi) end
                BP.vals[field] = v
                -- debounced per bar AND field: moving two sliders quickly keeps both (Codex 11-25)
                -- (the bar is an object: pending[bar][field], never a string key; Codex 11-25)
                local bar, token = BP.bar, {}
                pending[bar] = pending[bar] or {}
                pending[bar][field] = token
                C_Timer.After(0.15, function()
                    if pending[bar][field] == token then pending[bar][field] = nil; VB().BarSettingsHub.SetLayout(bar, field, v) end
                end)
            end)
        s:SetPoint("TOPLEFT", x, y)
        return s
    end
    BP.num = slider("num", "Buttons", 1, 12, -100)
    BP.cols = slider("cols", "Buttons per row", 1, 12, -140)
    BP.size = slider("size", "Button size", 20, 64, -180)
    BP.spacing = slider("spacing", "Spacing", 0, 12, -220)
    local rl = K.Text(BP, "GameFontHighlightSmall", "Show"); rl:SetPoint("TOPLEFT", x, -268)
    local defs = {}
    for _, r in ipairs(VB().SHOW_RULES or {}) do defs[#defs + 1] = { r.value, r.label } end
    BP.rule = K.Segments(BP, defs, 130, function(v)
        VB():BarConfig(BP.bar.def.key).show = v
        VB().BarSettingsHub.ApplyShown(BP.bar)
        BarsRender()
    end)
    BP.rule[1]:SetPoint("TOPLEFT", x + 50, -264)
    BP.custom = K.Search(BP, 400, "[mod:shift] show; hide", function() end)
    BP.custom:SetPoint("TOPLEFT", x, -298)
    BP.custom:SetScript("OnEnterPressed", function(e)
        local text = strtrim(e:GetText() or "")
        if text ~= "" and not (text:find("show") or text:find("hide")) then
            VB():Print("custom show rule needs \"show\" and/or \"hide\", e.g. [combat] show; hide")
        else
            VB():BarConfig(BP.bar.def.key).showCustom = text
            VB().BarSettingsHub.ApplyShown(BP.bar)
        end
        e:ClearFocus()
    end)
    BP.customHint = K.Text(BP, "GameFontDisableSmall", "Macro conditions, e.g.  [mod:shift] show; hide   (Enter to apply)")
    BP.customHint:SetPoint("TOPLEFT", BP.custom, "BOTTOMLEFT", 0, -4)
    local note = K.Text(BP, "GameFontDisableSmall", "Changes apply out of combat (in a fight they wait for it to end). Move bars with \"Move bars\" on the Settings page.")
    note:SetPoint("BOTTOMLEFT", x, 14)
    BP:SetScript("OnShow", BarsRender)
    return BP
end

----------------------------------------------------------------------
-- VoidFrames: click bindings (its editor: mouse buttons x modifiers; a spell name or target / focus / menu / assist;
-- drag a spell onto a box). Saved by VoidFrames itself (VF:SetBinding), per character and spec.
----------------------------------------------------------------------
local function VF() return _G.VoidFrames end
local CB

local function spellFromCursor()
    local kind, _, _, spellID = GetCursorInfo()
    if kind == "spell" and spellID then return C_Spell.GetSpellName(spellID) end
end

local function BindRender()
    if not (CB and CB:IsVisible()) then return end
    local V = VF()
    local b = V:GetBindings()
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local spec = getSpec and getSpec()
    local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
    local name = spec and getInfo and select(2, getInfo(spec))
    CB.spec:SetText((UnitName("player") or "") .. (name and (" - " .. name) or ""))
    for _, box in ipairs(CB.boxes) do
        if not box:HasFocus() then box:SetText(b[box.key] or ""); box:SetCursorPosition(0) end
    end
end

local function BindBuild(host)
    CB = CreateFrame("Frame", nil, host)
    CB:SetAllPoints()
    local V = VF()
    local t = K.Text(CB, "GameFontNormalLarge", "|cff00c7ffClick bindings|r"); t:SetPoint("TOPLEFT", 16, -10)
    CB.spec = K.Text(CB, "GameFontHighlightSmall"); CB.spec:SetPoint("TOPLEFT", 16, -32)
    CB.note = K.Text(CB, "GameFontHighlightSmall"); CB.note:SetPoint("TOPRIGHT", -16, -14)
    local CELL_W, CELL_H, LABEL_W, top = 170, 22, 90, -64
    local function commit(box)
        VF():SetBinding(box.key, box:GetText())
        box:ClearFocus()
        CB.note:SetText(InCombatLockdown() and "|cffffd100Saved: applies when combat ends.|r" or "|cff33ff33Saved.|r")
    end
    for c, m in ipairs(V.MODIFIERS) do
        local h = K.Text(CB, "GameFontNormal", m.label)
        h:SetPoint("TOPLEFT", 16 + LABEL_W + (c - 1) * (CELL_W + 8), top)
    end
    CB.boxes = {}
    for r, btn in ipairs(V.BUTTONS) do
        local y = top - 20 - (r - 1) * (CELL_H + 8)
        local lab = K.Text(CB, "GameFontHighlight", btn.label); lab:SetPoint("TOPLEFT", 16, y - 4)
        for c, m in ipairs(V.MODIFIERS) do
            local box = CreateFrame("EditBox", nil, CB)
            box:SetSize(CELL_W, CELL_H)
            box:SetPoint("TOPLEFT", 16 + LABEL_W + (c - 1) * (CELL_W + 8), y)
            box:SetAutoFocus(false); box:SetFontObject("GameFontHighlightSmall"); box:SetTextInsets(6, 6, 0, 0)
            K.Box(box, { 0.03, 0.03, 0.05, 1 }, K.EDGE)
            box.key = m.id .. btn.id
            box:SetScript("OnEnterPressed", commit)
            box:SetScript("OnEscapePressed", function(s) s:ClearFocus(); BindRender() end)
            box:SetScript("OnEditFocusGained", function(s) K.Recolor(s, nil, { K.A[1], K.A[2], K.A[3], 0.9 }) end)
            box:SetScript("OnEditFocusLost", function(s) K.Recolor(s, nil, K.EDGE) end)
            box:SetScript("OnHide", box.ClearFocus)
            local function drop(s)
                local n = spellFromCursor()
                if n then ClearCursor(); s:SetText(n); commit(s) end
            end
            box:SetScript("OnReceiveDrag", drop)
            box:SetScript("OnMouseUp", drop)
            CB.boxes[#CB.boxes + 1] = box
        end
    end
    local help = K.Text(CB, "GameFontDisableSmall", "Type a spell name, or target / focus / menu / assist. Drag a spell from your spellbook onto a box. Enter saves; empty = unbound. Saved per character and spec.")
    help:SetPoint("BOTTOMLEFT", 16, 14); help:SetWidth(760)
    CB:SetScript("OnShow", BindRender)
    K.LiveEvents(CB, { "PLAYER_SPECIALIZATION_CHANGED" }, BindRender)
    return CB
end

for _, a in ipairs({ { "VoidBars", "Action bars" }, { "VoidPlates", "Nameplates" }, { "VoidFrames", "Party and raid frames" } }) do
    local name, title = a[1], a[2]
    local sections = { { key = "settings", label = "Settings", build = fromOptions(name, title) } }
    if name == "VoidBars" then
        table.insert(sections, 1, { key = "bars", label = "Each bar", build = BarsBuild,
            available = function() local v = VB(); return v and v.BarSettingsHub and v.bars and #v.bars > 0 end })
    elseif name == "VoidFrames" then
        sections[#sections + 1] = { key = "binds", label = "Click bindings", build = BindBuild,
            available = function() local v = VF(); return v and v.GetBindings and v.SetBinding and v.MODIFIERS and v.BUTTONS end }
    end
    ns.RegisterPage(name, {
        available = function() return hasCategory(name) end,
        sections = sections,
    })
end

