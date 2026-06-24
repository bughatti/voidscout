----------------------------------------------------------------------
-- VoidScout LabelPicker — floating icon + role/subcategory picker.
--
-- v0.2.0 scope:
--   * Free-floating 40x40 icon, draggable via Shift+drag
--   * Default position: top-right near minimap (offset from UIParent)
--   * Always visible during gameplay
--   * Badge text shows current label code (D / D+U / T+R / H+S / etc.)
--   * Click → expand picker frame (Tank/Healer/DPS + Utility/Soaks/Rescues)
--   * Role auto-defaults from spec, auto-flips on PLAYER_SPECIALIZATION_CHANGED
--   * State saved to VoidScoutCharDB.label + VoidScoutDB.iconPos
--
-- Not in v0.2:
--   * Boss-specific subcategories (Kicks, Orbs, etc.)
--   * CLEU scoring during fights
--   * Per-encounter label persistence
--   * Visual prompts on zone-in / boss pull
----------------------------------------------------------------------

local mod = {}
VoidScout.LabelPicker = mod

local ICON_SIZE      = 40
local PICKER_WIDTH   = 280
local PICKER_HEIGHT  = 400

local C = {
    bg        = { 0.05, 0.05, 0.07, 0.95 },
    border    = { 0x00/255, 0xC7/255, 0xFF/255, 0.7 },
    titleBg   = { 0x00/255, 0xC7/255, 0xFF/255, 0.15 },
    accent    = "ff00c7ff",
    accentRGB = { 0x00/255, 0xC7/255, 0xFF/255 },
    text      = { 0.92, 0.92, 0.95 },
    textDim   = { 0.55, 0.55, 0.62 },
    rolePicked = { 0x00/255, 0xC7/255, 0xFF/255, 0.4 },  -- cyan highlight for selected role
}

