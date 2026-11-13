-- Forever Blacklist: "Sync" tab - peers, trust list and activity log.
local _, FBL = ...

local T, W = FBL.Theme, FBL.Widgets
local View = {}
FBL.Views.sync = View

local function createPeerRow(row)
    row:SetHeight(34)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetTexture(T.WHITE)
    row.bg:SetAllPoints()
    row.bg:SetVertexColor(1, 1, 1, 0.03)
    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetTexture(T.WHITE)
    row.dot:SetSize(8, 8)
    row.dot:SetPoint("LEFT", 10, 0)
    row.name = W.Text(row, "GameFontHighlight", "")
    row.name:SetPoint("LEFT", row.dot, "RIGHT", 8, 6)
    row.meta = W.Text(row, "GameFontDisableSmall", "")
    row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.trust = W.Button(row, "Trust", 64, 20)
    row.trust:SetPoint("RIGHT", -76, 0)
    row.sync = W.Button(row, "Sync", 60, 20)
    row.sync:SetPoint("RIGHT", -8, 0)
end

local function initPeerRow(row, p)
    local trusted = FBL.IsTrusted(p.name)
    local badge = ""
    if trusted and p.trustsMe then badge = "  |cff40ff40mutual trust - auto-sync|r"
    elseif trusted then badge = "  |cffffd100trusted (waiting for them to trust you)|r"
    elseif p.trustsMe then badge = "  |cff40c0fftrusts you|r" end
    local live = select(2, FBL.NormalizeName(p.name or ""))
    live = live and FBL.Comm.online[live]
    row.dot:SetVertexColor(live and 0.3 or 0.4, live and 0.9 or 0.4, live and 0.4 or 0.4)
    row.name:SetText(FBL.ShortName(p.name) .. badge .. (p.guildmate and "  |cff40c0ffguild|r" or ""))
    row.meta:SetText(("v%s  -  %s entries  -  seen %s via %s"):format(p.version or "?", p.count or "?",
        FBL.TimeAgo(p.lastSeen), (p.via or "?"):lower()))
    row.trust.text:SetText(trusted and "Untrust" or "Trust")
    row.trust:SetScript("OnClick", function() FBL.SetTrusted(p.name, not trusted) end)
    row.sync:SetScript("OnClick", function() FBL.Comm.RequestFrom(p.name, 0) end)
end

local function createLogRow(row)
    row:SetHeight(18)
    row.time = W.Text(row, "GameFontDisableSmall", "")
    row.time:SetPoint("LEFT", 6, 0)
    row.time:SetWidth(52)
    row.text = W.Text(row, "GameFontHighlightSmall", "")
    row.text:SetPoint("LEFT", row.time, "RIGHT", 4, 0)
    row.text:SetPoint("RIGHT", -4, 0)
    row.text:SetWordWrap(false)
end

local function initLogRow(row, l)
    row.time:SetText(date("%H:%M", l.t))
    row.text:SetText(l.text)
end

