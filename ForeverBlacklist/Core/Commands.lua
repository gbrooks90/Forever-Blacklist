-- Forever Blacklist: slash commands.
local _, FBL = ...

local HELP = {
    "|cffffd100/fbl|r - open or close the window",
    "|cffffd100/fbl add|r [name] [reason text] - blacklist your target or a name",
    "|cffffd100/fbl remove|r name - remove someone",
    "|cffffd100/fbl check|r name - is this person blacklisted?",
    "|cffffd100/fbl map|r [name] - show last known location on the world map",
    "|cffffd100/fbl sync|r [name] - announce to the network, or pull from a player",
    "|cffffd100/fbl trust|r name - trust a player for sync",
    "|cffffd100/fbl inbox|r - review shared entries",
    "|cffffd100/fbl options|r - settings",
    "|cffffd100/fbl export|r / |cffffd100import|r - share by copy/paste",
}

local function targetName()
    if not UnitIsPlayer("target") then return nil end
    local n, r = UnitName("target")
    return FBL.Safe(n), FBL.Safe(r)
end

local commands = {}

commands.add = function(rest)
    local name, comment = rest:match("^(%S+)%s*(.*)$")
    if not name then
        FBL.ShowAddDialog({ unit = "target" })
        return
    end
    FBL.ShowAddDialog({ name = name, comment = comment ~= "" and comment or nil })
end

commands.remove = function(rest)
    local name, realm = rest, nil
    if name == "" then name, realm = targetName() end
    local e = name and FBL.IsBlacklisted(name, realm)
    if not e then FBL.Print("Not on your blacklist.") return end
    FBL.ConfirmRemove(e.key)
end
commands.del = commands.remove

commands.check = function(rest)
    local name, realm = rest, nil
    if name == "" then name, realm = targetName() end
    if not name then FBL.Print("Usage: /fbl check Name") return end
    local e = FBL.IsBlacklisted(name, realm)
    if e then
        FBL.Alert(e, "is on your blacklist", true)
    else
        FBL.Print("%s is not blacklisted.", name)
    end
end

commands.map = function(rest)
    if rest == "" then
        FBL.opt.mapPins = not FBL.opt.mapPins
        FBL.RefreshMapPins()
        FBL.Print("Map pins %s.", FBL.opt.mapPins and "shown" or "hidden")
        return
    end
    local e = FBL.IsBlacklisted(rest)
    local s = e and FBL.LastSighting(e)
    if not s then FBL.Print("No known location for %s.", rest) return end
    FBL.ShowOnMap(e.key, s)
end

commands.sync = function(rest)
    if rest ~= "" then FBL.Comm.RequestFrom(rest, 0) return end
    FBL.Comm.JoinChannel()
    FBL.Comm.SendHello(true)
    FBL.Print("Announced to your sync network.")
end

commands.trust = function(rest)
    local name = rest ~= "" and rest or FBL.NormalizeName(targetName())
    if not name then FBL.Print("Usage: /fbl trust Name") return end
    FBL.SetTrusted(name, true)
    FBL.Print("%s is now trusted for sync.", name)
end

commands.untrust = function(rest)
    if rest == "" then return end
    FBL.SetTrusted(rest, false)
    FBL.Print("%s is no longer trusted.", rest)
end

commands.inbox = function() FBL.ShowView("inbox") end
commands.options = function() FBL.ShowView("options") end
commands.config = commands.options
commands.export = function()
    local str, n = FBL.ExportString()
    FBL.Widgets.TextPopup(("Export - %d entries (Ctrl+C to copy)"):format(n), str)
end
commands.import = function()
    FBL.Widgets.TextPopup("Import - paste an export string", "", function(text)
        local counts, err = FBL.ImportString(text)
        if counts then FBL.Print("Imported: %d new, %d updated.", counts.added, counts.updated)
        else FBL.Print("|cffff6060Import failed:|r %s", tostring(err)) end
    end, "Import")
end
commands.help = function()
    FBL.Print("commands:")
    for _, l in ipairs(HELP) do DEFAULT_CHAT_FRAME:AddMessage("   " .. l) end
end

SLASH_FOREVERBLACKLIST1 = "/fbl"
SLASH_FOREVERBLACKLIST2 = "/blacklist"
SLASH_FOREVERBLACKLIST3 = "/foreverblacklist"
SlashCmdList.FOREVERBLACKLIST = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower()
    if not cmd then FBL.Toggle() return end
    local fn = commands[cmd]
    if fn then fn(rest or "") else commands.help() end
end
