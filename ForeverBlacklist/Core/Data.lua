-- Forever Blacklist: the data model, merge rules and sightings.
local _, FBL = ...

local Now, Safe = FBL.Now, FBL.Safe

-- Fields describing *who* the character is. Refreshed whenever we see them and
-- merged by `infoAt` so a fresher sighting from a peer can update them.
FBL.INFO_FIELDS = {
    "guid", "race", "raceFile", "class", "classFile", "level", "faction", "sex",
    "guild", "guildRank", "title", "pvpRank",
}
-- Fields describing *why* they're listed. Merged last-writer-wins by `updatedAt`.
FBL.CORE_FIELDS = { "category", "severity", "comment", "tags", "alts", "deleted", "updatedBy" }

-- Short keys keep addon messages small.
local WIRE = {
    name = "n", guid = "g", race = "r", raceFile = "rf", class = "c", classFile = "cf",
    level = "l", faction = "f", sex = "x", guild = "gu", guildRank = "gr", title = "ti", pvpRank = "pr",
    category = "ca", severity = "sv", comment = "co", tags = "tg", alts = "al", deleted = "d",
    addedBy = "ab", addedAt = "aa", updatedAt = "ua", updatedBy = "ub", infoAt = "ia",
    firstSeen = "fs", seenCount = "sc",
}
local UNWIRE = {}
for k, v in pairs(WIRE) do UNWIRE[v] = k end

---------------------------------------------------------------------------
-- Lookup
---------------------------------------------------------------------------
function FBL.GetEntry(nameOrKey, realm)
    if not nameOrKey or not FBL.db then return nil end
    local _, key = FBL.NormalizeName(nameOrKey, realm)
    return key and FBL.db.entries[key]
end

--- Returns the entry only if it is an active (not deleted) blacklist record.
function FBL.IsBlacklisted(name, realm)
    local e = FBL.GetEntry(name, realm)
    if e and not e.deleted then return e end
end

function FBL.CountEntries()
    local n = 0
    if FBL.db then
        for _, e in pairs(FBL.db.entries) do
            if not e.deleted then n = n + 1 end
        end
    end
    return n
end

local SORTERS = {
    name = function(a, b) return (a.name or "") < (b.name or "") end,
    recent = function(a, b) return (a.updatedAt or 0) > (b.updatedAt or 0) end,
    seen = function(a, b)
        local sa, sb = a.sightings and a.sightings[1], b.sightings and b.sightings[1]
        return (sa and sa.t or 0) > (sb and sb.t or 0)
    end,
    severity = function(a, b)
        if (a.severity or 1) == (b.severity or 1) then return (a.name or "") < (b.name or "") end
        return (a.severity or 1) > (b.severity or 1)
    end,
    level = function(a, b) return (tonumber(a.level) or 0) > (tonumber(b.level) or 0) end,
}

