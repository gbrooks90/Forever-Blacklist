-- Forever Blacklist: add / edit dialog.
local _, FBL = ...

local T, W = FBL.Theme, FBL.Widgets
local dlg
local state = {}

local function updatePreview()
    local info = state.info
    T.SetClassIcon(dlg.icon, info and info.classFile)
    if info then
        local bits = {}
        if info.level then bits[#bits + 1] = "Level " .. info.level end
        if info.race then bits[#bits + 1] = info.race end
        if info.class then bits[#bits + 1] = info.class end
        local _, _, _, hex = FBL.ClassColor(info.classFile)
        dlg.preview:SetText(("|c%s%s|r\n%s%s"):format(hex or "ffffffff", info.name or "",
            table.concat(bits, " "), info.guild and ("  |cff40ff40<" .. info.guild .. ">|r") or ""))
    else
        dlg.preview:SetText("|cff888888No details yet - they'll be filled in\nautomatically the next time you see them.|r")
    end
    local existing = FBL.IsBlacklisted(dlg.name:GetText())
    dlg.existsNote:SetText(existing and "|cffffd100Already listed - saving will update the entry.|r" or "")
end

local function useUnit(unit)
    local info = FBL.ReadUnit(unit)
    if not info then return false end
    state.info = info
    local full = FBL.NormalizeName(info.name, info.realm)
    dlg.name:SetText(FBL.ShortName(full))
    state.realm = info.realm
    local existing = FBL.IsBlacklisted(full)
    if existing then
        state.category = existing.category
        state.severity = existing.severity
        dlg.comment.edit:SetText(existing.comment or "")
        dlg.tags:SetText(existing.tags or "")
    end
    dlg.category:Refresh()
    dlg.severity:Refresh()
    updatePreview()
    return true
end

local function create()
    dlg = CreateFrame("Frame", "ForeverBlacklistAddDialog", UIParent, "BackdropTemplate")
    dlg:SetSize(420, 440)
    dlg:SetPoint("CENTER", 0, 40)
    dlg:SetFrameStrata("DIALOG")
    dlg:SetToplevel(true)
    T.Backdrop(dlg, T.BG, T.ACCENT)
    dlg:EnableMouse(true)
    dlg:SetMovable(true)
    dlg:RegisterForDrag("LeftButton")
    dlg:SetScript("OnDragStart", dlg.StartMoving)
    dlg:SetScript("OnDragStop", dlg.StopMovingOrSizing)
    tinsert(UISpecialFrames, "ForeverBlacklistAddDialog")

    local head = CreateFrame("Frame", nil, dlg)
    head:SetPoint("TOPLEFT", 1, -1)
    head:SetPoint("TOPRIGHT", -1, -1)
    head:SetHeight(40)
    T.Gradient(head, "BACKGROUND", { 0.32, 0.05, 0.09, 1 }, { 0.08, 0.03, 0.04, 1 }):SetAllPoints()
    local skull = head:CreateTexture(nil, "ARTWORK")
    skull:SetTexture(T.SKULL)
    skull:SetSize(22, 22)
    skull:SetPoint("LEFT", 12, 0)
    dlg.title = W.Text(head, "GameFontNormalLarge", "Add to Blacklist")
    dlg.title:SetPoint("LEFT", skull, "RIGHT", 8, 0)
    local close = CreateFrame("Button", nil, head, "UIPanelCloseButtonNoScripts")
    close:SetPoint("RIGHT", -4, 0)
    close:SetScript("OnClick", function() dlg:Hide() end)

    local nameLabel = W.Text(dlg, "GameFontNormalSmall", "Character name (Name or Name-Realm)")
    nameLabel:SetPoint("TOPLEFT", 16, -54)
    dlg.name = W.EditBox(dlg, 270, 26, "Name")
    dlg.name:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -4)
    dlg.name:SetMaxLetters(60)
    dlg.name:HookScript("OnTextChanged", function(_, user)
        if user then state.info = nil; state.realm = nil end
        updatePreview()
    end)
    local tgt = W.Button(dlg, "Use Target", 104, 26)
    tgt:SetPoint("LEFT", dlg.name, "RIGHT", 6, 0)
    tgt:SetScript("OnClick", function()
        if not useUnit("target") then FBL.Print("You need a player targeted.") end
    end)

    local card = W.Panel(dlg, { 0.09, 0.09, 0.11, 1 })
    card:SetPoint("TOPLEFT", dlg.name, "BOTTOMLEFT", 0, -10)
    card:SetSize(388, 56)
    dlg.icon = card:CreateTexture(nil, "ARTWORK")
    dlg.icon:SetSize(40, 40)
    dlg.icon:SetPoint("LEFT", 8, 0)
    dlg.preview = W.Text(card, "GameFontHighlightSmall", "")
    dlg.preview:SetPoint("LEFT", dlg.icon, "RIGHT", 10, 0)
    dlg.preview:SetPoint("RIGHT", -8, 0)
    dlg.existsNote = W.Text(dlg, "GameFontNormalSmall", "")
    dlg.existsNote:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -4)

    local catLabel = W.Text(dlg, "GameFontNormalSmall", "Reason")
    catLabel:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -22)
    dlg.category = W.Dropdown(dlg, 180, function()
        local o = {}
        for _, c in ipairs(FBL.CATEGORIES) do o[#o + 1] = { value = c.key, label = ("|cff%s%s|r"):format(c.color, c.label) } end
        return o
    end, function() return state.category end, function(v) state.category = v end)
    dlg.category:SetPoint("TOPLEFT", catLabel, "BOTTOMLEFT", 0, -4)
    local sevLabel = W.Text(dlg, "GameFontNormalSmall", "Severity")
    sevLabel:SetPoint("LEFT", catLabel, "LEFT", 200, 0)
    dlg.severity = W.SeverityPicker(dlg, function() return state.severity end, function(v) state.severity = v end, 18)
    dlg.severity:SetPoint("TOPLEFT", sevLabel, "BOTTOMLEFT", 0, -8)

    local cLabel = W.Text(dlg, "GameFontNormalSmall", "What happened? (shared with your sync network)")
    cLabel:SetPoint("TOPLEFT", dlg.category, "BOTTOMLEFT", 0, -12)
    dlg.comment = W.TextArea(dlg, 388, 90, 1000)
    dlg.comment:SetPoint("TOPLEFT", cLabel, "BOTTOMLEFT", 0, -4)
    local tLabel = W.Text(dlg, "GameFontNormalSmall", "Tags")
    tLabel:SetPoint("TOPLEFT", dlg.comment, "BOTTOMLEFT", 0, -8)
    dlg.tags = W.EditBox(dlg, 388, 22, "Optional: pvp, dungeon, gold, ...")
    dlg.tags:SetPoint("TOPLEFT", tLabel, "BOTTOMLEFT", 0, -4)
    dlg.tags:SetMaxLetters(200)

    local save = W.Button(dlg, "Blacklist", 120, 28, "accent")
    save:SetPoint("BOTTOMRIGHT", -16, 14)
    local cancel = W.Button(dlg, "Cancel", 90, 28)
    cancel:SetPoint("RIGHT", save, "LEFT", -8, 0)
    cancel:SetScript("OnClick", function() dlg:Hide() end)
    save:SetScript("OnClick", function()
        local name = dlg.name:GetText()
        if name == "" then FBL.Print("Enter a name first.") return end
        local fields = {
            name = name, realm = state.realm, category = state.category, severity = state.severity,
            comment = dlg.comment.edit:GetText(), tags = dlg.tags:GetText(),
        }
        local full = FBL.NormalizeName(name, state.realm)
        if full == FBL.playerName then FBL.Print("You can't blacklist yourself!") return end
        if state.info then
            for _, f in ipairs(FBL.INFO_FIELDS) do fields[f] = state.info[f] end
        end
        local e, isNew = FBL.SaveEntry(fields)
        if not e then FBL.Print("Could not save that name.") return end
        -- if we're looking at them right now, record a sighting immediately
        if state.unit and FBL.Detection and UnitExists(state.unit) and FBL.Safe(UnitIsVisible(state.unit)) then
            FBL.Detection.Spotted(e, state.unit, nil, true)
        end
        FBL.Print("%s %s (%s).", FBL.ColoredName(e), isNew and "blacklisted" or "updated", FBL.Category(e.category).label)
        PlaySound(SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE or 857)
        dlg:Hide()
        FBL.selectedKey = e.key
        FBL.RefreshCurrentView()
    end)
    dlg.saveBtn = save
end

--- opts: { name, realm, unit }
function FBL.ShowAddDialog(opts)
    if not dlg then create() end
    opts = opts or {}
    wipe(state)
    state.category, state.severity, state.unit = "OTHER", 3, opts.unit
    dlg.comment.edit:SetText("")
    dlg.tags:SetText("")
    dlg.name:SetText("")
    local ok = opts.unit and useUnit(opts.unit)
    if not ok then
        if opts.unit == "target" and not opts.name then
            FBL.Print("No player targeted - enter a name instead.")
        end
        if opts.name then
            local full = FBL.NormalizeName(opts.name, opts.realm)
            dlg.name:SetText(FBL.ShortName(full))
            state.realm = opts.realm
            local existing = FBL.IsBlacklisted(full)
            if existing then
                state.category, state.severity = existing.category, existing.severity
                dlg.comment.edit:SetText(existing.comment or "")
                dlg.tags:SetText(existing.tags or "")
            end
        end
        updatePreview()
    end
    if opts.category then state.category = opts.category end
    if opts.comment then dlg.comment.edit:SetText(opts.comment) end
    dlg.category:Refresh()
    dlg.severity:Refresh()
    dlg.title:SetText(FBL.IsBlacklisted(dlg.name:GetText(), state.realm) and "Edit Blacklist Entry" or "Add to Blacklist")
    dlg:Show()
    if dlg.name:GetText() == "" then dlg.name:SetFocus() else dlg.comment.edit:SetFocus() end
end
