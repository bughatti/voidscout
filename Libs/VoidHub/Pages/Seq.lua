----------------------------------------------------------------------
-- VoidHub page for VoidSequencer, in the hub's own look (the user, 2026-11-24: "find a way to get seq to work in
-- there"). Everything goes through VoidSequencer's own functions (VoidSequencerHub = its VS namespace, the same calls
-- its options panel makes), so an edit here is an edit there:
--   Rotation  ST / AoE, the steps (top = highest priority; each step casts its first ready spell), spell tiles with
--             VoidSequencer's spell list or a custom name, Up / Down / Delete, + Spell, + Add step, Restore defaults
--   Settings  enable, cadence glow, the ST/AoE switch, the keybind, the talent build, the rotation pick, the rotation
--             check (Details / Test my rotation), modifier casts (ALT / CTRL / SHIFT)
-- An older VoidSequencer without the hook: its own panel is borrowed instead (K.CanvasPage).
----------------------------------------------------------------------
local ns = _G.VoidHubWin
if not ns or ns.skip then return end   -- another Void addon's copy of VoidHub runs the window
local K = ns.Kit

local function VS() return _G.VoidSequencerHub end
local ED, ST
local mode = "ST"
local pendingCustom   -- { kind = "spell", step, slot } or { kind = "mod", key }

local function refreshAll()
    if ED and ED:IsVisible() and ED.Render then ED.Render() end
    if ST and ST:IsVisible() and ST.Render then ST.Render() end
end

