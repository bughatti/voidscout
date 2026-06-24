----------------------------------------------------------------------
-- VoidScout — first-run consent dialog + opt-out controls.
--
-- VoidScout's value loop depends on uploading two streams of data to
-- api.voidscout.io so the community percentile model has fresh inputs:
--
--   1) FightRecorder fight summaries (per-pull axes + roster) →
--      VoidScoutDB.scores
--   2) PlayerScan player profile captures (names/realms/classes visible
--      to your client via mouseover, party/raid roster, LFG roster) →
--      VoidScoutDB.playerScan.players
--
-- The companion Go uploader (voidscout-uploader/main.go) drains both
-- tables and POSTs to /api/ingest/fight + /api/profile/batch. Because
-- the uploader can run silently on any install, we MUST get explicit
-- consent before populating either table.
--
-- The choice persists in VoidScoutDB.consent:
--   "allowed"  → fight summaries + player profiles persist locally,
--                uploader drains as normal
--   "local"    → addon still functions for in-game tooltip/panel reads
--                (VoidScoutBundle.lua data is bundled with the addon,
--                not user-contributed), but the addon does NOT write
--                fight summaries to VoidScoutDB.scores or new profile
--                captures to VoidScoutDB.playerScan.players. Uploader
--                has nothing to drain.
--   nil        → first run; dialog will fire next PLAYER_LOGIN
--
-- /vs consent → shows current state; if no choice on file, opens dialog
-- /vs optout  → switch to local-only
-- /vs optin   → switch to uploads enabled
--
-- Subcommands are dispatched by Core.lua's existing /vs handler, which
-- calls the public VoidScout_SetConsent_* / VoidScout_PrintConsentStatus
-- helpers defined here. Registering /vs directly from this module would
-- clobber the rest of the slash surface (log, pugs, preview, etc.).
--
-- The primary UX surface for VoidScout is the LFG side panel + tooltip
-- integration; the slash command is a fallback per the team rule against
-- typed-slash-first UX (see feedback-no-typed-slash-commands memory).
----------------------------------------------------------------------

local CONSENT_VERSION = 3  -- bump if we add new data categories (v2: gear + achievements explicit; v3: explained the companion-uploader requirement + voidscout.io/install)

VoidScoutDB = VoidScoutDB or {}

local function readConsent()
    local c = VoidScoutDB.consent
    if type(c) ~= "table" then return nil end
    if c.version ~= CONSENT_VERSION then return nil end  -- new version → re-prompt
    return c.choice  -- "allowed" or "local"
end

local function writeConsent(choice)
    VoidScoutDB.consent = {
        version   = CONSENT_VERSION,
        choice    = choice,
        chosen_at = time(),
    }
end

-- Public predicate read by FightRecorder + PlayerScan at every
-- persistence write site. Returns true ONLY when the user has
-- explicitly chosen "allowed". A missing choice (nil) or "local"
-- choice both return false so we fail closed.
function VoidScout_IsUploadAllowed()
    return readConsent() == "allowed"
end

