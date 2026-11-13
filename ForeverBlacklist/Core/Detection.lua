-- Forever Blacklist: spotting blacklisted players, recording sightings, alerts
-- and the protection options (auto-decline, whisper filter, tooltips, menus).
local _, FBL = ...

local Now, Safe = FBL.Now, FBL.Safe
local D = {}
FBL.Detection = D

---------------------------------------------------------------------------
-- Alerts (cooldown per player)
---------------------------------------------------------------------------
local lastAlert = {}

function FBL.Alert(e, context, force)
    local o = FBL.opt
    if not o.alertsEnabled and not force then return end
    if (e.severity or 1) < (o.minAlertSeverity or 1) and not force then return end
    local inInstance = Safe(IsInInstance())
    if inInstance and not o.alertInInstances and not force then return end
    local now = Now()
    if not force and (lastAlert[e.key] or 0) > now - (o.alertCooldown or 5) * 60 then return end
    lastAlert[e.key] = now

    local cat = FBL.Category(e.category)
    if o.alertChat then
        local link = ("|Haddon:ForeverBlacklist:%s|h[%s]|h"):format(e.key, FBL.ShortName(e.name))
        local _, _, _, hex = FBL.ClassColor(e.classFile)
        FBL.Print("|c%s%s|r %s - |cff%s%s|r%s", hex or "ffffffff", link, context or "spotted",
            cat.color, cat.label, (e.comment and e.comment ~= "") and (": " .. e.comment:sub(1, 80)) or "")
    end
    if FBL.ShowToast then FBL.ShowToast(e, context) end
    if o.alertFlash and FBL.FlashScreen then FBL.FlashScreen(e.severity) end
    FBL.PlayAlertSound()
end

function FBL.PlayAlertSound(key)
    key = key or FBL.opt.alertSound
    for _, s in ipairs(FBL.SOUNDS) do
        if s.key == key and s.kit then
            local id = (SOUNDKIT and SOUNDKIT[s.kit]) or s.fallback
            if id then PlaySound(id, "Master") end
            return
        end
    end
end

---------------------------------------------------------------------------
-- Seeing someone
---------------------------------------------------------------------------
local lastSightingRecorded = {}

--- Called whenever we encounter a blacklisted player near us.
-- unit may be nil (e.g. /say from someone without a unit token).
function D.Spotted(e, unit, context, nearby, forceAlert)
    local now = Now()
    local changed = false
    if unit and FBL.opt.refreshDetailsOnSight then
        local info = FBL.ReadUnit(unit)
        if info and FBL.ApplyUnitInfo(e, info) then changed = true end
    end
    if nearby and FBL.opt.recordSightings and (lastSightingRecorded[e.key] or 0) < now - 60 then
        lastSightingRecorded[e.key] = now
        local loc = FBL.GetPlayerLocation()
        loc.t = now
        loc.by = FBL.playerName
        if FBL.AddSighting(e, loc) then
            e.seenCount = (e.seenCount or 0) + 1
            changed = true
        end
    end
    if changed then
        FBL:Fire("ENTRY_CHANGED", e, "seen")
        if nearby and FBL.Comm then FBL.Comm.BroadcastSighting(e) end
    end
    FBL.Alert(e, context, forceAlert)
end

local function checkUnit(unit, context)
    if not FBL.db or not unit then return end
    if not Safe(UnitIsPlayer(unit)) then return end
    local name, realm = FBL.UnitName(unit)
    name, realm = Safe(name), Safe(realm)
    if not name then return end
    local e = FBL.IsBlacklisted(name, realm)
    if e then D.Spotted(e, unit, context, true) end
    return e
end
D.CheckUnit = checkUnit

FBL:RegisterEvent("PLAYER_TARGET_CHANGED", function() checkUnit("target", "targeted") end)
FBL:RegisterEvent("UPDATE_MOUSEOVER_UNIT", function() checkUnit("mouseover", "nearby") end)
FBL:RegisterEvent("PLAYER_FOCUS_CHANGED", function() checkUnit("focus", "focused") end)

---------------------------------------------------------------------------
-- Nameplates: detection + optional marker
---------------------------------------------------------------------------
local markers, markerPool = {}, {}

local function getMarker()
    local m = table.remove(markerPool)
    if m then return m end
    m = CreateFrame("Frame", nil, UIParent)
    m:SetSize(26, 26)
    m.glow = m:CreateTexture(nil, "BACKGROUND")
    m.glow:SetPoint("CENTER")
    m.glow:SetSize(44, 44)
    m.glow:SetTexture("Interface\\Cooldown\\star4")
    m.glow:SetBlendMode("ADD")
    m.icon = m:CreateTexture(nil, "ARTWORK")
    m.icon:SetAllPoints()
    m.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
    local ag = m:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0.35); a:SetDuration(0.8)
    a:SetTarget(m.glow)
    m.anim = ag
    return m
end

