-- Forever Blacklist: detail panel for a single entry.
local _, FBL = ...

local T, W = FBL.Theme, FBL.Widgets
local DV = {}
FBL.DetailView = DV

local STAT_ROWS = {
    { function() return FBL.surnameMode and "Ruleset" or "Realm" end, function(e)
        local realm = e.name and e.name:match("%-(.+)$")
        if realm and FBL.surnameMode then
            -- WoW Forever is realmless; internal names look like "CAMWOWUS2Realm3PvE"
            local lower = realm:lower()
            for _, rs in ipairs({ { "hardcore", "Hardcore" }, { "pvp", "PvP" }, { "pve", "PvE" }, { "rp", "Roleplay" } }) do
                if lower:sub(-#rs[1]) == rs[1] then return rs[2] end
            end
            return nil
        end
        return realm
    end },
    { "Gender", function(e) return e.sex end },
    { "Title", function(e) return e.title end },
    { "PvP rank", function(e) return e.pvpRank end },
    { "Added by", function(e) return e.addedBy and FBL.ShortName(e.addedBy) end },
    { "Added", function(e) return e.addedAt and date("%b %d, %Y", e.addedAt) end },
    { "Updated", function(e)
        return e.updatedAt and (FBL.TimeAgo(e.updatedAt) .. (e.updatedBy and (" by " .. FBL.ShortName(e.updatedBy)) or ""))
    end },
    { "Times seen", function(e) return tostring(e.seenCount or #(e.sightings or {})) end },
    { "First seen", function(e) return e.firstSeen and date("%b %d, %Y", e.firstSeen) end },
    { "Shared by", function(e) return e.source and FBL.ShortName(e.source) end },
}

local function sightingText(s)
    local where = s.zone or "Unknown"
    if s.sub and s.sub ~= "" and s.sub ~= s.zone then where = where .. " - " .. s.sub end
    if s.x and s.y then where = where .. ("  |cff888888(%.1f, %.1f)|r"):format(s.x * 100, s.y * 100) end
    if s.instance and s.instance ~= "none" then where = where .. " |cffb266ff[" .. s.instance .. "]|r" end
    return where
end

local function createSightingRow(row)
    row:SetHeight(22)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(T.WHITE)
    hl:SetAllPoints()
    hl:SetVertexColor(1, 1, 1, 0.05)
    row.pin = row:CreateTexture(nil, "ARTWORK")
    row.pin:SetSize(14, 14)
    row.pin:SetPoint("LEFT", 4, 0)
    row.pin:SetTexture("Interface\\Minimap\\Tracking\\None")
    row.when = W.Text(row, "GameFontHighlightSmall", "")
    row.when:SetPoint("LEFT", 22, 0)
    row.when:SetWidth(70)
    row.where = W.Text(row, "GameFontHighlightSmall", "")
    row.where:SetPoint("LEFT", row.when, "RIGHT", 6, 0)
    row.where:SetPoint("RIGHT", -110, 0)
    row.where:SetWordWrap(false)
    row.by = W.Text(row, "GameFontDisableSmall", "")
    row.by:SetPoint("RIGHT", -6, 0)
    row.by:SetJustifyH("RIGHT")
    row:SetScript("OnClick", function(self)
        if self.data and self.data.mapID then FBL.ShowOnMap(self.entryKey, self.data) end
    end)
    row:SetScript("OnEnter", function(self)
        if not self.data then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(date("%A %b %d, %H:%M", self.data.t), 1, 1, 1)
        GameTooltip:AddLine(sightingText(self.data), nil, nil, nil, true)
        if self.data.mapID then GameTooltip:AddLine("Click to show on the world map", 0.4, 0.8, 1) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
end

local function initSightingRow(row, s)
    row.data = s
    row.entryKey = DV.currentKey
    row.when:SetText(FBL.TimeAgo(s.t))
    row.where:SetText(sightingText(s))
    row.by:SetText(s.by and ("by " .. FBL.ShortName(s.by)) or "")
    row.pin:SetDesaturated(not s.mapID)
end

function DV.Create(parent)
    local d = CreateFrame("Frame", nil, parent)
    d:SetAllPoints()

    -- empty state
    d.empty = CreateFrame("Frame", nil, d)
    d.empty:SetAllPoints()
    local skull = d.empty:CreateTexture(nil, "ARTWORK")
    skull:SetTexture(T.SKULL)
    skull:SetSize(72, 72)
    skull:SetPoint("CENTER", 0, 40)
    skull:SetAlpha(0.15)
    local et = W.Text(d.empty, "GameFontDisableLarge", "Select someone on the left")
    et:SetPoint("TOP", skull, "BOTTOM", 0, -12)

    local body = CreateFrame("Frame", nil, d)
    body:SetAllPoints()
    d.body = body

    -- header card
    local header = CreateFrame("Frame", nil, body)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(96)
    d.headerBg = T.Gradient(header, "BACKGROUND", { 0.2, 0.2, 0.25, 0.6 }, { 0.08, 0.08, 0.1, 0 })
    d.headerBg:SetAllPoints()

    local iconFrame = CreateFrame("Frame", nil, header, "BackdropTemplate")
    iconFrame:SetSize(66, 66)
    iconFrame:SetPoint("LEFT", 14, 0)
    T.Backdrop(iconFrame, { 0, 0, 0, 1 }, T.BORDER, 2)
    d.iconFrame = iconFrame
    d.icon = iconFrame:CreateTexture(nil, "ARTWORK")
    d.icon:SetPoint("TOPLEFT", 2, -2)
    d.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    d.race = header:CreateTexture(nil, "OVERLAY")
    d.race:SetSize(26, 26)
    d.race:SetPoint("BOTTOMRIGHT", iconFrame, 8, -8)

    d.name = header:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    d.name:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 14, -2)
    d.line2 = W.Text(header, "GameFontHighlight", "")
    d.line2:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -4)
    d.faction = header:CreateTexture(nil, "ARTWORK")
    d.faction:SetSize(18, 18)
    d.faction:SetPoint("TOPLEFT", d.line2, "BOTTOMLEFT", -2, -4)
    d.line3 = W.Text(header, "GameFontNormalSmall", "")
    d.line3:SetPoint("LEFT", d.faction, "RIGHT", 4, 0)

    d.severity = W.SeverityPicker(header, function() return d.entry and d.entry.severity or 1 end, function(v)
        if d.entry then FBL.SaveEntry({ name = d.entry.name, severity = v }) end
    end, 18)
    d.severity:SetPoint("TOPRIGHT", -90, -14)
    d.category = W.Dropdown(header, 170, function()
        local o = {}
        for _, c in ipairs(FBL.CATEGORIES) do o[#o + 1] = { value = c.key, label = ("|cff%s%s|r"):format(c.color, c.label) } end
        return o
    end, function() return d.entry and d.entry.category end, function(v)
        if d.entry then FBL.SaveEntry({ name = d.entry.name, category = v }) end
    end)
    d.category:SetPoint("TOPRIGHT", -14, -44)

    -- left column: why
    local why = W.Header(body, "Why they're here")
    why:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 14, -10)
    why.line:SetPoint("RIGHT", body, "LEFT", 310, 0)
    d.comment = W.TextArea(body, 300, 70, 1000)
    d.comment:SetPoint("TOPLEFT", why, "BOTTOMLEFT", 0, -8)
    d.tagsLabel = W.Text(body, "GameFontNormalSmall", "Tags")
    d.tagsLabel:SetPoint("TOPLEFT", d.comment, "BOTTOMLEFT", 0, -8)
    d.tags = W.EditBox(body, 147, 22, "pvp, stv, ...")
    d.tags:SetPoint("TOPLEFT", d.tagsLabel, "BOTTOMLEFT", 0, -4)
    d.tags:SetMaxLetters(200)
    d.alts = W.EditBox(body, 147, 22, "Alt1, Alt2")
    d.alts:SetPoint("LEFT", d.tags, "RIGHT", 6, 0)
    d.alts:SetMaxLetters(200)
    d.altsLabel = W.Text(body, "GameFontNormalSmall", "Known alts")
    d.altsLabel:SetPoint("BOTTOMLEFT", d.alts, "TOPLEFT", 0, 4)

    d.save = W.Button(body, "Save notes", 100, 22, "accent")
    d.save:SetPoint("TOPLEFT", d.tags, "BOTTOMLEFT", 0, -8)
    d.revert = W.Button(body, "Revert", 70, 22)
    d.revert:SetPoint("LEFT", d.save, "RIGHT", 6, 0)
    d.dirtyText = W.Text(body, "GameFontDisableSmall", "")
    d.dirtyText:SetPoint("LEFT", d.revert, "RIGHT", 8, 0)

    local function markDirty()
        if d.loading or not d.entry then return end
        local e = d.entry
        local dirty = (d.comment.edit:GetText() ~= (e.comment or ""))
            or (d.tags:GetText() ~= (e.tags or "")) or (d.alts:GetText() ~= (e.alts or ""))
        d.dirty = dirty
        if dirty then d.save:Enable(); d.revert:Enable() else d.save:Disable(); d.revert:Disable() end
        d.dirtyText:SetText(dirty and "|cffffd100unsaved changes|r" or "")
    end
    d.comment.edit:HookScript("OnTextChanged", markDirty)
    d.tags:HookScript("OnTextChanged", markDirty)
    d.alts:HookScript("OnTextChanged", markDirty)
    local function save()
        if not d.entry then return end
        FBL.SaveEntry({ name = d.entry.name, comment = d.comment.edit:GetText(), tags = d.tags:GetText(), alts = d.alts:GetText() })
        d.dirty = false
        DV.Show(d, d.entry, true)
    end
    d.save:SetScript("OnClick", save)
    d.tags:SetScript("OnEnterPressed", function(self) self:ClearFocus(); save() end)
    d.alts:SetScript("OnEnterPressed", function(self) self:ClearFocus(); save() end)
    d.revert:SetScript("OnClick", function() d.dirty = false; DV.Show(d, d.entry, true) end)

    -- right column: details
    local det = W.Header(body, "Profile")
    det:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 330, -10)
    d.stats = {}
    for i, def in ipairs(STAT_ROWS) do
        local k = W.Text(body, "GameFontDisableSmall", type(def[1]) == "function" and def[1]() or def[1])
        k:SetPoint("TOPLEFT", det, "BOTTOMLEFT", 0, -8 - (i - 1) * 16)
        local v = W.Text(body, "GameFontHighlightSmall", "")
        v:SetPoint("LEFT", k, "LEFT", 74, 0)
        v:SetPoint("RIGHT", body, "RIGHT", -12, 0)
        v:SetWordWrap(false)
        d.stats[i] = v
    end

    -- sightings
    local sh = W.Header(body, "Sightings")
    sh:SetPoint("TOPLEFT", d.save, "BOTTOMLEFT", 0, -14)
    d.sightCount = W.Text(body, "GameFontDisableSmall", "")
    d.sightCount:SetPoint("LEFT", sh, "RIGHT", 6, 0)
    sh.line:SetPoint("LEFT", d.sightCount, "RIGHT", 6, 0)
    d.sightings = W.List(body, 22, initSightingRow, createSightingRow)
    d.sightings:SetPoint("TOPLEFT", sh, "BOTTOMLEFT", 0, -6)
    d.sightings:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -26, 42)
    d.noSight = W.Text(body, "GameFontDisableSmall", "Not seen yet. Sightings are recorded when you (or a synced\nfriend) target, mouse over or see their nameplate.")
    d.noSight:SetPoint("TOPLEFT", d.sightings, "TOPLEFT", 4, -6)

    -- action bar
    d.mapBtn = W.Button(body, "Show on Map", 110, 24, "accent")
    d.mapBtn:SetPoint("BOTTOMLEFT", 12, 10)
    d.mapBtn:SetScript("OnClick", function()
        local s = FBL.LastSighting(d.entry)
        if s then FBL.ShowOnMap(d.entry.key, s) end
    end)
    d.shareBtn = W.Button(body, "Share Now", 90, 24)
    d.shareBtn:SetPoint("LEFT", d.mapBtn, "RIGHT", 6, 0)
    d.shareBtn:SetScript("OnClick", function()
        if d.entry then FBL.Comm.BroadcastEntry(d.entry); FBL.Print("Shared %s with your sync network.", FBL.ColoredName(d.entry)) end
    end)
    W.Tooltip(d.shareBtn, "Share now", "Re-broadcast this entry to your guild, group and sync channel.")
    d.whisperBtn = W.Button(body, "Whisper", 80, 24)
    d.whisperBtn:SetPoint("LEFT", d.shareBtn, "RIGHT", 6, 0)
    d.whisperBtn:SetScript("OnClick", function()
        if not d.entry then return end
        local tell = _G.ChatFrame_SendTell or (ChatFrameUtil and ChatFrameUtil.SendTell)
        if tell then tell(FBL.ShortName(d.entry.name)) end
    end)
    d.copyBtn = W.Button(body, "Copy Name", 90, 24)
    d.copyBtn:SetPoint("LEFT", d.whisperBtn, "RIGHT", 6, 0)
    d.copyBtn:SetScript("OnClick", function()
        if d.entry then W.TextPopup("Copy name (Ctrl+C)", d.entry.name) end
    end)
    d.removeBtn = W.Button(body, "Remove", 80, 24, "danger")
    d.removeBtn:SetPoint("BOTTOMRIGHT", -12, 10)
    d.removeBtn:SetScript("OnClick", function() if d.entry then FBL.ConfirmRemove(d.entry.key) end end)

    return d