----------------------------------------------------------------------
-- Dialog
----------------------------------------------------------------------
local dlg
local function BuildDialog()
    if dlg then return dlg end
    local f = CreateFrame("Frame", "VoidScout_ConsentDialog", UIParent, "BackdropTemplate")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetSize(640, 540)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("|cff00c7ffVoidScout|r - what gets uploaded")

    local body = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    body:SetPoint("TOPLEFT", 22, -50)
    body:SetPoint("TOPRIGHT", -22, -50)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetText(
        "VoidScout scores pug applicants by absorbing the things you can already see in-game and shipping them to |cffffd700api.voidscout.io|r so the community has fresh percentile data.\n\n" ..
        "|cffffd700What we upload:|r\n" ..
        "  - Per-fight summaries: encounter, duration, outcome, your party/raid roster (names, realms, classes, specs)\n" ..
        "  - 8-axis behavioral scores from Blizzard's damage meter API\n" ..
        "  - |cffffd700Equipped gear:|r item links per slot (item ID, enchants, gems, transmog) for you AND any player you've mouseovered or inspected\n" ..
        "  - |cffffd700Achievements visible via inspection:|r boss-kill achievements seen through GetAchievementComparisonInfo\n" ..
        "  - Player profile captures: names/realms/classes of players visible to your client (mouseover, party, LFG roster)\n\n" ..
        "|cffffd700We do NOT upload:|r chat/whisper content, bag contents, bank, currency, system info, anything from protected actions, anything from players not visible to your client.\n\n" ..
        "|cffffd700Note about Blizzard API:|r the server ALSO fetches public Blizzard profile data (gear, raid progress, M+ keys) for characters already in our database. That runs server-side against Blizzard's official API — independent of this consent.\n\n" ..
        "|cffffd700How uploading works:|r WoW addons can't send data over the web, so uploads go through a small separate app you install once -- |cffffd700voidscout-uploader|r (open-source, a single ~7 MB file). Get it at |cff00c7ffvoidscout.io/install|r. Without it nothing uploads -- the addon still works fully (bundle-backed scores + tooltips).\n\n" ..
        "Local-only mode: the addon's panel + tooltip + bundle-backed scores keep working. We just won't record new fight summaries or profile captures to your SavedVariables, so the uploader has nothing to drain."
    )

    local btn_allow = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btn_allow:SetSize(170, 26)
    btn_allow:SetPoint("BOTTOMLEFT", 22, 18)
    btn_allow:SetText("Allow uploads")
    btn_allow:SetScript("OnClick", function()
        writeConsent("allowed")
        print("|cff00c7ff[VoidScout]|r uploads ENABLED. Change anytime with |cffffd700/vs|r.")
        f:Hide()
    end)

    local btn_local = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btn_local:SetSize(190, 26)
    btn_local:SetPoint("BOTTOM", 0, 18)
    btn_local:SetText("Local-only (no upload)")
    btn_local:SetScript("OnClick", function()
        writeConsent("local")
        print("|cff00c7ff[VoidScout]|r local-only mode. Your captures stay off the wire. Change with |cffffd700/vs|r.")
        f:Hide()
    end)

    -- "Delete + go local" — the strongest opt-out. Sets the request flag
    -- in SavedVariables; the Go uploader (next run) POSTs /api/opt-out
    -- so the server deletes the existing data and adds this identity to
    -- the permanent block list. Also flips consent to local-only so no
    -- further uploads happen between now and uploader-run.
    local btn_delete = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btn_delete:SetSize(190, 26)
    btn_delete:SetPoint("BOTTOMRIGHT", -22, 18)
    btn_delete:SetText("Delete + go local")
    btn_delete:SetScript("OnClick", function()
        VoidScoutDB = VoidScoutDB or {}
        writeConsent("local")
        -- Resolve identity at request time.
        local name  = UnitName("player") or ""
        local realm = GetRealmName() or ""
        realm = realm:gsub("[^%w]", "")  -- match server slug rules
        local region = "us"
        if GetCurrentRegion then
            local rid = GetCurrentRegion()
            region = ({"us","kr","eu","tw","cn"})[rid] or "us"
        end
        VoidScoutDB.opt_out_requested = {
            name           = name,
            realm          = realm,
            region         = region,
            requested_at   = time(),
            source         = "VoidScout-in-game",
            attempts       = 0,
        }
        print(("|cffffd700[VoidScout]|r Deletion requested for |cffffaa20%s-%s-%s|r. The uploader will send the request to voidscout.io within ~15 min. Addon stays usable; only your data on the server is removed."):format(
            name, realm, region:upper()))
        f:Hide()
    end)

    local btn_close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    btn_close:SetPoint("TOPRIGHT", -4, -4)

    f:Hide()
    dlg = f
    return f
end

local function ShowDialog()
    BuildDialog():Show()
end

-- Expose the show function for programmatic open (e.g. from a settings
-- button in the LFG panel). Kept under the VoidScout namespace so the
-- panel can call VoidScout_ShowConsentDialog() without touching globals.
function VoidScout_ShowConsentDialog()
    ShowDialog()
end

-- Programmatic setters used by Core.lua's existing /vs slash handler
-- (it dispatches /vs optout, /vs optin, /vs consent). We do NOT
-- register a separate /vs SlashCmdList entry here because Core.lua
-- already owns /vs — registering ours would clobber the rest of the
-- existing surface (log, pugs, preview, scan, etc.).
function VoidScout_SetConsent_OptOut()
    writeConsent("local")
    print("|cff00c7ff[VoidScout]|r switched to LOCAL-ONLY. New fight summaries and profile captures will not be recorded.")
end

function VoidScout_SetConsent_OptIn()
    writeConsent("allowed")
    print("|cff00c7ff[VoidScout]|r switched to UPLOADS ENABLED.")
end

function VoidScout_PrintConsentStatus()
    local c = readConsent()
    if c == "allowed" then
        print("|cff00c7ff[VoidScout]|r consent: |cff20ff20uploads ENABLED|r. /vs optout to stop.")
    elseif c == "local" then
        print("|cff00c7ff[VoidScout]|r consent: |cffffaa20LOCAL-ONLY|r. /vs optin to allow uploads.")
    else
        print("|cff00c7ff[VoidScout]|r no consent choice on file. Opening dialog...")
        ShowDialog()
    end
end

----------------------------------------------------------------------
-- Login trigger
----------------------------------------------------------------------
local f = CreateFrame("Frame", "VoidScout_ConsentLoginFrame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        if readConsent() == nil then
            -- Delay one second so the login chat dust settles before
            -- popping a fullscreen dialog at the user.
            C_Timer.After(1.0, ShowDialog)
        end
        self:UnregisterAllEvents()
    end
end)
