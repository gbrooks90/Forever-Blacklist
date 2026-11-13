-- Forever Blacklist: draggable minimap button (no library needed).
local _, FBL = ...

local T = FBL.Theme
local btn

local function position()
    local angle = math.rad(FBL.opt.minimapAngle or 205)
    local radius = (Minimap:GetWidth() / 2) + 6
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function create()
    btn = CreateFrame("Button", "ForeverBlacklistMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture(T.SKULL)
    btn.icon = icon
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    btn.badge = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    btn.badge:SetPoint("BOTTOMRIGHT", -2, 2)
    btn.badge:SetTextColor(1, 0.82, 0)

    btn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            FBL.ShowView("options")
        elseif IsShiftKeyDown() then
            FBL.ShowAddDialog({ unit = "target" })
        else
            FBL.Toggle()
        end
    end)
    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            FBL.opt.minimapAngle = math.deg(math.atan2(cy - my, cx - mx)) % 360
            position()
        end)
    end)
    btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("|cffe0324bForever|r Blacklist")
        GameTooltip:AddLine(("%d blacklisted"):format(FBL.CountEntries()), 1, 1, 1)
        local inbox = #FBL.db.inbox
        if inbox > 0 then GameTooltip:AddLine(("%d shared entr%s to review"):format(inbox, inbox == 1 and "y" or "ies"), 1, 0.82, 0) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Click", "Open window", 0.4, 0.8, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Shift-click", "Blacklist target", 0.4, 0.8, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Right-click", "Options", 0.4, 0.8, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Drag", "Move button", 0.4, 0.8, 1, 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)
end

function FBL.UpdateMinimapButton()
    if not btn then create() end
    position()
    btn:SetShown(FBL.opt.minimapShown)
    local n = #FBL.db.inbox
    btn.badge:SetText(n > 0 and n or "")
end

FBL:On("LOGIN", FBL.UpdateMinimapButton)
FBL:On("INBOX_CHANGED", function() if btn then FBL.UpdateMinimapButton() end end)

-- Addon compartment (the puzzle-piece menu by the minimap), when the client has one
FBL:On("LOGIN", function()
    if AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
        AddonCompartmentFrame:RegisterAddon({
            text = "Forever Blacklist",
            icon = T.LOGO,
            notCheckable = true,
            func = function() FBL.Toggle() end,
        })
    end
end)
