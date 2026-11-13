-- Forever Blacklist: the "Blacklist" tab (searchable list + detail panel).
local _, FBL = ...

local T, W = FBL.Theme, FBL.Widgets
local View = {}
FBL.Views.list = View

local state = { search = "", sort = "recent", category = nil }

local SORTS = {
    { value = "recent",   label = "Recently updated" },
    { value = "seen",     label = "Last seen" },
    { value = "severity", label = "Severity" },
    { value = "name",     label = "Name" },
    { value = "level",    label = "Level" },
}

local function categoryOptions()
    local opts = { { value = false, label = "All reasons" } }
    for _, c in ipairs(FBL.CATEGORIES) do
        opts[#opts + 1] = { value = c.key, label = ("|cff%s%s|r"):format(c.color, c.label) }
    end
    return opts
end

local function createRow(row)
    row:SetHeight(46)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetTexture(T.WHITE)
    row.bg:SetPoint("TOPLEFT", 0, -1)
    row.bg:SetPoint("BOTTOMRIGHT", 0, 1)
    row.sel = row:CreateTexture(nil, "BORDER")
    row.sel:SetTexture(T.WHITE)
    row.sel:SetPoint("TOPLEFT", 0, -1)
    row.sel:SetPoint("BOTTOMLEFT", 0, 1)
    row.sel:SetWidth(3)
    row.sel:SetVertexColor(T.Color(T.ACCENT))
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(T.WHITE)
    hl:SetAllPoints()
    hl:SetVertexColor(1, 1, 1, 0.05)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(32, 32)
    row.icon:SetPoint("LEFT", 10, 0)
    row.faction = row:CreateTexture(nil, "OVERLAY")
    row.faction:SetSize(16, 16)
    row.faction:SetPoint("BOTTOMRIGHT", row.icon, 5, -5)

    row.name = W.Text(row, "GameFontNormal", "")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, 0)
    row.sub = W.Text(row, "GameFontDisableSmall", "")
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.cat = W.Text(row, "GameFontNormalSmall", "")
    row.cat:SetPoint("TOPRIGHT", -8, -8)
    row.cat:SetJustifyH("RIGHT")
    row.seen = W.Text(row, "GameFontDisableSmall", "")
    row.seen:SetPoint("BOTTOMRIGHT", -8, 8)
    row.seen:SetJustifyH("RIGHT")
    row.skulls = {}
    for i = 1, 5 do
        local s = row:CreateTexture(nil, "ARTWORK")
        s:SetSize(10, 10)
        s:SetTexture(T.SKULL)
        s:SetPoint("BOTTOMRIGHT", row.seen, "BOTTOMLEFT", -6 - (5 - i) * 11, 1)
        row.skulls[i] = s
    end
    row:SetScript("OnClick", function(self)
        FBL.selectedKey = self.key
        View.Refresh(View.frame)
    end)
end