function View.Create(f)
    -- status card
    local card = W.Panel(f, { 0.075, 0.075, 0.09, 0.95 })
    card:SetPoint("TOPLEFT")
    card:SetPoint("TOPRIGHT")
    card:SetHeight(92)
    local title = W.Text(card, "GameFontNormalLarge", "Sync network")
    title:SetPoint("TOPLEFT", 14, -12)
    f.status = W.Text(card, "GameFontHighlightSmall", "")
    f.status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    f.status:SetPoint("RIGHT", -360, 0)
    f.stats = W.Text(card, "GameFontDisableSmall", "")
    f.stats:SetPoint("TOPLEFT", f.status, "BOTTOMLEFT", 0, -6)

    local now = W.Button(card, "Sync Now", 100, 24, "accent")
    now:SetPoint("TOPRIGHT", -12, -14)
    now:SetScript("OnClick", function()
        FBL.Comm.JoinChannel()
        FBL.Comm.SendHello(true)
        FBL.Comm.Log("Announced to sync network")
    end)
    W.Tooltip(now, "Sync now", "Say hello on every enabled channel. Peers with newer data will be asked for it.")
    local tgt = W.Button(card, "Sync with Target", 130, 24)
    tgt:SetPoint("RIGHT", now, "LEFT", -6, 0)
    tgt:SetScript("OnClick", function()
        local name, realm = FBL.UnitName("target")
        name, realm = FBL.Safe(name), FBL.Safe(realm)
        if name and UnitIsPlayer("target") then
            FBL.Comm.RequestFrom(FBL.NormalizeName(name, realm), 0)
        else
            FBL.Print("Target a player who uses Forever Blacklist first.")
        end
    end)
    local trustT = W.Button(card, "Trust Target", 110, 24)
    trustT:SetPoint("TOPRIGHT", now, "BOTTOMRIGHT", 0, -6)
    trustT:SetScript("OnClick", function()
        local name, realm = FBL.UnitName("target")
        name, realm = FBL.Safe(name), FBL.Safe(realm)
        if name and UnitIsPlayer("target") then
            FBL.SetTrusted(FBL.NormalizeName(name, realm), true)
            FBL.Print("%s is now trusted.", name)
        end
    end)
    local add = W.EditBox(card, 130, 24, "Trust by name...")
    add:SetPoint("RIGHT", trustT, "LEFT", -6, 0)
    add:SetScript("OnEnterPressed", function(self)
        local t = self:GetText()
        if t ~= "" then FBL.SetTrusted(t, true); self:SetText("") end
        self:ClearFocus()
    end)

    -- peers
    local peers = W.Panel(f, { 0.075, 0.075, 0.09, 0.95 })
    peers:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -10)
    peers:SetPoint("BOTTOMLEFT")
    peers:SetWidth(470)
    local ph = W.Header(peers, "Peers & trusted players")
    ph:SetPoint("TOPLEFT", 12, -10)
    f.peers = W.List(peers, 34, initPeerRow, createPeerRow)
    f.peers:SetPoint("TOPLEFT", 8, -30)
    f.peers:SetPoint("BOTTOMRIGHT", -22, 8)
    f.noPeers = W.Text(peers, "GameFontDisable", "No other Forever Blacklist users seen yet.\nGuildmates and group members are found automatically.")
    f.noPeers:SetJustifyH("CENTER")
    f.noPeers:SetPoint("CENTER")

    -- log
    local log = W.Panel(f, { 0.075, 0.075, 0.09, 0.95 })
    log:SetPoint("TOPLEFT", peers, "TOPRIGHT", 10, 0)
    log:SetPoint("BOTTOMRIGHT")
    local lh = W.Header(log, "Activity")
    lh:SetPoint("TOPLEFT", 12, -10)
    f.log = W.List(log, 18, initLogRow, createLogRow)
    f.log:SetPoint("TOPLEFT", 8, -30)
    f.log:SetPoint("BOTTOMRIGHT", -22, 8)
end

function View.Refresh(f)
    local o = FBL.opt
    local on = {}
    if o.syncGuild then on[#on + 1] = IsInGuild() and "guild" or "|cff777777guild (none)|r" end
    if o.syncGroup then on[#on + 1] = "party/raid" end
    if o.syncChannelEnabled then
        local id = FBL.Comm.ChannelId()
        on[#on + 1] = ("channel |cffffd100%s|r%s"):format(o.syncChannelName, id and "" or " |cffff6060(not joined)|r")
    end
    if not o.syncEnabled then
        f.status:SetText("|cffff6060Sync is turned off.|r Enable it under Options to share your blacklist.")
    else
        local accept = (o.acceptFrom == "ALL" and "everyone") or (o.acceptFrom == "GUILD" and "guild, friends & trusted") or "trusted players only"
        f.status:SetText(("Sharing over %s.  Accepting from %s%s."):format(
            #on > 0 and table.concat(on, ", ") or "|cffff6060nothing|r", accept,
            o.reviewIncoming and ", new entries go to your Inbox" or ""))
    end
    local s = FBL.Comm.stats
    f.stats:SetText(("This session: %d messages sent (%.1f KB), %d received (%.1f KB)"):format(
        s.sent, s.bytesOut / 1024, s.received, s.bytesIn / 1024))

    -- peers: everyone seen plus trusted players never seen
    local list, seen = {}, {}
    for k, p in pairs(FBL.db.peers) do list[#list + 1] = p; seen[k] = true end
    for k, name in pairs(FBL.db.trusted) do
        if not seen[k] then list[#list + 1] = { name = name } end
    end
    local mutual = 0
    for k in pairs(FBL.db.trusted) do
        local p = FBL.db.peers[k]
        if p and p.trustsMe then mutual = mutual + 1 end
    end
    f.stats:SetText(f.stats:GetText() .. ("   |   %d mutual trust%s"):format(mutual, mutual == 1 and "" or "s"))
    table.sort(list, function(a, b) return (a.lastSeen or 0) > (b.lastSeen or 0) end)
    f.peers:SetItems(list)
    f.noPeers:SetShown(#list == 0)
    f.log:SetItems(FBL.db.syncLog)
end
