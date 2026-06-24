----------------------------------------------------------------------
-- VoidScout — Utility-aware LFG addon
--
-- v0.1.0: empty scaffold. Validates the side-panel UI lives in the
-- right place, looks right, and toggles cleanly. No scoring, no
-- filtering yet — just the visual frame next to Blizzard's Premade
-- Groups window and an Enable checkbox.
--
-- Iteration plan (see VOIDSCOUT-DESIGN.md):
--   M1: empty side panel + enable toggle             ← we are here
--   M2: label picker (floating icon) + CLEU scoring
--   M3: LFG applicant badge inline + relay query
--   M4: composition gap meter
----------------------------------------------------------------------

VoidScout = VoidScout or {}
VoidScout.VERSION = C_AddOns and C_AddOns.GetAddOnMetadata
                    and C_AddOns.GetAddOnMetadata("VoidScout", "Version")
                    or "?"

----------------------------------------------------------------------
-- SavedVariables init
----------------------------------------------------------------------
local function InitSavedVars()
    VoidScoutDB = VoidScoutDB or {}
    if VoidScoutDB.enabled == nil then VoidScoutDB.enabled = true end
    if VoidScoutDB.cleuEnabled == nil then VoidScoutDB.cleuEnabled = false end  -- legacy, kept for safety
    if VoidScoutDB.autoSetupDone == nil then VoidScoutDB.autoSetupDone = false end
end

----------------------------------------------------------------------
-- VoidScoutCache merge
--
-- VoidScoutCache.lua is a non-SavedVariable file written by the sync
-- script. It contains the server's authoritative fight data. We merge
-- it into VoidScoutDB.scores so in-game numbers match the website.
--
-- Tracking: VoidScoutDB.lastCacheApplied stores the timestamp of the
-- cache we last merged. On reloads we only re-merge if the cache has
-- a newer timestamp — avoids wiping new fights you've played since.
----------------------------------------------------------------------
local function MergeVoidScoutCache()
    if not VoidScoutCache then return end
    local cache_ts = VoidScoutCache.timestamp or 0
    local last_applied = VoidScoutDB.lastCacheApplied or 0
    if cache_ts <= last_applied then return end  -- already merged

    local n_players, n_added, n_kept = 0, 0, 0
    local players = VoidScoutCache.players
    if type(players) == "table" then
        VoidScoutDB.scores = VoidScoutDB.scores or {}
        for name, pdata in pairs(players) do
            if type(pdata) == "table" and type(pdata.fights) == "table" then
                local rec = VoidScoutDB.scores[name] or { fights = {} }
                -- Dedupe by timestamp — only add cache fights we don't already have
                local existing_ts = {}
                for _, f in ipairs(rec.fights) do
                    if f.timestamp then existing_ts[f.timestamp] = true end
                end
                for _, f in ipairs(pdata.fights) do
                    if not (f.timestamp and existing_ts[f.timestamp]) then
                        table.insert(rec.fights, f)
                        n_added = n_added + 1
                    end
                end
                n_kept = n_kept + #rec.fights - n_added
                -- Sort by timestamp ascending so newest stays at the bottom
                table.sort(rec.fights, function(a, b)
                    return (a.timestamp or 0) < (b.timestamp or 0)
                end)
                VoidScoutDB.scores[name] = rec
                n_players = n_players + 1
            end
        end
    end

    VoidScoutDB.lastCacheApplied = cache_ts
    -- Background sync stays silent (no login chat) for a clean, professional load.
    -- n_players/n_added/n_kept are computed above and available if debug logging is ever wanted.
end

