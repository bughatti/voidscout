-- VoidScout.S2Probe: one-shot Season 2 data probe (/vs s2).
-- Dumps to a COPYABLE popup (never chat): current M+ season ID, the season's
-- challenge-map table (id/name/timer), and every Encounter Journal instance of
-- the latest tier with BOTH encounter IDs per boss -- journalEncounterID (EJ)
-- and dungeonEncounterID (what ENCOUNTER_START / our fights table uses).
-- Purpose: feed the backend S2 config (season id, Venomous Abyss + new dungeon
-- encounter IDs, M+ timer data) without hand-copying from wowhead.

local VoidScout = _G.VoidScout
local P = {}
if VoidScout then VoidScout.S2Probe = P end

local function safe(fn, ...)
    if not fn then return nil end
    local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h end
end

local copyFrame
local function ShowCopy(text)
    if not copyFrame then
        copyFrame = CreateFrame("Frame", "VoidScoutS2Copy", UIParent, "BackdropTemplate")
        copyFrame:SetSize(560, 420); copyFrame:SetPoint("CENTER")
        copyFrame:SetFrameStrata("FULLSCREEN_DIALOG"); copyFrame:SetToplevel(true)
        copyFrame:SetMovable(true); copyFrame:EnableMouse(true); copyFrame:RegisterForDrag("LeftButton")
        copyFrame:SetScript("OnDragStart", copyFrame.StartMoving)
        copyFrame:SetScript("OnDragStop", copyFrame.StopMovingOrSizing)
        copyFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        copyFrame:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
        copyFrame:SetBackdropBorderColor(0.3, 0.6, 0.9, 0.8)
        local title = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -8); title:SetText("VoidScout — S2 Probe (Ctrl+C, paste to Claude)")
        local close = CreateFrame("Button", nil, copyFrame, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)
        local scroll = CreateFrame("ScrollFrame", nil, copyFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -30); scroll:SetPoint("BOTTOMRIGHT", -30, 12)
        local eb = CreateFrame("EditBox", nil, scroll)
        eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal); eb:SetWidth(500)
        eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
        scroll:SetScrollChild(eb)
        copyFrame.eb = eb
    end
    copyFrame.eb:SetText(text)
    copyFrame:Show()
    copyFrame.eb:SetFocus()
    copyFrame.eb:HighlightText()
end

function P:Run()
    local out = {}
    local function add(fmt, ...) out[#out + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end

    add("== VoidScout S2 probe, %s ==", date("%Y-%m-%d %H:%M"))
    add("build: %s (%s)", (select(1, GetBuildInfo())) or "?", (select(2, GetBuildInfo())) or "?")

    -- M+ season + challenge maps
    add("\n-- MythicPlus --")
    add("currentSeason: %s", tostring(safe(C_MythicPlus.GetCurrentSeason)))
    add("currentUIDisplaySeason: %s", tostring(safe(C_MythicPlus.GetCurrentUIDisplaySeason)))
    local maps = safe(C_ChallengeMode.GetMapTable) or {}
    add("challengeMaps (%d):", #maps)
    for _, mid in ipairs(maps) do
        local name, id, timeLimit = safe(C_ChallengeMode.GetMapUIInfo, mid)
        add("  %d\t%s\ttimer=%ss", id or mid, name or "?", tostring(timeLimit))
    end

    -- Encounter Journal: latest tier, all instances, both encounter IDs
    safe(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
    local numTiers = safe(EJ_GetNumTiers) or 0
    safe(EJ_SelectTier, numTiers)
    add("\n-- EncounterJournal tier %d/%d --", numTiers, numTiers)
    for _, isRaid in ipairs({ true, false }) do
        add(isRaid and "\n[RAIDS]" or "\n[DUNGEONS]")
        local i = 1
        while true do
            local instID, instName = safe(EJ_GetInstanceByIndex, i, isRaid)
            if not instID then break end
            add("%s (journalInstance %d):", instName or "?", instID)
            safe(EJ_SelectInstance, instID)
            local b = 1
            while true do
                -- name, desc, journalEncounterID, rootSection, link, journalInstanceID, dungeonEncounterID, instanceID
                local bName, _, jID, _, _, _, dID = safe(EJ_GetEncounterInfoByIndex, b, instID)
                if not bName then break end
                add("  boss %d\t%s\tjournalEnc=%s\tdungeonEnc=%s", b, bName, tostring(jID), tostring(dID))
                b = b + 1
            end
            i = i + 1
        end
    end

    ShowCopy(table.concat(out, "\n"))
end
