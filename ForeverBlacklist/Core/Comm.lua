-- Forever Blacklist: addon-to-addon sync.
--
-- Every logical message is a packed table prefixed by a one-letter type:
--   H  hello      {v, ver, c = count, m = data stamp, r = wants reply}
--   Q  request    {rid, since}             -> peer answers with A batches over WHISPER
--   A  answer     {rid, e = {wire...}, done}
--   E  entry      wire entry (local add / edit / delete)
--   S  sighting   partial wire entry (info + 1 sighting) for an entry peers already have
--
-- Messages are split into <=255 byte chunks: "<id>\t<seq>\t<total>\t<data>".
local _, FBL = ...

local Comm = {}
FBL.Comm = Comm

local PREFIX = "FBLv1"
local CHUNK = 230
local Now, Safe = FBL.Now, FBL.Safe
local S -- serializer, set on load

---------------------------------------------------------------------------
-- Log (shown on the Sync tab)
---------------------------------------------------------------------------
function Comm.Log(fmt, ...)
    local text = select("#", ...) > 0 and fmt:format(...) or fmt
    local log = FBL.db.syncLog
    table.insert(log, 1, { t = Now(), text = text })
    while #log > 60 do table.remove(log) end
    FBL:Fire("SYNC_LOG")
end

---------------------------------------------------------------------------
-- Outgoing queue with a token bucket (the server throttles per prefix)
---------------------------------------------------------------------------
local queues = { high = {}, bulk = {} }
local tokens, MAX_TOKENS, REGEN = 8, 8, 1.0  -- REGEN tokens per second
local ticker
local stats = { sent = 0, received = 0, bytesOut = 0, bytesIn = 0 }
Comm.stats = stats

local function sendRaw(item)
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, item.msg, item.dist, item.target)
    if not ok then return false end
    -- Mainline returns an Enum.SendAddonMessageResult (0 = success); older clients a boolean
    if result == nil or result == true or result == 0 then
        stats.sent = stats.sent + 1
        stats.bytesOut = stats.bytesOut + #item.msg
        return true
    end
    return false
end

