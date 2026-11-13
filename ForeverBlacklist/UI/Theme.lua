-- Forever Blacklist: colours, textures and backdrop helpers.
local _, FBL = ...

local T = {}
FBL.Theme = T

T.WHITE = "Interface\\Buttons\\WHITE8X8"
T.ACCENT = { 0.878, 0.196, 0.294 }       -- crimson
T.ACCENT_DARK = { 0.45, 0.08, 0.13 }
T.GOLD = { 1.0, 0.82, 0.0 }
T.BG = { 0.055, 0.055, 0.070, 0.96 }
T.BG_LIGHT = { 0.10, 0.10, 0.125, 0.95 }
T.BG_ROW = { 0.13, 0.13, 0.16, 0.9 }
T.BORDER = { 0.22, 0.22, 0.27, 1 }
T.TEXT_DIM = { 0.62, 0.62, 0.68 }

T.FACTION_ICONS = {
    Alliance = "Interface\\FriendsFrame\\PlusManz-Alliance",
    Horde = "Interface\\FriendsFrame\\PlusManz-Horde",
}
T.FACTION_COLORS = {
    Alliance = { 0.30, 0.55, 1.00 },
    Horde = { 0.90, 0.20, 0.20 },
    Neutral = { 0.85, 0.75, 0.45 },
}
T.SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
T.LOGO = "Interface\\Icons\\Ability_Rogue_FeignDeath"

function T.Backdrop(frame, bg, border, edge)
    if not frame.SetBackdrop then Mixin(frame, BackdropTemplateMixin) end
    frame:SetBackdrop({ bgFile = T.WHITE, edgeFile = T.WHITE, edgeSize = edge or 1 })
    bg = bg or T.BG
    border = border or T.BORDER
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

--- A vertical gradient strip, used for headers.
function T.Gradient(frame, layer, top, bottom)
    local tex = frame:CreateTexture(nil, layer or "BACKGROUND", nil, 1)
    tex:SetTexture(T.WHITE)
    if tex.SetGradient and CreateColor then
        tex:SetGradient("VERTICAL", CreateColor(bottom[1], bottom[2], bottom[3], bottom[4] or 1),
            CreateColor(top[1], top[2], top[3], top[4] or 1))
    else
        tex:SetVertexColor(top[1], top[2], top[3], top[4] or 1)
    end
    return tex
end

--- Sets a texture to a class icon (atlas when available, texture coords otherwise).
function T.SetClassIcon(tex, classFile)
    if classFile then
        local atlas = "classicon-" .. classFile:lower()
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
            tex:SetAtlas(atlas)
            return
        end
        local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
        if coords then
            tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
            tex:SetTexCoord(unpack(coords))
            return
        end
    end
    tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

function T.SetRaceIcon(tex, raceFile, sex)
    if raceFile then
        local g = (sex == "Female") and "female" or "male"
        local atlas = ("raceicon-%s-%s"):format(raceFile:lower(), g)
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
            tex:SetAtlas(atlas)
            tex:Show()
            return true
        end
    end
    tex:Hide()
    return false
end

function T.SetFactionIcon(tex, faction)
    local path = T.FACTION_ICONS[faction or ""]
    if path then
        tex:SetTexture(path)
        tex:SetTexCoord(0, 1, 0, 1)
        tex:Show()
    else
        tex:Hide()
    end
end

function T.Color(c) return c[1], c[2], c[3], c[4] or 1 end