local function initRow(row, e)
    row.key = e.key
    local idx = (row.GetElementDataIndex and row:GetElementDataIndex()) or 0
    row.bg:SetVertexColor(1, 1, 1, idx % 2 == 0 and 0.025 or 0.05)
    row.sel:SetShown(FBL.selectedKey == e.key)
    T.SetClassIcon(row.icon, e.classFile)
    T.SetFactionIcon(row.faction, e.faction)
    row.name:SetText(FBL.ColoredName(e))
    local bits = {}
    if e.level then bits[#bits + 1] = tostring(e.level) end
    if e.race then bits[#bits + 1] = e.race end
    if e.class then bits[#bits + 1] = e.class end
    if e.guild then bits[#bits + 1] = "<" .. e.guild .. ">" end
    row.sub:SetText(#bits > 0 and table.concat(bits, " ") or "Details unknown - target them to fill in")
    local cat = FBL.Category(e.category)
    row.cat:SetText(("|cff%s%s|r"):format(cat.color, cat.label))
    local last = FBL.LastSighting(e)
    row.seen:SetText(last and FBL.TimeAgo(last.t) or "never seen")
    local c = FBL.SEVERITY_COLORS[e.severity or 1]
    for i, s in ipairs(row.skulls) do
        if i <= (e.severity or 1) then s:SetVertexColor(c[1], c[2], c[3]); s:SetAlpha(1)
        else s:SetVertexColor(1, 1, 1); s:SetAlpha(0.12) end
    end
end

function View.Create(f)
    View.frame = f
    local left = W.Panel(f, { 0.075, 0.075, 0.09, 0.95 })
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(330)

    local search = W.EditBox(left, 310, 26, "Search name, guild, reason, notes...")
    search:SetPoint("TOPLEFT", 10, -10)
    local mag = search:CreateTexture(nil, "OVERLAY")
    mag:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    mag:SetSize(14, 14)
    mag:SetPoint("RIGHT", -8, -1)
    search:SetScript("OnTextChanged", function(self)
        if self.placeholder then self.placeholder:SetShown(self:GetText() == "") end
        state.search = self:GetText()
        View.RefreshList()
    end)

    local sort = W.Dropdown(left, 150, SORTS, function() return state.sort end, function(v)
        state.sort = v; View.RefreshList()
    end)
    sort:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)
    local cat = W.Dropdown(left, 150, categoryOptions, function() return state.category or false end, function(v)
        state.category = v or nil; View.RefreshList()
    end)
    cat:SetPoint("LEFT", sort, "RIGHT", 10, 0)

    local list = W.List(left, 46, initRow, createRow)
    list:SetPoint("TOPLEFT", sort, "BOTTOMLEFT", 0, -8)
    list:SetPoint("BOTTOMRIGHT", -22, 44)
    View.list = list

    f.empty = W.Text(left, "GameFontDisable", "No one here yet.\n\nTarget a player and click\n|cffe0324b+ Add Target|r, or right-click\nany player's name.")
    f.empty:SetPoint("CENTER", list, "CENTER")
    f.empty:SetJustifyH("CENTER")

    local add = W.Button(left, "New Entry", 100, 24, "accent")
    add:SetPoint("BOTTOMLEFT", 10, 10)
    add:SetScript("OnClick", function() FBL.ShowAddDialog({}) end)
    local export = W.Button(left, "Export", 70, 24)
    export:SetPoint("LEFT", add, "RIGHT", 6, 0)
    export:SetScript("OnClick", function()
        local str, n = FBL.ExportString()
        W.TextPopup(("Export - %d entries (Ctrl+C to copy)"):format(n), str)
    end)
    local import = W.Button(left, "Import", 70, 24)
    import:SetPoint("LEFT", export, "RIGHT", 6, 0)
    import:SetScript("OnClick", function()
        W.TextPopup("Import - paste an export string", "", function(text)
            local counts, err = FBL.ImportString(text)
            if counts then
                FBL.Print("Imported: %d new, %d updated.", counts.added, counts.updated)
            else
                FBL.Print("|cffff6060Import failed:|r %s", tostring(err))
            end
        end, "Import")
    end)
    f.total = W.Text(left, "GameFontDisableSmall", "")
    f.total:SetPoint("BOTTOMRIGHT", -10, 16)
    f.total:SetJustifyH("RIGHT")

    local right = W.Panel(f, { 0.075, 0.075, 0.09, 0.95 })
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0)
    right:SetPoint("BOTTOMRIGHT")
    f.detail = FBL.DetailView.Create(right)
end

function View.RefreshList()
    local f = View.frame
    if not f then return end
    local items = FBL.QueryEntries(state.search, state.sort, { category = state.category })
    View.list:SetItems(items)
    f.empty:SetShown(#items == 0)
    f.total:SetText(("%d shown"):format(#items))
    if not FBL.selectedKey and items[1] then FBL.selectedKey = items[1].key end
    return items
end

function View.Refresh(f)
    View.RefreshList()
    FBL.DetailView.Show(f.detail, FBL.selectedKey and FBL.db.entries[FBL.selectedKey])
end
