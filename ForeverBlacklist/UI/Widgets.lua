-- Forever Blacklist: styled widget factory.
local _, FBL = ...

local T = FBL.Theme
local W = {}
FBL.Widgets = W

function W.Panel(parent, bg, border)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    T.Backdrop(f, bg or T.BG_LIGHT, border)
    return f
end

function W.Text(parent, font, text, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    if text then fs:SetText(text) end
    if r then fs:SetTextColor(r, g, b) end
    fs:SetJustifyH("LEFT")
    return fs
end

function W.Header(parent, text)
    local fs = W.Text(parent, "GameFontNormal", text:upper())
    fs:SetTextColor(T.ACCENT[1], T.ACCENT[2], T.ACCENT[3])
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture(T.WHITE)
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 6, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -12, 0)
    line:SetVertexColor(T.ACCENT[1], T.ACCENT[2], T.ACCENT[3], 0.35)
    fs.line = line
    return fs
end

local function tooltipFor(widget, title, body)
    if not title then return end
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        if body then GameTooltip:AddLine(body, nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", GameTooltip_Hide)
end
W.Tooltip = tooltipFor

--- Flat button. style: "accent" | "danger" | nil
function W.Button(parent, text, width, height, style)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width or 100, height or 24)
    local bg = (style == "accent" and { 0.55, 0.10, 0.17, 0.95 })
        or (style == "danger" and { 0.30, 0.06, 0.06, 0.95 })
        or { 0.16, 0.16, 0.20, 0.95 }
    local border = (style == "accent" and T.ACCENT) or (style == "danger" and { 0.7, 0.15, 0.15 }) or T.BORDER
    T.Backdrop(b, bg, border)
    b.bgColor, b.borderColor = bg, border
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(text or "")
    b:SetFontString(b.text)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(T.WHITE)
    hl:SetPoint("TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:SetVertexColor(1, 1, 1, 0.07)
    b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self.text:SetPoint("CENTER", 1, -1) end end)
    b:SetScript("OnMouseUp", function(self) self.text:SetPoint("CENTER") end)
    hooksecurefunc(b, "Disable", function(self)
        self.text:SetTextColor(0.5, 0.5, 0.5)
        self:SetBackdropColor(0.12, 0.12, 0.14, 0.9)
        self:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)
    end)
    hooksecurefunc(b, "Enable", function(self)
        self.text:SetTextColor(1, 1, 1)
        self:SetBackdropColor(T.Color(self.bgColor))
        self:SetBackdropBorderColor(T.Color(self.borderColor))
    end)
    return b
end

function W.IconButton(parent, icon, size, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size or 20, size or 20)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(icon)
    b:SetHighlightTexture(icon, "ADD")
    b:GetHighlightTexture():SetAlpha(0.4)
    tooltipFor(b, tip)
    return b
end

function W.EditBox(parent, width, height, placeholder)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width or 160, height or 24)
    T.Backdrop(box, { 0.03, 0.03, 0.04, 0.95 }, T.BORDER)
    box:SetFontObject("ChatFontNormal")
    box:SetTextInsets(8, 8, 0, 0)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    box:HookScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(T.Color(T.ACCENT)) end)
    box:HookScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(T.Color(T.BORDER)) end)
    if placeholder then
        local ph = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        ph:SetPoint("LEFT", 9, 0)
        ph:SetText(placeholder)
        box.placeholder = ph
        box:HookScript("OnTextChanged", function(self)
            ph:SetShown(self:GetText() == "")
        end)
    end
    return box
end

