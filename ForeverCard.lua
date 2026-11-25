-- VoidScout ForeverCard (WoW Forever only, TOC [AllowLoadGameType camelot]): the score card.
-- Retail's card (LFGPanel) is built on retail content -- its score only counts current-tier
-- retail bosses, so in Forever it found nothing, and its raid / M+ / probability / achievement
-- parts don't exist there. This card shows the same kind of thing from your Forever fights:
-- VoidScout score, Commitment, the axes, item level, average DPS, deaths, runs together; and on
-- your own card the two things to work on.
-- The user, 2026-11-18: "it also has a popup for me to see my scores" + leaders see "their scores
-- and how well they are geared and play".
-- API: VoidScout.ForeverCard.Lookup(name) -> data or nil
--      VoidScout.ForeverCard:ShowFor(name, anchor)  (docked beside anchor; hover card)
--      VoidScout.ForeverCard:HideFor()
--      VoidScout.ForeverCard:ToggleMine()           (your card, movable, kept where you leave it)
if (select(4, GetBuildInfo()) or 0) >= 100000 then return end

local _, ns = ...
local C = {}
VoidScout = VoidScout or {}
VoidScout.ForeverCard = C

local AXES = { "Damage", "Interrupts", "Dispels", "Avoidance", "Activity", "Survival", "Teamwork" }
local TIPS = {
    Damage = "more damage: no gaps, cooldowns on the boss",
    Interrupts = "kick more: watch enemy casts",
    Dispels = "dispel more: watch your party's debuffs",
    Avoidance = "take less avoidable damage: step out of it",
    Activity = "fewer pauses between casts",
    Survival = "die less: defensives, potions, bandages",
    Teamwork = "use your group utility",
}
local NO_DISPEL = { WARRIOR = true, ROGUE = true, HUNTER = true }   -- no friendly dispel in Classic content

local function secret(v) return issecretvalue and issecretvalue(v) end

local function colorFor(score)
    if not score then return 0.5, 0.5, 0.5 end
    if score >= 80 then return 0.12, 1, 0 end
    if score >= 50 then return 1, 1, 1 end
    return 0.62, 0.62, 0.62
end
C.ColorFor = colorFor

local function ago(t)
    local s = time() - t
    if s < 3600 then return math.max(1, math.floor(s / 60)) .. "m ago" end
    if s < 86400 then return math.floor(s / 3600) .. "h ago" end
    return math.floor(s / 86400) .. "d ago"
end

----------------------------------------------------------------------
-- data
----------------------------------------------------------------------
-- "First Surname" / "First-Surname" -> the scores key; a bare first name finds its surname
function C.KeyFor(name)
    if type(name) ~= "string" or secret(name) or name == "" then return nil end
    local key = name:gsub("%s+", "-")
    local scores = VoidScoutDB and VoidScoutDB.scores
    if scores and not scores[key] and not key:find("-", 1, true) then
        local pre = key .. "-"
        for k in pairs(scores) do
            if k:sub(1, #pre) == pre then return k end
        end
    end
    return key
end

local function myKey() return VoidScoutDB and VoidScoutDB.me and VoidScoutDB.me.key end

function C.Lookup(name)
    local key = C.KeyFor(name)
    if not key then return nil end
    local d = { key = key, name = key:gsub("%-", " "), axes = {}, fights = 0 }
    local rec = VoidScoutDB and VoidScoutDB.scores and VoidScoutDB.scores[key]
    local sum, n = {}, {}
    local dpsSum, dpsN, deaths, lastAt = 0, 0, 0, 0
    for _, f in ipairs(rec and rec.fights or {}) do
        if f.data_quality ~= "stale" then
            d.fights = d.fights + 1
            for _, a in ipairs(AXES) do
                local v = f.axes and f.axes[a]
                if type(v) == "number" and not (a == "Dispels" and NO_DISPEL[f.class or ""]) then
                    sum[a] = (sum[a] or 0) + v; n[a] = (n[a] or 0) + 1
                end
            end
            local raw = f.raw or {}
            if type(raw.dps) == "number" and raw.dps > 0 then dpsSum = dpsSum + raw.dps; dpsN = dpsN + 1 end
            if raw.died then deaths = deaths + 1 end
            local at = f.timestamp or 0
            if at >= lastAt then
                lastAt = at
                d.class = f.class or raw.class or d.class
                if type(raw.ilvl) == "number" then d.ilvl, d.ilvlAt, d.ilvlFrom = raw.ilvl, at, "fight" end
            end
            if type(raw.ilvl) == "number" and not d.ilvl then d.ilvl, d.ilvlAt, d.ilvlFrom = raw.ilvl, at, "fight" end
        end
    end
    local oSum, oN = 0, 0
    for _, a in ipairs(AXES) do
        if n[a] then
            d.axes[a] = math.floor(sum[a] / n[a] + 0.5)
            oSum = oSum + d.axes[a]; oN = oN + 1
        end
    end
    d.overall = (oN > 0) and math.floor(oSum / oN + 0.5) or nil
    d.dps = (dpsN > 0) and math.floor(dpsSum / dpsN + 0.5) or nil
    d.deaths = deaths

    -- Commitment (stays through the run) and runs together, from the fight log rosters
    local me = myKey()
    local total, stayed, together = {}, {}, {}
    for _, f in ipairs(VoidScoutDB and VoidScoutDB.fightLog or {}) do
        local pug = f.pug_id or "_"
        total[pug] = (total[pug] or 0) + 1
        local has, hasMe = false, false
        for _, r in ipairs(f.roster or {}) do
            if r == key then has = true end
            if r == me then hasMe = true end
        end
        if has then
            stayed[pug] = (stayed[pug] or 0) + 1
            if hasMe and key ~= me then together[pug] = true end
            if (f.end_ts or 0) > (d.lastSeen or 0) then d.lastSeen = f.end_ts end
        end
    end
    local cs, cn = 0, 0
    for pug, s in pairs(stayed) do cs = cs + s / (total[pug] or 1); cn = cn + 1 end
    d.commitment = (cn > 0) and math.floor(cs / cn * 100 + 0.5) or nil
    d.runs = cn
    local t = 0
    for _ in pairs(together) do t = t + 1 end
    d.runsWithMe = t

    -- a fresh inspect beats an item level from an old fight
    if VoidScout.ForeverGear then
        local il, at = VoidScout.ForeverGear.Get(key)
        if il and (not d.ilvlAt or at >= d.ilvlAt) then d.ilvl, d.ilvlAt, d.ilvlFrom = il, at, "inspect" end
    end
    if d.fights == 0 and d.runs == 0 and not d.ilvl then return nil end
    return d
end

----------------------------------------------------------------------
-- the card
----------------------------------------------------------------------
local W, PAD, ROW = 240, 9, 15

local function newCard(name)
    local p = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    p:SetWidth(W)
    p:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    p:SetBackdropColor(0, 0, 0, 0.88)
    p:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.9)
    p:SetFrameStrata("DIALOG")
    p:SetClampedToScreen(true)
    p.lines = {}
    p:Hide()
    return p
