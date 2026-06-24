----------------------------------------------------------------------
-- VoidScout LeaderProbabilityOverlay
--
-- Adds a Probability Score badge to each applicant row in the LFG
-- applicant viewer when you're a leader. Score computed locally via
-- VoidScout.TimerScore using:
--   * applicant spec/class/ilvl (from C_LFGList.GetApplicantMemberInfo)
--   * leader's hosted dungeon + key level (from C_LFGList.GetActiveEntryInfo)
--
-- Bootstrap state: scores only show when we can compute (need spec).
-- For applicants we have richer DB data for, the score becomes more
-- accurate (axes-aware). For now: spec+ilvl+Murlok class baseline.
----------------------------------------------------------------------

VoidScout = VoidScout or {}
local mod = {}
VoidScout.LeaderProbabilityOverlay = mod

-- Score color thresholds
local function color_for(score)
    if score >= 85 then return 0.20, 1.00, 0.20  -- green
    elseif score >= 70 then return 1.00, 0.85, 0.20  -- yellow
    elseif score >= 50 then return 1.00, 0.55, 0.20  -- orange
    else                   return 1.00, 0.30, 0.30  -- red
    end
end

-- Determine the leader's currently-hosted dungeon + key level from
-- their own LFG listing. Returns nil if not hosting an M+.
local function leader_context()
    if not C_LFGList or not C_LFGList.GetActiveEntryInfo then return nil end
    local entry = C_LFGList.GetActiveEntryInfo()
    if not entry then return nil end
    local actID = (entry.activityIDs and entry.activityIDs[1]) or entry.activityID
    if not actID then return nil end
    local act = C_LFGList.GetActivityInfoTable(actID)
    if not act then return nil end
    -- Try to read the leader's selected keystone level from their own
    -- listing's playerCount filter or note; fallback: prompt-derived.
    -- For now: assume leader's listing implies +N where N is encoded in
    -- the activity name OR they're hosting at their best key level.
    -- Quick heuristic: parse activity fullName for "+%d" (often "+15 X")
    -- Primary: leader (you) holds the keystone they'll insert. Read its level.
    local lvl = 0
    if C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel then
        local k = C_MythicPlus.GetOwnedKeystoneLevel() or 0
        if k > 0 then lvl = k end
    end
    -- Secondary: parse activity fullName for "+N" (some Blizzard configs)
    if lvl == 0 and act.fullName then
        lvl = tonumber(act.fullName:match("%+(%d+)")) or 0
    end
    if lvl == 0 then
        -- No signal — use a realistic floor for premade pugs, not 10
        lvl = 12
    end
    return {
        dungeon_id   = act.mapID or 0,
        dungeon_name = act.shortName or act.fullName or "M+",
        keylevel     = lvl,
    }
end

-- Compute probability for an applicant given their class/spec/ilvl
-- + Blizzard-exposed signals (M+ rating, known-leaver flag).
local function compute(class_file, spec_id, ilvl, mp_rating, is_leaver, ctx)
    if not VoidScout.TimerScore or not class_file then return nil end
    local spec_name = nil
    if spec_id and spec_id > 0 and GetSpecializationInfoByID then
        local _, name = GetSpecializationInfoByID(spec_id)
        spec_name = name
    end
    if not spec_name then return nil end
    local score = VoidScout.TimerScore:ScorePlayer(
        class_file, spec_name, ilvl or 0,
        (ctx and ctx.keylevel) or 10,
        (ctx and ctx.dungeon_id) or nil,
        { mp_rating = mp_rating, is_leaver = is_leaver }
    )
    return score
end

-- Add or update the badge on a member frame
local function update_badge(member, score)
    if not member then return end
    if not member.VoidProbBadge then
        local fs = member:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        -- Anchor to the RIGHT of the role icon, in the gap between
        -- Role and iLvl columns.
        if member.RoleIcon1 then
            fs:SetPoint("LEFT", member.RoleIcon1, "RIGHT", 4, 0)
        else
            fs:SetPoint("RIGHT", member, "RIGHT", -180, 0)
        end
        fs:SetJustifyH("LEFT")
        member.VoidProbBadge = fs
    end
    if not score then
        member.VoidProbBadge:SetText("")
        return
    end
    local r, g, b = color_for(score)
    member.VoidProbBadge:SetText(("|cff%02x%02x%02x%d|r"):format(
        math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), score))
