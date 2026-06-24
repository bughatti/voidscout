----------------------------------------------------------------------
-- VoidScout LFGFieldScanner
--
-- One-shot diagnostic: `/vs scan` walks every visible LFG search-result
-- entry and dumps EVERY field of its searchResultInfo + every text we
-- can extract from the rendered frame, trying multiple conversion paths
-- (tostring, format, concat, GetText). Output goes to chat AND a
-- copyable popup so we can see exactly which fields hold the "+N" key
-- level and which conversion path makes them readable.
--
-- After we identify which signal works, the main code can use it.
----------------------------------------------------------------------

VoidScout = VoidScout or {}
local mod = {}
VoidScout.LFGFieldScanner = mod

local function safe_tostring(v)
    if v == nil then return "nil" end
    local ok, s = pcall(tostring, v)
    if ok and s then return s end
    return "<tostring-error>"
end

local function safe_format(v)
    if v == nil then return "nil" end
    local ok, s = pcall(function() return ("%s"):format(v) end)
    if ok and s then return s end
    return "<format-error>"
end

local function safe_concat(v)
    if v == nil then return "nil" end
    local ok, s = pcall(function() return "" .. v end)
    if ok and s then return s end
    return "<concat-error>"
end

local function safe_match(v, pat)
    if v == nil then return "nil" end
    local ok, m = pcall(function() return v:match(pat) end)
    if ok then return tostring(m) end
    return "<match-error>"
end