local ROLE_LABELS = {
    TANK   = "Tank",
    HEALER = "Healer",
    DPS    = "DPS",
}
local ROLE_CODES = {
    TANK = "T", HEALER = "H", DPS = "D",
}
-- Universal "duties" — what user is doing in the fight.
-- These map to backend mechanic groupings per-boss (see voidscout-data/*.json
-- duty_to_mechanics). Adding a new universal duty: add it here.
local SUBCAT_LABELS = {
    boss_dps  = "Boss DPS",
    add_duty  = "Add Duty",
    kicks     = "Kicks",
    soaks     = "Soaks",
    rescues   = "Rescues",
    dispels   = "Dispels",
    utility   = "Utility (other)",
}
local SUBCAT_ORDER = { "boss_dps", "add_duty", "kicks", "soaks", "rescues", "dispels", "utility" }
local SUBCAT_CODES = {
    boss_dps  = "B",
    add_duty  = "A",
    kicks     = "K",
    soaks     = "S",
    rescues   = "R",
    dispels   = "Dp",
    utility   = "U",
}

local icon = nil
local picker = nil
local roleButtons = {}
local subcatChecks = {}

----------------------------------------------------------------------
-- Defaults + state
----------------------------------------------------------------------
local function ComputeDefaultRole()
    local specIdx = GetSpecialization and GetSpecialization()
    if not specIdx then return "DPS" end
    local role = GetSpecializationRole and GetSpecializationRole(specIdx)
    if role == "TANK"   then return "TANK"   end
    if role == "HEALER" then return "HEALER" end
    return "DPS"
end

local function InitState()
    -- Per-character: role + subcategory selections (each char's spec /
    -- duties differ — DK DPS uses different subcats than druid tank).
    VoidScoutCharDB = VoidScoutCharDB or {}
    if not VoidScoutCharDB.label then
        -- First load of this char after per-char migration. Copy legacy
        -- subcategories from the old account-wide store (if any) but
        -- recompute role from THIS char's spec so the druid tank doesn't
        -- inherit the DK's DPS role.
        local legacy_subs = (VoidScoutDB and VoidScoutDB.label and VoidScoutDB.label.subcats) or {}
        local cloned = {}
        for k, v in pairs(legacy_subs) do cloned[k] = v end
        VoidScoutCharDB.label = {
            role    = ComputeDefaultRole(),
            subcats = cloned,
        }
    end
    if not VoidScoutCharDB.label.role then
        VoidScoutCharDB.label.role = ComputeDefaultRole()
    end
    VoidScoutCharDB.label.subcats = VoidScoutCharDB.label.subcats or {}

    -- Account-wide: icon position (icon stays put across chars).
    VoidScoutDB.iconPos = VoidScoutDB.iconPos or {
        point  = "TOPRIGHT",
        relTo  = "UIParent",
        relPt  = "TOPRIGHT",
        x      = -220,
        y      = -60,
    }
end

local function GetBadgeText()
    local label = VoidScoutCharDB.label or {}
    local roleCode = ROLE_CODES[label.role] or "?"
    local subList = {}
    for _, k in ipairs(SUBCAT_ORDER) do
        if label.subcats and label.subcats[k] then
            subList[#subList + 1] = SUBCAT_CODES[k]
        end
    end
    if #subList == 0 then return roleCode end
    return roleCode .. "+" .. table.concat(subList)
end

local function GetLabelDescription()
    local label = VoidScoutCharDB.label or {}
    local roleStr = ROLE_LABELS[label.role] or "?"
    local subs = {}
    for _, k in ipairs(SUBCAT_ORDER) do
        if label.subcats and label.subcats[k] then
            subs[#subs + 1] = SUBCAT_LABELS[k]
        end
    end
    if #subs == 0 then return roleStr end
    return roleStr .. " / " .. table.concat(subs, ", ")
end

----------------------------------------------------------------------
-- Icon construction
----------------------------------------------------------------------
local function UpdateBadge()
    if not icon or not icon._badge then return end
    icon._badge:SetText(GetBadgeText())
end

local function CreateIcon()
    if icon then return icon end

    icon = CreateFrame("Button", "VoidScoutIcon", UIParent, "BackdropTemplate")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetFrameStrata("MEDIUM")
    icon:SetClampedToScreen(true)
    icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    icon:RegisterForDrag("LeftButton")
    icon:SetMovable(true)

    -- Restore saved position
    icon:ClearAllPoints()
    local p = VoidScoutDB.iconPos
    icon:SetPoint(p.point, UIParent, p.relPt or p.point, p.x, p.y)

    -- Backdrop
    icon:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    icon:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
    icon:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], C.border[4])

    -- Spyglass texture as background icon (subtle, low alpha)
    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
    tex:SetPoint("TOPLEFT", icon, "TOPLEFT", 2, -2)
    tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
    tex:SetAlpha(0.45)
    tex:SetDesaturated(true)

    -- Badge text overlay (current label code)
    local badge = icon:CreateFontString(nil, "OVERLAY")
    badge:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    badge:SetTextColor(C.accentRGB[1], C.accentRGB[2], C.accentRGB[3])
    badge:SetPoint("CENTER", icon, "CENTER", 0, 0)
    icon._badge = badge

    -- Plain drag to move (RegisterForDrag separates click from drag)
    icon:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    icon:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPt, x, y = self:GetPoint()
        VoidScoutDB.iconPos = {
            point = point, relTo = "UIParent", relPt = relPt, x = x, y = y,
        }
    end)

    -- Click → toggle picker (left) or open priority popup (right)
    icon:SetScript("OnClick", function(self, btn)
        if btn == "LeftButton" then
            mod:TogglePicker()
        elseif btn == "RightButton" then
            if VoidScout.TrashDiscovery and VoidScout.TrashDiscovery.ShowPriorityPopup then
                VoidScout.TrashDiscovery:ShowPriorityPopup()
            end
        end
    end)

    -- Tooltip
    icon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText("|c" .. C.accent .. "VoidScout|r", 1, 1, 1)
        GameTooltip:AddLine("Current label: " .. GetLabelDescription(), 0.92, 0.92, 0.95, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click: change role / subcategory", 0.55, 0.55, 0.62)
        GameTooltip:AddLine("Right-click: priority interrupt candidates", 0.55, 0.55, 0.62)
        GameTooltip:AddLine("Drag: move icon", 0.55, 0.55, 0.62)
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UpdateBadge()
    return icon
end

----------------------------------------------------------------------
-- Picker construction
----------------------------------------------------------------------
local function PaintRoleButtons()
    for roleKey, btn in pairs(roleButtons) do
        if roleKey == VoidScoutCharDB.label.role then
            btn.bg:SetVertexColor(C.rolePicked[1], C.rolePicked[2], C.rolePicked[3], C.rolePicked[4])
            btn.text:SetTextColor(1, 1, 1)
        else
            btn.bg:SetVertexColor(0.15, 0.15, 0.18, 0.6)
            btn.text:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
        end
    end
end

local function SyncSubcatChecks()
    for _, k in ipairs(SUBCAT_ORDER) do
        local cb = subcatChecks[k]
        if cb then
            cb:SetChecked(VoidScoutCharDB.label.subcats[k] and true or false)
        end
    end
end

local function CreatePicker()
    if picker then return picker end

    picker = CreateFrame("Frame", "VoidScoutPicker", UIParent, "BackdropTemplate")
    picker:SetSize(PICKER_WIDTH, PICKER_HEIGHT)
    picker:SetFrameStrata("DIALOG")
    picker:SetClampedToScreen(true)
    picker:Hide()

    picker:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    picker:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
    picker:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], C.border[4])

    -- Title bar
    local titleBg = picker:CreateTexture(nil, "ARTWORK")
    titleBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    titleBg:SetVertexColor(C.titleBg[1], C.titleBg[2], C.titleBg[3], C.titleBg[4])
    titleBg:SetPoint("TOPLEFT",  picker, "TOPLEFT",   1, -1)
    titleBg:SetPoint("TOPRIGHT", picker, "TOPRIGHT", -1, -1)
    titleBg:SetHeight(26)

    local title = picker:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    title:SetText("|c" .. C.accent .. "VoidScout|r  Role Picker")
    title:SetPoint("LEFT", titleBg, "LEFT", 10, 0)

    -- Close button (top-right of picker)
    local close = CreateFrame("Button", nil, picker, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:SetPoint("RIGHT", titleBg, "RIGHT", 4, 0)
    close:SetScript("OnClick", function() picker:Hide() end)

    -- "ROLE" section label
    local roleLabel = picker:CreateFontString(nil, "OVERLAY")
    roleLabel:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    roleLabel:SetText("ROLE")
    roleLabel:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    roleLabel:SetPoint("TOPLEFT", picker, "TOPLEFT", 12, -36)

    -- Role buttons (3 equal-width pills)
    local roleRow = CreateFrame("Frame", nil, picker)
    roleRow:SetPoint("TOPLEFT", roleLabel, "BOTTOMLEFT", 0, -6)
    roleRow:SetPoint("TOPRIGHT", picker, "TOPRIGHT", -12, -52)
    roleRow:SetHeight(34)

    local roleOrder = { "TANK", "HEALER", "DPS" }
    local btnWidth = (PICKER_WIDTH - 24 - 2 * 8) / 3
    for i, roleKey in ipairs(roleOrder) do
        local btn = CreateFrame("Button", nil, roleRow, "BackdropTemplate")
        btn:SetSize(btnWidth, 30)
        btn:SetPoint("LEFT", roleRow, "LEFT", (i - 1) * (btnWidth + 8), 0)
        btn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        btn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 0.5)

        local bg = btn:CreateTexture(nil, "ARTWORK")
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        bg:SetPoint("TOPLEFT",  btn, "TOPLEFT",   1, -1)
        bg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        btn.bg = bg

        local txt = btn:CreateFontString(nil, "OVERLAY")
        txt:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        txt:SetText(ROLE_LABELS[roleKey])
        txt:SetPoint("CENTER", btn, "CENTER", 0, 0)
        btn.text = txt

        btn:SetScript("OnClick", function()
            VoidScoutCharDB.label.role = roleKey
            PaintRoleButtons()
            UpdateBadge()
        end)
        roleButtons[roleKey] = btn
    end

    -- Auto-default note
    local autoNote = picker:CreateFontString(nil, "OVERLAY")
    autoNote:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    autoNote:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    autoNote:SetText("(auto-set from spec; changes when you respec)")
    autoNote:SetPoint("TOPLEFT", roleRow, "BOTTOMLEFT", 0, -4)

    -- "DUTIES (pick what you're doing this fight)" section label
    local subLabel = picker:CreateFontString(nil, "OVERLAY")
    subLabel:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    subLabel:SetText("DUTIES (pick what you're doing)")
    subLabel:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    subLabel:SetPoint("TOPLEFT", autoNote, "BOTTOMLEFT", 0, -16)

    -- Subcategory checkboxes
    local prevAnchor = subLabel
    for _, key in ipairs(SUBCAT_ORDER) do
        local cb = CreateFrame("CheckButton", nil, picker, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, -4)

        local lbl = picker:CreateFontString(nil, "OVERLAY")
        lbl:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
        lbl:SetText(SUBCAT_LABELS[key])
        lbl:SetTextColor(C.text[1], C.text[2], C.text[3])
        lbl:SetPoint("LEFT", cb, "RIGHT", 4, 1)

        cb:SetChecked(VoidScoutCharDB.label.subcats[key] and true or false)
        cb:SetScript("OnClick", function(self)
            VoidScoutCharDB.label.subcats[key] = self:GetChecked() and true or nil
            UpdateBadge()
        end)
        subcatChecks[key] = cb
        prevAnchor = cb
    end

    -- Footer hint
    local footer = picker:CreateFontString(nil, "OVERLAY")
    footer:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    footer:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    footer:SetText("Boss-specific duties (Orbs, Memory, Realm, etc.)\nwill appear here when in a known fight.")
    footer:SetJustifyH("CENTER")
    footer:SetPoint("BOTTOM", picker, "BOTTOM", 0, 12)

    -- Position picker near the icon when opened
    picker:HookScript("OnShow", function(self)
        self:ClearAllPoints()
        if icon then
            -- If icon is on right half of screen, picker opens to the LEFT of it.
            local _, _, _, iconX = icon:GetPoint()
            local screenW = UIParent:GetWidth()
            if iconX and iconX < -(screenW * 0.5) then
                -- icon is right-anchored far from center → open picker to its left
                self:SetPoint("TOPRIGHT", icon, "TOPLEFT", -8, 0)
            else
                self:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 0)
            end
        else
            self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        PaintRoleButtons()
        SyncSubcatChecks()
    end)

    -- Close on Escape
    tinsert(UISpecialFrames, "VoidScoutPicker")

    return picker
end

function mod:TogglePicker()
    if not picker then CreatePicker() end
    if picker:IsShown() then picker:Hide() else picker:Show() end
end

----------------------------------------------------------------------
-- Spec / character change → auto-flip role
--
-- Fires on:
--   PLAYER_SPECIALIZATION_CHANGED — live respec mid-session
--   PLAYER_ENTERING_WORLD         — character login / zone-in, catches
--                                    "respec while offline" + the case
--                                    where the user logs into a different
--                                    char (per-char DB ensures the role
--                                    is re-evaluated against THIS char's
--                                    current spec).
----------------------------------------------------------------------
local specWatcher = CreateFrame("Frame")
specWatcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
specWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
specWatcher:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit and unit ~= "player" then return end
    -- Defensive: ensure state is initialized (PLAYER_ENTERING_WORLD can
    -- fire before our own login init in rare cases).
    if not (VoidScoutCharDB and VoidScoutCharDB.label) then return end
    local newRole = ComputeDefaultRole()
    if newRole ~= VoidScoutCharDB.label.role then
        VoidScoutCharDB.label.role = newRole
        UpdateBadge()
        if picker and picker:IsShown() then PaintRoleButtons() end
        local reason = (event == "PLAYER_SPECIALIZATION_CHANGED") and "spec change" or "char/spec detected on login"
        print(("|c%sVoidScout:|r role auto-flipped to %s (%s)"):format(C.accent, ROLE_LABELS[newRole], reason))
    end
end)

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------
function mod:Init()
    InitState()
    CreateIcon()
end