--- Multi-line scrolling text box. Returns container; container.edit is the EditBox.
function W.TextArea(parent, width, height, maxLetters)
    local holder = W.Panel(parent, { 0.03, 0.03, 0.04, 0.95 })
    holder:SetSize(width, height)
    local sf = CreateFrame("ScrollFrame", nil, holder, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 6, -6)
    sf:SetPoint("BOTTOMRIGHT", -24, 6)
    local edit = CreateFrame("EditBox", nil, sf)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(width - 34)
    edit:SetMaxLetters(maxLetters or 0)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    edit:SetScript("OnCursorChanged", function(self, _, y, _, h)
        local vs, height2 = sf:GetVerticalScroll(), sf:GetHeight()
        y = -y
        if y < vs then sf:SetVerticalScroll(y)
        elseif y + h > vs + height2 then sf:SetVerticalScroll(y + h - height2) end
    end)
    sf:SetScrollChild(edit)
    holder:EnableMouse(true)
    holder:SetScript("OnMouseDown", function() edit:SetFocus() end)
    edit:HookScript("OnEditFocusGained", function() holder:SetBackdropBorderColor(T.Color(T.ACCENT)) end)
    edit:HookScript("OnEditFocusLost", function() holder:SetBackdropBorderColor(T.Color(T.BORDER)) end)
    holder.edit = edit
    holder.scroll = sf
    return holder
end

function W.Check(parent, label, get, set, tip)
    local c = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
    c:SetSize(18, 18)
    T.Backdrop(c, { 0.03, 0.03, 0.04, 1 }, T.BORDER)
    local mark = c:CreateTexture(nil, "ARTWORK")
    mark:SetTexture(T.WHITE)
    mark:SetPoint("TOPLEFT", 4, -4)
    mark:SetPoint("BOTTOMRIGHT", -4, 4)
    mark:SetVertexColor(T.Color(T.ACCENT))
    c:SetCheckedTexture(mark)
    local hl = c:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(T.WHITE)
    hl:SetAllPoints()
    hl:SetVertexColor(1, 1, 1, 0.08)
    c.label = W.Text(c, "GameFontHighlight", label)
    c.label:SetPoint("LEFT", c, "RIGHT", 8, 0)
    c:SetHitRectInsets(0, -(c.label:GetStringWidth() + 10), 0, 0)
    c.Refresh = function(self) self:SetChecked(get() and true or false) end
    c:SetScript("OnClick", function(self)
        set(self:GetChecked())
        PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
    end)
    c:SetScript("OnShow", c.Refresh)
    tooltipFor(c, label, tip)
    c:Refresh()
    return c
end

function W.Slider(parent, label, minV, maxV, step, get, set, fmt, width)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width or 220, 40)
    holder.label = W.Text(holder, "GameFontHighlight", label)
    holder.label:SetPoint("TOPLEFT")
    holder.value = W.Text(holder, "GameFontNormal", "")
    holder.value:SetPoint("TOPRIGHT")
    holder.value:SetJustifyH("RIGHT")
    local s = CreateFrame("Slider", nil, holder, "BackdropTemplate")
    s:SetOrientation("HORIZONTAL")
    s:SetPoint("TOPLEFT", 0, -20)
    s:SetPoint("TOPRIGHT", 0, -20)
    s:SetHeight(10)
    T.Backdrop(s, { 0.03, 0.03, 0.04, 1 }, T.BORDER)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(T.WHITE)
    thumb:SetSize(10, 16)
    thumb:SetVertexColor(T.Color(T.ACCENT))
    s:SetThumbTexture(thumb)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    local function show(v) holder.value:SetText((fmt or "%s"):format(v)) end
    s:SetScript("OnValueChanged", function(_, v, user)
        v = math.floor(v / step + 0.5) * step
        show(v)
        if user then set(v) end
    end)
    holder.Refresh = function()
        local v = get()
        s:SetValue(v)
        show(v)
    end
    holder:SetScript("OnShow", holder.Refresh)
    holder.slider = s
    holder:Refresh()
    return holder
end

--- Modern dropdown (WowStyle1DropdownTemplate + Menu API).
-- options: array of { value, label } or function returning one.
function W.Dropdown(parent, width, options, get, set)
    local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dd:SetWidth(width or 160)
    dd:SetupMenu(function(_, root)
        local opts = type(options) == "function" and options() or options
        for _, o in ipairs(opts) do
            root:CreateRadio(o.label, function() return get() == o.value end, function()
                set(o.value)
            end, o.value)
        end
    end)
    dd.Refresh = function(self) if self.GenerateMenu then self:GenerateMenu() end end
    return dd