end

function DV.Show(d, e, forceFields)
    if e and e.deleted then e = nil end
    d.empty:SetShown(not e)
    d.body:SetShown(e ~= nil)
    if not e then d.entry = nil return end
    local changedEntry = d.entry ~= e
    d.entry = e

    local r, g, b = FBL.ClassColor(e.classFile)
    T.SetClassIcon(d.icon, e.classFile)
    d.iconFrame:SetBackdropBorderColor(r, g, b, 1)
    T.SetRaceIcon(d.race, e.raceFile, e.sex)
    d.name:SetText(FBL.ShortName(e.name))
    d.name:SetTextColor(r, g, b)

    local l2 = {}
    l2[#l2 + 1] = e.level and ("Level " .. e.level) or "Level ?"
    if e.race then l2[#l2 + 1] = e.race end
    l2[#l2 + 1] = e.class or ""
    d.line2:SetText(table.concat(l2, " "))

    T.SetFactionIcon(d.faction, e.faction)
    local fc = T.FACTION_COLORS[e.faction or ""] or { 0.7, 0.7, 0.7 }
    local l3 = ("|cff%02x%02x%02x%s|r"):format(fc[1] * 255, fc[2] * 255, fc[3] * 255, e.faction or "Unknown faction")
    if e.guild then
        l3 = l3 .. "   |cff40ff40<" .. e.guild .. ">|r" .. (e.guildRank and (" |cff999999" .. e.guildRank .. "|r") or "")
    end
    d.line3:SetText(l3)
    d.line3:ClearAllPoints()
    if d.faction:IsShown() then d.line3:SetPoint("LEFT", d.faction, "RIGHT", 4, 0)
    else d.line3:SetPoint("TOPLEFT", d.line2, "BOTTOMLEFT", 0, -6) end

    d.severity:Refresh()
    d.category:Refresh()

    if changedEntry or forceFields or not d.dirty then
        d.loading = true
        d.comment.edit:SetText(e.comment or "")
        d.tags:SetText(e.tags or "")
        d.alts:SetText(e.alts or "")
        d.loading = false
        d.dirty = false
        d.save:Disable(); d.revert:Disable()
        d.dirtyText:SetText("")
    end

    for i, def in ipairs(STAT_ROWS) do
        d.stats[i]:SetText(def[2](e) or "|cff666666-|r")
    end

    local list = {}
    DV.currentKey = e.key
    for i, s in ipairs(e.sightings or {}) do list[i] = s end
    d.sightings:SetItems(list)
    d.noSight:SetShown(#list == 0)
    d.sightCount:SetText(#list > 0 and ("(" .. #list .. ")") or "")
    local last = list[1]
    if last and last.mapID then d.mapBtn:Enable() else d.mapBtn:Disable() end
    if FBL.opt.syncEnabled then d.shareBtn:Enable() else d.shareBtn:Disable() end
end

StaticPopupDialogs["FOREVER_BLACKLIST_REMOVE"] = {
    text = "Remove %s from your blacklist?",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(_, key) FBL.RemoveEntry(key) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function FBL.ConfirmRemove(key)
    local e = FBL.db.entries[key]
    if not e then return end
    if not FBL.opt.confirmDelete then FBL.RemoveEntry(key) return end
    local dialog = StaticPopup_Show("FOREVER_BLACKLIST_REMOVE", FBL.ColoredName(e))
    if dialog then dialog.data = key end
end
