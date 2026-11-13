-- Forever Blacklist: core namespace, saved variables, events and shared helpers.
local ADDON_NAME, FBL = ...
_G.ForeverBlacklist = FBL

FBL.name = ADDON_NAME
FBL.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "1.0.0"
FBL.PROTOCOL = 1

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
FBL.CATEGORIES = {
    { key = "NINJA",    label = "Ninja looter",     color = "ffb347", icon = "Interface\\Icons\\INV_Misc_Bag_10" },
    { key = "SCAM",     label = "Scammer",          color = "ffd700", icon = "Interface\\Icons\\INV_Misc_Coin_02" },
    { key = "GRIEF",    label = "Griefer / ganker", color = "e0324b", icon = "Interface\\Icons\\Ability_Warrior_Rampage" },
    { key = "TOXIC",    label = "Toxic / abusive",  color = "b266ff", icon = "Interface\\Icons\\Spell_Shadow_AuraOfDarkness" },
    { key = "QUITTER",  label = "Quits groups",     color = "66b3ff", icon = "Interface\\Icons\\Spell_Magic_PolymorphRabbit" },
    { key = "BOT",      label = "Bot / cheater",    color = "a0a0a0", icon = "Interface\\Icons\\INV_Gizmo_02" },
    { key = "SPAM",     label = "Spammer",          color = "7fd17f", icon = "Interface\\Icons\\INV_Letter_15" },
    { key = "OTHER",    label = "Other",            color = "cccccc", icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
}
FBL.CATEGORY_BY_KEY = {}
for i, c in ipairs(FBL.CATEGORIES) do
    c.index = i
    FBL.CATEGORY_BY_KEY[c.key] = c
end

FBL.SEVERITY_LABELS = { "Minor", "Caution", "Avoid", "Dangerous", "Never group" }
FBL.SEVERITY_COLORS = {
    { 0.60, 0.80, 0.40 },
    { 0.95, 0.85, 0.30 },
    { 1.00, 0.60, 0.20 },
    { 0.95, 0.30, 0.25 },
    { 0.85, 0.10, 0.45 },
}

FBL.SOUNDS = {
    { key = "RAID_WARNING", label = "Raid warning", kit = "RAID_WARNING", fallback = 8959 },
    { key = "READY_CHECK",  label = "Ready check",  kit = "READY_CHECK", fallback = 8960 },
    { key = "PVP_FLAG",     label = "PvP flag taken", kit = "PVP_THROUGH_QUEUE", fallback = 8458 },
    { key = "ALARM",        label = "Alarm clock",  kit = "ALARM_CLOCK_WARNING_3", fallback = 12889 },
    { key = "NONE",         label = "Silent" },
}

---------------------------------------------------------------------------
-- Defaults
---------------------------------------------------------------------------
FBL.DEFAULTS = {
    entries = {},
    inbox = {},
    trusted = {},
    peers = {},
    syncLog = {},
    lastSync = {},
    options = {
        -- alerts
        alertsEnabled = true,
        alertSound = "RAID_WARNING",
        alertFlash = true,
        alertChat = true,
        alertCooldown = 5,          -- minutes per player
        alertInInstances = true,
        alertOnGroupJoin = true,
        announceToGroup = false,
        minAlertSeverity = 1,
        -- protection
        autoDeclineInvites = true,
        autoDeclineTrades = false,
        autoDeclineDuels = true,
        hideWhispers = false,
        chatTag = true,
        tooltipInfo = true,
        nameplateMarker = true,
        -- tracking
        recordSightings = true,
        maxSightings = 25,
        refreshDetailsOnSight = true,
        -- sync
        syncEnabled = true,
        syncGuild = true,
        syncGroup = true,
        syncChannelEnabled = false,
        syncChannelName = "FBLSync",
        syncWhisperTrusted = true,
        acceptFrom = "ALL",         -- ALL | GUILD | TRUSTED
        reviewIncoming = true,
        shareSightings = true,
        shareDeletes = true,
        -- map
        mapPins = true,
        mapPinMaxAgeDays = 30,
        mapPinScale = 1.0,
        mapShowOnContinent = true,
        mapShowTrail = true,
        mapMinSeverity = 1,
        -- misc
        minimapShown = true,
        minimapAngle = 205,
        confirmDelete = true,
        windowScale = 1.0,
        windowLocked = false,
    },
    window = {},
}

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local issecret = _G.issecretvalue

--- Returns nil for Midnight-era "secret" values that addons may not read.
function FBL.Safe(v)
    if v ~= nil and issecret and issecret(v) then return nil end
    return v
end

function FBL.Print(msg, ...)
    if select("#", ...) > 0 then msg = msg:format(...) end
    DEFAULT_CHAT_FRAME:AddMessage("|cffe0324bForever|r|cffffffffBlacklist|r: " .. tostring(msg))
end

function FBL.Now()
    return (GetServerTime and GetServerTime()) or time()
end

function FBL.CopyDefaults(src, dst)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = FBL.CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

function FBL.PlayerRealm()
    local r = GetNormalizedRealmName and GetNormalizedRealmName()
    if not r or r == "" then r = (GetRealmName() or ""):gsub("[%s%-]", "") end
    return r
end

--- Normalises "name", "name-realm" or (name, realm) into "Name-Realm" plus a lowercase key.
function FBL.NormalizeName(name, realm)
    name = FBL.Safe(name)
    if not name or name == "" then return nil end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    local n, r = name:match("^([^%-]+)%-(.+)$")
    if n then
        name = n
        if not realm or realm == "" then realm = r end
    end
    if not realm or realm == "" then realm = FBL.PlayerRealm() end
    realm = realm:gsub("[%s%-']", "")
    -- capitalise first letter, keep UTF-8 tail untouched
    -- WoW Forever names are "First Last": capitalise each part, collapse extra spaces
    name = name:gsub("%s+", " ")
    name = name:gsub("[^ ]+", function(word)
        local first, rest = word:match("^([\1-\127\194-\244][\128-\191]*)(.*)$")
        if first then return first:upper() .. rest:lower() end
        return word
    end)
    local full = name .. "-" .. realm
    return full, full:lower(), name, realm
end

function FBL.ShortName(full)
    if not full then return "?" end
    local n, r = full:match("^([^%-]+)%-(.+)$")
    if n and r == FBL.PlayerRealm() then return n end
    return full
end

function FBL.TimeAgo(t)
    if not t then return "never" end
    local d = FBL.Now() - t
    if d < 60 then return "just now" end
    if d < 3600 then return ("%dm ago"):format(math.floor(d / 60)) end
    if d < 86400 then return ("%dh ago"):format(math.floor(d / 3600)) end
    if d < 86400 * 60 then return ("%dd ago"):format(math.floor(d / 86400)) end
    return date("%b %d, %Y", t)
end

function FBL.ClassColor(classFile)
    if classFile then
        local c = (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(classFile))
            or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile])
        if c then return c.r, c.g, c.b, (c.GenerateHexColor and c:GenerateHexColor()) or c.colorStr end
    end
    return 0.8, 0.8, 0.8, "ffcccccc"