-- the custom-name box (the panel's own popups keep the panel's own state, so the hub has its own)
StaticPopupDialogs["VOIDHUB_SEQ_CUSTOM"] = {
    text = "Enter the exact spell or ability name:",
    button1 = ACCEPT, button2 = CANCEL,
    hasEditBox = true,
    OnAccept = function(self)
        local box = self.editBox or self:GetEditBox()
        local txt = (box:GetText() or ""):gsub("[\r\n%[%]]", ""):gsub("^%s+", ""):gsub("%s+$", "")
        local p, V = pendingCustom, VS()
        pendingCustom = nil
        if not (p and V) then return end
        if p.kind == "mod" then V.SetMod(p.key, txt)
        elseif txt ~= "" then V.SetSpell(mode, p.step, p.slot, txt); V.Apply() end
        refreshAll()
    end,
    EditBoxOnEnterPressed = function(self) local d = self:GetParent(); local b = (d.GetButton1 and d:GetButton1()) or d.button1; if b then b:Click() end end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

----------------------------------------------------------------------
-- Your own rotations (VoidSequencer 1.2.0, MyRotations.lua; the hub, 2026-11-25): the same choices as the panel's
-- Rotation menu, through the same VS calls (UseMine, NewMine, RenameMine, DeleteMine, ExportMine, ImportMine).
----------------------------------------------------------------------
local pendingName   -- { action = "new" | "blank" | "rename" | "delete", old, default }
StaticPopupDialogs["VOIDHUB_SEQ_NAME"] = {
    text = "%s",
    button1 = ACCEPT, button2 = CANCEL,
    hasEditBox = true, editBoxWidth = 260,
    OnShow = function(self)
        local box = self.editBox or self:GetEditBox()
        box:SetText(pendingName and pendingName.default or ""); box:HighlightText(); box:SetFocus()
    end,
    OnAccept = function(self)
        local box = self.editBox or self:GetEditBox()
        local txt = (box:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local p, V = pendingName, VS()
        pendingName = nil
        if not (p and V) or txt == "" then return end
        if p.action == "new" then V.NewMine(txt, false)
        elseif p.action == "blank" then V.NewMine(txt, true)
        elseif p.action == "rename" then V.RenameMine(p.old, txt) end
        refreshAll()
    end,
    EditBoxOnEnterPressed = function(self) local d = self:GetParent(); local b = (d.GetButton1 and d:GetButton1()) or d.button1; if b then b:Click() end end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
StaticPopupDialogs["VOIDHUB_SEQ_DELETE"] = {
    text = "Delete your rotation \"%s\"? This can't be undone (Export it first to keep a copy).",
    button1 = DELETE, button2 = CANCEL,
    OnAccept = function()
        local p, V = pendingName, VS()
        pendingName = nil
        if p and V and p.action == "delete" then V.DeleteMine(p.old); refreshAll() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- a text box for Export / Import / Every press, in the hub's look: { title, help, text, okText, readOnly, onAccept }
local TD
local function textDialog(o)
    if not TD then
        TD = CreateFrame("Frame", "VoidHubSeqText", UIParent, "BackdropTemplate")
        TD:SetSize(560, 340); TD:SetPoint("CENTER"); TD:SetFrameStrata("DIALOG"); TD:EnableMouse(true)
        K.Box(TD, K.BG, { K.A[1], K.A[2], K.A[3], 0.8 })
        TD:SetMovable(true); TD:RegisterForDrag("LeftButton")
        TD:SetScript("OnDragStart", TD.StartMoving); TD:SetScript("OnDragStop", TD.StopMovingOrSizing)
        tinsert(UISpecialFrames, "VoidHubSeqText")   -- Esc closes it
        TD.title = K.Text(TD, "GameFontNormalLarge"); TD.title:SetPoint("TOPLEFT", 14, -12)
        TD.help = K.Text(TD, "GameFontHighlightSmall"); TD.help:SetPoint("TOPLEFT", 14, -36); TD.help:SetWidth(530)
        local area = CreateFrame("Frame", nil, TD, "BackdropTemplate")
        area:SetPoint("TOPLEFT", 14, -72); area:SetPoint("BOTTOMRIGHT", -14, 46)
        K.Box(area, K.PANEL, K.EDGE)
        local sf = CreateFrame("ScrollFrame", nil, area)
        sf:SetPoint("TOPLEFT", 6, -6); sf:SetPoint("BOTTOMRIGHT", -6, 6)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true); eb:SetAutoFocus(false); eb:SetFontObject("ChatFontNormal")
        eb:SetWidth(510); eb:SetMaxLetters(0)
        eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
        eb:SetScript("OnCursorChanged", function(_, _, y, _, h)   -- keep the cursor in view
            local top = sf:GetVerticalScroll()
            if -y < top then sf:SetVerticalScroll(-y) elseif -y + h > top + sf:GetHeight() then sf:SetVerticalScroll(-y + h - sf:GetHeight()) end
        end)
        sf:SetScrollChild(eb)
        sf:EnableMouseWheel(true)
        sf:SetScript("OnMouseWheel", function(s, d)
            local m = math.max(0, eb:GetHeight() - s:GetHeight())
            s:SetVerticalScroll(math.min(m, math.max(0, s:GetVerticalScroll() - d * 30)))
        end)
        area:EnableMouse(true); area:SetScript("OnMouseDown", function() eb:SetFocus() end)
        TD.edit = eb
        TD.ok = K.Button(TD, "OK", 100, function()
            local fn = TD.onAccept
            if fn and fn(TD.edit:GetText() or "") == false then return end   -- false = keep it open (an import error)
            TD:Hide()
        end)
        TD.ok:SetPoint("BOTTOMRIGHT", -14, 12)
        TD.cancel = K.Button(TD, "Close", 100, function() TD:Hide() end)
        TD.cancel:SetPoint("RIGHT", TD.ok, "LEFT", -8, 0)
    end
    TD.title:SetText(o.title or ""); TD.help:SetText(o.help or "")
    TD.edit:SetText(o.text or ""); TD.edit:SetCursorPosition(0)
    TD.onAccept = o.onAccept
    TD.ok:SetShown(not o.readOnly); TD.ok:SetLabel(o.okText or "OK")
    TD:Show()
    TD.edit:SetFocus()
    if o.readOnly then TD.edit:HighlightText() end
end

-- the label: which rotation key 1 runs
local function rotationLabel()
    local V = VS()
    local mineName = V.MineActive and V.MineActive()
    if mineName then return "|cff55ff55Yours:|r " .. mineName end
    local choices = V.RotationChoices and V.RotationChoices() or {}
    local cur, text = V.CurrentSpec and V.CurrentSpec(), V.SuggestedLabel and V.SuggestedLabel() or "(no rotation for this spec yet)"
    for _, c in ipairs(choices) do if c.key == cur then text = c.label end end
    if not (V.GetRotationPick and V.GetRotationPick()) and #choices > 0 then text = "Auto: " .. text end
    return "Suggested: " .. text
end

-- the menu: suggested ones, yours, new / rename / delete, share
local function rotationMenu(owner)
    local V = VS()
    local choices = V.RotationChoices and V.RotationChoices() or {}
    local pick = V.GetRotationPick and V.GetRotationPick()
    local mineName = V.MineActive and V.MineActive()
    local list = V.MineList and V.MineList() or {}
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Suggested (comes with VoidSequencer, updated by us)")
        if #choices > 0 then
            root:CreateRadio("Automatic (matches your hero tree)", function() return not mineName and pick == nil end,
                function() if mineName then V.UseMine(nil) end; V.SetRotationPick(nil); refreshAll() end)
            for _, c in ipairs(choices) do
                root:CreateRadio(c.label, function() return not mineName and pick == c.key end,
                    function() if mineName then V.UseMine(nil) end; V.SetRotationPick(c.key); refreshAll() end)
            end
        elseif V.UseMine then
            root:CreateRadio(V.SuggestedLabel and V.SuggestedLabel() or "Suggested", function() return not mineName end,
                function() V.UseMine(nil); refreshAll() end)
        end
        if not V.MineList then return end   -- an older VoidSequencer: no rotations of your own yet
        root:CreateDivider()
        root:CreateTitle("Your own (never changed by updates)")
        if #list == 0 then root:CreateButton("|cff888888none yet: make one below, or just edit a step|r", function() end) end
        for _, r in ipairs(list) do
            root:CreateRadio(r.name, function() return mineName == r.name end, function() V.UseMine(r.name); refreshAll() end)
        end
        root:CreateDivider()
        root:CreateButton("New: copy of what runs now...", function()
            pendingName = { action = "new", default = mineName and (mineName .. " copy") or (V.MineDefaultName and V.MineDefaultName()) or "My rotation" }
            StaticPopup_Show("VOIDHUB_SEQ_NAME", "Name your new rotation:")
        end)
        root:CreateButton("New: start empty...", function()
            pendingName = { action = "blank", default = "My rotation" }
            StaticPopup_Show("VOIDHUB_SEQ_NAME", "Name your new, empty rotation:")
        end)
        if mineName then
            root:CreateButton("Rename \"" .. mineName .. "\"...", function()
                pendingName = { action = "rename", old = mineName, default = mineName }
                StaticPopup_Show("VOIDHUB_SEQ_NAME", "New name:")
            end)
            root:CreateButton("|cffff5555Delete \"" .. mineName .. "\"...|r", function()
                pendingName = { action = "delete", old = mineName }
                StaticPopup_Show("VOIDHUB_SEQ_DELETE", mineName)
            end)
        end
        root:CreateDivider()
        root:CreateButton("Share: export as text...", function()
            textDialog({ title = "Share your rotation", readOnly = true, text = V.ExportMine(mineName),
                help = "Select all (Ctrl+A), copy (Ctrl+C) and paste it anywhere (Discord, a friend). They import it with Rotation > Import." })
        end)
        root:CreateButton("Import: paste a shared rotation...", function()
            textDialog({ title = "Import a rotation", text = "", okText = "Import",
                help = "Paste the text someone shared (Ctrl+V), then Import. It's added to your own rotations and switched on; nothing you have is replaced.",
                onAccept = function(text)
                    local r, msg = V.ImportMine(text)
                    if not r then print("|cffff5555VoidSequencer|r: " .. tostring(msg)) return false end
                    refreshAll()
                    return true
                end })
        end)
    end)
end

local function headDialog()
    local V = VS()
    textDialog({ title = "Every press", okText = "Save", text = V.GetHead and V.GetHead() or "",
        help = "One macro line per row; they run on every press, before the step. Examples: /startattack   /petattack [@target,harm,nodead]   /cast [@target,harm] !Auto Shot",
        onAccept = function(text) V.SetHead(text); refreshAll(); return true end })
end

----------------------------------------------------------------------
-- Rotation editor
----------------------------------------------------------------------
local function spellMenu(tile, stepIdx, slotIdx)
    local V = VS()
    MenuUtil.CreateContextMenu(tile, function(_, root)
        root:CreateTitle("Pick a spell")
        for _, name in ipairs(V.SpellPool()) do
            root:CreateButton(name, function() V.SetSpell(mode, stepIdx, slotIdx, name); V.Apply(); refreshAll() end)
        end
        root:CreateDivider()
        root:CreateButton("Custom spell name...", function()
            pendingCustom = { kind = "spell", step = stepIdx, slot = slotIdx }
            StaticPopup_Show("VOIDHUB_SEQ_CUSTOM")
        end)
        if #V.Seq(mode)[stepIdx] > 1 then
            root:CreateButton("|cffff5555Remove this spell|r", function() V.RemoveSpell(mode, stepIdx, slotIdx); V.Apply(); refreshAll() end)
        end
    end)
end

local function EditorBuild(host)
    ED = CreateFrame("Frame", nil, host)
    ED:SetAllPoints()
    ED.head = K.Text(ED, "GameFontNormalLarge"); ED.head:SetPoint("TOPLEFT", 16, -10)
    ED.tabs = K.Segments(ED, { { "ST", "Single target" }, { "AOE", "AoE" } }, 120, function(m) mode = m; ED.list.off = 0; ED.Render() end)
    ED.tabs[1]:SetPoint("TOPLEFT", 16, -38)
    local def = K.Button(ED, "Restore defaults", 130, function() local V = VS(); if V.Defaults then V.Defaults(mode); refreshAll() end end)
    def:SetPoint("LEFT", ED.tabs[2], "RIGHT", 24, 0)
    local add = K.Button(ED, "+ Add step", 100, function() local V = VS(); V.AddStep(mode); V.Apply(); refreshAll() end)
    add:SetPoint("LEFT", def, "RIGHT", 8, 0)
    -- which rotation runs, and your own (switch, new, rename, delete, share): the panel's Rotation menu
    ED.rot = K.Button(ED, "", 300, function(b) rotationMenu(b) end)
    ED.rot:SetPoint("LEFT", ED.head, "RIGHT", 16, 0)
    ED.rot.text:SetWidth(288); ED.rot.text:SetWordWrap(false)
    local head = K.Button(ED, "Every press...", 110, function() if VS().GetHead then headDialog() end end)
    head:SetPoint("LEFT", add, "RIGHT", 8, 0)
    ED.check = K.Text(ED, "GameFontHighlightSmall"); ED.check:SetPoint("TOPRIGHT", -16, -16)
    local hint = K.Text(ED, "GameFontDisableSmall", "Top = highest priority. Each step casts its first ready spell; the spells after it are fallbacks. Click a spell to change it. Edits apply at once (or when you leave combat).")
    hint:SetPoint("TOPLEFT", 16, -66); hint:SetWidth(900)
    ED.list = K.List(ED, 30, function(r)
        r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetPoint("TOPLEFT"); r.bg:SetPoint("BOTTOMRIGHT", 0, 2)
        r.num = K.Text(r, "GameFontNormal"); r.num:SetPoint("LEFT", 0, 0); r.num:SetWidth(26); r.num:SetJustifyH("RIGHT")
        r.up = K.Button(r, "Up", 34, function() VS().MoveStep(mode, r.idx, -1); VS().Apply(); refreshAll() end)
        r.up:SetPoint("LEFT", r.num, "RIGHT", 6, 0)
        r.dn = K.Button(r, "Down", 44, function() VS().MoveStep(mode, r.idx, 1); VS().Apply(); refreshAll() end)
        r.dn:SetPoint("LEFT", r.up, "RIGHT", 3, 0)
        r.del = K.Button(r, "Delete", 52, function()
            if #VS().Seq(mode) > 1 then VS().RemoveStep(mode, r.idx); VS().Apply(); refreshAll() end
        end)
        r.del:SetPoint("LEFT", r.dn, "RIGHT", 3, 0)
        r.tiles = {}
        r.plus = K.Button(r, "+ Spell", 62, function() VS().AddSpell(mode, r.idx, ""); refreshAll() end)
    end, function(r, step, i)
        r.idx = i
        r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0.06)
        r.num:SetText(i .. ".")
        for _, t in ipairs(r.tiles) do t:Hide() end
        local x = 200
        for j, spell in ipairs(step) do
            local t = r.tiles[j]
            if not t then
                t = K.Button(r, "", 116, nil)
                t.text:SetWidth(108); t.text:SetWordWrap(false)
                r.tiles[j] = t
            end
            t:SetScript("OnClick", function(s) spellMenu(s, r.idx, j) end)
            t:SetLabel(spell ~= "" and spell or "|cff999999(pick)|r")
            t:ClearAllPoints(); t:SetPoint("LEFT", r, "LEFT", x, 0)
            t:Show()
            x = x + 120
        end
        r.plus:ClearAllPoints(); r.plus:SetPoint("LEFT", r, "LEFT", x, 0)
    end)
    ED.list:SetPoint("TOPLEFT", 12, -92); ED.list:SetPoint("BOTTOMRIGHT", -12, 10)
    function ED.Render()
        local V = VS()
        local spec = V.CurrentSpec and V.CurrentSpec() or ""
        ED.head:SetText("|cff00c7ffRotation|r" .. (spec ~= "" and ("  |cff8c8c9e" .. spec .. "|r") or ""))
        ED.rot:SetLabel(rotationLabel())
        ED.tabs:Select(mode)
        ED.check:SetText("Rotation check: " .. (V.RotationSummary and V.RotationSummary() or ""))
        ED.list:SetData(V.Seq(mode) or {}, true)
    end
    ED:SetScript("OnShow", function() ED.Render() end)
    return ED
end

----------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------
local function SettingsBuild(host)
    ST = CreateFrame("Frame", nil, host)
    ST:SetAllPoints()
    local V = VS()
    local x, y = 16, -14
    local h = K.Text(ST, "GameFontNormal", "|cff00c7ffVoidSequencer|r"); h:SetPoint("TOPLEFT", x, y); y = y - 26
    ST.enable = K.Check(ST, "Enable VoidSequencer  (binds your key and runs the rotation)", function(_, on) if VS().SetEnabled then VS().SetEnabled(on) end end)
    ST.enable:SetPoint("TOPLEFT", x, y); y = y - 24
    ST.pacer = K.Check(ST, "Cadence glow  (lights up when a press will land: tap in rhythm, don't over-mash)", function(_, on) if VS().SetPacer then VS().SetPacer(on) end end)
    ST.pacer:SetPoint("TOPLEFT", x, y); y = y - 24
    ST.switch = K.Check(ST, "Show the ST / AoE switch on screen", function(s, on)
        if InCombatLockdown() then
            s:SetChecked(not on)
            print("|cffcc66ffVoidSequencer|r: leave combat to show or hide the switch.")
            return
        end
        VoidSequencerDB.switchHidden = not on
        if VS().ApplyEnabled then VS().ApplyEnabled() end
    end)
    ST.switch:SetPoint("TOPLEFT", x, y); y = y - 34

    local function row(label, w)
        local l = K.Text(ST, "GameFontHighlight", label); l:SetPoint("TOPLEFT", x, y - 4)
        local b = K.Button(ST, "", w or 260, nil); b:SetPoint("TOPLEFT", x + 190, y)
        b.text:SetWidth((w or 260) - 12); b.text:SetWordWrap(false)
        y = y - 30
        return b
    end
    ST.key = row("Rotation key", 160)
    ST.key:SetScript("OnClick", function(b) b:SetLabel("|cffffff00press a key...|r"); if VS().CaptureKey then VS().CaptureKey() end end)
    ST.build = row("Recommended talent build", 300)
    ST.build:SetScript("OnClick", function(self)
        local V2 = VS()
        local builds = (V2.RecommendedBuilds and V2.RecommendedBuilds()) or {}
        local specs = {}
        local _, _, classID = UnitClass("player")
        local cur = C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecialization()
        for i = 1, (C_SpecializationInfo.GetNumSpecializationsForClassID and C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0) do
            local id, name = C_SpecializationInfo.GetSpecializationInfo(i)
            local list = id and V2.BuildsForSpec and V2.BuildsForSpec(id, name) or {}
            if #list > 0 then specs[#specs + 1] = { id = id, name = name, current = (i == cur), builds = list } end
        end
        if #builds == 0 and #specs == 0 then return end
        MenuUtil.CreateContextMenu(self, function(_, root)
            if #specs > 0 then
                root:CreateTitle("Switch to a build (spec, talents, hero tree)")
                for _, sp in ipairs(specs) do
                    local sub = root:CreateButton(sp.name .. (sp.current and "  (current)" or ""))
                    for _, b in ipairs(sp.builds) do sub:CreateButton(b.name or "Build", function() V2.SwitchToBuild(sp.id, b) end) end
                end
            end
            if #builds == 0 then return end
            if #specs > 0 then root:CreateDivider() end
            root:CreateTitle("Put a build on your current talents")
            for _, b in ipairs(builds) do root:CreateButton(b.name or "Build", function() if V2.StageBuild then V2.StageBuild(b.build, b.name) end end) end
            local strings = {}
            for _, b in ipairs(builds) do if type(b.build) == "string" then strings[#strings + 1] = b end end
            if #strings == 0 then return end
            root:CreateDivider()
            local save = root:CreateButton("Save as a new loadout instead")
            for _, b in ipairs(strings) do save:CreateButton(b.name or "Build", function() if V2.ImportBuild then V2.ImportBuild(b.build, "VoidSeq " .. (b.name or "Build")) end end) end
        end)
    end)
    ST.rot = row("Rotation", 300)
    ST.rot:SetScript("OnClick", function(self) rotationMenu(self) end)
    local cl = K.Text(ST, "GameFontHighlight", "Rotation check"); cl:SetPoint("TOPLEFT", x, y - 4)
    ST.check = K.Text(ST, "GameFontHighlightSmall"); ST.check:SetPoint("TOPLEFT", x + 190, y - 5); ST.check:SetWidth(300); ST.check:SetWordWrap(false)
    local det = K.Button(ST, "Details", 70, function() if VS().PrintRotationCheck then VS().PrintRotationCheck() end end); det:SetPoint("TOPLEFT", x + 500, y)
    local test = K.Button(ST, "Test my rotation", 130, function() if VS().OpenRotationTest then VS().OpenRotationTest() end end); test:SetPoint("LEFT", det, "RIGHT", 6, 0)
    y = y - 40
    local mh = K.Text(ST, "GameFontNormal", "|cff00c7ffModifier casts|r  |cff8c8c9ehold the key while you press your rotation key|r"); mh:SetPoint("TOPLEFT", x, y); y = y - 26
    ST.mods = {}
    for _, d in ipairs({ { "alt", "Hold ALT" }, { "ctrl", "Hold CTRL" }, { "shift", "Hold SHIFT" } }) do
        local key, label = d[1], d[2]
        local b = row(label, 220)
        b:SetScript("OnClick", function(self)
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateTitle("Pick an ability for " .. label)
                root:CreateButton("|cff888888(none)|r", function() VS().SetMod(key, ""); refreshAll() end)
                root:CreateDivider()
                for _, name in ipairs(VS().SpellPool()) do root:CreateButton(name, function() VS().SetMod(key, name); refreshAll() end) end
                root:CreateDivider()
                root:CreateButton("Custom ability name...", function() pendingCustom = { kind = "mod", key = key }; StaticPopup_Show("VOIDHUB_SEQ_CUSTOM") end)
            end)
        end)
        ST.mods[key] = b
    end
    function ST.Render()
        local V2 = VS()
        if V2.GetEnabled then ST.enable:SetChecked(V2.GetEnabled()) end
        if V2.GetPacer then ST.pacer:SetChecked(V2.GetPacer()) end
        ST.switch:SetChecked(not (VoidSequencerDB and VoidSequencerDB.switchHidden))
        local k = V2.GetKey and V2.GetKey()
        local shown = k and ((GetBindingText and GetBindingText(k)) or k)
        ST.key:SetLabel(shown and ("|cff55ff55" .. shown .. "|r  (change)") or "|cffff5555unbound|r  (set)")
        -- builds: the panel's own count (switch list, else this class's builds)
        local n, builds = 0, (V2.RecommendedBuilds and V2.RecommendedBuilds()) or {}
        n = #builds
        ST.build:SetLabel(n > 0 and ("Choose a build...  (" .. n .. ")") or "(no builds for your class yet)")
        ST.rot:SetLabel(rotationLabel())
        ST.check:SetText(V2.RotationSummary and V2.RotationSummary() or "")
        for key, b in pairs(ST.mods) do
            local m = (V2.GetMod and V2.GetMod(key)) or ""
            b:SetLabel(m ~= "" and m or "|cff888888(none)|r")
        end
    end
    ST:SetScript("OnShow", function() ST.Render() end)
    return ST
end

-- VoidSequencer refreshes its options after a key capture, a rotation pick, a talent change: the hub follows
do
    local hooked
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        local V = VS()
        if hooked or not (V and V.RefreshOptions) then return end
        hooked = true
        hooksecurefunc(V, "RefreshOptions", function() refreshAll() end)
    end)
end

ns.RegisterPage("VoidSequencer", {
    available = function() return VS() ~= nil or K.SettingsCategory("VoidSequencer") ~= nil end,
    sections = function()
        if VS() and VS().Seq then
            return {
                { key = "rotation", label = "Rotation", build = EditorBuild },
                { key = "settings", label = "Settings", build = SettingsBuild },
            }
        end
        return { { key = "editor", label = "Rotations", build = function(host)
            return K.CanvasPage(host, "VoidSequencer") or K.Text(host, "GameFontDisableSmall", "VoidSequencer's options aren't registered yet.")
        end } }
    end,
})
