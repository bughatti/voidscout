----------------------------------------------------------------------
-- VoidScout Minimap — standardized minimap button.
-- Global name VoidScoutMinimapBtn so VoidHubBundle discovers it.
--
--   Size: 28x28 button, 20x20 icon, 54x54 border, offset (-2, 2)
--   Radius: (Minimap:GetWidth() / 2) + 6
--   Angle stored as DEGREES in VoidScoutCharDB.minimapAngle (default 250)
--
-- Click behavior:
--   Left  -> open the LFG side panel preview (same as /vs show)
--   Right -> open the consent dialog (same as /vs consent)
----------------------------------------------------------------------
local btn

local function PositionButton(b)
    VoidScoutCharDB = VoidScoutCharDB or {}
    local angle  = math.rad(VoidScoutCharDB.minimapAngle or 250)
    local radius = (Minimap:GetWidth() / 2) + 6
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", radius * math.cos(angle), radius * math.sin(angle))
end

local function CreateMinimapButton()
    if btn then return btn end
    if _G.VoidScoutMinimapBtn then btn = _G.VoidScoutMinimapBtn; return btn end
    if not Minimap then return end

    btn = CreateFrame("Button", "VoidScoutMinimapBtn", Minimap)
    btn:SetSize(28, 28)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 10)

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    -- Spyglass — matches the TOC IconTexture and the "scout" theme
    icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if VoidScout_ShowConsentDialog then
                VoidScout_ShowConsentDialog()
            end
            return
        end
        -- Left-click: open Blizzard's Group Finder window (where the
        -- VoidScout LFG side panel attaches). If it's already open,
        -- toggle the floating VoidScoutMyPanel summary card.
        local lfgFrame = _G.PVEFrame
        if lfgFrame and lfgFrame:IsShown() then
            local p = _G.VoidScoutMyPanel
            if p and p:IsShown() then
                p:Hide()
            elseif p then
                p:Show()
            end
        else
            -- Open the Group Finder via the Blizzard helper.
            if PVEFrame_ToggleFrame then
                PVEFrame_ToggleFrame("GroupFinderFrame", LFGListPVEStub)
            elseif ToggleLFDParentFrame then
                ToggleLFDParentFrame()
            end
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("|cff00c7ffVoidScout|r", 1, 1, 1)
        -- Surface consent state when known.
        if VoidScoutDB and VoidScoutDB.consent then
            local c = VoidScoutDB.consent.choice
            local mode = "(undecided)"
            if c == "allowed" then
                mode = "|cff20ff20uploads ENABLED|r"
            elseif c == "local" then
                mode = "|cffffaa20LOCAL-ONLY|r"
            end
            GameTooltip:AddLine("Mode: " .. mode, 0.85, 0.85, 0.85)
            GameTooltip:AddLine(" ", 1, 1, 1)
        end
        GameTooltip:AddLine("Left-click: open scoring panel", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("Right-click: consent / opt-out", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("Drag: reposition around minimap", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetMovable(true)
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self) self._dragging = true end)
    btn:SetScript("OnDragStop",  function(self) self._dragging = false end)
    btn:SetScript("OnUpdate", function(self)
        if self._dragging then
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local px, py = GetCursorPosition()
            if not mx or not px or not scale then return end
            px = px / scale; py = py / scale
            VoidScoutCharDB = VoidScoutCharDB or {}
            VoidScoutCharDB.minimapAngle = math.deg(math.atan2(py - my, px - mx))
            PositionButton(self)
        end
    end)

    PositionButton(btn)
    return btn
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    CreateMinimapButton()
    VoidScoutCharDB = VoidScoutCharDB or {}
    if btn and VoidScoutCharDB.minimapHidden then btn:Hide() end
end)