end

function FBL.ColoredName(entry)
    local _, _, _, hex = FBL.ClassColor(entry and entry.classFile)
    return ("|c%s%s|r"):format(hex or "ffcccccc", FBL.ShortName(entry and entry.name))
end

function FBL.Category(key)
    return FBL.CATEGORY_BY_KEY[key or "OTHER"] or FBL.CATEGORY_BY_KEY.OTHER
end

---------------------------------------------------------------------------
-- Event dispatcher + simple callback bus for UI refreshes
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}
FBL.eventFrame = eventFrame

function FBL:RegisterEvent(event, fn)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], fn)
    eventFrame:RegisterEvent(event)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], event, ...)
        if not ok then geterrorhandler()(err) end
    end
end)

local callbacks = {}
function FBL:On(name, fn)
    callbacks[name] = callbacks[name] or {}
    table.insert(callbacks[name], fn)
end

function FBL:Fire(name, ...)
    local list = callbacks[name]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then geterrorhandler()(err) end
    end
end

---------------------------------------------------------------------------
-- Load
---------------------------------------------------------------------------
FBL:RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= ADDON_NAME then return end
    ForeverBlacklistDB = FBL.CopyDefaults(FBL.DEFAULTS, ForeverBlacklistDB)
    ForeverBlacklistCharDB = ForeverBlacklistCharDB or {}
    FBL.db = ForeverBlacklistDB
    FBL.opt = ForeverBlacklistDB.options
    FBL.char = ForeverBlacklistCharDB
    FBL:Fire("DB_READY")
end)

FBL:RegisterEvent("PLAYER_LOGIN", function()
    FBL.playerName = FBL.NormalizeName(UnitName("player"))
    FBL:Fire("LOGIN")
    local count = FBL.CountEntries and FBL.CountEntries() or 0
    FBL.Print("v%s loaded - %d blacklisted. Type |cffffd100/fbl|r to open.", FBL.version, count)
end)
