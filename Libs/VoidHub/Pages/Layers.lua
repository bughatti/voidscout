----------------------------------------------------------------------
-- VoidHub page: VoidLayer (WoW Forever). The same layer window, drawn with the hub's kit:
--   Layers   your layer, players seen, same layer elsewhere, group / world-refresh warnings,
--            other layers you can hop to (with their rares), rares on your layer, Group hop /
--            Fresh layer / Refresh, the status line
--   Settings the five options behind VoidLayer's gear
-- Data: VoidLayerCore (shared by every Void addon) + VoidLayerHub (VoidLayer/UI.lua's own helpers).
----------------------------------------------------------------------
local ns = _G.VoidHubWin
if not ns or ns.skip then return end   -- another Void addon's copy of VoidHub runs the window
local K = ns.Kit

local function core() return _G.VoidLayerCore end
local function H() return _G.VoidLayerHub end
local P
local ROWS = 8

local function tip(f, title, body, extra)
    f:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:AddLine(type(title) == "function" and title(s) or title, 1, 1, 1)
        GameTooltip:AddLine(type(body) == "function" and body(s) or body, 0.8, 0.8, 0.8, true)
        local x = extra and extra(s)
        if x then GameTooltip:AddLine(x, 1, 0.82, 0, true) end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- a row: name, what, and a Hop button
local function MakeRow(r)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
    r.a = K.Text(r, "GameFontHighlight"); r.a:SetPoint("LEFT", 6, 0); r.a:SetWidth(170); r.a:SetWordWrap(false)
    r.b = K.Text(r, "GameFontHighlightSmall"); r.b:SetPoint("LEFT", r.a, "RIGHT", 6, 0); r.b:SetPoint("RIGHT", -70, 0); r.b:SetWordWrap(false)
    r.hop = K.Button(r, "Hop", 56)
    r.hop:SetPoint("RIGHT", -4, 0)
    r.hop:SetScript("OnClick", function(s)
        local c, it = core(), s:GetParent().item
        if c and it then c:Start(it.pair, it.zone, it.prefer) end
    end)
    r:SetScript("OnEnter", function(s) if s.item and s.item.tip then s.item.tip(s) end end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
local function FillRow(r, it, i)
    r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
    r.a:SetText(it.a); r.b:SetText(it.b)
    r.hop:SetShown(it.canHop)
    r.hop:SetEnabled(it.hopOn and true or false)
    r.hop:SetAlpha(it.hopOn and 1 or 0.4)
end

local function Update()
    if not (P and P:IsVisible()) then return end
    local c, h = core(), H()
    local cur, zone
    if c then cur, zone = c:Here() end
    local forever = h and h.Forever and h.Forever()
    P.zoneTitle:SetText("|cff00c7ff" .. (h and h.ZoneName(zone) or "?") .. "|r")
    -- you
    if not forever then
        P.mine:SetText("Layers are a WoW Forever thing.")
    elseif not c then
        P.mine:SetText("Starting up...")
    elseif cur then
        local here = c:Counts(zone)[cur] or 0
        P.mine:SetText(("You're on |cffffd200%s|r%s"):format(c:Label(zone, cur),
            here > 0 and ("  ·  %d Void player%s here too"):format(here, here == 1 and "" or "s") or ""))
    else
        P.mine:SetText("Your layer: |cff999999none here|r (no zone, or inside a dungeon)")
    end
    local lines = {}
    if forever and c and cur then
        local s = h.SeenText(c, zone, cur); if s then lines[#lines + 1] = s end
        local sp = c.SameLayer and h.SpanText(c, zone, cur); if sp then lines[#lines + 1] = "|cff888888" .. sp .. "|r" end
    end
    local g = (forever and c and c.GroupLayer) and c:GroupLayer() or nil
    local rj = c and c.Rejoining and c:Rejoining()
    if rj then
        lines[#lines + 1] = "|cffff8c40" .. (rj.phase == "asking" and ("Asking %s for a re-invite..."):format(rj.leader)
            or ("Waiting for %s's invite..."):format(rj.leader)) .. "|r"
    elseif g and g.differs then
        lines[#lines + 1] = ("|cffff8c40Not on %s's layer%s: Group hop fixes it.|r"):format(g.leader or "the leader",
            g.how == "exact" and g.pair and (" (%s)"):format(c:Label(zone, g.pair)) or "")
    end
    P.info:SetText(table.concat(lines, "\n"))
    -- world refresh
    local left = forever and h.RefreshLeft()
    if left then
        P.wr:SetText(left > 0 and ("|cffff8c40World refresh in %d:%02d: the game moves you to another layer.|r"):format(math.floor(left / 60), math.floor(left % 60))
            or "|cffff8c40World refresh any moment: the game moves you to another layer.|r")
        P.wr:Show(); P.wrBtn:Show(); P.wrBtn:SetEnabled(h.CanRefreshNow())
    else
        P.wr:Hide(); P.wrBtn:Hide()
    end

    -- other layers you can be brought to (with their rares)
    local blocked = c and c:Blocked()
    local online = c and c:Online()
    P.layersH:SetText("Other layers" .. (online and ("  |cff888888· %d Void online|r"):format(online) or ""))
    local list = (c and zone) and h.OtherLayers(c, zone, cur) or {}
    local seenCounts = (c and zone and c.SeenCounts) and c:SeenCounts(zone) or {}
    local rows = {}
    for _, l in ipairs(list) do
        local what = l.n > 0 and ("%d Void player%s"):format(l.n, l.n == 1 and "" or "s") or ""
        local sc = seenCounts[l.pair]
        if sc then what = (what ~= "" and what .. " · " or "") .. ("%d seen"):format(sc) end
        if l.rares then
            local x = l.rares[1]
            what = ("|cffff8040%s|r%s · %s"):format(x.name, #l.rares > 1 and (" +" .. (#l.rares - 1)) or "", what)
        end
        local spot = c.SpotCleared and c:SpotCleared(zone, l.pair)
        if spot then what = (what ~= "" and what .. " · " or "") .. ("|cffcc6666spot cleared %s ago|r"):format(h.Ago(spot)) end
        rows[#rows + 1] = { a = c:Label(zone, l.pair), b = what, pair = l.pair, canHop = true, hopOn = not blocked,
            tip = function(s)
                GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
                GameTooltip:AddLine(c:Label(zone, l.pair) .. "  |cff777777" .. l.pair .. "|r", 1, 1, 1)
                GameTooltip:AddLine("A Void player there can bring you over.", 0.8, 0.8, 0.8, true)
                for _, x in ipairs(l.rares or {}) do GameTooltip:AddLine(("Rare up: %s, %s ago"):format(x.name, h.Ago(x.age)), 1, 0.5, 0.25) end
                GameTooltip:Show()
            end }
    end
    P.layers:SetData(rows, true)
    P.layersEmpty:SetShown(#rows == 0)
    P.layersEmpty:SetText(P.asking and GetTime() - P.asking < 7 and "Asking the Void players here..."
        or "Nobody known who can bring you to another layer right now: Refresh asks the Void players here.")

    -- rares you can walk to (your layer, or next door on it)
    local rares = {}
    for _, x in ipairs((c and zone) and c:Rares(zone) or {}) do if x.same then rares[#rares + 1] = x end end
    if c and zone and c.RaresNextDoor then for _, x in ipairs(c:RaresNextDoor()) do rares[#rares + 1] = x end end
    local rrows = {}
    for _, x in ipairs(rares) do
        local where = x.nextDoor and ("|cff33ff33your layer|r, " .. h.ZoneName(x.zone)) or x.same and "|cff33ff33your layer|r" or c:Label(zone, x.pair)
        rrows[#rrows + 1] = { a = (x.hp == 0 and "|cff888888" or "|cffffd200") .. x.name .. "|r",
            b = ("%s · %s%s"):format(where, x.hp == 0 and "dead " or (x.hp < 100 and (x.hp .. "% ") or ""), h.Ago(x.age)),
            pair = x.pair, zone = x.zone, prefer = x.origin,
            canHop = not x.same and not x.nextDoor and x.hp > 0 and cur ~= nil, hopOn = not blocked,
            tip = function(s)
                GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
                GameTooltip:AddLine(x.name, 1, 0.82, 0)
                if x.nextDoor then
                    GameTooltip:AddLine(("In %s, on your layer. Walk over: no hop needed."):format(h.ZoneName(x.zone)), 1, 1, 1, true)
                else
                    GameTooltip:AddLine(x.same and "On your layer" or c:Label(zone, x.pair), 1, 1, 1)
                end
                if x.x > 0 or x.y > 0 then GameTooltip:AddLine(("Seen near %.0f, %.0f, %s ago"):format(x.x / 10, x.y / 10, h.Ago(x.age)), 0.8, 0.8, 0.8) end
                GameTooltip:Show()
            end }
    end
    P.rares:SetData(rrows, true)
    P.raresEmpty:SetShown(#rrows == 0)

    -- buttons
    local lead = UnitIsGroupLeader("player")
    if issecretvalue and issecretvalue(lead) then lead = false end
    local why = (not IsInGroup()) and "Only in a party or a raid."
        or lead and "You lead this group: the others use Group hop to come to your layer."
        or IsInInstance() and "Not inside a dungeon or raid."
        or InCombatLockdown() and "Not in combat."
        or rj and "Already on its way." or nil
    P.any.why = why
    P.any:SetEnabled(c ~= nil and c.Rejoin ~= nil and why == nil); P.any:SetAlpha(P.any:IsEnabled() and 1 or 0.45)
    local wait = (c and zone) and c:AskLeft(zone) or 0
    P.refresh:SetEnabled(c ~= nil and zone ~= nil and wait == 0); P.refresh:SetAlpha(P.refresh:IsEnabled() and 1 or 0.45)
    P.refresh:SetLabel(wait > 0 and ("Refresh %d:%02d"):format(math.floor(wait / 60), math.floor(wait % 60)) or "Refresh")
    local moving = c and c.MovingGroup and (c:MovingGroup() or c:Following())
    if moving then
        P.fresh.mode, P.fresh.why = "cancel", nil
        P.fresh:SetLabel("Cancel move"); P.fresh:SetEnabled(true)
    elseif c and c.MoveGroup and IsInGroup() and not IsInRaid() then
        P.fresh.mode, P.fresh.why = "group", c:MoveGroupBlocked()
        P.fresh:SetLabel("Move group"); P.fresh:SetEnabled(P.fresh.why == nil)
    else
        P.fresh.mode, P.fresh.why = nil, nil
        P.fresh:SetLabel("Fresh layer")
        P.fresh:SetEnabled(c ~= nil and c.StartFresh ~= nil and not blocked and cur ~= nil)
    end
    P.fresh:SetAlpha(P.fresh:IsEnabled() and 1 or 0.45)

    local status = c and ((c.GroupMoveStatus and c:GroupMoveStatus()) or c:Status())
    if not status and c then
        status = c:Blocked()
        if status == "A hop is under way." then status = nil end
        if not status then status = c:BlockReason() end
        if not status and c.FinderListed and c:FinderListed() then
            status = "|cff33ff33Hosting from your Group Finder listing:|r whisper inv, layer or swap and you're brought here."
        end
    end
    P.status:SetText(status or "")
end

local function Build(host)
    P = CreateFrame("Frame", nil, host)
    P:SetAllPoints()
    -- left: you
    P.zoneTitle = K.Text(P, "GameFontNormalLarge"); P.zoneTitle:SetPoint("TOPLEFT", 16, -12)
    P.mine = K.Text(P, "GameFontHighlight"); P.mine:SetPoint("TOPLEFT", 16, -40); P.mine:SetWidth(330)
    P.info = K.Text(P, "GameFontHighlightSmall"); P.info:SetPoint("TOPLEFT", P.mine, "BOTTOMLEFT", 0, -8); P.info:SetWidth(330)
    P.info:SetSpacing(3)
    P.wr = K.Text(P, "GameFontHighlightSmall"); P.wr:SetPoint("TOPLEFT", P.info, "BOTTOMLEFT", 0, -14); P.wr:SetWidth(330)
    P.wrBtn = K.Button(P, "New layer now", 120, function() local h = H(); if h then h.RefreshNow() end end)
    P.wrBtn:SetPoint("TOPLEFT", P.wr, "BOTTOMLEFT", 0, -6)
    tip(P.wrBtn, "New layer now", "The game has a world refresh coming for you, which moves you to another layer. This does it right away: solo, no group or host needed. The game picks the layer. Out of combat only.")

    -- the three buttons and the status line (bottom left)
    P.any = K.Button(P, "Group hop", 106, function() local c = core(); if c and c.Rejoin then c:Rejoin() end end)
    P.any:SetPoint("BOTTOMLEFT", 16, 40)
    tip(P.any, "Group hop", "Onto your group's layer, in a party or a raid: joining a group puts you on its leader's layer, so this leaves the group and gets you re-invited. With VoidLayer on the leader it happens by itself in a second or two; without it, the leader gets a whisper asking for the invite. Only you leave, the group stays. Not in combat or inside dungeons.",
        function(s) return s.why end)
    -- solo: Fresh layer; in a party: Move group (core 10); while a group move is under way: Cancel
    P.fresh = K.Button(P, "Fresh layer", 106, function()
        local c = core()
        if not c then return end
        if P.fresh.mode == "cancel" then c:MoveGroupCancel()
        elseif P.fresh.mode == "group" then c:MoveGroup()
        elseif c.StartFresh then c:StartFresh() end
    end)
    P.fresh:SetPoint("LEFT", P.any, "RIGHT", 6, 0)
    tip(P.fresh,
        function(s) return s.mode == "cancel" and "Cancel the group move" or s.mode == "group" and "Move group" or "Fresh layer here" end,
        function(s)
            if s.mode == "cancel" then return "Moving it: stops the hop and invites everyone back to where you are. Following: you stop waiting for the invite (it still shows up as usual)." end
            if s.mode == "group" then return "Takes your whole party to a fresh layer: the others leave the group, you hop (like Fresh layer) and invite them back. Joining puts them on your layer, so everyone lands there. With VoidLayer they leave and accept by themselves; without it they get a whisper. Anyone in the party can start it. Nobody leaves until a Void player on another layer is found; if the hop fails, you invite them back anyway." end
            return "Hops you to another layer: the one where the mobs around you are most likely up. Cleared this spot? This picks the layer where nobody reported clearing it, or reported it longest ago, and skips one you cleared it on yourself in the last 10 minutes. Only Void players report clears."
        end,
        function(s)
            if s.mode == "group" then return s.why end
            if s.mode then return nil end
            local c = core()
            local cur, zone; if c then cur, zone = c:Here() end
            if c and cur and c.SpotCleared then
                local age = c:SpotCleared(zone, cur)
                return age and ("This spot on your layer: cleared %s ago."):format(H().Ago(age)) or "This spot on your layer: no clear seen yet."
            end
        end)
    P.refresh = K.Button(P, "Refresh", 106, function()
        local c = core()
        local zone; if c then zone = select(2, c:Here()) end
        if zone and c:Ask(zone) then P.asking = GetTime() end
        Update()
    end)
    P.refresh:SetPoint("LEFT", P.fresh, "RIGHT", 6, 0)
    tip(P.refresh, "Ask the Void players in this zone which layer they're on", "Once every 2 minutes per zone, to keep the chatter down.")
    P.status = K.Text(P, "GameFontHighlightSmall"); P.status:SetPoint("BOTTOMLEFT", 16, 14); P.status:SetWidth(600)

    -- right: other layers, rares
    local right = CreateFrame("Frame", nil, P)
    right:SetPoint("TOPLEFT", 380, -10); right:SetPoint("BOTTOMRIGHT", -12, 70)
    P.layersH = K.Text(right, "GameFontNormal"); P.layersH:SetPoint("TOPLEFT", 0, 0)
    P.layers = K.List(right, 26, MakeRow, FillRow)
    P.layers:SetPoint("TOPLEFT", 0, -20); P.layers:SetPoint("RIGHT"); P.layers:SetHeight(26 * ROWS)
    P.layersEmpty = K.Text(right, "GameFontDisableSmall"); P.layersEmpty:SetPoint("TOPLEFT", 4, -24); P.layersEmpty:SetWidth(520)
    P.raresH = K.Text(right, "GameFontNormal", "Rares on your layer"); P.raresH:SetPoint("TOPLEFT", P.layers, "BOTTOMLEFT", 0, -14)
    P.rares = K.List(right, 26, MakeRow, FillRow)
    P.rares:SetPoint("TOPLEFT", P.raresH, "BOTTOMLEFT", 0, -6); P.rares:SetPoint("BOTTOMRIGHT")
    P.raresEmpty = K.Text(right, "GameFontDisableSmall", "None seen on your layer lately."); P.raresEmpty:SetPoint("TOPLEFT", P.raresH, "BOTTOMLEFT", 4, -8)

    P:SetScript("OnShow", function()
        local c = core()
        local zone; if c then zone = select(2, c:Here()) end
        if zone and c:Ask(zone) then P.asking = GetTime() end
        Update()
    end)
    P.elapsed = 0
    P:SetScript("OnUpdate", function(s, dt)
        s.elapsed = s.elapsed + dt
        if s.elapsed >= 1 then s.elapsed = 0; Update() end
    end)
    return P
end

-- the five options behind VoidLayer's gear
local function SettingsBuild(host)
    local function C(m) return function(...) local c = core(); if c and c[m] then return c[m](c, ...) end end end
    return K.SettingsPage(host, {
        { title = "Layers", items = {
            { "check", "Help others change layer", C("HostingOn"), C("SetHosting"),
              "When a Void player on your layer asks, you send them a quick group invite; the group ends on its own after 3 minutes. Only while you're solo, out of combat and outside dungeons, at most once every 2 minutes. Every hop works because someone helps." },
            { "check", "Host from my Group Finder listing", C("FinderOn"), C("SetFinder"),
              "Post a Group Finder listing (Custom, a note with the word \"layer\"). While it's up, anyone who whispers you inv, layer or swap, or clicks Group Invite on it, gets an invite onto your layer: no addon needed on their side. Same limits as helping. Friends' and guildmates' invites are never touched." },
            { "check", "Rare alerts", C("PopupsOn"), C("SetPopups"),
              "A rare up on another layer of your zone asks \"Hop there?\"; one on your layer gets a line in chat." },
            { "check", "Stay grouped after a hop", C("StayOn"), C("SetStay"),
              "Only needed if leaving the group sends you back to your old layer; VoidLayer turns this on by itself when it sees that happen." },
            { "check", "Show my layer under the minimap", function() local h = H(); return h and h.LabelOn() end,
              function(on) local h = H(); if h then h.SetLabel(on) end end, "Click it to open the VoidLayer window. Drag to move it." },
        } },
    }, 380)
end

ns.RegisterPage("VoidLayer", {
    available = function() return H() ~= nil end,
    sections = {
        { key = "layers", label = "Layers", build = Build },
        { key = "settings", label = "Settings", build = SettingsBuild },
    },
})