-- Try every conversion + match on one value
local function probe(label, v)
    local lines = {}
    local ts = safe_tostring(v)
    local fm = safe_format(v)
    local cc = safe_concat(v)
    lines[#lines+1] = "  " .. label .. ":"
    lines[#lines+1] = "    type=" .. type(v)
    lines[#lines+1] = '    tostring="' .. ts .. '"'
    lines[#lines+1] = '    format  ="' .. fm .. '"'
    lines[#lines+1] = '    concat  ="' .. cc .. '"'
    -- Try matching "+N" via each rendered form. Escape via concat to avoid
    -- :format's percent-handling.
    lines[#lines+1] = "    match(tostring,+N) = " .. safe_match(ts, "%+(%d+)")
    lines[#lines+1] = "    match(format,  +N) = " .. safe_match(fm, "%+(%d+)")
    lines[#lines+1] = "    match(concat,  +N) = " .. safe_match(cc, "%+(%d+)")
    -- issecretvalue?
    if _G.issecretvalue then
        local ok, secret = pcall(issecretvalue, v)
        lines[#lines+1] = "    issecretvalue=" .. (ok and tostring(secret) or "err")
    end
    return lines
end

-- Walk a frame's children + regions and dump ALL fontstrings with text.
-- This finds the listing title even if Blizzard renamed the field.
local function dump_frame_text(frame)
    local lines = {}
    if not frame then return lines end
    lines[#lines+1] = "  -- Walking frame text regions --"

    -- Known/named children
    local named_candidates = {
        "Name", "Title", "GroupName", "ListingName", "Header",
        "ActivityName", "Activity", "Description",
        "Difficulty", "KeyLevel", "DataDisplay",
        "Members", "Leader", "PartyName",
    }
    for _, key in ipairs(named_candidates) do
        local sub = frame[key]
        if sub and sub.GetText then
            local ok, txt = pcall(sub.GetText, sub)
            if ok and txt and txt ~= "" then
                lines[#lines+1] = ("    frame." .. key .. ":GetText() = \"" .. tostring(txt) .. "\"")
                -- Quick match test
                local n = txt:match("%+(%d+)")
                if n then lines[#lines+1] = ("      ^^ MATCHED +N = " .. n) end
            end
        end
    end

    -- Walk all regions (fontstrings, textures)
    if frame.GetRegions then
        local i = 0
        for _, region in ipairs({frame:GetRegions()}) do
            i = i + 1
            if region.GetText then
                local ok, txt = pcall(region.GetText, region)
                if ok and txt and txt ~= "" then
                    lines[#lines+1] = ("    region[" .. i .. "]:GetText() = \"" .. tostring(txt) .. "\"")
                    local n = txt:match("%+(%d+)")
                    if n then lines[#lines+1] = ("      ^^ MATCHED +N = " .. n) end
                end
            end
        end
    end

    -- Walk all children
    if frame.GetChildren then
        local children = { frame:GetChildren() }
        for ci, child in ipairs(children) do
            if child.GetRegions then
                for _, region in ipairs({child:GetRegions()}) do
                    if region.GetText then
                        local ok, txt = pcall(region.GetText, region)
                        if ok and txt and txt ~= "" then
                            lines[#lines+1] = ("    child[" .. ci .. "].region:GetText() = \"" .. tostring(txt) .. "\"")
                            local n = txt:match("%+(%d+)")
                            if n then lines[#lines+1] = ("      ^^ MATCHED +N = " .. n) end
                        end
                    end
                end
            end
        end
    end

    return lines
end

-- Walk the visible LFG SearchPanel result buttons
local function find_visible_entries()
    local sp = LFGListFrame and LFGListFrame.SearchPanel
    if not sp then return {} end
    local out = {}
    -- Modern LFG uses a scrollbox; try GetScrollFrame or children
    local sbox = sp.ScrollBox or sp.ResultsScrollFrame
    if sbox and sbox.GetFrames then
        for _, frame in ipairs(sbox:GetFrames()) do
            if frame.resultID then out[#out+1] = frame end
        end
    end
    -- Fallback: walk children
    if #out == 0 and sp.GetChildren then
        for _, child in ipairs({sp:GetChildren()}) do
            if child.resultID then out[#out+1] = child end
        end
    end
    return out
end

function mod:Scan(max_entries)
    max_entries = max_entries or 3
    local lines = {
        "============ VoidScout LFG Field Scan ============",
        ("Time: %s"):format(date("%H:%M:%S")),
    }

    local frames = find_visible_entries()
    lines[#lines+1] = ("Found %d visible entry frames"):format(#frames)

    if #frames == 0 then
        lines[#lines+1] = ""
        lines[#lines+1] = "ERROR: No entry frames found. Open Premade Groups,"
        lines[#lines+1] = "       do a search so results are visible, then re-run /vs scan."
    end

    for i = 1, math.min(#frames, max_entries) do
        local f = frames[i]
        lines[#lines+1] = ""
        lines[#lines+1] = ("---- Entry #%d  resultID=%s ----"):format(i, tostring(f.resultID))

        -- Walk the rendered frame to find ALL text — locates listing title
        -- regardless of which key Blizzard stores it under in 12.0.5
        for _, ln in ipairs(dump_frame_text(f)) do
            lines[#lines+1] = ln
        end

        -- Search result info fields
        local ok, info = pcall(C_LFGList.GetSearchResultInfo, f.resultID)
        if ok and info then
            for _, key in ipairs({
                "name", "comment", "voiceChat", "leaderName",
                "leaderOverallDungeonScore", "requiredDungeonScore",
                "requiredItemLevel", "numMembers",
            }) do
                for _, ln in ipairs(probe("info." .. key, info[key])) do
                    lines[#lines+1] = ln
                end
            end
            -- leaderDungeonScoreInfo struct dive (recursive 1 level)
            local ldsi = info.leaderDungeonScoreInfo
            if ldsi then
                lines[#lines+1] = "  info.leaderDungeonScoreInfo:"
                lines[#lines+1] = "    type=" .. type(ldsi)
                if type(ldsi) == "table" then
                    for k, v in pairs(ldsi) do
                        lines[#lines+1] = "    [" .. tostring(k) .. "] type=" .. type(v)
                        if type(v) == "table" then
                            for k2, v2 in pairs(v) do
                                lines[#lines+1] = "       ." .. tostring(k2)
                                                    .. " = " .. safe_tostring(v2)
                                                    .. " (" .. type(v2) .. ")"
                            end
                        end
                    end
                end
            end
            -- Also dive leaderBestDungeonScoreInfo
            local lbdsi = info.leaderBestDungeonScoreInfo
            if lbdsi then
                lines[#lines+1] = "  info.leaderBestDungeonScoreInfo:"
                lines[#lines+1] = "    type=" .. type(lbdsi)
                if type(lbdsi) == "table" then
                    for k, v in pairs(lbdsi) do
                        lines[#lines+1] = "    ." .. tostring(k)
                                            .. " = " .. safe_tostring(v)
                                            .. " (" .. type(v) .. ")"
                    end
                end
            end
            -- activity full name
            local actID = (info.activityIDs and info.activityIDs[1]) or info.activityID
            if actID and C_LFGList.GetActivityFullName then
                local ok2, full = pcall(C_LFGList.GetActivityFullName, actID, nil, info.isWarMode)
                if ok2 then
                    for _, ln in ipairs(probe(("GetActivityFullName(%d)"):format(actID), full)) do
                        lines[#lines+1] = ln
                    end
                end
            end
        else
            lines[#lines+1] = "  GetSearchResultInfo FAILED"
        end
    end

    lines[#lines+1] = "============ END SCAN ============"

    -- Dump to chat AND save to SavedVariables for inspection
    for _, l in ipairs(lines) do print(l) end
    VoidScoutDB = VoidScoutDB or {}
    VoidScoutDB.last_field_scan = table.concat(lines, "\n")

    -- Show copyable popup
    if VoidScout and VoidScout.LFGPanel and VoidScout.LFGPanel.ShowCopyablePopup then
        VoidScout.LFGPanel:ShowCopyablePopup("VoidScout Field Scan",
            VoidScoutDB.last_field_scan)
    end

    return VoidScoutDB.last_field_scan
end

-- Slash to run
SLASH_VOIDSCOUTSCAN1 = "/vsscan"
SlashCmdList["VOIDSCOUTSCAN"] = function()
    mod:Scan(3)
end