local function attachMarker(unit, e)
    if not FBL.opt.nameplateMarker or not C_NamePlate then return end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end
    local m = markers[unit] or getMarker()
    markers[unit] = m
    local ok = pcall(function()
        m:SetParent(plate)
        m:ClearAllPoints()
        m:SetPoint("BOTTOM", plate, "TOP", 0, 2)
    end)
    if not ok then return end
    local c = FBL.SEVERITY_COLORS[e.severity or 1]
    m.glow:SetVertexColor(c[1], c[2], c[3])
    m:Show()
    m.anim:Play()
end

local function detachMarker(unit)
    local m = markers[unit]
    if not m then return end
    markers[unit] = nil
    m.anim:Stop()
    m:Hide()
    pcall(m.SetParent, m, UIParent)
    markerPool[#markerPool + 1] = m
end

FBL:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unit)
    local e = checkUnit(unit, "nearby")
    if e then attachMarker(unit, e) end
end)
FBL:RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, unit) detachMarker(unit) end)

function D.RefreshNameplates()
    for unit in pairs(markers) do detachMarker(unit) end
    if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        unit = Safe(unit)
        if unit then
            local name, realm = FBL.UnitName(unit)
            local e = FBL.IsBlacklisted(Safe(name), Safe(realm))
            if e then attachMarker(unit, e) end
        end
    end
end
FBL:On("ENTRY_CHANGED", function(_, how)
    if how ~= "seen" then D.RefreshNameplates() end
end)

---------------------------------------------------------------------------
-- Group members
---------------------------------------------------------------------------
local knownInGroup = {}

