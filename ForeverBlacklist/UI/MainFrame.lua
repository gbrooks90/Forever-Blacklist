-- Forever Blacklist: main window shell (title bar, tabs, view switching).
local _, FBL = ...

local T, W = FBL.Theme, FBL.Widgets
FBL.Views = {}

local TABS = {
    { key = "list",    label = "Blacklist" },
    { key = "inbox",   label = "Inbox" },
    { key = "sync",    label = "Sync" },
    { key = "options", label = "Options" },
}

local frame

local function savePosition()
    local point, _, rel, x, y = frame:GetPoint(1)
    FBL.db.window.point, FBL.db.window.rel, FBL.db.window.x, FBL.db.window.y = point, rel, x, y
end

local function createTab(parent, info, index)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(110, 30)
    b.text = W.Text(b, "GameFontHighlight", info.label)
    b.text:SetPoint("CENTER")
    b.badge = CreateFrame("Frame", nil, b, "BackdropTemplate")
    T.Backdrop(b.badge, T.ACCENT, T.ACCENT)
    b.badge:SetSize(18, 14)
    b.badge:SetPoint("LEFT", b.text, "RIGHT", 4, 0)
    b.badge.text = W.Text(b.badge, "GameFontHighlightSmall", "")
    b.badge.text:SetPoint("CENTER")
    b.badge:Hide()
    b.underline = b:CreateTexture(nil, "ARTWORK")
    b.underline:SetTexture(T.WHITE)
    b.underline:SetHeight(2)
    b.underline:SetPoint("BOTTOMLEFT", 8, 0)
    b.underline:SetPoint("BOTTOMRIGHT", -8, 0)
    b.underline:SetVertexColor(T.Color(T.ACCENT))
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(T.WHITE)
    hl:SetAllPoints()
    hl:SetVertexColor(1, 1, 1, 0.04)
    b:SetPoint("LEFT", (index - 1) * 112 + 10, 0)
    b.key = info.key
    b:SetScript("OnClick", function() FBL.ShowView(info.key) PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB or 841) end)
    return b
end

local function updateBadges()
    if not frame then return end
    local n = #FBL.db.inbox
    local tab = frame.tabs.inbox
    tab.badge:SetShown(n > 0)
    tab.badge.text:SetText(n > 99 and "99+" or tostring(n))
    tab.badge:SetWidth(math.max(18, tab.badge.text:GetStringWidth() + 8))
    frame.count:SetText(("%d blacklisted"):format(FBL.CountEntries()))
end

local function updateSyncDot()
    if not frame then return end
    local o = FBL.opt
    local recent = 0
    for _, p in pairs(FBL.db.peers) do
        if (p.lastSeen or 0) > FBL.Now() - 900 then recent = recent + 1 end
    end
    if not o.syncEnabled then
        frame.syncDot:SetVertexColor(0.5, 0.5, 0.5)
        frame.syncText:SetText("Sync off")
    elseif recent > 0 then
        frame.syncDot:SetVertexColor(0.3, 0.9, 0.4)
        frame.syncText:SetText(("%d peer%s online"):format(recent, recent == 1 and "" or "s"))
    else
        frame.syncDot:SetVertexColor(0.95, 0.75, 0.2)
        frame.syncText:SetText("No peers yet")
    end
end

