-- MCWoWBotsStatusPanel — live visual panel for bot status
--
-- Consumes MCWoWBotsStatus.botData populated by the BotStatusBroadcaster
-- whisper channel (MCWoWBotsStatus.lua). Renders a scrollable list of bots
-- with their current state, target, and active strategies. Auto-refreshes
-- 1Hz; cheap to keep open. Draggable and dismissable.
--
-- Toggle:  /mcwbpanel    or   /mcwbp    or   /mcwbs panel
--
-- Design choices:
--   * Pure CreateFrame (no XML) so a single .lua file ships the whole panel.
--   * FauxScrollFrame for the list — vanilla 1.12-native, no Ace dependency.
--   * Sort bots alphabetically each refresh — deterministic ordering, costs
--     nothing on a 40-bot table.
--   * One OnUpdate accumulator on the panel frame itself; we don't refresh
--     when hidden because OnUpdate doesn't fire on hidden frames.

local PANEL_NAME = "MCWoWBotsStatusPanel"
local ROW_HEIGHT = 32
local NUM_ROWS = 12
local PANEL_W = 480
local PANEL_H = 30 + NUM_ROWS * ROW_HEIGHT + 20

-- ============================================================
-- Frame
-- ============================================================
local panel = CreateFrame("Frame", PANEL_NAME, UIParent)
panel:SetWidth(PANEL_W)
panel:SetHeight(PANEL_H)
panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
panel:Hide()
panel:SetMovable(true)
panel:EnableMouse(true)
panel:SetClampedToScreen(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", function() panel:StartMoving() end)
panel:SetScript("OnDragStop",  function() panel:StopMovingOrSizing() end)
panel:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
panel:SetFrameStrata("MEDIUM")

-- Title
local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", panel, "TOP", 0, -14)
title:SetText("Bot Status")

-- Hint text (top-right under title)
local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -32)
hint:SetText("Live view of every bot's active strategies (auto-refresh 1Hz)")
hint:SetTextColor(0.7, 0.7, 0.7)

-- Close button
local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)

-- ============================================================
-- Scroll frame + rows
-- ============================================================
local scroll = CreateFrame("ScrollFrame", PANEL_NAME .. "Scroll", panel, "FauxScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -52)
scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, 16)

local rows = {}

local function CreateRow(i)
    local row = CreateFrame("Frame", PANEL_NAME .. "Row" .. i, panel)
    row:SetWidth(PANEL_W - 48)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -((i - 1) * ROW_HEIGHT))

    -- Light alternating background for readability
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(row)
    if math.mod(i, 2) == 0 then
        bg:SetTexture(1, 1, 1, 0.04)
    else
        bg:SetTexture(1, 1, 1, 0.0)
    end

    -- Bot name (top-left)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)
    row.name:SetWidth(140)
    row.name:SetJustifyH("LEFT")

    -- State badge (top-right of name area)
    row.state = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.state:SetPoint("TOPLEFT", row.name, "TOPRIGHT", 6, 0)
    row.state:SetWidth(90)
    row.state:SetJustifyH("LEFT")

    -- Target (rest of top line)
    row.target = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.target:SetPoint("TOPLEFT", row.state, "TOPRIGHT", 4, 0)
    row.target:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.target:SetJustifyH("LEFT")
    row.target:SetTextColor(1, 0.82, 0)

    -- Strategies list (bottom line, full width)
    row.strats = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.strats:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 4)
    row.strats:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.strats:SetJustifyH("LEFT")
    row.strats:SetTextColor(0.7, 0.85, 1)
    row.strats:SetNonSpaceWrap(false)

    return row
end

for i = 1, NUM_ROWS do
    rows[i] = CreateRow(i)
end

-- ============================================================
-- Refresh logic
-- ============================================================
local function StateColor(state)
    if state == "COMBAT" then
        return 1, 0.3, 0.3
    elseif state == "DEAD" then
        return 0.5, 0.5, 0.5
    elseif state == "REACTION" then
        return 1, 0.7, 0.2
    elseif state == "NON_COMBAT" then
        return 0.3, 1, 0.3
    end
    return 0.7, 0.7, 0.7
end

local function Refresh()
    local data = MCWoWBotsStatus and MCWoWBotsStatus.botData or {}

    -- Build sorted name list
    local names = {}
    for n in pairs(data) do
        table.insert(names, n)
    end
    table.sort(names)
    local total = table.getn(names)

    -- Update title with count
    if total > 0 then
        title:SetText("Bot Status (" .. total .. ")")
    else
        title:SetText("Bot Status")
    end

    -- Faux scroll math
    FauxScrollFrame_Update(scroll, total, NUM_ROWS, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(scroll)

    for i = 1, NUM_ROWS do
        local row = rows[i]
        local idx = offset + i
        local name = names[idx]
        if name then
            local d = data[name]
            row.name:SetText(name)

            local stateText = d.state ~= "" and d.state or "?"
            row.state:SetText("[" .. stateText .. "]")
            row.state:SetTextColor(StateColor(d.state))

            if d.target and d.target ~= "" then
                row.target:SetText("> " .. d.target)
            else
                row.target:SetText("")
            end

            if d.strategies and table.getn(d.strategies) > 0 then
                row.strats:SetText(table.concat(d.strategies, ", "))
            else
                row.strats:SetText("(no strategies)")
            end
            row:Show()
        else
            row:Hide()
        end
    end

    if total == 0 then
        -- Empty-state hint in row 1
        rows[1].name:SetText("")
        rows[1].state:SetText("")
        rows[1].target:SetText("")
        rows[1].strats:SetText("Waiting for bot whispers... (master must be logged in, bots must have ticked at least once)")
        rows[1].strats:SetTextColor(0.7, 0.7, 0.4)
        rows[1]:Show()
    else
        -- Reset row 1 color if it was the empty hint
        rows[1].strats:SetTextColor(0.7, 0.85, 1)
    end
end

scroll:SetScript("OnVerticalScroll", function()
    FauxScrollFrame_OnVerticalScroll(ROW_HEIGHT)
    Refresh()
end)

-- ============================================================
-- Auto-refresh ticker (1Hz)
-- ============================================================
-- OnUpdate fires every frame while the frame is shown; we accumulate to 1s
-- so we don't burn CPU re-rendering 60 times/s for a list that ticks at
-- best every 2s server-side.
local refreshAcc = 0
panel:SetScript("OnUpdate", function()
    refreshAcc = refreshAcc + arg1
    if refreshAcc >= 1.0 then
        refreshAcc = 0
        Refresh()
    end
end)

-- Initial render on show (don't wait the 1s)
panel:SetScript("OnShow", function()
    refreshAcc = 0
    Refresh()
end)

-- ============================================================
-- Toggle entry points
-- ============================================================
function MCWoWBotsStatusPanel_Toggle()
    if panel:IsShown() then
        panel:Hide()
    else
        panel:Show()
    end
end

SLASH_MCWBPANEL1 = "/mcwbpanel"
SLASH_MCWBPANEL2 = "/mcwbp"
SlashCmdList["MCWBPANEL"] = function()
    MCWoWBotsStatusPanel_Toggle()
end

-- Hook /mcwbs to add the "panel" subcommand (preserves existing behavior).
do
    local origHandler = SlashCmdList["MCWBS"]
    SlashCmdList["MCWBS"] = function(msg)
        local trimmed = msg or ""
        trimmed = string.gsub(trimmed, "^%s+", "")
        trimmed = string.gsub(trimmed, "%s+$", "")
        if trimmed == "panel" then
            MCWoWBotsStatusPanel_Toggle()
            return
        end
        return origHandler(msg)
    end
end