----------------------------------------------------------------------
-- First-time auto-setup: enable Blizzard's damage meter cvar so
-- C_DamageMeter scoring works for new users without manual /editmode.
-- Runs once per character; sets VoidScoutDB.autoSetupDone so reruns
-- skip. User can re-trigger via /vs autosetup if needed.
----------------------------------------------------------------------
local function AutoSetupDamageMeter(force)
    if VoidScoutDB.autoSetupDone and not force then return end

    -- 1) Enable the cvar
    local cur = GetCVar and GetCVar("damageMeterEnabled")
    if cur ~= "1" then
        local ok = pcall(SetCVar, "damageMeterEnabled", "1")
        if ok then
            print("|cffffd100VoidScout:|r enabled Blizzard damage meter cvar (required for scoring)")
        end
    end

    -- 2) Verify availability
    if C_DamageMeter and C_DamageMeter.IsDamageMeterAvailable then
        local avail, reason = C_DamageMeter.IsDamageMeterAvailable()
        if not avail then
            print(("|cffff8080VoidScout:|r damage meter unavailable: %s. " ..
                  "Open Edit Mode (/editmode) and enable Damage Meter to score fights."):format(tostring(reason)))
        end
    end

    VoidScoutDB.autoSetupDone = true
end

----------------------------------------------------------------------
-- Lifecycle: wait for PLAYER_LOGIN, force-load Blizzard's LFG UI,
-- then hand off to LFGPanel.lua's Init.
----------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_LOGIN" then return end

    InitSavedVars()
    MergeVoidScoutCache()
    AutoSetupDamageMeter(false)

    -- LFGListFrame lives inside Blizzard_LookingForGroupUI, which is
    -- an on-demand load. Force it now so our hooks attach immediately
    -- instead of waiting for the player to first open the panel.
    pcall(function()
        if C_AddOns and C_AddOns.LoadAddOn then
            C_AddOns.LoadAddOn("Blizzard_LookingForGroupUI")
        elseif LoadAddOn then
            LoadAddOn("Blizzard_LookingForGroupUI")
        end
    end)

    if VoidScout.PlayerScan and VoidScout.PlayerScan.Init then
        VoidScout.PlayerScan:Init()
    end

    if VoidScout.LFGPanel and VoidScout.LFGPanel.Init then
        VoidScout.LFGPanel:Init()
    end

    if VoidScout.LabelPicker and VoidScout.LabelPicker.Init then
        VoidScout.LabelPicker:Init()
    end

    if VoidScout.FightRecorder and VoidScout.FightRecorder.Init then
        VoidScout.FightRecorder:Init()
    end

    if VoidScout.LeaderProbabilityOverlay
       and VoidScout.LeaderProbabilityOverlay.Init then
        VoidScout.LeaderProbabilityOverlay:Init()
    end

    if VoidScout.PreflightDetector and VoidScout.PreflightDetector.Init then
        VoidScout.PreflightDetector:Init()
    end

    if VoidScout.TrashDiscovery and VoidScout.TrashDiscovery.Init then
        VoidScout.TrashDiscovery:Init()
    end

    -- Slash for diagnostic access to the fight log
    SLASH_VOIDSCOUT1 = "/vs"
    SLASH_VOIDSCOUT2 = "/voidscout"
    SlashCmdList["VOIDSCOUT"] = function(msg)
        msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if msg == "" or msg == "log" then
            if VoidScout.FightRecorder then VoidScout.FightRecorder:DumpLog(20) end
        elseif msg == "log clear" or msg == "clear" then
            if VoidScout.FightRecorder then VoidScout.FightRecorder:ClearLog() end
        elseif msg == "pugs" then
            if VoidScout.FightRecorder then VoidScout.FightRecorder:DumpPugs() end
        elseif msg == "priority" or msg == "kicks" then
            if VoidScout.TrashDiscovery and VoidScout.TrashDiscovery.ShowPriorityPopup then
                VoidScout.TrashDiscovery:ShowPriorityPopup()
            else
                print("|cffff7777VoidScout:|r TrashDiscovery not loaded.")
            end
        elseif msg:match("^preview") then
            local n = tonumber(msg:match("preview%s+(%d+)")) or 1
            if VoidScout.LFGPanel and VoidScout.LFGPanel.Preview then
                VoidScout.LFGPanel:Preview(n)
            end
        elseif msg == "me" or msg == "diag" then
            if VoidScout.LFGPanel and VoidScout.LFGPanel.DiagnoseMe then
                VoidScout.LFGPanel:DiagnoseMe()
            end
        elseif msg == "status" then
            if VoidScout.LFGPanel and VoidScout.LFGPanel.Status then
                VoidScout.LFGPanel:Status()
            end
        elseif msg == "show" then
            if VoidScout.LFGPanel and VoidScout.LFGPanel.Preview then
                VoidScout.LFGPanel:Preview(0)
                local p = _G.VoidScoutMyPanel
                if p then p:Show() end
            end
        elseif msg == "refresh" then
            -- Force refresh my panel data
            if VoidScout.LFGPanel then
                VoidScout.LFGPanel:SetDebug(true)
                if VoidScout.LFGPanel.Preview then
                    VoidScout.LFGPanel:Preview(0)
                end
                VoidScout.LFGPanel:SetDebug(false)
            end
        elseif msg == "debug on" then
            if VoidScout.LFGPanel and VoidScout.LFGPanel.SetDebug then
                VoidScout.LFGPanel:SetDebug(true)
            end
        elseif msg == "debug off" then
            if VoidScout.LFGPanel and VoidScout.LFGPanel.SetDebug then
                VoidScout.LFGPanel:SetDebug(false)
            end
        elseif msg == "cleu on" then
            if VoidScout.FightRecorder and VoidScout.FightRecorder.SetCLEU then
                VoidScout.FightRecorder:SetCLEU(true)
            end
        elseif msg == "cleu off" then
            if VoidScout.FightRecorder and VoidScout.FightRecorder.SetCLEU then
                VoidScout.FightRecorder:SetCLEU(false)
            end
        elseif msg == "prob debug on" then
            if VoidScout.LeaderProbabilityOverlay and VoidScout.LeaderProbabilityOverlay.SetDebug then
                VoidScout.LeaderProbabilityOverlay:SetDebug(true)
            end
        elseif msg == "prob debug off" then
            if VoidScout.LeaderProbabilityOverlay and VoidScout.LeaderProbabilityOverlay.SetDebug then
                VoidScout.LeaderProbabilityOverlay:SetDebug(false)
            end
        elseif msg == "prob" then
            -- Diagnostic: probability overlay state
            local lp = VoidScout.LeaderProbabilityOverlay
            local lines = {
                "|cff00c7ffVoidScout Probability diagnostic|r",
                ("  LeaderProbabilityOverlay loaded: %s"):format(tostring(lp ~= nil)),
                ("  Applicant hook installed: %s"):format(tostring(lp and lp._hooked or false)),
                ("  LFGListApplicationViewer_UpdateApplicantMember exists: %s"):format(
                    tostring(_G.LFGListApplicationViewer_UpdateApplicantMember ~= nil)),
            }
            local entry = C_LFGList and C_LFGList.GetActiveEntryInfo and C_LFGList.GetActiveEntryInfo()
            lines[#lines+1] = ("  GetActiveEntryInfo: %s"):format(tostring(entry ~= nil))
            if entry then
                local aid = entry.activityIDs and entry.activityIDs[1] or entry.activityID
                lines[#lines+1] = ("  activityID: %s"):format(tostring(aid))
                if aid and C_LFGList.GetActivityInfoTable then
                    local act = C_LFGList.GetActivityInfoTable(aid)
                    if act then
                        lines[#lines+1] = ("  mapID: %s  fullName: %s"):format(
                            tostring(act.mapID), tostring(act.fullName))
                    end
                end
            end
            local kl = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel
                       and C_MythicPlus.GetOwnedKeystoneLevel() or 0
            lines[#lines+1] = ("  OwnedKeystoneLevel: %s"):format(tostring(kl))
            for _, l in ipairs(lines) do print(l) end
        elseif msg == "predictions" or msg == "calibration" then
            -- Show prediction-vs-outcome calibration log
            if not VoidScoutDB.runs then
                print("|cff00c7ff[VS]|r No runs recorded yet.")
                return
            end
            local rows = {}
            for _, r in pairs(VoidScoutDB.runs) do
                rows[#rows+1] = r
            end
            table.sort(rows, function(a, b) return (a.started_at or 0) > (b.started_at or 0) end)
            print("|cff00c7ff[VS] Probability calibration log (most recent first)|r")
            print(("  %-19s %-22s %-8s %-9s %-10s"):format("when", "dungeon", "+level", "predict", "outcome"))
            local correct = 0
            local total = 0
            for i = 1, math.min(15, #rows) do
                local r = rows[i]
                local when = r.started_at and date("%m/%d %H:%M", r.started_at) or "?"
                local dname = (r.dungeon_name or "?"):sub(1, 22)
                local lvl = r.keystone_level or 0
                local pred = r.predicted_score or 0
                local outcome = r.outcome or "?"
                -- Calibration check (binary): predicted>=70 should time
                if r.outcome == "timed" or r.outcome == "depleted" or r.outcome == "abandoned" then
                    total = total + 1
                    local pred_says_yes = pred >= 70
                    local actually_timed = r.outcome == "timed"
                    if pred_says_yes == actually_timed then correct = correct + 1 end
                end
                local color = (outcome == "timed" and "20ff20") or
                              (outcome == "depleted" and "ffd820") or
                              (outcome == "abandoned" and "ff4040") or "999999"
                print(("  %-19s %-22s +%-7d %-9d |cff%s%-10s|r"):format(
                    when, dname, lvl, pred, color, outcome))
            end
            if total > 0 then
                print(("  Calibration accuracy: %d/%d (%d%%)"):format(
                    correct, total, math.floor(100 * correct / total)))
            end
        elseif msg == "group" or msg == "party" then
            -- Score the current party for their active key.
            local n = (GetNumGroupMembers and GetNumGroupMembers()) or 1
            if n < 2 then
                print("|cff00c7ff[VS]|r Not in a group. Join a party to score it.")
                return
            end
            -- Find key level: try active LFG entry, then own keystone, then default
            local kl = 0
            if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
                local active = C_ChallengeMode.GetActiveKeystoneInfo()
                if active and active > 0 then kl = active end
            end
            if kl == 0 and C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel then
                kl = C_MythicPlus.GetOwnedKeystoneLevel() or 0
            end
            if kl == 0 and C_LFGList and C_LFGList.GetActiveEntryInfo then
                local entry = C_LFGList.GetActiveEntryInfo()
                if entry then kl = 12 end
            end
            if kl == 0 then kl = 12 end

            -- Find dungeon: from active challenge, then LFG listing
            local mapID = 0
            if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
                mapID = C_ChallengeMode.GetActiveChallengeMapID() or 0
            end
            if mapID == 0 and C_LFGList and C_LFGList.GetActiveEntryInfo then
                local entry = C_LFGList.GetActiveEntryInfo()
                if entry then
                    local aid = (entry.activityIDs and entry.activityIDs[1]) or entry.activityID
                    if aid and C_LFGList.GetActivityInfoTable then
                        local act = C_LFGList.GetActivityInfoTable(aid)
                        if act then mapID = act.mapID or 0 end
                    end
                end
            end

            -- Build player list
            local players = {}
            local units = { "player" }
            local prefix = IsInRaid and IsInRaid() and "raid" or "party"
            for i = 1, n - 1 do units[#units+1] = prefix .. i end
            for _, u in ipairs(units) do
                if UnitExists(u) then
                    local _, classFile = UnitClass(u)
                    local ilvl = 0
                    if u == "player" then
                        ilvl = math.floor(select(2, GetAverageItemLevel()) or 0)
                    end
                    -- Try cached PlayerScan data for party members
                    if ilvl == 0 and VoidScout.PlayerScan then
                        local guid = UnitGUID(u)
                        if guid then
                            local rec = VoidScout.PlayerScan.GetByGUID and VoidScout.PlayerScan:GetByGUID(guid)
                            if rec then ilvl = rec.ilvl or 0 end
                        end
                    end
                    -- Get spec: only reliable for self without async inspect
                    local specName
                    if u == "player" then
                        local specID = GetSpecialization and GetSpecialization()
                        if specID then
                            local _, sn = GetSpecializationInfo(specID)
                            specName = sn
                        end
                    end
                    players[#players+1] = {
                        classFile = classFile,
                        specName  = specName or "?",
                        ilvl      = ilvl > 0 and ilvl or 280,  -- ballpark default
                    }
                end
            end

            if not VoidScout.TimerScore then
                print("|cff00c7ff[VS]|r TimerScore not loaded.")
                return
            end
            local grp = VoidScout.TimerScore:ScoreGroup(players, kl, mapID > 0 and mapID or nil)
            if not grp then
                print("|cff00c7ff[VS]|r Group scoring failed.")
                return
            end
            -- Resolve dungeon name (prefer TimerData profile)
            local dname = "?"
            if mapID > 0 and VoidScout.TimerData then
                local prof = VoidScout.TimerData:GetDungeonProfile(mapID)
                if prof and prof.name then dname = prof.name end
            end
            if dname == "?" and mapID > 0 then
                dname = "map " .. mapID
            end
            -- Annotate where the key level came from
            local kl_src = ""
            if kl == 12 then kl_src = " (default — keystone not slotted yet)" end

            print(("|cff00c7ff[VS]|r Group Probability for +%d %s: |cff20ff20%d|r%s"):format(
                kl, dname, grp.group_score or 0, kl_src))
            print(("  avg per-player: %d   utility mod: %+d   players scored: %d"):format(
                grp.avg_player or 0, grp.utility_mod or 0, #players))
            for _, note in ipairs(grp.utility_notes or {}) do
                print("  " .. note)
            end
        elseif msg == "autosetup" then
            AutoSetupDamageMeter(true)
        elseif msg == "mergepugs" then
            if VoidScout.FightRecorder and VoidScout.FightRecorder.MergeSplitPugs then
                VoidScout.FightRecorder:MergeSplitPugs()
            end
        elseif msg == "lastrun" or msg == "last" then
            if VoidScout.FightRecorder and VoidScout.FightRecorder.DumpLastRun then
                VoidScout.FightRecorder:DumpLastRun()
            end
        elseif msg:match("^timer") then
            -- /vs timer 14         → score self for hypothetical +14 MT
            -- /vs timer 14 group   → score current party (5 ppl) for +14 MT
            local kl_str, mode = msg:match("^timer%s+(%d+)%s*(%a*)$")
            local kl = tonumber(kl_str) or 14
            local dungeonID = 2811  -- Magisters' Terrace (PoC only)
            if not VoidScout.TimerScore then
                print("|cffff8080VoidScout:|r TimerScore module not loaded")
                return
            end
            if mode == "group" then
                -- Build a list of party units that need inspection. GetInspectSpecialization
                -- only returns non-zero AFTER a successful NotifyInspect → INSPECT_READY
                -- round-trip. We need to do this asynchronously, then score.
                local function specNameFor(unit)
                    local specID
                    if unit == "player" then
                        specID = GetSpecialization()
                        if specID and specID > 0 then
                            local _, n = GetSpecializationInfo(specID)
                            return n
                        end
                        return nil
                    end
                    specID = GetInspectSpecialization(unit)
                    if specID and specID > 0 then
                        local _, n = GetSpecializationInfoByID(specID)
                        return n
                    end
                    return nil
                end

                local function buildAndScore()
                    local players = {}
                    local function add(unit)
                        if not UnitExists(unit) then return end
                        local _, classFile = UnitClass(unit)
                        table.insert(players, {
                            classFile = classFile,
                            specName  = specNameFor(unit) or "Unknown",
                            ilvl      = unit == "player" and math.floor(select(2, GetAverageItemLevel())) or nil,
                        })
                    end
                    add("player")
                    for i = 1, 4 do add("party" .. i) end
                    local res = VoidScout.TimerScore:ScoreGroup(players, kl, dungeonID)
                    if not res then print("|cffff8080VoidScout:|r group score failed"); return end
                    print(("|cff00c7ffVoidScout TimedPossibility (group, +%d MT):|r |cffffcc00%d|r"):format(kl, res.group_score))
                    print(("  avg player: %d  utility: %+d"):format(res.avg_player, res.utility_mod))
                    for _, n in ipairs(res.utility_notes) do print("  " .. n) end
                    for _, pp in ipairs(res.per_player) do
                        print(("  • %s/%s: %d"):format(pp.player.classFile or "?", pp.player.specName or "?", pp.score or 0))
                    end
                end

                -- Inspect all party members sequentially. Blizzard only allows one
                -- outstanding NotifyInspect at a time; chain via INSPECT_READY.
                local queue = {}
                for i = 1, 4 do
                    local unit = "party" .. i
                    if UnitExists(unit) and CanInspect(unit) and not specNameFor(unit) then
                        table.insert(queue, unit)
                    end
                end

                if #queue == 0 then
                    buildAndScore()
                else
                    print(("|c%sVoidScout:|r inspecting %d party member%s..."):format(
                        "ff00c7ff", #queue, #queue == 1 and "" or "s"))
                    local frame = CreateFrame("Frame")
                    local idx = 0
                    local timeout

                    local function tryNext()
                        idx = idx + 1
                        if idx > #queue then
                            if timeout then timeout:Cancel() end
                            frame:UnregisterAllEvents()
                            buildAndScore()
                            return
                        end
                        local unit = queue[idx]
                        local expected_guid = UnitGUID(unit)
                        frame.expected = expected_guid
                        NotifyInspect(unit)
                    end

                    frame:RegisterEvent("INSPECT_READY")
                    frame:SetScript("OnEvent", function(self, _, guid)
                        if guid == self.expected then tryNext() end
                    end)
                    timeout = C_Timer.NewTimer(4, function()
                        frame:UnregisterAllEvents()
                        print("|cffff8080VoidScout:|r inspect timed out — scoring with partial data")
                        buildAndScore()
                    end)
                    tryNext()
                end
            else
                local score, bd = VoidScout.TimerScore:ScoreSelf(kl, dungeonID)
                if not score then
                    print("|cffff8080VoidScout:|r " .. (bd and bd.error or "score failed"))
                    return
                end
                print(("|cff00c7ffVoidScout TimedPossibility (self, +%d MT):|r |cffffcc00%d|r"):format(kl, score))
                print(VoidScout.TimerScore:FormatBreakdown(bd))
            end
        elseif msg == "scan rp" or msg == "scan raidprog" then
            -- Dump what GetRaidProgress returns for self
            if not VoidScout.PlayerScan then return end
            local name = UnitName("player")
            local realm = GetRealmName()
            local rp = VoidScout.PlayerScan:GetRaidProgress(name, realm)
            print(("|cff00c7ffVoidScout|r GetRaidProgress for %s-%s:"):format(name, realm))
            if not rp then print("  |cffff8080nil|r"); return end
            print(("  parse_avg=%s"):format(tostring(rp.parse_avg)))
            for _, r in ipairs({"Voidspire","Dreamrift","MQD"}) do
                local v = rp[r] or {}
                print(("  %s: N=%s H=%s M=%s"):format(r, tostring(v.N), tostring(v.H), tostring(v.M)))
            end
            local arc = rp.archon or {}
            print(("  archon table present: %s"):format(rp.archon and "YES" or "NO"))
            for _, d in ipairs({"N","H","M"}) do
                local s = arc[d]
                if s then
                    print(("    %s: progress=%s total=%s avg=%s"):format(d, tostring(s.progress), tostring(s.total), tostring(s.avg)))
                else
                    print(("    %s: nil"):format(d))
                end
            end

        elseif msg == "scan probe" or msg == "scan probe me" then
            if VoidScout.PlayerScan and VoidScout.PlayerScan.Probe then
                VoidScout.PlayerScan:Probe()
            end
        elseif msg:match("^scan probe ") then
            local target = msg:match("^scan probe (.+)$")
            local n, r = target:match("^([^-]+)-(.+)$")
            if VoidScout.PlayerScan and VoidScout.PlayerScan.Probe then
                VoidScout.PlayerScan:Probe(n or target, r)
            end
        elseif msg == "scan" or msg == "scan stats" then
            if VoidScout.PlayerScan then
                local s = VoidScout.PlayerScan:Stats()
                print(("|cff00c7ffVoidScout scan|r %d players | deep:%d ach:%d scrapes:%d | attempts:%d | combat:%s instance:%s"):format(
                    s.total, s.deep_inspected, s.achievements_pulled, s.tooltip_scrapes, s.attempts,
                    s.in_combat and "YES" or "no", s.in_instance and "YES" or "no"))
            end
        elseif msg == "scan rediscover" then
            if VoidScout.PlayerScan and VoidScout.PlayerScan.AutoDiscoverBossKills then
                VoidScout.PlayerScan.AutoDiscoverBossKills(true)
            end
        elseif msg == "scan dump cats" then
            -- Dump every achievement category name + count, to diagnose
            -- whether Heroic/Normal raid kill achievements exist at all.
            if C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn("Blizzard_AchievementUI") end
            local cats = GetCategoryList() or {}
            print(("|cff00c7ffVoidScout:|r %d categories total"):format(#cats))
            for _, catID in ipairs(cats) do
                local n = GetCategoryInfo(catID)
                local count = GetCategoryNumAchievements(catID) or 0
                local lower = (n or ""):lower()
                if lower:find("raid") or lower:find("heroic") or lower:find("mythic")
                   or lower:find("normal") or lower:find("voidspire")
                   or lower:find("dreamrift") or lower:find("quel") then
                    print(("  id=%-5s n=%-3d  %s"):format(tostring(catID), count, tostring(n)))
                end
            end
        elseif msg == "scan debug on" then
            if VoidScout.PlayerScan then VoidScout.PlayerScan:SetDebug(true) end
        elseif msg == "scan debug off" then
            if VoidScout.PlayerScan then VoidScout.PlayerScan:SetDebug(false) end
        elseif msg:match("^scan discover ") or msg:match("^discover ") then
            -- /vs discover <substring>
            -- Walks every achievement category, prints any whose name matches.
            -- Use to find real Midnight achievement IDs (boss kills, raid metas, etc).
            local needle = msg:match("discover%s+(.+)$")
            if not needle or needle == "" then
                print("|cff00c7ffVoidScout:|r usage: /vs discover <substring>")
                return
            end
            needle = needle:lower()
            local cats = GetCategoryList and GetCategoryList() or {}
            local hits = 0
            for _, catID in ipairs(cats) do
                local n = GetCategoryNumAchievements and GetCategoryNumAchievements(catID) or 0
                for i = 1, n do
                    local achID, achName, _, completed = GetAchievementInfo(catID, i)
                    if achID and achName and achName:lower():find(needle, 1, true) then
                        print(("  id=%-7d %s%s"):format(achID, achName, completed and "  |cff66ff66[have]|r" or ""))
                        hits = hits + 1
                    end
                end
            end
            print(("|cff00c7ffVoidScout:|r %d match(es) for '%s'"):format(hits, needle))
        elseif msg:match("^scan find ") then
            local target = msg:match("^scan find (.+)$")
            if VoidScout.PlayerScan and target then
                local hits = 0
                for _, p in pairs((VoidScoutDB.playerScan and VoidScoutDB.playerScan.players) or {}) do
                    if p.name and p.name:lower():find(target, 1, true) then
                        hits = hits + 1
                        local ach_n = 0
                        if p.achievements then for _ in pairs(p.achievements) do ach_n = ach_n + 1 end end
                        print(("  %s-%s %s lvl%d ilvl=%s spec=%s ach=%d rio=%s arc=%s wcl=%s"):format(
                            p.name, p.realm or "?", p.class or "?", p.level or 0,
                            tostring(p.ilvl or "?"), p.spec or "-", ach_n,
                            tostring(p.scraped_rio or "-"), tostring(p.scraped_archon or "-"),
                            tostring(p.scraped_wcl or "-")))
                    end
                end
                print(("|cff00c7ffVoidScout scan|r %d match(es) for '%s'"):format(hits, target))
            end
        elseif msg == "consent" or msg == "privacy" then
            if VoidScout_PrintConsentStatus then VoidScout_PrintConsentStatus() end
        elseif msg == "optout" or msg == "consent optout" or msg == "consent local" then
            if VoidScout_SetConsent_OptOut then VoidScout_SetConsent_OptOut() end
        elseif msg == "optin" or msg == "consent optin" or msg == "consent allow" then
            if VoidScout_SetConsent_OptIn then VoidScout_SetConsent_OptIn() end
        else
            print("|cff00c7ffVoidScout:|r /vs log | pugs | me | status | show | scan | scan find <name> | consent | log clear")
        end
    end

end)