local function create()
    frame = CreateFrame("Frame", "ForeverBlacklistFrame", UIParent, "BackdropTemplate")
    frame:SetSize(920, 580)
    T.Backdrop(frame, T.BG, { 0, 0, 0, 1 })
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) if not FBL.opt.windowLocked then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePosition() end)
    tinsert(UISpecialFrames, "ForeverBlacklistFrame")
    local pos = FBL.db.window
    if pos.point then
        frame:SetPoint(pos.point, UIParent, pos.rel or pos.point, pos.x or 0, pos.y or 0)
    else
        frame:SetPoint("CENTER")
    end
    frame:SetScale(FBL.opt.windowScale or 1)

    -- outer glow border
    local outer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    outer:SetPoint("TOPLEFT", -1, 1)
    outer:SetPoint("BOTTOMRIGHT", 1, -1)
    outer:SetFrameLevel(frame:GetFrameLevel())
    T.Backdrop(outer, { 0, 0, 0, 0 }, { T.ACCENT[1], T.ACCENT[2], T.ACCENT[3], 0.6 })

    -- title bar
    local title = CreateFrame("Frame", nil, frame)
    title:SetPoint("TOPLEFT", 1, -1)
    title:SetPoint("TOPRIGHT", -1, -1)
    title:SetHeight(54)
    local g = T.Gradient(title, "BACKGROUND", { 0.32, 0.05, 0.09, 1 }, { 0.08, 0.03, 0.04, 1 })
    g:SetAllPoints()
    local sep = title:CreateTexture(nil, "ARTWORK")
    sep:SetTexture(T.WHITE)
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT")
    sep:SetPoint("BOTTOMRIGHT")
    sep:SetVertexColor(T.ACCENT[1], T.ACCENT[2], T.ACCENT[3], 0.8)

    local logoRing = title:CreateTexture(nil, "ARTWORK")
    logoRing:SetSize(40, 40)
    logoRing:SetPoint("LEFT", 12, 0)
    logoRing:SetTexture(T.LOGO)
    logoRing:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local logoBorder = CreateFrame("Frame", nil, title, "BackdropTemplate")
    logoBorder:SetPoint("TOPLEFT", logoRing, -1, 1)
    logoBorder:SetPoint("BOTTOMRIGHT", logoRing, 1, -1)
    T.Backdrop(logoBorder, { 0, 0, 0, 0 }, T.ACCENT)
    local skull = title:CreateTexture(nil, "OVERLAY")
    skull:SetSize(18, 18)
    skull:SetPoint("BOTTOMRIGHT", logoRing, 5, -5)
    skull:SetTexture(T.SKULL)

    local name = title:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    name:SetPoint("TOPLEFT", logoRing, "TOPRIGHT", 12, -1)
    name:SetText("|cffe0324bFOREVER|r BLACKLIST")
    frame.count = W.Text(title, "GameFontDisableSmall", "")
    frame.count:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 1, -3)

    local close = CreateFrame("Button", nil, title, "UIPanelCloseButtonNoScripts")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- sync status pill
    local pill = CreateFrame("Button", nil, title, "BackdropTemplate")
    pill:SetSize(140, 22)
    pill:SetPoint("RIGHT", close, "LEFT", -10, -10)
    T.Backdrop(pill, { 0, 0, 0, 0.45 }, T.BORDER)
    frame.syncDot = pill:CreateTexture(nil, "ARTWORK")
    frame.syncDot:SetTexture(T.WHITE)
    frame.syncDot:SetSize(8, 8)
    frame.syncDot:SetPoint("LEFT", 8, 0)
    frame.syncText = W.Text(pill, "GameFontHighlightSmall", "")
    frame.syncText:SetPoint("LEFT", frame.syncDot, "RIGHT", 6, 0)
    pill:SetScript("OnClick", function() FBL.ShowView("sync") end)

    -- tab strip
    local strip = CreateFrame("Frame", nil, frame)
    strip:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, 0)
    strip:SetHeight(32)
    local sbg = strip:CreateTexture(nil, "BACKGROUND")
    sbg:SetAllPoints()
    sbg:SetTexture(T.WHITE)
    sbg:SetVertexColor(0.07, 0.07, 0.09, 1)
    frame.tabs = {}
    for i, info in ipairs(TABS) do frame.tabs[info.key] = createTab(strip, info, i) end

    local quickAdd = W.Button(strip, "+ Add Target", 110, 22, "accent")
    quickAdd:SetPoint("RIGHT", -10, 0)
    quickAdd:SetScript("OnClick", function() FBL.ShowAddDialog({ unit = "target" }) end)
    W.Tooltip(quickAdd, "Add your current target", "Captures race, class, level, faction, guild and more.")
    frame.quickAdd = quickAdd

    -- content area
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 10, -10)
    content:SetPoint("BOTTOMRIGHT", -10, 10)
    frame.content = content
    frame.views = {}

    frame:SetScript("OnShow", function()
        updateBadges(); updateSyncDot()
        PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN or 839)
    end)
    frame:SetScript("OnHide", function() PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE or 840) end)
    frame:Hide()
end

function FBL.GetMainFrame()
    if not frame then create() end
    return frame
end

function FBL.ShowView(key)
    local f = FBL.GetMainFrame()
    for k, tab in pairs(f.tabs) do
        local sel = (k == key)
        tab.underline:SetShown(sel)
        tab.text:SetTextColor(sel and 1 or T.TEXT_DIM[1], sel and 1 or T.TEXT_DIM[2], sel and 1 or T.TEXT_DIM[3])
    end
    for k, v in pairs(f.views) do v:SetShown(k == key) end
    if not f.views[key] then
        local def = FBL.Views[key]
        if def then
            local v = CreateFrame("Frame", nil, f.content)
            v:SetAllPoints()
            def.Create(v)
            v.def = def
            f.views[key] = v
        end
    end
    local v = f.views[key]
    if v then
        v:Show()
        if v.def.Refresh then v.def.Refresh(v) end
    end
    f.current = key
    f:Show()
end

function FBL.Toggle()
    local f = FBL.GetMainFrame()
    if f:IsShown() then f:Hide() else FBL.ShowView(f.current or "list") end
end

function FBL.RefreshCurrentView()
    if not frame or not frame:IsShown() then return end
    local v = frame.views[frame.current]
    if v and v.def.Refresh then v.def.Refresh(v) end
    updateBadges()
    updateSyncDot()
end

function FBL.ApplyWindowScale()
    if frame then frame:SetScale(FBL.opt.windowScale or 1) end
end

--- Opens the window on a specific entry.
function FBL.OpenEntry(key)
    FBL.selectedKey = key
    FBL.ShowView("list")
end

-- live refresh, throttled
local pending
local function scheduleRefresh()
    if pending then return end
    pending = true
    C_Timer.After(0.25, function() pending = false; FBL.RefreshCurrentView() end)
end
FBL:On("ENTRY_CHANGED", scheduleRefresh)
FBL:On("INBOX_CHANGED", scheduleRefresh)
FBL:On("PEERS_CHANGED", scheduleRefresh)
FBL:On("SYNC_LOG", scheduleRefresh)
FBL:On("TRUST_CHANGED", scheduleRefresh)
