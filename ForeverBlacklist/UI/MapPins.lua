-- Forever Blacklist: world map pins for the last known sighting of each player.
local _, FBL = ...

local T = FBL.Theme
local TEMPLATE = "ForeverBlacklistMapPinTemplate"

---------------------------------------------------------------------------
-- Pin mixin (must exist before MapPins.xml loads)
---------------------------------------------------------------------------
ForeverBlacklistMapPinMixin = CreateFromMixins(MapCanvasPinMixin or {})
local Pin = ForeverBlacklistMapPinMixin

function Pin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    self:SetScalingLimits(1, 1.0, 1.25)
    self:RegisterForClicks("LeftButtonUp")
    -- let right-clicks fall through so the map can still zoom out
    if self.SetPassThroughButtons then pcall(self.SetPassThroughButtons, self, "RightButton") end
end

function Pin:OnAcquired(entry, sighting, x, y, isTrail, highlighted)
    self.entry, self.sighting, self.isTrail = entry, sighting, isTrail
    self:SetPosition(x, y)
    local scale = FBL.opt.mapPinScale or 1
    local c = FBL.SEVERITY_COLORS[entry.severity or 1]
    local age = FBL.Now() - (sighting.t or 0)
    local maxAge = (FBL.opt.mapPinMaxAgeDays or 30) * 86400
    local fade = 1 - math.min(0.6, (age / maxAge) * 0.6)

    if isTrail then
        self:SetSize(10 * scale, 10 * scale)
        self.Icon:SetTexture(T.WHITE)
        self.Icon:SetVertexColor(c[1], c[2], c[3])
        self.Glow:Hide()
        self.Class:Hide()
        self:SetAlpha(0.45 * fade)
    else
        local size = (highlighted and 30 or 22) * scale
        self:SetSize(size, size)
        self.Icon:SetTexture(T.SKULL)
        self.Icon:SetVertexColor(1, 1, 1)
        self.Glow:SetSize(size * 2, size * 2)
        self.Glow:SetVertexColor(c[1], c[2], c[3])
        self.Glow:Show()
        self.Class:SetSize(size * 0.6, size * 0.6)
        T.SetClassIcon(self.Class, entry.classFile)
        self.Class:Show()
        self:SetAlpha(fade)
    end
    if highlighted then self.Pulse:Play() else self.Pulse:Stop() end
end

function Pin:OnReleased()
    self.Pulse:Stop()
    self.entry, self.sighting = nil, nil
end

