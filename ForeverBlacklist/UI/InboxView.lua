-- Forever Blacklist: "Inbox" tab - entries shared by others awaiting review.
local _, FBL = ...

local T, W = FBL.Theme, FBL.Widgets
local View = {}
FBL.Views.inbox = View

local function createRow(row)
    row:SetHeight(64)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetTexture(T.WHITE)
    row.bg:SetPoint("TOPLEFT", 0, -2)
    row.bg:SetPoint("BOTTOMRIGHT", 0, 2)
    row.bg:SetVertexColor(1, 1, 1, 0.04)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(38, 38)
    row.icon:SetPoint("LEFT", 12, 0)
    row.name = W.Text(row, "GameFontNormalLarge", "")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 12, 2)
    row.info = W.Text(row, "GameFontDisableSmall", "")
    row.info:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
    row.reason = W.Text(row, "GameFontHighlightSmall", "")
    row.reason:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)
    row.reason:SetPoint("RIGHT", -200, 0)
    row.reason:SetWordWrap(false)
    row.from = W.Text(row, "GameFontDisableSmall", "")
    row.from:SetPoint("TOPLEFT", row.reason, "BOTTOMLEFT", 0, -3)
    row.accept = W.Button(row, "Accept", 80, 24, "accent")
    row.accept:SetPoint("RIGHT", -100, 0)
    row.reject = W.Button(row, "Reject", 80, 24, "danger")
    row.reject:SetPoint("RIGHT", -12, 0)
    row.trust = W.IconButton(row, "Interface\\FriendsFrame\\StatusIcon-Online", 14, "Trust this sender")
    row.trust:SetPoint("LEFT", row.from, "RIGHT", 6, 0)
end

local function findIndex(item)
    for i, it in ipairs(FBL.db.inbox) do if it == item then return i end end
end

local function initRow(row, item)
    local e = item.entry
    T.SetClassIcon(row.icon, e.classFile)
    row.name:SetText(FBL.ColoredName(e))
    local bits = {}
    if e.level then bits[#bits + 1] = "Lvl " .. e.level end
    if e.race then bits[#bits + 1] = e.race end
    if e.class then bits[#bits + 1] = e.class end
    if e.faction then bits[#bits + 1] = e.faction end
    row.info:SetText(table.concat(bits, " "))
    local cat = FBL.Category(e.category)
    local sev = FBL.SEVERITY_LABELS[e.severity or 1]
    row.reason:SetText(("|cff%s%s|r (%s)%s"):format(cat.color, cat.label, sev,
        (e.comment and e.comment ~= "") and (' - "' .. e.comment .. '"') or ""))
    local trusted = FBL.IsTrusted(item.from)
    row.from:SetText(("Shared by %s%s, %s"):format(FBL.ShortName(item.from),
        trusted and " |cff40ff40(trusted)|r" or "", FBL.TimeAgo(item.receivedAt)))
    row.trust:SetShown(not trusted and item.from ~= "Import")
    row.accept:SetScript("OnClick", function() local i = findIndex(item); if i then FBL.AcceptInbox(i) end end)
    row.reject:SetScript("OnClick", function() local i = findIndex(item); if i then FBL.RejectInbox(i) end end)
    row.trust:SetScript("OnClick", function()
        FBL.SetTrusted(item.from, true)
        FBL.Print("%s is now trusted. Their future shares can skip review if you set Accept from: Trusted.", FBL.ShortName(item.from))
    end)
end

function View.Create(f)
    local top = W.Panel(f, { 0.075, 0.075, 0.09, 0.95 })
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetHeight(60)
    local title = W.Text(top, "GameFontNormalLarge", "Shared with you")
    title:SetPoint("TOPLEFT", 14, -12)
    f.sub = W.Text(top, "GameFontDisableSmall", "")
    f.sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    local all = W.Button(top, "Accept All", 100, 24, "accent")
    all:SetPoint("RIGHT", -120, 0)
    all:SetScript("OnClick", FBL.AcceptAllInbox)
    local none = W.Button(top, "Reject All", 100, 24, "danger")
    none:SetPoint("RIGHT", -12, 0)
    none:SetScript("OnClick", function() while #FBL.db.inbox > 0 do FBL.RejectInbox(1) end end)
    f.allBtn, f.noneBtn = all, none

    local panel = W.Panel(f, { 0.075, 0.075, 0.09, 0.95 })
    panel:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -10)
    panel:SetPoint("BOTTOMRIGHT")
    f.list = W.List(panel, 64, initRow, createRow)
    f.list:SetPoint("TOPLEFT", 8, -8)
    f.list:SetPoint("BOTTOMRIGHT", -24, 8)
    f.empty = W.Text(panel, "GameFontDisable", "Nothing to review.\n\nWhen someone using Forever Blacklist shares a new entry\nit will wait here until you accept it (see Options > Sync).")
    f.empty:SetJustifyH("CENTER")
    f.empty:SetPoint("CENTER")
end

function View.Refresh(f)
    local n = #FBL.db.inbox
    f.list:SetItems(FBL.db.inbox)
    f.empty:SetShown(n == 0)
    f.sub:SetText(FBL.opt.reviewIncoming
        and ("%d waiting. Accepted entries join your blacklist; rejected ones are ignored unless updated."):format(n)
        or "Review is off - shared entries are added automatically.")
    if n > 0 then f.allBtn:Enable(); f.noneBtn:Enable() else f.allBtn:Disable(); f.noneBtn:Disable() end
end
