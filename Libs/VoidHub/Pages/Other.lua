----------------------------------------------------------------------
-- VoidHub pages for "Other":
--   VoidChat      Settings: its gear menu (time stamps, a tab per whisper, fade, text size, background, hide
--                 Blizzard's chat, put the window back). The chat window itself stays where you play.
--   VoidCalendar  Agenda: every event from today on (this month and next), from VoidCalendar's own reader
--                 (VoidCalendar.Events:GetEvents), its times (your local / the server's) and colors; click = its
--                 event popup, "Create event" = its create popup. Settings: its options. The month grid stays in
--                 VoidCalendar's window for now (Open the month view).
----------------------------------------------------------------------
local ns = _G.VoidHubWin
if not ns or ns.skip then return end   -- another Void addon's copy of VoidHub runs the window
local K = ns.Kit

----------------------------------------------------------------------
-- VoidChat
----------------------------------------------------------------------
local function CH() return _G.VoidChatHub end

local function ChatSettings(host)
    local H = CH()
    local function flag(key) return function() return H.DB()[key] == true end, function(on) H.Toggle(key, on) end end
    local g1, s1 = flag("stamps")
    local g2, s2 = flag("whisperTabs")
    local g3, s3 = flag("fade")
    return K.SettingsPage(host, {
        { title = "Chat", items = {
            { "check", "Show the time on each line", g1, s1 },
            { "check", "A tab for each person you whisper", g2, s2, "Off: the person tabs close now, not only new ones." },
            { "check", "Fade the window when idle", g3, s3 },
            { "choice", "Text size", { { 11, "11" }, { 12, "12" }, { 13, "13" }, { 14, "14" }, { 16, "16" }, { 18, "18" } },
              function() return H.DB().font end, function(v) H.SetFont(v) end },
            { "choice", "Background", { { 0, "Clear" }, { 0.3, "Light" }, { 0.55, "Medium" }, { 0.8, "Dark" } },
              function() return H.DB().bg end, function(v) H.SetBg(v) end },
        } },
        { title = "Window", items = {
            { "check", "Hide Blizzard's chat window (reloads)", function() return H.DB().hideBlizzard end, function(on) H.SetHideBlizzard(on) end,
              "Changing this reloads your interface right away." },
            { "button", "Put the window back where it started", function() H.ResetSpot() end },
            { "note", "Tabs: right-click a tab on the chat window to edit it.", h = 22 },
        } },
    }, 380)
end

ns.RegisterPage("VoidChat", {
    available = function() return CH() ~= nil end,
    sections = { { key = "settings", label = "Settings", build = ChatSettings } },
})

----------------------------------------------------------------------
-- VoidCalendar
----------------------------------------------------------------------
local function VC() return _G.VoidCalendar end
local AP
local DOW = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
local MON = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

local function evKey(e)
    return ("%04d-%02d-%02d:%02d%02d:%s"):format(e.startYear or 0, e.startMonth or 0, e.startDay or 0,
        e.startHour or 0, e.startMin or 0, tostring(e.title or ""):sub(1, 32))
end
local function isBlizz(e)
    local t = (e.calendarType or ""):upper()
    return e.category == "blizzard" or t == "HOLIDAY" or t == "RAID_LOCKOUT" or t == "RAID_RESET" or t == "ARENA"
end

local function AgendaRender()
    if not (AP and AP:IsVisible()) then return end
    local C = VC()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        AP.note:SetText("|cffffd200The game hides calendar events from addons right now (chat lockdown): they show again when it lifts.|r")
        return
    end
    -- the calendar API on this month (only when it isn't already: VoidCalendar's own rule, the other way loops)
    local now = C_DateAndTime.GetCurrentCalendarTime()
    if not now then return end
    local cur = C_Calendar.GetMonthInfo and C_Calendar.GetMonthInfo(0)
    if not (cur and cur.month == now.month and cur.year == now.year) and C_Calendar.SetAbsMonth then
        C_Calendar.SetAbsMonth(now.month, now.year)
    end
    local hide = C:GetDB().hideBlizzEvents
    local local_ = C:GetDB().primaryTimeIs == "local"
    local rows = {}
    for off = 0, 1 do
        local mi = C_Calendar.GetMonthInfo(off)
        if mi then
            for d = (off == 0 and now.monthDay or 1), (mi.numDays or 30) do
                local list = {}
                for _, e in ipairs(C.Events:GetEvents(off, d) or {}) do
                    if not (hide and isBlizz(e)) then list[#list + 1] = e end
                end
                if #list > 0 then
                    local wd = ((mi.firstWeekday or 1) - 1 + d - 1) % 7 + 1
                    local today = off == 0 and d == now.monthDay
                    rows[#rows + 1] = { head = ("%s%s, %s %d|r"):format(today and "|cff33ff33Today · " or "|cffffd200", DOW[wd], MON[mi.month] or "?", d) }
                    for _, e in ipairs(list) do
                        local t
                        if local_ then
                            local u = C.TimeUtil:ServerEventToPlayerUnix(e.startYear, e.startMonth, e.startDay, e.startHour, e.startMin, e.creator, evKey(e))
                            t = u and C.TimeUtil:FormatPlayerTime(u, "%I:%M %p"):gsub("^0", "") or ""
                        else
                            t = C.TimeUtil:FormatServerTime(e.startHour, e.startMin, "%d:%02d %s")
                        end
                        rows[#rows + 1] = { e = e, off = off, day = d, time = t }
                    end
                end
            end
        end
    end
    AP.list:SetData(rows, true)
    AP.note:SetText(#rows == 0 and "|cff8c8c9eNothing on your calendar from today to the end of next month (events load a few seconds after login).|r"
        or ("|cff8c8c9eTimes are %s. Click an event for its details and sign-ups.|r"):format(local_ and "your local time" or "server time"))
end

local function AgendaBuild(host)
    AP = CreateFrame("Frame", nil, host)
    AP:SetAllPoints()
    local h = K.Text(AP, "GameFontNormalLarge", "|cff00c7ffComing up|r"); h:SetPoint("TOPLEFT", 16, -10)
    AP.note = K.Text(AP, "GameFontDisableSmall"); AP.note:SetPoint("TOPLEFT", 16, -32); AP.note:SetWidth(620)
    local create = K.Button(AP, "Create event", 110, function()
        local n = C_DateAndTime.GetCurrentCalendarTime()
        if n and VC().EventCreate then VC().EventCreate:Show({ year = n.year, month = n.month, day = n.monthDay }, "PLAYER") end
    end)
    create:SetPoint("TOPRIGHT", -16, -10)
    local month = K.Button(AP, "Month view", 110, function() ns.Open("VoidCalendar", "month") end)
    month:SetPoint("RIGHT", create, "LEFT", -8, 0)
    AP.list = K.List(AP, 22, function(r)
        r:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        r:GetHighlightTexture():SetVertexColor(K.A[1], K.A[2], K.A[3], 0.10)
        r.bar = r:CreateTexture(nil, "ARTWORK"); r.bar:SetPoint("TOPLEFT", 4, -3); r.bar:SetPoint("BOTTOMLEFT", 4, 3); r.bar:SetWidth(3)
        r.time = K.Text(r, "GameFontHighlight"); r.time:SetPoint("LEFT", 14, 0); r.time:SetWidth(90)
        r.title = K.Text(r, "GameFontHighlight"); r.title:SetPoint("LEFT", 108, 0); r.title:SetPoint("RIGHT", -8, 0); r.title:SetWordWrap(false)
        r:SetScript("OnClick", function(s)
            local it = s.item
            if it and it.e and VC().EventDetail then VC().EventDetail:Show(it.off, it.day, it.e.idx) end
        end)
        r:SetScript("OnEnter", function(s)
            local it, C = s.item, VC()
            if not (it and it.e) then return end
            local e = it.e
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetText(e.title, 1, 1, 1)
            local tz = C.TimeUtil:GetEventTzInfo(e.startYear, e.startMonth, e.startDay, e.creator, evKey(e))
            local u = C.TimeUtil:ServerEventToPlayerUnix(e.startYear, e.startMonth, e.startDay, e.startHour, e.startMin, e.creator, evKey(e))
            GameTooltip:AddDoubleLine(("Server (%s):"):format(tz.abbr), C.TimeUtil:FormatServerTime(e.startHour, e.startMin), 0.7, 0.7, 0.7, 1, 1, 1)
            GameTooltip:AddDoubleLine("Your local:", u and C.TimeUtil:FormatPlayerTime(u) or "-", 0, 0.78, 1, 1, 1, 0.6)
            if e.description and e.description ~= "" then GameTooltip:AddLine(" "); GameTooltip:AddLine(e.description:sub(1, 200), 0.8, 0.8, 0.85, true) end
            GameTooltip:AddLine("Click: details and sign-ups", 0.5, 0.8, 1)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end, function(r, it)
        if it.head then
            r.bar:Hide(); r.time:SetText(""); r.title:SetPoint("LEFT", 8, 0); r.title:SetText(it.head); r:EnableMouse(false)
            return
        end
        r:EnableMouse(true)
        local P = VC().palette or {}
        local c = P[it.e.category] or P.other or { 0.55, 0.55, 0.6 }
        r.bar:SetColorTexture(c[1], c[2], c[3], 1); r.bar:Show()
        r.time:SetText("|cffeeeeff" .. (it.time or "") .. "|r")
        r.title:SetPoint("LEFT", 108, 0)
        r.title:SetText(it.e.title or "")
    end)
    AP.list:SetPoint("TOPLEFT", 8, -56); AP.list:SetPoint("BOTTOMRIGHT", -12, 10)
    AP:SetScript("OnShow", function()
        if C_Calendar and C_Calendar.OpenCalendar then pcall(C_Calendar.OpenCalendar) end   -- ask for fresh data
        AgendaRender()
    end)
    -- data arrives a few seconds after asking, and changes when events are made / signed up to
    K.LiveEvents(AP, { "CALENDAR_UPDATE_EVENT_LIST", "CALENDAR_NEW_EVENT", "CALENDAR_UPDATE_INVITE_LIST" }, AgendaRender)
    return AP
end

----------------------------------------------------------------------
-- The month grid (VoidCalendar's window, in the hub): 6 x 7 days, up to 3 events a day (+N), today lit.
-- Event rows use VoidCalendar's OWN handlers (Calendar.Hub.RowScripts: click = the event, right-click = its menu with
-- copy / edit / delete / time zone; hover = both times). A day: click = create an event there, right-click = create
-- (yours / guild / community) or paste a copied event. Moves the calendar API's month only when it isn't there already
-- (VoidCalendar's own rule: the other way loops).
----------------------------------------------------------------------
local MG
local function MonthRender()
    if not (MG and MG:IsVisible()) then return end
    local C = VC()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return end
    local now = C_DateAndTime.GetCurrentCalendarTime()
    if not now then return end
    local tm, ty = now.month + MG.offset, now.year
    while tm > 12 do tm = tm - 12; ty = ty + 1 end
    while tm < 1 do tm = tm + 12; ty = ty - 1 end
    local cur = C_Calendar.GetMonthInfo and C_Calendar.GetMonthInfo(0)
    if not (cur and cur.month == tm and cur.year == ty) and C_Calendar.SetAbsMonth then C_Calendar.SetAbsMonth(tm, ty) end
    local mi = C_Calendar.GetMonthInfo(0)
    if not mi then return end
    MG.title:SetText(("%s %d"):format(C.Calendar.Hub.MONTH_NAMES[mi.month] or "?", mi.year))
    local first, num = mi.firstWeekday or 1, mi.numDays or 30
    local today = C.TimeUtil:GetCurrentServerCalendar() or {}
    local hide, local_ = C:GetDB().hideBlizzEvents, C:GetDB().primaryTimeIs == "local"
    local P = C.palette or {}
    for i, cell in ipairs(MG.cells) do
        local d = i - (first - 1)
        if d < 1 or d > num then
            cell.day:SetText(""); cell:SetAlpha(0.25); cell.info = nil; cell.today:Hide()
            for _, r in ipairs(cell.rows) do r:Hide() end
            cell.more:SetText("")
        else
            cell:SetAlpha(1)
            cell.info = { year = mi.year, month = mi.month, day = d }
            cell.day:SetText(tostring(d))
            cell.today:SetShown(mi.year == today.year and mi.month == today.month and d == today.day)
            local list = {}
            for _, e in ipairs(C.Events:GetEvents(0, d) or {}) do if not (hide and isBlizz(e)) then list[#list + 1] = e end end
            for k, r in ipairs(cell.rows) do
                local e = list[k]
                if e then
                    local c = P[e.category] or P.other or { 0.55, 0.55, 0.6 }
                    K.Recolor(r, { c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 0.7 }, { c[1], c[2], c[3], 0.6 })
                    local t
                    if local_ then
                        local u = C.TimeUtil:ServerEventToPlayerUnix(e.startYear, e.startMonth, e.startDay, e.startHour, e.startMin, e.creator, evKey(e))
                        t = u and C.TimeUtil:FormatPlayerTime(u, "%I:%M%p"):gsub("^0", "") or ""
                    else
                        t = C.TimeUtil:FormatServerTime(e.startHour, e.startMin, "%d:%02d%s")
                    end
                    r.label:SetText(("|cffeeeeff%s|r %s"):format((t:gsub(" ", "")), e.title))   -- (gsub's count dropped)
                    r._eventData, r._monthOffset, r._day = e, 0, d
                    r:Show()
                else
                    r:Hide(); r._eventData = nil
                end
            end
            cell.more:SetText(#list > 3 and ("+%d"):format(#list - 3) or "")
        end
    end
end

local function dayMenu(cell)
    local C = VC()
    if not (cell.info and C.ContextMenu) then return end
    local items = {
        { label = "Create Event", callback = function() C.EventCreate:Show(cell.info, "PLAYER") end },
        { label = "Create Guild Event", callback = function() C.EventCreate:Show(cell.info, "GUILD") end },
        { label = "Create Community Event", callback = function() C.EventCreate:Show(cell.info, "COMMUNITY") end },
    }
    if C._copiedEvent then   -- VoidCalendar's own paste (Calendar.lua, the day header's menu)
        items[#items + 1] = { separator = true, label = "" }
        items[#items + 1] = { label = ("Paste '%s' here"):format(C._copiedEvent.title or "event"), callback = function()
            local d = cell.info
            local cur = C_Calendar.GetMonthInfo and C_Calendar.GetMonthInfo(0)
            local off = (cur and cur.year and cur.month) and ((d.year - cur.year) * 12 + (d.month - cur.month)) or 0
            if C_Calendar.ContextMenuEventClipboard then pcall(C_Calendar.ContextMenuEventClipboard) end
            if C_Calendar.GetDayEvent then pcall(C_Calendar.GetDayEvent, off, d.day, 1) end
            if C_Calendar.ContextMenuSelectEvent then pcall(C_Calendar.ContextMenuSelectEvent, off, d.day, 1) end
            if C_Calendar.ContextMenuEventPaste then pcall(C_Calendar.ContextMenuEventPaste, off, d.day) end
            print(("|cff00c7ff[VoidCalendar]|r Pasted '%s' to %04d-%02d-%02d"):format(C._copiedEvent.title or "event", d.year, d.month, d.day))
            C_Timer.After(1, MonthRender); C_Timer.After(3, MonthRender)
        end }
    end
    C.ContextMenu:Show(items)
end

local function MonthBuild(host)
    MG = CreateFrame("Frame", nil, host)
    MG:SetAllPoints()
    MG.offset = 0
    local C = VC()
    local prev = K.Button(MG, "<", 28, function() MG.offset = MG.offset - 1; MonthRender() end); prev:SetPoint("TOPLEFT", 12, -8)
    MG.title = K.Text(MG, "GameFontNormalLarge"); MG.title:SetPoint("LEFT", prev, "RIGHT", 12, 0); MG.title:SetWidth(200)
    local nextB = K.Button(MG, ">", 28, function() MG.offset = MG.offset + 1; MonthRender() end); nextB:SetPoint("LEFT", MG.title, "RIGHT", 8, 0)
    local todayB = K.Button(MG, "Today", 70, function() MG.offset = 0; MonthRender() end); todayB:SetPoint("LEFT", nextB, "RIGHT", 8, 0)
    local hint = K.Text(MG, "GameFontDisableSmall", "Click a day: create an event. Click an event: details. Right-click either: more.")
    hint:SetPoint("TOPRIGHT", -12, -14)
    local onClick, onEnter = C.Calendar.Hub.RowScripts()
    local W = math.floor(((host:GetWidth() or 0) > 300 and host:GetWidth() or 980) - 24)
    local cw = math.floor(W / 7)
    local ch = math.floor((((host:GetHeight() or 0) > 200 and host:GetHeight() or 488) - 64) / 6)
    for c = 1, 7 do
        local h = K.Text(MG, "GameFontNormalSmall", C.Calendar.Hub.DAYS_OF_WEEK[c]); h:SetPoint("TOPLEFT", 12 + (c - 1) * cw + 4, -38)
    end
    MG.cells = {}
    for i = 1, 42 do
        local col, row = (i - 1) % 7, math.floor((i - 1) / 7)
        local cell = CreateFrame("Button", nil, MG)
        cell:SetSize(cw - 3, ch - 3)
        cell:SetPoint("TOPLEFT", 12 + col * cw, -54 - row * ch)
        K.Box(cell, { 0.05, 0.06, 0.08, 1 }, { 0.15, 0.18, 0.22, 1 })
        cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        cell.today = cell:CreateTexture(nil, "BACKGROUND", nil, 1); cell.today:SetAllPoints(); cell.today:SetColorTexture(K.A[1], K.A[2], K.A[3], 0.12)
        cell.day = K.Text(cell, "GameFontNormal"); cell.day:SetPoint("TOPLEFT", 4, -3)
        cell.more = K.Text(cell, "GameFontHighlightSmall"); cell.more:SetPoint("BOTTOMRIGHT", -4, 3); cell.more:SetTextColor(K.A[1], K.A[2], K.A[3])
        cell:SetScript("OnClick", function(s, button)
            if not s.info then return end
            if button == "RightButton" then dayMenu(s) else VC().EventCreate:Show(s.info, "PLAYER") end
        end)
        cell.rows = {}
        for k = 1, 3 do
            local r = CreateFrame("Button", nil, cell)
            r:SetHeight(14)
            r:SetPoint("TOPLEFT", 3, -18 - (k - 1) * 16); r:SetPoint("RIGHT", -3, 0)
            K.Box(r, { 0.2, 0.2, 0.25, 0.7 }, K.EDGE)
            r.label = K.Text(r, "GameFontHighlightSmall"); r.label:SetPoint("LEFT", 4, 0); r.label:SetPoint("RIGHT", -4, 0); r.label:SetWordWrap(false)
            r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            if onClick then r:SetScript("OnClick", onClick) end
            if onEnter then r:SetScript("OnEnter", onEnter) end
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            cell.rows[k] = r
        end
        MG.cells[i] = cell
    end
    MG:SetScript("OnShow", function()
        if C_Calendar and C_Calendar.OpenCalendar then pcall(C_Calendar.OpenCalendar) end
        MonthRender()
    end)
    K.LiveEvents(MG, { "CALENDAR_UPDATE_EVENT_LIST", "CALENDAR_NEW_EVENT", "CALENDAR_UPDATE_INVITE_LIST" }, MonthRender)
    return MG
end

local function CalSettings(host)
    local C = VC()
    local R = C.Reminders
    local items = {
        { "choice", "Bigger time", { { "local", "Your local" }, { "server", "Server" } },
          function() return C:GetDB().primaryTimeIs end, function(v) C:GetDB().primaryTimeIs = v; if C.Calendar then C.Calendar._lastSig = nil; if C.Calendar:IsShown() then C.Calendar:Refresh() end end end },
        { "check", "Hide Blizzard events (holidays, lockouts)", function() return C:GetDB().hideBlizzEvents end,
          function(on) C:GetDB().hideBlizzEvents = on; if C.Calendar and C.Calendar:IsShown() then C.Calendar:Refresh() end end },
    }
    if R and R.IsEnabled then
        items[#items + 1] = { "check", "Reminders before events you accepted", function() return R:IsEnabled() end, function(on) R:SetEnabled(on) end }
        items[#items + 1] = { "number", "Remind me (minutes before)", function() return VoidCalendarDB.defaultReminderMinutes or 30 end,
            function(v) VoidCalendarDB.defaultReminderMinutes = v; if R.Reschedule then R:Reschedule() end end, "Press Enter to save." }
        items[#items + 1] = { "check", "Reminder sound", function() return VoidCalendarDB.notificationSound end, function(on) VoidCalendarDB.notificationSound = on end }
    end
    return K.SettingsPage(host, { { title = "Calendar", items = items } }, 420)
end

ns.RegisterPage("VoidCalendar", {
    available = function() local c = VC(); return c ~= nil and c.Events ~= nil and c.TimeUtil ~= nil and c.GetDB ~= nil end,
    sections = {
        { key = "agenda", label = "Coming up", build = AgendaBuild },
        { key = "month", label = "Month", build = MonthBuild,
          available = function() local c = VC(); return c.Calendar and c.Calendar.Hub and c.EventCreate and c.ContextMenu end },
        { key = "settings", label = "Settings", build = CalSettings },
    },
})