end

local function on_applicant_member_update(member, appID, memberIdx)
    if not C_LFGList or not C_LFGList.GetApplicantMemberInfo then return end
    local ok, name, class, _localizedClass, _level, itemLevel,
          _honorLevel, _tank, _healer, _damage, _assignedRole,
          _relationship, dungeonScore, _pvpItemLevel, _factionGroup,
          _raceID, specID, isLeaver =
        pcall(C_LFGList.GetApplicantMemberInfo, appID, memberIdx)
    if not ok then return end
    local ctx = leader_context()
    if not ctx then update_badge(member, nil); return end
    local score = compute(class, specID, itemLevel, dungeonScore, isLeaver, ctx)
    update_badge(member, score)
    if mod._debug then
        print(("|cff00c7ff[VS prob]|r %s class=%s spec=%s ilvl=%s mp=%s leaver=%s -> score=%s"):format(
            tostring(name), tostring(class), tostring(specID),
            tostring(itemLevel), tostring(dungeonScore), tostring(isLeaver),
            tostring(score)))
    end
end

-- Toggle: prints per-applicant compute details when enabled
function mod:SetDebug(on)
    mod._debug = on and true or false
    print("|cff00c7ff[VS prob]|r debug = " .. tostring(mod._debug))
end

-- =====================================================================
-- PUBLIC HELPERS (exposed for LFGPanel tooltip hooks + diagnostics)
-- =====================================================================

-- Context from YOUR own listing (leader is YOU). Returns nil if not hosting.
function mod:ContextFromOwnListing()
    return leader_context()
end

