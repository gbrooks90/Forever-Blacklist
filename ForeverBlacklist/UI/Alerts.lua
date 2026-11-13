-- Forever Blacklist: alert toasts and screen-edge flash.
local _, FBL = ...

local T, W = FBL.Theme, FBL.Widgets
local toasts, active = {}, {}
local MAX_TOASTS, DURATION = 3, 7

local anchor = CreateFrame("Frame", "ForeverBlacklistToastAnchor", UIParent)
anchor:SetSize(360, 20)
anchor:SetPoint("TOP", UIParent, "TOP", 0, -140)

local function layout()
    for i, t in ipairs(active) do
        t:ClearAllPoints()
        t:SetPoint("TOP", anchor, "TOP", 0, -(i - 1) * 82)
    end
end

local function release(t)
    t:Hide()
    for i, a in ipairs(active) do
        if a == t then table.remove(active, i) break end
    end
    toasts[#toasts + 1] = t
    layout()
end

local function createToast()
    local t = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
    t:SetSize(360, 74)
    t:SetFrameStrata("HIGH")
    T.Backdrop(t, { 0.05, 0.03, 0.04, 0.94 }, T.ACCENT)

    t.stripe = t:CreateTexture(nil, "ARTWORK")
    t.stripe:SetTexture(T.WHITE)
    t.stripe:SetPoint("TOPLEFT", 1, -1)
    t.stripe:SetPoint("BOTTOMLEFT", 1, 1)
    t.stripe:SetWidth(4)

    t.glow = t:CreateTexture(nil, "BACKGROUND", nil, 2)
    t.glow:SetTexture(T.WHITE)
    t.glow:SetPoint("TOPLEFT", 1, -1)
    t.glow:SetPoint("BOTTOMRIGHT", -1, 1)
    if t.glow.SetGradient and CreateColor then
        t.glow:SetGradient("HORIZONTAL", CreateColor(T.ACCENT[1], T.ACCENT[2], T.ACCENT[3], 0.35), CreateColor(0, 0, 0, 0))
    end

    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetSize(46, 46)
    t.icon:SetPoint("LEFT", 14, 0)
    t.skull = t:CreateTexture(nil, "OVERLAY")
    t.skull:SetSize(20, 20)
    t.skull:SetPoint("BOTTOMRIGHT", t.icon, "BOTTOMRIGHT", 6, -6)
    t.skull:SetTexture(T.SKULL)

    t.name = W.Text(t, "GameFontNormalLarge", "")
    t.name:SetPoint("TOPLEFT", t.icon, "TOPRIGHT", 12, 2)
    t.context = W.Text(t, "GameFontHighlightSmall", "")
    t.context:SetPoint("LEFT", t.name, "RIGHT", 6, 0)
    t.context:SetPoint("RIGHT", -10, 0)
    t.context:SetWordWrap(false)
    t.reason = W.Text(t, "GameFontNormal", "")
    t.reason:SetPoint("TOPLEFT", t.name, "BOTTOMLEFT", 0, -3)
    t.comment = W.Text(t, "GameFontDisableSmall", "")
    t.comment:SetPoint("TOPLEFT", t.reason, "BOTTOMLEFT", 0, -3)
    t.comment:SetPoint("RIGHT", -10, 0)
    t.comment:SetWordWrap(false)

    t.close = W.IconButton(t, "Interface\\Buttons\\UI-StopButton", 12)
    t.close:SetPoint("TOPRIGHT", -6, -6)
    t.close:SetScript("OnClick", function() release(t) end)

    local ag = t:CreateAnimationGroup()
    local slide = ag:CreateAnimation("Translation")
    slide:SetOffset(0, 30)
    slide:SetDuration(0)
    slide:SetOrder(1)
    local slideIn = ag:CreateAnimation("Translation")
    slideIn:SetOffset(0, -30)
    slideIn:SetDuration(0.25)
    slideIn:SetSmoothing("OUT")
    slideIn:SetOrder(2)
    local fadeIn = ag:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.25)
    fadeIn:SetOrder(2)
    t.inAnim = ag

    local out = t:CreateAnimationGroup()
    local fade = out:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(0.6)
    out:SetScript("OnFinished", function() release(t) end)
    t.outAnim = out

    t:SetScript("OnUpdate", function(self, el)
        if self:IsMouseOver() then return end
        self.remaining = self.remaining - el
        if self.remaining <= 0 and not self.outAnim:IsPlaying() then self.outAnim:Play() end
    end)
    t:SetScript("OnEnter", function(self) self.outAnim:Stop(); self:SetAlpha(1) end)
    t:SetScript("OnClick", function(self)
        if self.key and FBL.OpenEntry then FBL.OpenEntry(self.key) end
        release(self)
    end)
    return t
end

function FBL.ShowToast(e, context)
    -- refresh an existing toast for the same player
    for _, t in ipairs(active) do
        if t.key == e.key then
            t.context:SetText(context or "")
            t.remaining = DURATION
            return
        end
    end
    if #active >= MAX_TOASTS then release(active[#active]) end
    local t = table.remove(toasts) or createToast()
    t.key = e.key
    T.SetClassIcon(t.icon, e.classFile)
    local r, g, b = FBL.ClassColor(e.classFile)
    t.name:SetText(FBL.ShortName(e.name))
    t.name:SetTextColor(r, g, b)
    t.context:SetText(context or "")
    local cat = FBL.Category(e.category)
    local sev = FBL.SEVERITY_LABELS[e.severity or 1]
    local lvl = e.level and ("Lvl " .. e.level .. " ") or ""
    t.reason:SetText(("|cff%s%s|r  |cff999999%s- %s|r"):format(cat.color, cat.label, lvl, sev))
    t.comment:SetText(e.comment or "")
    local c = FBL.SEVERITY_COLORS[e.severity or 1]
    t.stripe:SetVertexColor(c[1], c[2], c[3])
    t.skull:SetVertexColor(c[1], c[2], c[3])
    t.remaining = DURATION
    t:SetAlpha(1)
    table.insert(active, 1, t)
    layout()
    t:Show()
    t.inAnim:Play()
end

---------------------------------------------------------------------------
-- Screen edge flash
---------------------------------------------------------------------------
local flash = CreateFrame("Frame", nil, UIParent)
flash:SetAllPoints()
flash:SetFrameStrata("FULLSCREEN_DIALOG")
flash:EnableMouse(false)
flash:Hide()
flash.tex = flash:CreateTexture(nil, "BACKGROUND")
flash.tex:SetAllPoints()
flash.tex:SetTexture("Interface\\FullScreenTextures\\LowHealth")
flash.tex:SetBlendMode("ADD")
local fa = flash:CreateAnimationGroup()
local p1 = fa:CreateAnimation("Alpha")
p1:SetFromAlpha(0); p1:SetToAlpha(1); p1:SetDuration(0.2); p1:SetOrder(1)
local p2 = fa:CreateAnimation("Alpha")
p2:SetFromAlpha(1); p2:SetToAlpha(0); p2:SetDuration(0.5); p2:SetOrder(2)
fa:SetLooping("NONE")
fa:SetScript("OnFinished", function(self)
    self.loops = (self.loops or 0) - 1
    if self.loops > 0 then self:Play() else flash:Hide() end
end)

function FBL.FlashScreen(severity)
    local c = FBL.SEVERITY_COLORS[severity or 4]
    flash.tex:SetVertexColor(c[1], c[2], c[3])
    fa.loops = 2
    flash:Show()
    fa:Stop()
    fa:Play()
end