--- Returns a sorted, filtered array of active entries.
function FBL.QueryEntries(search, sortKey, filter)
    local list = {}
    search = search and search:lower() or ""
    for _, e in pairs(FBL.db.entries) do
        if not e.deleted then
            local ok = true
            if search ~= "" then
                local hay = table.concat({
                    e.name or "", e.guild or "", e.comment or "", e.tags or "", e.race or "",
                    e.class or "", e.alts or "", FBL.Category(e.category).label,
                }, " "):lower()
                ok = hay:find(search, 1, true) ~= nil
            end
            if ok and filter then
                if filter.category and filter.category ~= e.category then ok = false end
                if filter.faction and filter.faction ~= e.faction then ok = false end
                if filter.minSeverity and (e.severity or 1) < filter.minSeverity then ok = false end
            end
            if ok then list[#list + 1] = e end
        end
    end
    table.sort(list, SORTERS[sortKey or "name"] or SORTERS.name)
    return list
end

---------------------------------------------------------------------------
-- Local edits
---------------------------------------------------------------------------
--- Creates or updates an entry from local input and broadcasts it.
-- fields: name (required), realm, category, severity, comment, tags, alts + any info field.
function FBL.SaveEntry(fields, silent)
    local full, key = FBL.NormalizeName(fields.name, fields.realm)
    if not key then return nil, "Invalid name" end
    local now = Now()
    local e = FBL.db.entries[key]
    local isNew = not e or e.deleted
    if not e then
        e = { key = key, name = full, addedBy = FBL.playerName, addedAt = now, sightings = {}, seenCount = 0 }
        FBL.db.entries[key] = e
    end
    if isNew and e.deleted then
        e.addedBy, e.addedAt = FBL.playerName, now
    end
    e.deleted = nil
    e.category = fields.category or e.category or "OTHER"
    e.severity = math.max(1, math.min(5, tonumber(fields.severity or e.severity or 2) or 2))
    if fields.comment ~= nil then e.comment = fields.comment end
    if fields.tags ~= nil then e.tags = fields.tags end
    if fields.alts ~= nil then e.alts = fields.alts end
    local infoChanged
    for _, f in ipairs(FBL.INFO_FIELDS) do
        if fields[f] ~= nil and fields[f] ~= "" then e[f] = fields[f]; infoChanged = true end
    end
    if infoChanged then e.infoAt = now end
    e.updatedAt, e.updatedBy = now, FBL.playerName
    FBL.db.rejected = FBL.db.rejected or {}
    FBL.db.rejected[key] = nil

    FBL:Fire("ENTRY_CHANGED", e, isNew and "added" or "updated")
    if not silent and FBL.Comm then FBL.Comm.BroadcastEntry(e) end
    return e, isNew
end

function FBL.RemoveEntry(key)
    local e = FBL.db.entries[key]
    if not e or e.deleted then return end
    e.deleted = true
    e.updatedAt, e.updatedBy = Now(), FBL.playerName
    FBL:Fire("ENTRY_CHANGED", e, "removed")
    if FBL.Comm and FBL.opt.shareDeletes then FBL.Comm.BroadcastEntry(e) end
end

---------------------------------------------------------------------------
-- Unit inspection
---------------------------------------------------------------------------
--- Reads everything we can learn about a player unit. Secret values are skipped.
function FBL.ReadUnit(unit)
    if not unit or not Safe(UnitExists(unit)) or not Safe(UnitIsPlayer(unit)) then return nil end
    local name, realm = UnitName(unit)
    name, realm = Safe(name), Safe(realm)
    if not name or name == "" or name == UNKNOWNOBJECT then return nil end
    local info = { name = name, realm = realm }
    info.guid = Safe(UnitGUID(unit))
    local race, raceFile = UnitRace(unit)
    info.race, info.raceFile = Safe(race), Safe(raceFile)
    local class, classFile = UnitClass(unit)
    info.class, info.classFile = Safe(class), Safe(classFile)
    local level = Safe(UnitLevel(unit))
    if level then info.level = (level > 0) and level or "??" end
    local faction = Safe(UnitFactionGroup(unit))
    info.faction = faction
    local sex = Safe(UnitSex(unit))
    info.sex = (sex == 2 and "Male") or (sex == 3 and "Female") or nil
    local gName, gRank = GetGuildInfo(unit)
    info.guild, info.guildRank = Safe(gName), Safe(gRank)
    local pvpName = UnitPVPName and Safe(UnitPVPName(unit))
    if pvpName and pvpName ~= name then info.title = pvpName end
    if UnitPVPRank then
        local rank = Safe(UnitPVPRank(unit))
        if rank and rank > 0 and GetPVPRankInfo then
            local rankName = Safe(GetPVPRankInfo(rank, unit))
            info.pvpRank = rankName
        end
    end
    return info
end

--- Copies freshly read unit info into an entry. Returns true if anything changed.
function FBL.ApplyUnitInfo(e, info)
    local changed
    for _, f in ipairs(FBL.INFO_FIELDS) do
        local v = info[f]
        if v ~= nil and v ~= "" and e[f] ~= v then
            -- don't downgrade a known level to "??"
            if not (f == "level" and v == "??" and tonumber(e.level)) then
                e[f] = v
                changed = true
            end
        end
    end
    if changed then e.infoAt = Now() end
    return changed
end

---------------------------------------------------------------------------
-- Sightings
---------------------------------------------------------------------------
--- Our own position, used as the approximate location of whoever we just saw.
function FBL.GetPlayerLocation()
    local loc = {
        zone = Safe(GetRealZoneText()) or "",
        sub = Safe(GetSubZoneText()) or "",
    }
    local mapID = C_Map.GetBestMapForUnit("player")
    mapID = Safe(mapID)
    if mapID then
        loc.mapID = mapID
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        if pos then
            local x, y = pos:GetXY()
            x, y = Safe(x), Safe(y)
            if x and y and (x > 0 or y > 0) then
                loc.x = math.floor(x * 10000 + 0.5) / 10000
                loc.y = math.floor(y * 10000 + 0.5) / 10000
            end
        end
    end
    local inInstance, instType = IsInInstance()
    if Safe(inInstance) then loc.instance = Safe(instType) end
    return loc
end

local function sightingKey(s)
    return (s.by or "?") .. ":" .. math.floor((s.t or 0) / 60)
end

--- Inserts a sighting (newest first), de-duplicating and trimming. Returns true if added.
function FBL.AddSighting(e, s)
    e.sightings = e.sightings or {}
    local k = sightingKey(s)
    for _, old in ipairs(e.sightings) do
        if sightingKey(old) == k then return false end
    end
    table.insert(e.sightings, s)
    table.sort(e.sightings, function(a, b) return (a.t or 0) > (b.t or 0) end)
    local max = (FBL.opt and FBL.opt.maxSightings) or 25
    while #e.sightings > max do table.remove(e.sightings) end
    if not e.firstSeen or (s.t and s.t < e.firstSeen) then e.firstSeen = s.t end
    return true
end

function FBL.LastSighting(e)
    return e and e.sightings and e.sightings[1]
end

---------------------------------------------------------------------------
-- Wire format
---------------------------------------------------------------------------
function FBL.ToWire(e, maxSightings)
    local w = {}
    for long, short in pairs(WIRE) do
        local v = e[long]
        if v ~= nil and v ~= "" then w[short] = v end
    end
    if maxSightings and maxSightings > 0 and e.sightings then
        local s = {}
        for i = 1, math.min(maxSightings, #e.sightings) do
            local o = e.sightings[i]
            s[i] = { o.t, o.mapID or 0, o.x or 0, o.y or 0, o.zone or "", o.sub or "", o.by or "" }
        end
        w.s = s
    end
    return w
end

function FBL.SightingFromWire(a)
    if type(a) ~= "table" then return nil end
    local s = { t = tonumber(a[1]), mapID = tonumber(a[2]), x = tonumber(a[3]), y = tonumber(a[4]),
        zone = a[5], sub = a[6], by = a[7] }
    if not s.t then return nil end
    if s.mapID == 0 then s.mapID = nil end
    if s.x == 0 and s.y == 0 then s.x, s.y = nil, nil end
    if s.zone == "" then s.zone = nil end
    if s.sub == "" then s.sub = nil end
    return s
end

function FBL.FromWire(w)
    if type(w) ~= "table" or type(w.n) ~= "string" then return nil end
    local e = {}
    for short, long in pairs(UNWIRE) do
        if w[short] ~= nil then e[long] = w[short] end
    end
    local full, key = FBL.NormalizeName(e.name)
    if not key then return nil end
    e.name, e.key = full, key
    e.updatedAt = tonumber(e.updatedAt) or 0
    e.infoAt = tonumber(e.infoAt)
    e.severity = tonumber(e.severity)
    e.sightings = {}
    if type(w.s) == "table" then
        for _, a in ipairs(w.s) do
            local s = FBL.SightingFromWire(a)
            if s then e.sightings[#e.sightings + 1] = s end
        end
    end
    -- clamp untrusted text
    if type(e.comment) == "string" and #e.comment > 1000 then e.comment = e.comment:sub(1, 1000) end
    if type(e.tags) == "string" and #e.tags > 200 then e.tags = e.tags:sub(1, 200) end
    if type(e.alts) == "string" and #e.alts > 200 then e.alts = e.alts:sub(1, 200) end
    if e.category and not FBL.CATEGORY_BY_KEY[e.category] then e.category = "OTHER" end
    return e
end

---------------------------------------------------------------------------
-- Merging remote data
---------------------------------------------------------------------------
local function copyFields(dst, src, fields)
    for _, f in ipairs(fields) do dst[f] = src[f] end
end

--- Merges a remote entry into the database.
-- Returns one of: "added", "updated", "removed", "sightings", "inbox", "ignored".
function FBL.MergeRemote(remote, sender, force)
    local db = FBL.db
    local key = remote.key
    local e = db.entries[key]
    db.rejected = db.rejected or {}

    if not e or (e.deleted and not remote.deleted and (remote.updatedAt or 0) > (e.updatedAt or 0)) then
        if remote.deleted then
            if not e then
                -- remember the tombstone so an old copy elsewhere can't resurrect it
                remote.sightings = {}
                db.entries[key] = remote
            end
            return "ignored"
        end
        if not force then
            local rej = db.rejected[key]
            if rej and rej >= (remote.updatedAt or 0) then return "ignored" end
            if FBL.opt.reviewIncoming then
                FBL.AddToInbox(remote, sender)
                return "inbox"
            end
        end
        remote.addedBy = remote.addedBy or sender
        remote.addedAt = remote.addedAt or remote.updatedAt
        remote.source = sender
        db.entries[key] = remote
        FBL:Fire("ENTRY_CHANGED", remote, "added")
        return "added"
    end

    local result = "ignored"
    -- why they're listed
    if (remote.updatedAt or 0) > (e.updatedAt or 0) then
        if remote.deleted and not e.deleted then
            local senderIsOwner = sender and e.addedBy and sender:lower() == e.addedBy:lower()
            if force or (FBL.opt.shareDeletes and (senderIsOwner or FBL.IsTrusted(sender))) then
                copyFields(e, remote, FBL.CORE_FIELDS)
                e.updatedAt = remote.updatedAt
                result = "removed"
            end
        elseif not remote.deleted then
            copyFields(e, remote, FBL.CORE_FIELDS)
            e.updatedAt = remote.updatedAt
            result = "updated"
        end
    end
    -- who they are
    if remote.infoAt and remote.infoAt > (e.infoAt or 0) then
        for _, f in ipairs(FBL.INFO_FIELDS) do
            if remote[f] ~= nil then e[f] = remote[f] end
        end
        e.infoAt = remote.infoAt
        if result == "ignored" then result = "updated" end
    end
    -- where they were
    local addedSighting
    for _, s in ipairs(remote.sightings or {}) do
        if FBL.AddSighting(e, s) then addedSighting = true end
    end
    if addedSighting and result == "ignored" then result = "sightings" end
    if (remote.addedAt or math.huge) < (e.addedAt or math.huge) then
        e.addedAt, e.addedBy = remote.addedAt, remote.addedBy or e.addedBy
    end

    if result ~= "ignored" then FBL:Fire("ENTRY_CHANGED", e, result) end
    return result
end

---------------------------------------------------------------------------
-- Inbox (incoming entries awaiting review)
---------------------------------------------------------------------------
function FBL.AddToInbox(remote, sender)
    local inbox = FBL.db.inbox
    for i, item in ipairs(inbox) do
        if item.entry.key == remote.key then
            if (remote.updatedAt or 0) >= (item.entry.updatedAt or 0) then
                inbox[i] = { entry = remote, from = sender, receivedAt = Now() }
                FBL:Fire("INBOX_CHANGED")
            end
            return
        end
    end
    table.insert(inbox, 1, { entry = remote, from = sender, receivedAt = Now() })
    while #inbox > 200 do table.remove(inbox) end
    FBL:Fire("INBOX_CHANGED")
end

function FBL.AcceptInbox(index)
    local item = table.remove(FBL.db.inbox, index)
    if not item then return end
    FBL.MergeRemote(item.entry, item.from, true)
    FBL:Fire("INBOX_CHANGED")
end

function FBL.RejectInbox(index)
    local item = table.remove(FBL.db.inbox, index)
    if not item then return end
    FBL.db.rejected = FBL.db.rejected or {}
    FBL.db.rejected[item.entry.key] = item.entry.updatedAt or Now()
    FBL:Fire("INBOX_CHANGED")
end

function FBL.AcceptAllInbox()
    while #FBL.db.inbox > 0 do FBL.AcceptInbox(1) end
end

---------------------------------------------------------------------------
-- Trust
---------------------------------------------------------------------------
function FBL.IsTrusted(sender)
    if not sender then return false end
    local _, key = FBL.NormalizeName(sender)
    return key and FBL.db.trusted[key] ~= nil
end

function FBL.SetTrusted(name, trusted)
    local full, key = FBL.NormalizeName(name)
    if not key then return end
    FBL.db.trusted[key] = trusted and full or nil
    FBL:Fire("TRUST_CHANGED")
end

local function isFriend(sender)
    if not C_FriendList or not C_FriendList.IsFriend then return false end
    local short = FBL.ShortName(sender)
    local ok, res = pcall(C_FriendList.IsFriend, short)
    return ok and res
end

--- Whether data from this sender on this channel should be accepted at all.
function FBL.AcceptsFrom(sender, channel)
    local mode = FBL.opt.acceptFrom
    if mode == "ALL" then return true end
    if FBL.IsTrusted(sender) then return true end
    if mode == "GUILD" then
        return channel == "GUILD" or isFriend(sender)
    end
    return false
end

---------------------------------------------------------------------------
-- Import / export
---------------------------------------------------------------------------
function FBL.ExportString(keys)
    local list = {}
    for key, e in pairs(FBL.db.entries) do
        if not e.deleted and (not keys or keys[key]) then
            list[#list + 1] = FBL.ToWire(e, 5)
        end
    end
    return FBL.Serializer.Export({ v = FBL.PROTOCOL, e = list }), #list
end

function FBL.ImportString(str)
    local data, err = FBL.Serializer.Import(str)
    if type(data) ~= "table" or type(data.e) ~= "table" then
        return nil, err or "Invalid data"
    end
    local counts = { added = 0, updated = 0, other = 0 }
    for _, w in ipairs(data.e) do
        local remote = FBL.FromWire(w)
        if remote then
            local r = FBL.MergeRemote(remote, "Import", true)
            if counts[r] then counts[r] = counts[r] + 1 else counts.other = counts.other + 1 end
        end
    end
    return counts
end

---------------------------------------------------------------------------
-- Migration: v1.0.0 lowercased the second word of "First Last" names.
---------------------------------------------------------------------------
FBL:On("DB_READY", function()
    local db = FBL.db
    local function fix(name) return (name and FBL.NormalizeName(name)) or name end
    for _, e in pairs(db.entries) do
        e.name = fix(e.name)
        e.addedBy, e.updatedBy, e.source = fix(e.addedBy), fix(e.updatedBy), e.source ~= "Import" and fix(e.source) or e.source
    end
    for _, p in pairs(db.peers) do p.name = fix(p.name) end
    for k, n in pairs(db.trusted) do db.trusted[k] = fix(n) end
    for _, item in ipairs(db.inbox) do item.entry.name = fix(item.entry.name) end
end)