local function pump(_, elapsed)
    tokens = math.min(MAX_TOKENS, tokens + REGEN * (elapsed or 0.1))
    while tokens >= 1 do
        local q = (#queues.high > 0 and queues.high) or (#queues.bulk > 0 and queues.bulk)
        if not q then break end
        local item = q[1]
        if sendRaw(item) then
            table.remove(q, 1)
            tokens = tokens - 1
        else
            item.tries = (item.tries or 0) + 1
            if item.tries > 20 then table.remove(q, 1) end
            tokens = 0 -- back off until the bucket refills
            break
        end
    end
end

local function ensureTicker()
    if ticker then return end
    local f = CreateFrame("Frame")
    local acc = 0
    f:SetScript("OnUpdate", function(_, el)
        acc = acc + el
        if acc >= 0.1 then pump(nil, acc); acc = 0 end
    end)
    ticker = f
end

local msgCounter = 0
local function nextId()
    msgCounter = (msgCounter + 1) % 1296
    local chars = "0123456789abcdefghijklmnopqrstuvwxyz"
    local a, b = math.floor(msgCounter / 36) + 1, (msgCounter % 36) + 1
    local r = math.random(1, 36)
    return chars:sub(r, r) .. chars:sub(a, a) .. chars:sub(b, b)
end

--- Queues a typed message to one distribution.
local function sendTo(kind, payload, dist, target, priority)
    local data = kind .. S.Pack(payload)
    local id = nextId()
    local total = math.max(1, math.ceil(#data / CHUNK))
    local q = queues[priority or "bulk"]
    for i = 1, total do
        local part = data:sub((i - 1) * CHUNK + 1, i * CHUNK)
        q[#q + 1] = { msg = ("%s\t%d\t%d\t%s"):format(id, i, total, part), dist = dist, target = target }
    end
    ensureTicker()
end

---------------------------------------------------------------------------
-- Distribution targets
---------------------------------------------------------------------------
local function groupDist()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

function Comm.ChannelId()
    if not FBL.opt.syncChannelEnabled then return nil end
    local id = GetChannelName(FBL.opt.syncChannelName or "")
    if id and id > 0 then return id end
end

--- Sends to every enabled shared distribution (guild, group, custom channel).
local function broadcast(kind, payload, priority)
    if not FBL.opt.syncEnabled then return end
    local o = FBL.opt
    if o.syncGuild and IsInGuild() then sendTo(kind, payload, "GUILD", nil, priority) end
    if o.syncGroup then
        local d = groupDist()
        if d then sendTo(kind, payload, d, nil, priority) end
    end
    local ch = Comm.ChannelId()
    if ch then sendTo(kind, payload, "CHANNEL", ch, priority) end
end

function Comm.Whisper(kind, payload, target, priority)
    if not FBL.opt.syncEnabled or not target then return end
    sendTo(kind, payload, "WHISPER", target, priority)
end

---------------------------------------------------------------------------
-- Public API used by the rest of the addon
---------------------------------------------------------------------------
--- Max of every timestamp we hold; peers use it to decide whether to ask us for data.
function Comm.DataStamp()
    local m = 0
    for _, e in pairs(FBL.db.entries) do
        m = math.max(m, e.updatedAt or 0, e.infoAt or 0)
        local s = e.sightings and e.sightings[1]
        if s and s.t then m = math.max(m, s.t) end
    end
    return m
end

function Comm.BroadcastEntry(e)
    broadcast("E", FBL.ToWire(e, 3), "high")
end

local lastSightShare = {}
function Comm.BroadcastSighting(e)
    if not FBL.opt.shareSightings then return end
    local now = Now()
    if (lastSightShare[e.key] or 0) > now - 120 then return end
    lastSightShare[e.key] = now
    local w = FBL.ToWire(e, 1)
    -- strip "why" fields: a sighting must never change the reason for a listing
    w.ca, w.sv, w.co, w.tg, w.al, w.d, w.ub, w.ua = nil, nil, nil, nil, nil, nil, nil, nil
    broadcast("S", w, "high")
end

function Comm.SendHello(wantReply, whisperTarget)
    local payload = { v = FBL.PROTOCOL, ver = FBL.version, c = FBL.CountEntries(), m = Comm.DataStamp(), r = wantReply or nil }
    if whisperTarget then
        Comm.Whisper("H", payload, whisperTarget, "high")
    else
        broadcast("H", payload, "high")
    end
end

--- Manually request a full sync from a specific player (e.g. your target).
function Comm.RequestFrom(name, since)
    local full = FBL.NormalizeName(name)
    if not full then return end
    local rid = nextId()
    Comm.pending = Comm.pending or {}
    Comm.pending[rid] = { peer = full, started = Now(), received = 0, stamp = nil }
    Comm.Whisper("Q", { rid = rid, since = since or 0 }, full, "high")
    Comm.Log("Requested sync from %s", FBL.ShortName(full))
end

---------------------------------------------------------------------------
-- Peers
---------------------------------------------------------------------------
local function peerKey(sender) local _, k = FBL.NormalizeName(sender); return k end

local function touchPeer(sender, dist, hello)
    local k = peerKey(sender)
    if not k then return end
    local p = FBL.db.peers[k] or { name = FBL.NormalizeName(sender) }
    p.lastSeen = Now()
    p.via = dist
    if dist == "GUILD" then p.guildmate = true end
    if hello then
        p.version, p.count, p.stamp = hello.ver, hello.c, hello.m
    end
    FBL.db.peers[k] = p
    FBL:Fire("PEERS_CHANGED")
    return p, k
end

local function isGuildmate(sender)
    local p = FBL.db.peers[peerKey(sender) or ""]
    if p and p.guildmate then return true end
    if C_GuildInfo and C_GuildInfo.MemberExistsByName then
        local ok, res = pcall(C_GuildInfo.MemberExistsByName, FBL.ShortName(sender))
        if ok and res then return true end
    end
    return false
end

local function accepts(sender, dist)
    if dist == "WHISPER" and isGuildmate(sender) then dist = "GUILD" end
    return FBL.AcceptsFrom(sender, dist)
end

---------------------------------------------------------------------------
-- Sync requests (one at a time to avoid storms)
---------------------------------------------------------------------------
local requestQueue, activeRequest = {}, nil

local function startNextRequest()
    if activeRequest and Now() - activeRequest.started < 90 then return end
    activeRequest = nil
    local nxt = table.remove(requestQueue, 1)
    if not nxt then return end
    local rid = nextId()
    activeRequest = { rid = rid, peer = nxt.peer, key = nxt.key, stamp = nxt.stamp, started = Now(), received = 0 }
    Comm.pending = Comm.pending or {}
    Comm.pending[rid] = activeRequest
    Comm.Whisper("Q", { rid = rid, since = FBL.db.lastSync[nxt.key] or 0 }, nxt.peer, "high")
    Comm.Log("Syncing with %s...", FBL.ShortName(nxt.peer))
end

local function queueRequest(peer, key, stamp)
    for _, r in ipairs(requestQueue) do if r.key == key then return end end
    if activeRequest and activeRequest.key == key then return end
    requestQueue[#requestQueue + 1] = { peer = peer, key = key, stamp = stamp }
    startNextRequest()
end

local answering = {}
local function answerRequest(sender, req)
    local since = tonumber(req.since) or 0
    local k = peerKey(sender)
    if answering[k] and Now() - answering[k] < 30 then return end
    answering[k] = Now()
    local batch, sent = {}, 0
    local function flush(done)
        Comm.Whisper("A", { rid = req.rid, e = batch, done = done or nil }, sender, "bulk")
        batch = {}
    end
    for _, e in pairs(FBL.db.entries) do
        local s = e.sightings and e.sightings[1]
        local stamp = math.max(e.updatedAt or 0, e.infoAt or 0, s and s.t or 0)
        if stamp > since and (not e.deleted or FBL.opt.shareDeletes) then
            batch[#batch + 1] = FBL.ToWire(e, 3)
            sent = sent + 1
            if #batch >= 4 then flush(false) end
            if sent >= 400 then break end
        end
    end
    flush(true)
    Comm.Log("Sent %d entr%s to %s", sent, sent == 1 and "y" or "ies", FBL.ShortName(sender))
end

---------------------------------------------------------------------------
-- Incoming
---------------------------------------------------------------------------
local function applyRemote(w, sender, dist)
    local remote = FBL.FromWire(w)
    if not remote then return end
    local r = FBL.MergeRemote(remote, sender)
    if r == "added" then
        Comm.Log("%s shared %s", FBL.ShortName(sender), FBL.ShortName(remote.name))
    elseif r == "inbox" then
        Comm.Log("%s shared %s (awaiting review)", FBL.ShortName(sender), FBL.ShortName(remote.name))
    elseif r == "removed" then
        Comm.Log("%s removed %s", FBL.ShortName(sender), FBL.ShortName(remote.name))
    end
    return r
end

local handlers = {}

handlers.H = function(sender, dist, p)
    local peer, key = touchPeer(sender, dist, p)
    if not peer then return end
    if p.r and dist ~= "WHISPER" then
        -- reply directly so the newcomer learns about us too (slight jitter)
        C_Timer.After(1 + math.random() * 4, function() Comm.SendHello(false, sender) end)
    end
    if (tonumber(p.m) or 0) > (FBL.db.lastSync[key] or 0) and accepts(sender, dist) then
        queueRequest(sender, key, tonumber(p.m))
    end
end

handlers.Q = function(sender, dist, p)
    touchPeer(sender, dist)
    if type(p.rid) ~= "string" then return end
    answerRequest(sender, p)
end

handlers.A = function(sender, dist, p)
    touchPeer(sender, dist)
    local pend = Comm.pending and Comm.pending[p.rid]
    if not pend then return end
    if not accepts(sender, dist) then return end
    for _, w in ipairs(type(p.e) == "table" and p.e or {}) do
        applyRemote(w, sender, dist)
        pend.received = pend.received + 1
    end
    if p.done then
        local key = peerKey(sender)
        local peer = FBL.db.peers[key]
        FBL.db.lastSync[key] = pend.stamp or (peer and peer.stamp) or Now()
        Comm.Log("Sync with %s complete (%d received)", FBL.ShortName(sender), pend.received)
        Comm.pending[p.rid] = nil
        if activeRequest and activeRequest.rid == p.rid then activeRequest = nil end
        C_Timer.After(2, startNextRequest)
    end
end

handlers.E = function(sender, dist, p)
    touchPeer(sender, dist)
    if not accepts(sender, dist) then return end
    applyRemote(p, sender, dist)
end

handlers.S = function(sender, dist, p)
    touchPeer(sender, dist)
    if not accepts(sender, dist) then return end
    local remote = FBL.FromWire(p)
    if not remote then return end
    local e = FBL.db.entries[remote.key]
    if not e then return end -- only enrich entries we already have
    remote.updatedAt = 0
    remote.deleted = nil
    FBL.MergeRemote(remote, sender)
end

-- chunk reassembly
local partial = {}

local function onChunk(sender, dist, msg)
    local id, seq, total, data = msg:match("^(%w+)\t(%d+)\t(%d+)\t(.*)$")
    if not id then return end
    seq, total = tonumber(seq), tonumber(total)
    if total > 200 or seq < 1 or seq > total then return end
    local k = sender .. ":" .. id
    local buf = partial[k]
    if not buf then
        buf = { parts = {}, n = 0, total = total, t = Now() }
        partial[k] = buf
    end
    if not buf.parts[seq] then
        buf.parts[seq] = data
        buf.n = buf.n + 1
    end
    if buf.n < buf.total then return end
    partial[k] = nil
    local full = table.concat(buf.parts)
    local kind = full:sub(1, 1)
    local payload = S.Unpack(full:sub(2))
    local h = handlers[kind]
    if h and type(payload) == "table" then h(sender, dist, payload) end
end

FBL:RegisterEvent("CHAT_MSG_ADDON", function(_, prefix, msg, dist, sender)
    if prefix ~= PREFIX then return end
    msg, sender = Safe(msg), Safe(sender)
    if not msg or not sender then return end
    local full = FBL.NormalizeName(sender)
    if not full or full == FBL.playerName then return end
    stats.received = stats.received + 1
    stats.bytesIn = stats.bytesIn + #msg
    onChunk(full, dist, msg)
end)

-- drop stale partial messages
C_Timer.NewTicker(30, function()
    local cutoff = Now() - 60
    for k, buf in pairs(partial) do
        if buf.t < cutoff then partial[k] = nil end
    end
end)

---------------------------------------------------------------------------
-- Custom channel
---------------------------------------------------------------------------
local function hideChannelFromChat(name)
    local remove = _G.ChatFrame_RemoveChannel or (ChatFrameUtil and ChatFrameUtil.RemoveChannel)
    if not remove then return end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf then pcall(remove, cf, name) end
    end
end

function Comm.JoinChannel()
    local name = FBL.opt.syncChannelName
    if not FBL.opt.syncChannelEnabled or not name or name == "" then return end
    if GetChannelName(name) > 0 then return end
    local join = _G.JoinTemporaryChannel or _G.JoinChannelByName
    if join then
        pcall(join, name)
        C_Timer.After(1, function() hideChannelFromChat(name) end)
    end
end

function Comm.LeaveChannel(name)
    name = name or FBL.opt.syncChannelName
    if name and GetChannelName(name) > 0 and LeaveChannelByName then
        pcall(LeaveChannelByName, name)
    end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
FBL:On("DB_READY", function()
    S = FBL.Serializer
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end)

FBL:On("LOGIN", function()
    C_Timer.After(8, function()
        Comm.JoinChannel()
        C_Timer.After(4, function()
            Comm.SendHello(true)
            -- trusted friends who are online but not in our guild/group
            if FBL.opt.syncWhisperTrusted and C_FriendList and C_FriendList.GetNumFriends then
                for i = 1, C_FriendList.GetNumFriends() do
                    local info = C_FriendList.GetFriendInfoByIndex(i)
                    if info and info.connected and FBL.IsTrusted(info.name) then
                        Comm.SendHello(true, info.name)
                    end
                end
            end
        end)
    end)
end)

local lastGroupHello = 0
FBL:RegisterEvent("GROUP_JOINED", function()
    if Now() - lastGroupHello < 30 then return end
    lastGroupHello = Now()
    C_Timer.After(3, function() Comm.SendHello(true) end)
end)