function Pin:OnMouseEnter()
    local e, s = self.entry, self.sighting
    if not e then return end
    local tt = GameTooltip
    tt:SetOwner(self, "ANCHOR_RIGHT")
    local _, _, _, hex = FBL.ClassColor(e.classFile)
    tt:SetText(("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:14|t |c%s%s|r"):format(hex or "ffffffff", FBL.ShortName(e.name)))
    local bits = {}
    if e.level then bits[#bits + 1] = "Level " .. e.level end
    if e.race then bits[#bits + 1] = e.race end
    if e.class then bits[#bits + 1] = e.class end
    if #bits > 0 then tt:AddLine(table.concat(bits, " "), 1, 1, 1) end
    if e.guild then tt:AddLine("<" .. e.guild .. ">", 0.25, 1, 0.25) end
    local cat = FBL.Category(e.category)
    local sc = FBL.SEVERITY_COLORS[e.severity or 1]
    tt:AddDoubleLine(("|cff%s%s|r"):format(cat.color, cat.label), FBL.SEVERITY_LABELS[e.severity or 1], 1, 1, 1, sc[1], sc[2], sc[3])
    if e.comment and e.comment ~= "" then tt:AddLine('"' .. e.comment:sub(1, 140) .. '"', 0.8, 0.8, 0.8, true) end
    tt:AddLine(" ")
    tt:AddLine((self.isTrail and "Earlier sighting " or "Last seen ") .. FBL.TimeAgo(s.t), 1, 0.82, 0)
    local where = s.zone or ""
    if s.sub and s.sub ~= "" and s.sub ~= s.zone then where = where .. " - " .. s.sub end
    tt:AddLine(where, 0.9, 0.9, 0.9)
    if s.by then tt:AddLine("Spotted by " .. FBL.ShortName(s.by), 0.6, 0.6, 0.6) end
    tt:AddLine("Click to open entry", 0.4, 0.8, 1)
    tt:Show()
end

function Pin:OnMouseLeave()
    GameTooltip:Hide()
end

function Pin:OnClick()
    if self.entry then FBL.OpenEntry(self.entry.key) end
end

---------------------------------------------------------------------------
-- Coordinates: translate a sighting onto whichever map is being viewed
---------------------------------------------------------------------------
local function translate(s, mapID)
    if not s.mapID or not s.x or not s.y then return nil end
    if s.mapID == mapID then return s.x, s.y end
    if not FBL.opt.mapShowOnContinent then return nil end
    local ok, cont, world = pcall(C_Map.GetWorldPosFromMapPos, s.mapID, CreateVector2D(s.x, s.y))
    if not ok or not cont or not world then return nil end
    local ok2, _, pos = pcall(C_Map.GetMapPosFromWorldPos, cont, world, mapID)
    if not ok2 or not pos then return nil end
    local x, y = pos:GetXY()
    if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
end

---------------------------------------------------------------------------
-- Data provider
---------------------------------------------------------------------------
local Provider = CreateFromMixins(MapCanvasDataProviderMixin or {})
FBL.MapProvider = Provider

function Provider:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
end

function Provider:OnMapChanged()
    self:RefreshAllData()
end

function Provider:RefreshAllData()
    self:RemoveAllData()
    if not FBL.db or not FBL.opt.mapPins then return end
    local map = self:GetMap()
    local mapID = map:GetMapID()
    if not mapID then return end
    local cutoff = FBL.Now() - (FBL.opt.mapPinMaxAgeDays or 30) * 86400
    local minSev = FBL.opt.mapMinSeverity or 1
    local shown = 0
    for key, e in pairs(FBL.db.entries) do
        if not e.deleted and (e.severity or 1) >= minSev and e.sightings and e.sightings[1] then
            local highlighted = (FBL.highlightKey == key)
            -- trail first so the main pin draws on top
            if FBL.opt.mapShowTrail then
                for i = 2, math.min(#e.sightings, 8) do
                    local s = e.sightings[i]
                    if s.t and s.t >= cutoff then
                        local x, y = translate(s, mapID)
                        if x then map:AcquirePin(TEMPLATE, e, s, x, y, true, false) end
                    end
                end
            end
            local last = e.sightings[1]
            if last.t and (last.t >= cutoff or highlighted) then
                local x, y = translate(last, mapID)
                if x then
                    map:AcquirePin(TEMPLATE, e, last, x, y, false, highlighted)
                    shown = shown + 1
                end
            end
        end
    end
    FBL.mapPinsShown = shown
end

function FBL.RefreshMapPins()
    if WorldMapFrame and WorldMapFrame:IsShown() then Provider:RefreshAllData() end
    if FBL.mapToggle then FBL.mapToggle:Update() end
end

--- Opens the world map at a sighting and highlights the player's pin.
function FBL.ShowOnMap(key, sighting)
    if not sighting or not sighting.mapID then return end
    if InCombatLockdown() then FBL.Print("Can't open the map in combat.") return end
    FBL.highlightKey = key
    if not FBL.opt.mapPins then FBL.opt.mapPins = true end
    if not WorldMapFrame:IsShown() then
        if ToggleWorldMap then ToggleWorldMap() else ShowUIPanel(WorldMapFrame) end
    end
    WorldMapFrame:SetMapID(sighting.mapID)
    Provider:RefreshAllData()
    C_Timer.After(12, function()
        if FBL.highlightKey == key then
            FBL.highlightKey = nil
            FBL.RefreshMapPins()
        end
    end)
end

---------------------------------------------------------------------------
-- Map toggle button
---------------------------------------------------------------------------
local function createToggle()
    local container = WorldMapFrame.ScrollContainer or WorldMapFrame
    local b = CreateFrame("Button", nil, container, "BackdropTemplate")
    b:SetSize(28, 28)
    -- bottom-left: the bottom-right corner belongs to the map's own buttons
    b:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 10, 10)
    b:SetFrameLevel(container:GetFrameLevel() + 20)
    T.Backdrop(b, { 0, 0, 0, 0.7 }, T.ACCENT)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 4, -4)
    b.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    b.icon:SetTexture(T.SKULL)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", 2, -2)
    function b:Update()
        local on = FBL.opt.mapPins
        self.icon:SetDesaturated(not on)
        self:SetBackdropBorderColor(on and T.ACCENT[1] or 0.3, on and T.ACCENT[2] or 0.3, on and T.ACCENT[3] or 0.3)
        self.count:SetText(on and (FBL.mapPinsShown or 0) > 0 and FBL.mapPinsShown or "")
    end
    b:SetScript("OnClick", function(self)
        FBL.opt.mapPins = not FBL.opt.mapPins
        Provider:RefreshAllData()
        self:Update()
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("|cffe0324bForever|r Blacklist")
        GameTooltip:AddLine(FBL.opt.mapPins and ("Showing %d last-known location(s) on this map."):format(FBL.mapPinsShown or 0)
            or "Pins hidden.", 1, 1, 1)
        GameTooltip:AddLine("Click to toggle", 0.4, 0.8, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    FBL.mapToggle = b
    return b
end

FBL:On("LOGIN", function()
    if not WorldMapFrame or not WorldMapFrame.AddDataProvider then return end
    WorldMapFrame:AddDataProvider(Provider)
    local toggle = createToggle()
    hooksecurefunc(WorldMapFrame, "OnMapChanged", function() toggle:Update() end)
    WorldMapFrame:HookScript("OnShow", function() toggle:Update() end)
end)

local pendingMap
FBL:On("ENTRY_CHANGED", function()
    if pendingMap or not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
    pendingMap = true
    C_Timer.After(0.5, function() pendingMap = false; FBL.RefreshMapPins() end)
end)
