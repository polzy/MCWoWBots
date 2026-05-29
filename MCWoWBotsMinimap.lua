-- MCWoWBotsMinimap — make the minimap button draggable via right-click,
-- and remember its position across sessions via MCWoWBotsV2DB.minimapPos.
--
-- The XML default anchors at TOPRIGHT but on many clients that conflicts
-- with another addon's button. This file lets the user reposition it
-- anywhere on (or around) the minimap with right-button drag.

local function InitMinimapButton()
    local btn = MCWoWBots_MinimapBtn
    if not btn or btn._mcwbDragInit then
        return
    end
    btn._mcwbDragInit = true

    -- Restore saved position if any.
    if MCWoWBotsV2DB and MCWoWBotsV2DB.minimapPos then
        local p = MCWoWBotsV2DB.minimapPos
        btn:ClearAllPoints()
        btn:SetPoint(p.point or "TOPRIGHT", Minimap, p.point or "TOPRIGHT", p.x or 0, p.y or 0)
    end

    btn:SetMovable(true)
    btn:RegisterForDrag("RightButton")
    btn:SetScript("OnDragStart", function()
        this:LockHighlight()
        this:StartMoving()
    end)
    btn:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        this:UnlockHighlight()
        MCWoWBotsV2DB = MCWoWBotsV2DB or {}
        local point, _, _, x, y = this:GetPoint()
        MCWoWBotsV2DB.minimapPos = { point = point, x = x, y = y }
    end)

    -- Subtle tooltip extension to advertise the drag.
    local oldOnEnter = btn:GetScript("OnEnter")
    btn:SetScript("OnEnter", function()
        if oldOnEnter then oldOnEnter() end
        if GameTooltip:IsShown() then
            GameTooltip:AddLine("Right-click drag to reposition", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
end

-- The XML/Lua of MCWoWBots.lua creates the button at file load. We register
-- a one-shot OnEvent on VARIABLES_LOADED so SavedVars are available when we
-- restore the position (file-scope chunks may run BEFORE V_LOADED on first
-- install of a SavedVariable).
local f = CreateFrame("Frame")
f:RegisterEvent("VARIABLES_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    InitMinimapButton()
end)
