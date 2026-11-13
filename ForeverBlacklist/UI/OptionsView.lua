-- Forever Blacklist: "Options" tab (+ a stub in the game's AddOns settings).
local _, FBL = ...

local T, W = FBL.Theme, FBL.Widgets
local View = {}
FBL.Views.options = View

local controls = {}

local function opt(key) return function() return FBL.opt[key] end end
local function setOpt(key, after)
    return function(v)
        FBL.opt[key] = v
        if after then after(v) end
        FBL:Fire("OPTIONS_CHANGED", key)
    end
end

--- Column layout helper.
local function Column(parent, x, width)
    local col = { y = -6, x = x, width = width, parent = parent }
    function col:Header(text)
        local h = W.Header(parent, text)
        h:SetPoint("TOPLEFT", self.x, self.y - 8)
        h.line:SetPoint("RIGHT", parent, "LEFT", self.x + self.width, 0)
        self.y = self.y - 34
    end
    function col:Check(label, key, tip, after)
        local c = W.Check(parent, label, opt(key), setOpt(key, after), tip)
        c:SetPoint("TOPLEFT", self.x + 2, self.y)
        controls[#controls + 1] = c
        self.y = self.y - 26
        return c
    end
    function col:Slider(label, key, minV, maxV, step, fmt, after)
        local s = W.Slider(parent, label, minV, maxV, step, opt(key), setOpt(key, after), fmt, self.width - 10)
        s:SetPoint("TOPLEFT", self.x + 2, self.y)
        controls[#controls + 1] = s
        self.y = self.y - 46
        return s
    end
    function col:Dropdown(label, key, options, after)
        local l = W.Text(parent, "GameFontHighlight", label)
        l:SetPoint("TOPLEFT", self.x + 2, self.y - 2)
        local d = W.Dropdown(parent, self.width - 20, options, opt(key), setOpt(key, after))
        d:SetPoint("TOPLEFT", self.x + 2, self.y - 20)
        controls[#controls + 1] = d
        self.y = self.y - 54
        return d
    end
    function col:Space(h) self.y = self.y - (h or 8) end
    return col
end

function View.Create(f)
    local panel = W.Panel(f, { 0.075, 0.075, 0.09, 0.95 })
    panel:SetAllPoints()
    local sf = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 8, -8)
    sf:SetPoint("BOTTOMRIGHT", -26, 8)
    local c = CreateFrame("Frame", nil, sf)
    c:SetSize(860, 640)
    sf:SetScrollChild(c)

    local colW = 270
    local a = Column(c, 10, colW)
    local b = Column(c, 10 + colW + 20, colW)
    local d = Column(c, 10 + (colW + 20) * 2, colW)

    -- Column 1: alerts
    a:Header("Alerts")
    a:Check("Enable alerts", "alertsEnabled", "Show a toast when a blacklisted player is spotted.")
    local soundOpts = {}
    for _, s in ipairs(FBL.SOUNDS) do soundOpts[#soundOpts + 1] = { value = s.key, label = s.label } end
    a:Dropdown("Alert sound", "alertSound", soundOpts, function(v) FBL.PlayAlertSound(v) end)
    a:Check("Flash screen edges", "alertFlash", "Pulse the screen edges in the severity colour.")
    a:Check("Print to chat", "alertChat", "Adds a clickable line to your chat window.")
    a:Check("Alert inside instances", "alertInInstances")
    a:Check("Alert when they join my group", "alertOnGroupJoin", "Always alerts (ignores cooldown) when a blacklisted player joins your party or raid.")
    a:Check("Tell my group too", "announceToGroup", "Posts a short line in party/raid chat when a blacklisted player joins.")
    a:Slider("Alert cooldown per player", "alertCooldown", 1, 60, 1, "%d min")
    a:Slider("Only alert at severity", "minAlertSeverity", 1, 5, 1, "%d+")
    local test = W.Button(c, "Test Alert", 110, 22)
    test:SetPoint("TOPLEFT", a.x + 2, a.y - 4)
    test:SetScript("OnClick", function()
        FBL.Alert({ key = "test", name = "Leeroy-Test", classFile = "PALADIN", level = 60, category = "GRIEF",
            severity = 4, comment = "This is what an alert looks like." }, "is nearby (test)", true)
    end)

    -- Column 2: protection + tracking
    b:Header("Protection")
    b:Check("Auto-decline group invites", "autoDeclineInvites")
    b:Check("Auto-cancel trades", "autoDeclineTrades", "When off you still get a warning when a trade opens.")
    b:Check("Auto-decline duels", "autoDeclineDuels")
    b:Check("Hide their whispers", "hideWhispers")
    b:Check("Tag their chat messages", "chatTag", "Prefixes their messages with a skull [BL] tag.")
    b:Check("Show info in unit tooltips", "tooltipInfo")
    b:Check("Mark their nameplates", "nameplateMarker", "Shows a pulsing skull above their nameplate.", function()
        FBL.Detection.RefreshNameplates()
    end)
    b:Header("Tracking")
    b:Check("Record sightings", "recordSightings", "Store where you were when you saw them (target, mouseover, nameplate, /say).")
    b:Check("Refresh details when seen", "refreshDetailsOnSight", "Update level, guild, title and so on each time you see them.")
    b:Slider("Sightings kept per player", "maxSightings", 5, 100, 5, "%d")

    -- Column 3: sync + map + window
    d:Header("Sync")
    d:Check("Enable sync", "syncEnabled", "Share entries and sightings with other Forever Blacklist users.")
    d:Check("Sync with guild", "syncGuild")
    d:Check("Sync with party / raid", "syncGroup")
    d:Check("Use a shared channel", "syncChannelEnabled", "Joins a hidden chat channel so friends across guilds can share.", function(v)
        if v then FBL.Comm.JoinChannel() else FBL.Comm.LeaveChannel() end
    end)
    local chan = W.EditBox(c, d.width - 20, 22, "Channel name")
    chan:SetPoint("TOPLEFT", d.x + 28, d.y + 2)
    chan:SetText(FBL.opt.syncChannelName or "")
    chan:SetScript("OnEnterPressed", function(self)
        local v = self:GetText():gsub("[^%w]", "")
        if v ~= "" and v ~= FBL.opt.syncChannelName then
            FBL.Comm.LeaveChannel()
            FBL.opt.syncChannelName = v
            FBL.Comm.JoinChannel()
        end
        self:SetText(FBL.opt.syncChannelName)
        self:ClearFocus()
    end)
    W.Tooltip(chan, "Shared channel", "Everyone who should share a blacklist uses the same name. Press Enter to apply.")
    d:Space(26)
    d:Dropdown("Accept shared entries from", "acceptFrom", {
        { value = "ALL", label = "Everyone" },
        { value = "GUILD", label = "Guild, friends & trusted" },
        { value = "TRUSTED", label = "Trusted players only" },
    })
    d:Check("Review new entries in Inbox", "reviewIncoming", "New entries from others wait for your approval.")
    d:Check("Share my sightings", "shareSightings", "Let peers' maps show where you last saw someone.")
    d:Check("Share & accept removals", "shareDeletes", "Removals are only accepted from the original author or trusted players.")
    d:Header("World map")
    d:Check("Show last-known locations", "mapPins", nil, function() FBL.RefreshMapPins() end)
    d:Check("Show on continent maps", "mapShowOnContinent", nil, function() FBL.RefreshMapPins() end)
    d:Check("Show sighting trail", "mapShowTrail", "Faint dots for earlier sightings on the same map.", function() FBL.RefreshMapPins() end)
    d:Slider("Hide sightings older than", "mapPinMaxAgeDays", 1, 180, 1, "%d days", function() FBL.RefreshMapPins() end)
    d:Slider("Pin size", "mapPinScale", 0.6, 2.0, 0.1, "%.1fx", function() FBL.RefreshMapPins() end)
    d:Slider("Only show severity", "mapMinSeverity", 1, 5, 1, "%d+", function() FBL.RefreshMapPins() end)

    -- window/misc go under column 2
    b:Header("Window")
    b:Check("Show minimap button", "minimapShown", nil, function() FBL.UpdateMinimapButton() end)
    b:Check("Confirm before removing", "confirmDelete")
    b:Check("Lock window position", "windowLocked")
    b:Slider("Window scale", "windowScale", 0.7, 1.4, 0.05, "%.2f", function() FBL.ApplyWindowScale() end)

    c:SetHeight(math.max(-a.y, -b.y, -d.y) + 30)
end

function View.Refresh()
    for _, ctl in ipairs(controls) do
        if ctl.Refresh then ctl:Refresh() end
    end
end

-- Stub page in Esc > Options > AddOns that points to our own window.
FBL:On("DB_READY", function()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local p = CreateFrame("Frame")
    local logo = p:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(T.LOGO)
    logo:SetSize(48, 48)
    logo:SetPoint("TOPLEFT", 16, -16)
    local t = p:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    t:SetPoint("LEFT", logo, "RIGHT", 12, 0)
    t:SetText("|cffe0324bForever|r Blacklist")
    local info = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    info:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -16)
    info:SetJustifyH("LEFT")
    info:SetText("All settings live in the Forever Blacklist window.\n\n/fbl - open the window\n/fbl add [name] - add target or name\n/fbl help - all commands")
    local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    b:SetSize(200, 26)
    b:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -16)
    b:SetText("Open Forever Blacklist")
    b:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        FBL.ShowView("options")
    end)
    local cat = Settings.RegisterCanvasLayoutCategory(p, "Forever Blacklist")
    Settings.RegisterAddOnCategory(cat)
    FBL.settingsCategory = cat
end)