end

-- a pool of label / value lines, laid out top to bottom
local function line(p, i)
    local l = p.lines[i]
    if not l then
        l = {}
        l.left = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        l.left:SetJustifyH("LEFT"); l.left:SetWordWrap(false)
        l.right = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l.right:SetJustifyH("RIGHT")
        l.div = p:CreateTexture(nil, "ARTWORK")
        p.lines[i] = l
    end
    return l
end

local function fill(p, d, isMe)
    local i, y = 0, -PAD
    local function add(left, right, opts)
        opts = opts or {}
        i = i + 1
        local l = line(p, i)
        l.div:Hide()
        if opts.div then
            l.left:Hide(); l.right:Hide()
            l.div:ClearAllPoints()
            l.div:SetPoint("TOPLEFT", PAD, y - 4); l.div:SetPoint("TOPRIGHT", -PAD, y - 4)
            l.div:SetHeight(1); l.div:SetColorTexture(0.7, 0.6, 0, 0.6); l.div:Show()
            y = y - 9
            return l
        end
        l.left:SetFontObject(opts.font or "GameFontHighlightSmall")
        l.right:SetFontObject(opts.rfont or "GameFontNormalSmall")
        l.left:ClearAllPoints(); l.right:ClearAllPoints()
        l.left:SetPoint("TOPLEFT", PAD + (opts.indent or 0), y)
        l.right:SetPoint("TOPRIGHT", -PAD, y)
        l.left:SetPoint("RIGHT", l.right, "LEFT", -6, 0)
        l.left:SetWordWrap(opts.wrap and true or false)   -- the Work on tips wrap: one line cut them ("cooldowns o...", 11-25)
        l.left:SetText(left or ""); l.right:SetText(right or "")
        l.left:SetTextColor(opts.lr or 1, opts.lg or 1, opts.lb or 1)
        l.right:SetTextColor(opts.r or 1, opts.g or 0.82, opts.b or 0)
        l.left:Show(); l.right:Show()
        y = y - (opts.wrap and math.max(ROW, (l.left:GetStringHeight() or 0) + 7) or (opts.h or ROW))
        return l
    end

    local cc = d.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[d.class]
    add(d.name, isMe and "" or "|cff00c7ffVoidScout|r", { font = "GameFontNormal", lr = cc and cc.r or 1, lg = cc and cc.g or 1, lb = cc and cc.b or 1, h = 17 })
    local meta = {}
    if d.fights > 0 then meta[#meta + 1] = d.fights .. " boss fight" .. (d.fights == 1 and "" or "s") end
    if not isMe and (d.runsWithMe or 0) > 0 then meta[#meta + 1] = "ran with you " .. d.runsWithMe .. "x" end
    if not isMe and d.lastSeen then meta[#meta + 1] = "last " .. ago(d.lastSeen) end
    add(#meta > 0 and table.concat(meta, "  ·  ") or "Not in your recorded fights yet", "", { lr = 0.6, lg = 0.6, lb = 0.6 })
    add(nil, nil, { div = true })
    local r, g, b = colorFor(d.overall)
    add("VoidScout Score", d.overall and tostring(d.overall) or "-", { font = "GameFontNormal", rfont = "GameFontNormalLarge", lr = 1, lg = 0.82, lb = 0, r = r, g = g, b = b, h = 19 })
    if d.commitment then
        local cr, cg, cb = colorFor(d.commitment)
        add("Commitment", d.commitment .. "%", { lr = 0.75, lg = 0.75, lb = 0.75, r = cr, g = cg, b = cb })
    end
    local any = false
    for _, a in ipairs(AXES) do
        local v = d.axes[a]
        if v then
            if not any then add(nil, nil, { div = true }); any = true end
            local ar, ag, ab = colorFor(v)
            add(a, tostring(v), { indent = 4, r = ar, g = ag, b = ab })
        end
    end
    add(nil, nil, { div = true })
    local il
    if d.ilvl then
        il = d.ilvl .. (d.ilvlFrom == "inspect" and ("  (inspected " .. ago(d.ilvlAt) .. ")") or ("  (in a fight " .. ago(d.ilvlAt) .. ")"))
    else
        il = isMe and "-" or "- (shows when they're near you)"
    end
    add("Item level", il, { lr = 0.75, lg = 0.75, lb = 0.75, r = 1, g = 1, b = 1 })
    if d.dps then add("Average DPS", tostring(d.dps), { lr = 0.75, lg = 0.75, lb = 0.75, r = 1, g = 1, b = 1 }) end
    if d.fights > 0 then
        add("Died in", ("%d of %d fights"):format(d.deaths, d.fights), { lr = 0.75, lg = 0.75, lb = 0.75, r = 1, g = 1, b = 1 })
    end
    -- your own card: the two weakest parts to work on
    if isMe then
        local weak = {}
        for _, a in ipairs(AXES) do if d.axes[a] and d.axes[a] < 75 then weak[#weak + 1] = a end end
        table.sort(weak, function(x, z) return d.axes[x] < d.axes[z] end)
        if #weak > 0 then
            add(nil, nil, { div = true })
            add("Work on", "", { font = "GameFontNormal", lr = 1, lg = 0.82, lb = 0 })
            for k = 1, math.min(2, #weak) do
                add(TIPS[weak[k]], "", { indent = 4, lr = 0.85, lg = 0.85, lb = 0.85, wrap = true })
            end
        end
    end
    for k = i + 1, #p.lines do
        local l = p.lines[k]
        l.left:Hide(); l.right:Hide(); l.div:Hide()
    end
    p:SetHeight(-y + PAD - 2)
end
C.Fill = fill

local hover, mineCard

function C:ShowFor(name, anchor, prefer)
    local d = C.Lookup(name)
    if not d then if hover then hover:Hide() end; return false end
    hover = hover or newCard("VoidScoutForeverHoverCard")
    fill(hover, d, d.key == myKey())
    hover.key = d.key
    hover:ClearAllPoints()
    if anchor then
        -- prefer = "LEFT" docks on the anchor's left (VoidLFG: its row tooltip goes right);
        -- either way it flips when there's no room on that side
        local s = anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local left, right = (anchor:GetLeft() or 0) * s, (anchor:GetRight() or 0) * s
        local roomLeft = left - W - 6 > 0
        local roomRight = right + W + 6 < GetScreenWidth()
        if (prefer == "LEFT" and roomLeft) or not roomRight then
            hover:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, 0)
        else
            hover:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
        end
    else
        hover:SetPoint("CENTER")
    end
    hover:Show()
    return true
end

function C:HideFor() if hover then hover:Hide() end end

function C:ToggleMine()
    if mineCard and mineCard:IsShown() then mineCard:Hide(); return end
    mineCard = mineCard or newCard("VoidScoutForeverMyCard")
    if not mineCard.moveSet then
        mineCard.moveSet = true
        mineCard:SetPoint("CENTER", 0, 100)
        local close = CreateFrame("Button", nil, mineCard, "UIPanelCloseButton")
        close:SetSize(20, 20); close:SetPoint("TOPRIGHT", 2, 2)
        if ns.Move then ns.Move(mineCard, { db = function() return VoidScoutDB end, key = "foreverMyCard" }) end
    end
    local me = myKey() or C.KeyFor(GetUnitName("player", false))
    local d = C.Lookup(me) or { key = me, name = (me or "You"):gsub("%-", " "), axes = {}, fights = 0, deaths = 0 }
    local _, cls = UnitClass("player")
    d.class = d.class or cls
    fill(mineCard, d, true)
    mineCard:Show()
end

-- refresh an open card when an inspect comes back
if VoidScout.ForeverGear then
    VoidScout.ForeverGear.OnUpdate(function(key)
        if mineCard and mineCard:IsShown() and key == myKey() then C:ToggleMine(); C:ToggleMine() end
        if hover and hover:IsShown() and hover.key == key then
            local d = C.Lookup(key)
            if d then fill(hover, d, key == myKey()) end
        end
    end)
end
