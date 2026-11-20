-- Two-client simulation of Forever Blacklist core (Init, Serializer, Data, Comm).
local ROOT = arg[1]
local clock = 1800000000
local wire = {}  -- pending messages {from, prefix, msg, dist, target}
local timers = {}

local function newEnv(playerName, guild)
  local env = {}
  local frames = {}
  local base = {
    pairs=pairs, ipairs=ipairs, type=type, tostring=tostring, tonumber=tonumber, select=select,
    string=string, table=table, math=math, pcall=pcall, error=error, setmetatable=setmetatable,
    next=next, print=print, unpack=table.unpack, os=os,
    date=function(f, t) return os.date(f, t) end, time=function() return clock end,
    GetServerTime=function() return math.floor(clock) end,
    GetNormalizedRealmName=function() return "Forever" end, GetRealmName=function() return "Forever" end,
    geterrorhandler=function() return function(e) print("ERR", e) end end,
    DEFAULT_CHAT_FRAME={AddMessage=function(_, m) env._chat = (env._chat or "") .. m .. "\n" end},
    C_AddOns={GetAddOnMetadata=function() return "1.0.0" end},
    CreateFrame=function()
      local f = {scripts={}, events={}}
      function f:RegisterEvent(e) self.events[e]=true end
      function f:SetScript(k, fn) self.scripts[k]=fn end
      frames[#frames+1]=f
      return f
    end,
    C_Timer={After=function(d, fn) timers[#timers+1]={t=clock+d, fn=fn} end,
             NewTicker=function() return {} end},
    C_ChatInfo={RegisterAddonMessagePrefix=function() end,
      SendAddonMessage=function(prefix, msg, dist, target)
        assert(#msg <= 255, "message too long: "..#msg)
        wire[#wire+1]={from=playerName, prefix=prefix, msg=msg, dist=dist, target=target}
        return 0
      end},
    IsInGuild=function() return guild end, IsInGroup=function() return false end, IsInRaid=function() return false end,
    GetChannelName=function() return 0 end, LE_PARTY_CATEGORY_INSTANCE=2,
    UnitName=function(unit)
      if unit == "player" then
        local first, last = playerName:match("^(%S+) (%S+)$")
        if first then return first, last end   -- WoW Forever: surname as 2nd value
        return playerName
      end
      local u = env._units and env._units[unit]
      if u then return u[1], u[2], u[3] end
    end,
    Enum={}, RAID_CLASS_COLORS={},
  }
  setmetatable(env, {__index=base})
  env._G = env
  env._frames = frames
  local ns = {}
  for _, f in ipairs({"Core/Init.lua","Core/Serializer.lua","Core/Data.lua","Core/Comm.lua"}) do
    local chunk = assert(loadfile(ROOT.."/"..f, "t", env))
    chunk("ForeverBlacklist", ns)
  end
  env.FBL = ns
  -- fire ADDON_LOADED and PLAYER_LOGIN
  local ef = ns.eventFrame
  ef.scripts.OnEvent(ef, "ADDON_LOADED", "ForeverBlacklist")
  ef.scripts.OnEvent(ef, "PLAYER_LOGIN")
  env.name = playerName
  return env
end

local A = newEnv("Alice", true)
local B = newEnv("Bob", true)
local clients = {Alice=A, Bob=B}

local function tick(seconds)
  for _ = 1, seconds * 10 do
    clock = clock + 0.1
    for _, c in pairs(clients) do
      for _, f in ipairs(c._frames) do if f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.1) end end
    end
    -- deliver
    local pending = wire; wire = {}
    for _, m in ipairs(pending) do
      for n, c in pairs(clients) do
        local deliver = (m.dist == "GUILD" and n ~= m.from) or (m.dist == "WHISPER" and (m.target or ""):match("^"..n))
        if deliver then
          local ef = c.FBL.eventFrame
          ef.scripts.OnEvent(ef, "CHAT_MSG_ADDON", m.prefix, m.msg, m.dist, m.from .. "-Forever")
        end
      end
    end
    local due = {}
    for i = #timers, 1, -1 do if timers[i].t <= clock then due[#due+1] = table.remove(timers, i) end end
    for _, t in ipairs(due) do t.fn() end
  end
end

local function check(cond, msg) print((cond and "PASS " or "FAIL ") .. msg) if not cond then FAILED = true end end

-- serializer round trip
local S = A.FBL.Serializer
local t = {a="hi^there~|pipe\nnew", b=1.5, c=-3, d=true, e={1,2,{x="y"}}, f=0.12345678}
local back = S.Deserialize(S.Serialize(t))
check(back.a == t.a and back.b == 1.5 and back.c == -3 and back.d == true and back.e[3].x == "y", "serializer round trip")
check(not S.Serialize(t):find("[%c|]"), "serialized output has no control chars or pipes")
check(S.DecodeBase64(S.EncodeBase64("hello world!?")) == "hello world!?", "base64 round trip")
for _, s in ipairs({"", "a", "ab", "abc", "abcd", string.char(0,255,10,124)}) do
  assert(S.DecodeBase64(S.EncodeBase64(s)) == s, "b64 "..#s)
end
check(true, "base64 edge lengths")
local imp = S.Import(S.Export({v=1, e={{n="X"}}}))
check(imp and imp.e[1].n == "X", "export/import string")

-- names
local N = A.FBL.NormalizeName
check(N("leeroy") == "Leeroy-Forever", "normalize plain name")
check(N("Leeroy-Other Realm") == "Leeroy-OtherRealm", "normalize name-realm")
check(N("Leeroy-Other", "Other") == "Leeroy-Other", "normalize name-realm with explicit realm")
check(select(2, N("LEEROY")) == "leeroy-forever", "key is lowercase")

-- initial sync: Bob logs in and pulls Alice's entries
A.FBL.SaveEntry({name="Gankster", category="GRIEF", severity=5, comment="Corpse camped me in STV", race="Orc", raceFile="Orc", classFile="ROGUE", level=60})
A.FBL.AddSighting(A.FBL.db.entries["gankster-forever"], {t=clock, mapID=1434, x=0.4, y=0.5, zone="Stranglethorn Vale", by="Alice-Forever"})
for i = 1, 30 do A.FBL.SaveEntry({name="Spammer"..string.char(96+i%26)..i, category="SPAM", comment=string.rep("long comment ", 10)}, true) end
wire = {}  -- drop live broadcasts so we test the pull path
B.FBL.opt.reviewIncoming = false
tick(60)
local bg = B.FBL.db.entries["gankster-forever"]
check(bg ~= nil, "Bob received Gankster via sync")
check(bg and bg.comment == "Corpse camped me in STV" and bg.severity == 5 and bg.category == "GRIEF", "fields intact")
check(bg and bg.sightings[1] and bg.sightings[1].mapID == 1434 and math.abs(bg.sightings[1].x - 0.4) < 1e-6, "sighting synced")
check(B.FBL.CountEntries() == 31, "Bob has all 31 entries (got "..B.FBL.CountEntries()..")")

-- live update
A.FBL.SaveEntry({name="Gankster", comment="Also ninja'd the Arcanite Reaper"})
tick(5)
check(B.FBL.db.entries["gankster-forever"].comment == "Also ninja'd the Arcanite Reaper", "live edit propagated")

-- sighting broadcast from Bob updates Alice
local be = B.FBL.db.entries["gankster-forever"]
B.FBL.AddSighting(be, {t=clock, mapID=1440, x=0.1, y=0.2, zone="Ashenvale", by="Bob-Forever"})
be.level = 60; be.guild = "Red Hand"; be.infoAt = clock
B.FBL.Comm.BroadcastSighting(be)
tick(5)
local ae = A.FBL.db.entries["gankster-forever"]
check(ae.sightings[1].zone == "Ashenvale" and ae.guild == "Red Hand", "Bob's sighting + info reached Alice")
check(ae.comment == "Also ninja'd the Arcanite Reaper", "sighting did not change the reason")

-- review inbox
B.FBL.opt.reviewIncoming = true
A.FBL.SaveEntry({name="Scammy", category="SCAM", comment="Fake trade"})
tick(5)
check(B.FBL.db.entries["scammy-forever"] == nil and #B.FBL.db.inbox == 1, "new entry went to Bob's inbox")
B.FBL.AcceptInbox(1)
check(B.FBL.IsBlacklisted("Scammy") ~= nil, "accepting inbox adds entry")

-- deletes: only from owner/trusted
B.FBL.SaveEntry({name="Mine", category="TOXIC"}) ; tick(5)
check(A.FBL.db.inbox[1] and A.FBL.db.inbox[1].entry.name == "Mine-Forever", "Alice got Bob's entry in inbox")
A.FBL.AcceptInbox(1)
A.FBL.RemoveEntry("gankster-forever"); tick(5)
check(B.FBL.IsBlacklisted("Gankster") == nil, "owner (Alice) delete propagated")
A.FBL.RemoveEntry("mine-forever"); tick(5)
check(B.FBL.IsBlacklisted("Mine") ~= nil, "non-owner delete ignored")
B.FBL.SetTrusted("Alice", true)
A.FBL.SaveEntry({name="Mine", category="TOXIC"}); tick(1)
A.FBL.RemoveEntry("mine-forever"); tick(5)
check(B.FBL.IsBlacklisted("Mine") == nil, "trusted delete accepted")

-- accept mode TRUSTED blocks strangers
B.FBL.SetTrusted("Alice", false)
B.FBL.opt.acceptFrom = "TRUSTED"
A.FBL.SaveEntry({name="Blocked", category="BOT"}); tick(5)
check(B.FBL.db.entries["blocked-forever"] == nil and #B.FBL.db.inbox == 0, "untrusted sender blocked in TRUSTED mode")

-- import/export
local str = A.FBL.ExportString()
local C = newEnv("Carol", false); clients.Carol = C
local counts = C.FBL.ImportString(str)
check(counts and counts.added == A.FBL.CountEntries(), "import added "..(counts and counts.added or "nil").." of "..A.FBL.CountEntries())

-- WoW Forever "First Last" names
check(N("quazi bro") == "Quazi Bro", "two-word name keeps both capitals, no realm")
check(N("Quazi   Bro-CAMWOWUS2Realm3PvE") == "Quazi Bro", "internal realm dropped from two-word name")
check(select(2, N("Quazi Bro-ShardA")) == select(2, N("quazi bro-ShardB")), "same player on different internal realms = same key")
local Q = newEnv("Quazi Bro", true); clients["Quazi Bro"] = Q
Q.FBL.opt.reviewIncoming = false
local sentTargets = {}
local origSend = Q.C_ChatInfo.SendAddonMessage
for _, c in pairs(clients) do
  local send = c.C_ChatInfo.SendAddonMessage
  rawset(c, "C_ChatInfo", {RegisterAddonMessagePrefix=function() end, SendAddonMessage=function(p, m, d, t)
    if d == "WHISPER" then sentTargets[t] = true end
    return send(p, m, d, t)
  end})
end
Q.FBL.Comm.SendHello(true)
tick(60)
check(Q.FBL.IsBlacklisted("Scammy") ~= nil, "Quazi Bro pulled entries via sync")
local bad = {}
for t in pairs(sentTargets) do if t:find("%-") or t == "Quazi bro" then bad[#bad+1] = t end end
check(sentTargets["Quazi Bro"] and #bad == 0, "whispers use exact 'Quazi Bro' with no realm suffix (bad: "..table.concat(bad, ",")..")")
check(A.FBL.Comm.WhisperTarget("Quazi Bro-Forever") == "Quazi Bro", "own-realm suffix stripped")
check(A.FBL.Comm.WhisperTarget("Someone Else-OtherRealm") == "Someone Else", "unknown two-word name whispered without realm")
check(A.FBL.Comm.WhisperTarget("Solo-OtherRealm") == "Solo-OtherRealm", "one-word foreign realm kept")
-- offline peer: system message is hidden and the queue is cleared
A.FBL.Comm.Whisper("H", {v=1}, "Gone Guy")
local hidden = A.FBL.Comm._systemFilter(nil, "CHAT_MSG_SYSTEM", "No player named 'Gone Guy' is currently playing.")
check(hidden == true, "offline-peer error hidden")
check(A.FBL.Comm._systemFilter(nil, "CHAT_MSG_SYSTEM", "No player named 'Random Person' is currently playing.") == false, "unrelated not-found errors still shown")

-- WoW Forever unit API returns the surname as a separate value
check(Q.FBL.surnameMode == true, "surname mode detected from own character")
check(A.FBL.surnameMode == false, "one-word client stays in normal mode")
check(Q.FBL.playerName == "Quazi Bro", "own name joined with a space ("..tostring(Q.FBL.playerName)..")")
Q._units = { target = {"Gank", "Lord"}, focus = {"Gank", "CAMWOWUS2Realm3PvE"}, mouseover = {"Gank Lord", "OtherRealm"} }
check(Q.FBL.UnitName("target") == "Gank Lord", "target 'Gank','Lord' -> 'Gank Lord'")
check(Q.FBL.NormalizeName(Q.FBL.UnitName("target")) == "Gank Lord", "no hyphen between first and last")
local n2, r2 = Q.FBL.UnitName("focus")
check(n2 == "Gank" and r2 == "CAMWOWUS2Realm3PvE", "realm-looking second value is not treated as a surname")
local n3, r3 = Q.FBL.UnitName("mouseover")
check(n3 == "Gank Lord" and r3 == "OtherRealm", "already-joined name keeps its realm")
-- migration of entries saved by v1.0.x as "First-Last"
Q.FBL.db.entries["evil-twin"] = { key = "evil-twin", name = "Evil-Twin", category = "GRIEF", updatedAt = 1, sightings = {} }
Q.FBL.db.trusted["good-pal"] = "Good-Pal"
Q.FBL:Fire("LOGIN")
check(Q.FBL.db.entries["evil-twin"] == nil and Q.FBL.IsBlacklisted("Evil Twin") ~= nil, "'Evil-Twin' migrated to 'Evil Twin'")
check(Q.FBL.IsTrusted("Good Pal"), "trusted 'Good-Pal' migrated")

-- Mutual trust: two players with no guild, group or channel in common
clients = {}
local Dn = newEnv("Dana Stone", false); clients["Dana Stone"] = Dn
local El = newEnv("Eli Fox", false); clients["Eli Fox"] = El
tick(15)
Dn.FBL.SaveEntry({name="Before Trust", category="SCAM"})
tick(5)
check(El.FBL.db.entries["before trust"] == nil, "nothing shared before trust")
Dn.FBL.SetTrusted("Eli Fox", true)
tick(5)
check(not Dn.FBL.IsMutual("Eli Fox"), "one-sided trust is not mutual")
El.FBL.SetTrusted("Dana Stone", true)
tick(30)
check(Dn.FBL.IsMutual("Eli Fox") and El.FBL.IsMutual("Dana Stone"), "mutual trust established both ways")
check(El.FBL.IsBlacklisted("Before Trust") ~= nil, "existing entries pulled automatically once mutual")
check(#El.FBL.db.inbox == 0, "mutual entries skipped the inbox")
Dn.FBL.SaveEntry({name="Live One", category="GRIEF", comment="live"})
tick(5)
check(El.FBL.IsBlacklisted("Live One") ~= nil, "live entry whispered to mutual peer")
El.FBL.SaveEntry({name="From Eli", category="TOXIC"})
tick(5)
check(Dn.FBL.IsBlacklisted("From Eli") ~= nil, "works in both directions")
-- Eli logs off; Dana adds entries; Eli logs back in and catches up without asking
clients["Eli Fox"] = nil
Dn.FBL.Comm.online["eli fox"] = nil
for i = 1, 6 do Dn.FBL.SaveEntry({name="Offline Add"..string.char(96+i), category="SPAM"}) end
tick(5)
clients["Eli Fox"] = El
El.FBL:Fire("LOGIN")
tick(60)
check(El.FBL.IsBlacklisted("Offline Adda") and El.FBL.IsBlacklisted("Offline Addf"), "caught up on login with no request")
-- untrust stops direct sync
El.FBL.SetTrusted("Dana Stone", false)
tick(5)
check(not Dn.FBL.IsMutual("Eli Fox"), "untrust is announced")
Dn.FBL.SaveEntry({name="After Untrust", category="BOT"})
tick(5)
check(El.FBL.db.entries["after untrust"] == nil, "no direct sync after untrust")

-- Migration: saved "First Last-InternalRealm" names lose the realm and merge
local M = newEnv("Mia Vale", false)
M.FBL.db.entries = {
  ["nest le-camwowus2realm3pve"] = { key="nest le-camwowus2realm3pve", name="Nest Le-CAMWOWUS2Realm3PvE", category="GRIEF",
    severity=5, comment="old", updatedAt=100, sightings={ {t=50, zone="Durotar", by="Quazi Bro-CAMWOWUS2Realm3PvE"} } },
  ["nest le-camwowus2realm7pve"] = { key="nest le-camwowus2realm7pve", name="Nest Le-CAMWOWUS2Realm7PvE", category="SCAM",
    severity=3, comment="newer", updatedAt=200, sightings={ {t=60, zone="Barrens"} } },
  ["solo-forever"] = { key="solo-forever", name="Solo-Forever", updatedAt=1, sightings={} },
}
M.FBL.db.trusted = { ["quazi bro-camwowus2realm3pve"] = "Quazi Bro-CAMWOWUS2Realm3PvE" }
M.FBL.RekeyDatabase()
local ne = M.FBL.db.entries["nest le"]
check(ne and ne.name == "Nest Le" and not M.FBL.db.entries["nest le-camwowus2realm3pve"], "'Nest Le-CAMWOW...' re-keyed to 'Nest Le'")
check(ne and ne.comment == "newer" and #ne.sightings == 2, "duplicates merged (newest reason, all sightings)")
check(ne and ne.realm and ne.realm:find("PvE$"), "internal realm kept for the Ruleset line")
check(ne and ne.sightings[2].by == "Quazi Bro", "sighting author cleaned")
check(M.FBL.db.entries["solo-forever"] ~= nil, "one-word names untouched")
check(M.FBL.IsTrusted("Quazi Bro"), "trusted list re-keyed")

print(FAILED and "SOME TESTS FAILED" or "ALL TESTS PASSED")