-- Context from a SEARCH RESULT (you're an applicant viewing a leader's
-- listing). Different source from your own listing — no keystone hint
-- since you don't hold their key, so we infer key level from the
-- listing's required dungeon score as a rough proxy.
-- rendered_name_hint: pass in self.Name:GetText() from the calling frame.
-- Blizzard already SetText()'d the kstring into the fontstring — GetText
-- returns a plain string we can :match. Bypasses the kstring API issues
-- of trying to tostring(info.name) directly.
function mod:ContextFromSearchResult(resultID, rendered_name_hint)
    if not resultID or not C_LFGList or not C_LFGList.GetSearchResultInfo then return nil end
    local info = C_LFGList.GetSearchResultInfo(resultID)
    if not info then return nil end
    local actID = (info.activityIDs and info.activityIDs[1]) or info.activityID
    if not actID then return nil end
    local act = C_LFGList.GetActivityInfoTable(actID)
    if not act then return nil end

    local activityFull = ""
    if C_LFGList.GetActivityFullName then
        local ok, full = pcall(C_LFGList.GetActivityFullName, actID, nil, info.isWarMode)
        if ok and full then activityFull = tostring(full) end
    end

    -- Key level inference — PGF/VoidWatcher pattern:
    --   1. Parse "+N" from listing name/comment, AFTER passing issecretvalue
    --      gate. Wrap in pcall — kstring ops can taint downstream code.
    --      Two regex variants: "%+(%d+)" catches "+14", "[Mm]%+%s*(%d+)"
    --      catches "M+ 14" / "m+14".
    --   2. info.leaderDungeonScoreInfo.bestRunLevel — Blizzard flattens this
    --      to the LISTED dungeon's struct (not the table of all dungeons the
    --      API docs claim).
    --   3. requiredDungeonScore / 200 + 10 — last resort
    --   4. Default: 12
    local kl, src = 0, "fallback12"

    -- KEY LEVEL IS UNKNOWABLE in WoW 12.0.5 — leader title is a kstring
    -- placeholder no addon can resolve. The caller should compute a RANGE
    -- of scores at multiple key levels and display them all.
    -- We still return a default keylevel for legacy callers, but mark it.
    kl, src = 0, "unknown"
    if kl == 0 and info.requiredDungeonScore and info.requiredDungeonScore > 0 then
        kl, src = math.floor(info.requiredDungeonScore / 200) + 10, "reqScore"
    end
    -- For legacy single-value callers, default to a sensible mid-bracket.
    local effective_kl = kl
    if effective_kl == 0 then effective_kl = 12 end
    if effective_kl < 2 then effective_kl = 2 end
    if effective_kl > 30 then effective_kl = 30 end
    kl = effective_kl

    -- Dungeon name: prefer the activity full name (already says "Skyreach")
    -- over the generic act.shortName which is often "Mythic+".
    local dname = activityFull ~= "" and activityFull or (act.shortName or act.fullName or "M+")
    -- Strip "+N " prefix and "(Mythic Keystone)" suffix for a clean label
    dname = dname:gsub("^%+%d+%s*", ""):gsub("%s*%(Mythic Keystone%)%s*$", "")

    if mod._debug then
        print(("|cff00c7ff[VS prob]|r leader '%s' dungeon=%s -> keylvl=%d (src=%s)"):format(
            tostring(info.leaderName), dname, kl, src))
        local nameSecret = (_G.issecretvalue and info.name and issecretvalue(info.name)) and "SECRET" or "ok"
        print(("  name[%s]='%s' activity='%s' reqScore=%s leaderBest=%s"):format(
            nameSecret,
            tostring(info.name),
            activityFull,
            tostring(info.requiredDungeonScore),
            tostring(info.leaderDungeonScoreInfo and info.leaderDungeonScoreInfo.bestRunLevel)))
    end

    return {
        dungeon_id      = act.mapID or 0,
        dungeon_name    = dname,
        keylevel        = kl,            -- legacy single-value (estimated)
        keylevel_known  = (src ~= "unknown"),
        leader_pb       = (type(info.leaderDungeonScoreInfo) == "table"
                           and type(info.leaderDungeonScoreInfo[1]) == "table"
                           and info.leaderDungeonScoreInfo[1].bestRunLevel) or nil,
        leader_overall  = info.leaderOverallDungeonScore or 0,
        required_score  = info.requiredDungeonScore or 0,
        required_ilvl   = info.requiredItemLevel or 0,
    }
end

-- Public: compute score given inputs. Wrapped so LFGPanel can use.
function mod:Score(class_file, spec_id, ilvl, mp_rating, is_leaver, ctx)
    return compute(class_file, spec_id, ilvl, mp_rating, is_leaver, ctx)
end

-- Public: same but with explicit specName (for self-scoring where
-- spec_id may not be directly available).
function mod:ScoreSpecName(class_file, spec_name, ilvl, mp_rating, is_leaver, ctx)
    if not VoidScout.TimerScore or not class_file or not spec_name then return nil end
    return VoidScout.TimerScore:ScorePlayer(
        class_file, spec_name, ilvl or 0,
        (ctx and ctx.keylevel) or 12,
        (ctx and ctx.dungeon_id) or nil,
        { mp_rating = mp_rating, is_leaver = is_leaver }
    )
end

local function try_install_hook()
    if mod._hooked then return true end
    if _G.LFGListApplicationViewer_UpdateApplicantMember then
        hooksecurefunc("LFGListApplicationViewer_UpdateApplicantMember",
                       on_applicant_member_update)
        mod._hooked = true
        return true
    end
    return false
end

function mod:Init()
    if try_install_hook() then return end
    -- Try every common signal that means "the LFG addon just became available"
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
    f:RegisterEvent("LFG_LIST_APPLICANT_LIST_UPDATED")
    f:SetScript("OnEvent", function(self)
        if try_install_hook() then
            self:UnregisterAllEvents()
        end
    end)
    -- Belt-and-suspenders: hook LFGListFrame:OnShow as another shot.
    if _G.LFGListFrame and not _G.LFGListFrame._voidScoutOnShowHooked then
        _G.LFGListFrame:HookScript("OnShow", function()
            try_install_hook()
        end)
        _G.LFGListFrame._voidScoutOnShowHooked = true
    end
end