local function announce(e)
    if not FBL.opt.announceToGroup then return end
    local chan = (IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT") or (IsInRaid() and "RAID") or "PARTY"
    local cat = FBL.Category(e.category)
    local msg = ("[Forever Blacklist] %s is on my blacklist: %s"):format(FBL.ShortName(e.name), cat.label)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    pcall(send, msg, chan)
end

FBL:RegisterEvent("GROUP_ROSTER_UPDATE", function()
    if not FBL.db then return end
    local current = {}
    local n = GetNumGroupMembers()
    local prefix = IsInRaid() and "raid" or "party"
    local count = IsInRaid() and n or (n - 1)
    for i = 1, count do
        local unit = prefix .. i
        local name, realm = FBL.UnitName(unit)
        name, realm = Safe(name), Safe(realm)
        if name then
            local e = FBL.IsBlacklisted(name, realm)
            if e then
                current[e.key] = true
                if not knownInGroup[e.key] and FBL.opt.alertOnGroupJoin then
                    D.Spotted(e, unit, "is in your group!", Safe(UnitIsVisible(unit)), true)
                    announce(e)
                end
            end
        end
    end
    knownInGroup = current
end)

---------------------------------------------------------------------------
-- Chat: nearby speech counts as a sighting; tag/hide messages
---------------------------------------------------------------------------
local NEARBY_EVENTS = { CHAT_MSG_SAY = true, CHAT_MSG_YELL = true, CHAT_MSG_EMOTE = true, CHAT_MSG_TEXT_EMOTE = true }

for ev in pairs(NEARBY_EVENTS) do
    FBL:RegisterEvent(ev, function(_, _, sender)
        sender = Safe(sender)
        local e = sender and FBL.IsBlacklisted(sender)
        if e then D.Spotted(e, nil, "is nearby (chat)", true) end
    end)
end

FBL:RegisterEvent("CHAT_MSG_WHISPER", function(_, _, sender)
    sender = Safe(sender)
    local e = sender and FBL.IsBlacklisted(sender)
    if e and not FBL.opt.hideWhispers then FBL.Alert(e, "whispered you") end
end)

local TAG = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|t|cffe0324b[BL]|r "

local function chatFilter(_, event, msg, sender, ...)
    if not FBL.db then return false end
    msg, sender = Safe(msg), Safe(sender)
    if not msg or not sender then return false end
    local e = FBL.IsBlacklisted(sender)
    if not e then return false end
    if FBL.opt.hideWhispers and (event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER") then
        return true
    end
    if FBL.opt.chatTag ~= false then
        return false, TAG .. msg, sender, ...
    end
    return false
end

local CHAT_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER", "CHAT_MSG_CHANNEL", "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_GUILD",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_EMOTE",
}
local addFilter = _G.ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
if addFilter then
    for _, ev in ipairs(CHAT_EVENTS) do pcall(addFilter, ev, chatFilter) end
end

-- clickable [Name] links in our own chat output open the entry
local function onHyperlink(link)
    local key = type(link) == "string" and link:match("^addon:ForeverBlacklist:(.+)$")
    if key and FBL.OpenEntry then FBL.OpenEntry(key) return true end
end
if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("SetItemRef", function(_, link) onHyperlink(link) end, FBL)
else
    hooksecurefunc("SetItemRef", function(link) onHyperlink(link) end)
end

---------------------------------------------------------------------------
-- Protection: invites, trades, duels
---------------------------------------------------------------------------
FBL:RegisterEvent("PARTY_INVITE_REQUEST", function(_, name)
    name = Safe(name)
    local e = name and FBL.IsBlacklisted(name)
    if not e then return end
    if FBL.opt.autoDeclineInvites then
        DeclineGroup()
        StaticPopup_Hide("PARTY_INVITE")
        FBL.Print("Declined a group invite from blacklisted %s.", FBL.ColoredName(e))
    else
        FBL.Alert(e, "invited you to a group", true)
    end
end)

FBL:RegisterEvent("TRADE_SHOW", function()
    local name, realm = FBL.UnitName("NPC")
    local e = FBL.IsBlacklisted(Safe(name), Safe(realm))
    if not e then return end
    if FBL.opt.autoDeclineTrades then
        CancelTrade()
        FBL.Print("Cancelled a trade with blacklisted %s.", FBL.ColoredName(e))
    else
        FBL.Alert(e, "opened a trade with you - careful!", true)
    end
end)

FBL:RegisterEvent("DUEL_REQUESTED", function(_, name)
    name = Safe(name)
    local e = name and FBL.IsBlacklisted(name)
    if not e or not FBL.opt.autoDeclineDuels then return end
    CancelDuel()
    StaticPopup_Hide("DUEL_REQUESTED")
    FBL.Print("Declined a duel from blacklisted %s.", FBL.ColoredName(e))
end)

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
local function addTooltipLines(tooltip)
    if not FBL.db or not FBL.opt.tooltipInfo then return end
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    unit = ok and Safe(unit)
    if not unit or not Safe(UnitIsPlayer(unit)) then return end
    local name, realm = FBL.UnitName(unit)
    local e = FBL.IsBlacklisted(Safe(name), Safe(realm))
    if not e then return end
    local cat = FBL.Category(e.category)
    local sc = FBL.SEVERITY_COLORS[e.severity or 1]
    tooltip:AddLine(" ")
    tooltip:AddDoubleLine("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:14|t |cffe0324bBLACKLISTED|r",
        FBL.SEVERITY_LABELS[e.severity or 1], 1, 1, 1, sc[1], sc[2], sc[3])
    tooltip:AddLine(("|cff%s%s|r"):format(cat.color, cat.label))
    if e.comment and e.comment ~= "" then
        tooltip:AddLine('"' .. e.comment:sub(1, 120) .. (#e.comment > 120 and "..." or "") .. '"', 0.85, 0.85, 0.85, true)
    end
    local by = e.addedBy and FBL.ShortName(e.addedBy) or "?"
    tooltip:AddLine(("Added by %s, %s"):format(by, FBL.TimeAgo(e.addedAt)), 0.6, 0.6, 0.6)
    tooltip:Show()
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if tooltip == GameTooltip then addTooltipLines(tooltip) end
    end)
end

---------------------------------------------------------------------------
-- Right-click unit menus
---------------------------------------------------------------------------
local MENU_TAGS = {
    "MENU_UNIT_PLAYER", "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS",
    "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FRIEND", "MENU_UNIT_COMMUNITIES_GUILD_MEMBER",
    "MENU_UNIT_COMMUNITIES_MEMBER", "MENU_UNIT_GUILD", "MENU_UNIT_CHAT_ROSTER",
}

local function menuName(ctx)
    if not ctx then return end
    local name, realm = FBL.JoinName(ctx.name, ctx.server)
    if ctx.unit and (not name) then
        name, realm = FBL.UnitName(ctx.unit)
        name, realm = Safe(name), Safe(realm)
    end
    return name, realm
end

if Menu and Menu.ModifyMenu then
    for _, tag in ipairs(MENU_TAGS) do
        Menu.ModifyMenu(tag, function(_, root, ctx)
            local name, realm = menuName(ctx)
            if not name or not FBL.db then return end
            local full = FBL.NormalizeName(name, realm)
            if full == FBL.playerName then return end
            local e = FBL.IsBlacklisted(name, realm)
            root:CreateDivider()
            root:CreateTitle("|cffe0324bForever|r Blacklist")
            if e then
                root:CreateButton("Edit blacklist entry", function() FBL.OpenEntry(e.key) end)
                root:CreateButton("|cffff6060Remove from blacklist|r", function() FBL.ConfirmRemove(e.key) end)
            else
                root:CreateButton("Add to blacklist...", function()
                    FBL.ShowAddDialog({ name = name, realm = realm, unit = Safe(ctx.unit) })
                end)
            end
            if FBL.opt.syncEnabled then
                local trusted = FBL.IsTrusted(full)
                root:CreateButton(trusted and "Untrust for sync" or "Trust for sync", function()
                    FBL.SetTrusted(full, not trusted)
                    FBL.Print("%s %s.", FBL.ShortName(full), trusted and "is no longer trusted" or "is now trusted for sync")
                end)
                root:CreateButton("Sync blacklist with player", function() FBL.Comm.RequestFrom(full) end)
            end
        end)
    end
end