end

--- Five clickable skull pips for severity.
function W.SeverityPicker(parent, get, set, size)
    size = size or 20
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size * 5 + 16, size)
    f.pips = {}
    local function paint(hover)
        local v = hover or get() or 1
        local c = FBL.SEVERITY_COLORS[v]
        for i, p in ipairs(f.pips) do
            if i <= v then
                p.tex:SetDesaturated(false)
                p.tex:SetVertexColor(c[1], c[2], c[3])
                p.tex:SetAlpha(1)
            else
                p.tex:SetDesaturated(true)
                p.tex:SetVertexColor(1, 1, 1)
                p.tex:SetAlpha(0.25)
            end
        end
        if f.label then
            f.label:SetText(FBL.SEVERITY_LABELS[v])
            f.label:SetTextColor(c[1], c[2], c[3])
        end
    end
    for i = 1, 5 do
        local p = CreateFrame("Button", nil, f)
        p:SetSize(size, size)
        p:SetPoint("LEFT", (i - 1) * (size + 4), 0)
        p.tex = p:CreateTexture(nil, "ARTWORK")
        p.tex:SetAllPoints()
        p.tex:SetTexture(T.SKULL)
        p:SetScript("OnEnter", function() paint(i) end)
        p:SetScript("OnLeave", function() paint() end)
        p:SetScript("OnClick", function() set(i); paint() end)
        f.pips[i] = p
    end
    f.label = W.Text(f, "GameFontNormalSmall", "")
    f.label:SetPoint("LEFT", f, "RIGHT", 4, 0)
    f.Refresh = function() paint() end
    paint()
    return f
end

--- Virtualised list using ScrollBox. init(row, data) is called for each visible row.
function W.List(parent, rowHeight, init, create)
    local box = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
    local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, 0)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(rowHeight)
    view:SetElementInitializer("Button", function(row, data)
        if not row.created then
            row.created = true
            create(row)
        end
        init(row, data)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    -- hide the scrollbar when everything fits
    if ScrollUtil.AddManagedScrollBarVisibilityBehavior then
        ScrollUtil.AddManagedScrollBarVisibilityBehavior(box, bar)
    end
    box.bar = bar
    box.SetItems = function(self, items)
        local copy = {}
        for i, v in ipairs(items) do copy[i] = v end
        items = copy
        self:SetDataProvider(CreateDataProvider(items), ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
    end
    return box
end

--- Simple selectable-text popup used for export, import and copying names.
function W.TextPopup(title, text, onAccept, acceptLabel)
    local f = W.popup
    if not f then
        f = CreateFrame("Frame", "ForeverBlacklistTextPopup", UIParent, "BackdropTemplate")
        T.Backdrop(f, T.BG, T.ACCENT)
        f:SetSize(520, 320)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f.title = W.Text(f, "GameFontNormalLarge", "")
        f.title:SetPoint("TOPLEFT", 14, -12)
        f.area = W.TextArea(f, 492, 220)
        f.area:SetPoint("TOP", 0, -40)
        f.ok = W.Button(f, "OK", 110, 26, "accent")
        f.ok:SetPoint("BOTTOMRIGHT", -14, 12)
        f.cancel = W.Button(f, "Close", 110, 26)
        f.cancel:SetPoint("RIGHT", f.ok, "LEFT", -8, 0)
        f.cancel:SetScript("OnClick", function() f:Hide() end)
        tinsert(UISpecialFrames, "ForeverBlacklistTextPopup")
        W.popup = f
    end
    f.title:SetText(title)
    f.area.edit:SetText(text or "")
    f.ok:SetShown(onAccept ~= nil)
    f.ok.text:SetText(acceptLabel or "OK")
    f.ok:SetScript("OnClick", function()
        if onAccept then onAccept(f.area.edit:GetText()) end
        f:Hide()
    end)
    f:Show()
    f.area.edit:SetFocus()
    f.area.edit:HighlightText()
end
