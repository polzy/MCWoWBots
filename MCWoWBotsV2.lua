-- MCWoWBotsV2 — refonte UI complète with tabbed interface
--
-- This is the V2 frame. The legacy MCWoWBots.xml main frame is kept
-- side-by-side until V2 covers everything; you can use either via
-- /mcwb (V2) or the original button (V1). The two share zero state,
-- so they can't desync.
--
-- Tabs:
--   Roster    — class/spec/role per bot, sortable list
--   Combat    — live target + state (consumes MCWoWBotsStatus.botData)
--   Gear      — buttons wrapping V1 functions (Prepare Raid, Apply Resist,
--               Revive All, Set Tanks/Healers, Smart Roles)
--   Strategy  — focused view of one bot's active strategies (selectable)
--   Logs      — scrolling history of state changes (last 60s)
--
-- Saved variables: MCWoWBotsV2DB.framePos, .lastTab.
--
-- Slash:  /mcwb   toggle the V2 window

-- ============================================================
-- Constants
-- ============================================================
local FRAME_NAME = "MCWoWBotsV2Frame"
local FRAME_W = 560
local FRAME_H = 460
local TAB_H = 24
local TAB_W = 96
local CONTENT_TOP = 60   -- distance from top of frame where content area starts
local CONTENT_BOT = 16

local TABS = {
    { id = "roster",   label = "Roster"   },
    { id = "combat",   label = "Combat"   },
    { id = "gear",     label = "Gear"     },
    { id = "strategy", label = "Strategy" },
    { id = "logs",     label = "Logs"     },
}

-- ============================================================
-- Saved Variables init (loaded by .toc)
-- ============================================================
MCWoWBotsV2DB = MCWoWBotsV2DB or {}
if not MCWoWBotsV2DB.framePos then
    MCWoWBotsV2DB.framePos = { point = "CENTER", x = 0, y = 0 }
end
if not MCWoWBotsV2DB.lastTab then
    MCWoWBotsV2DB.lastTab = "roster"
end
if not MCWoWBotsV2DB.logs then
    MCWoWBotsV2DB.logs = {}  -- circular buffer-ish (capped at 80 entries)
end

-- ============================================================
-- Main frame
-- ============================================================
local frame = CreateFrame("Frame", FRAME_NAME, UIParent)
frame:SetWidth(FRAME_W)
frame:SetHeight(FRAME_H)
frame:SetPoint(MCWoWBotsV2DB.framePos.point, UIParent,
               MCWoWBotsV2DB.framePos.point,
               MCWoWBotsV2DB.framePos.x, MCWoWBotsV2DB.framePos.y)
frame:Hide()
frame:SetMovable(true)
frame:EnableMouse(true)
frame:SetClampedToScreen(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function() frame:StartMoving() end)
frame:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    local point, _, _, x, y = frame:GetPoint()
    MCWoWBotsV2DB.framePos.point = point
    MCWoWBotsV2DB.framePos.x = x
    MCWoWBotsV2DB.framePos.y = y
end)
frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
frame:SetFrameStrata("MEDIUM")

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", frame, "TOP", 0, -14)
title:SetText("MCWoWBots v2")

local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

-- ============================================================
-- Content area (parent of all tab panels)
-- ============================================================
local content = CreateFrame("Frame", FRAME_NAME .. "Content", frame)
content:SetPoint("TOPLEFT",     frame, "TOPLEFT",     16, -CONTENT_TOP)
content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, CONTENT_BOT)

local tabPanels = {}  -- map id → Frame
local tabButtons = {} -- map id → Button

local function SwitchTab(id)
    for tabId, panel in pairs(tabPanels) do
        if tabId == id then panel:Show() else panel:Hide() end
    end
    for tabId, btn in pairs(tabButtons) do
        if tabId == id then
            btn:LockHighlight()
            btn:SetButtonState("PUSHED", true)
        else
            btn:UnlockHighlight()
            btn:SetButtonState("NORMAL", false)
        end
    end
    MCWoWBotsV2DB.lastTab = id
end

-- Tab buttons (along the top under the title)
for i, tab in ipairs(TABS) do
    local btn = CreateFrame("Button", FRAME_NAME .. "Tab" .. tab.id, frame, "UIPanelButtonTemplate")
    btn:SetWidth(TAB_W)
    btn:SetHeight(TAB_H)
    btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 16 + (i - 1) * (TAB_W + 4), -32)
    btn:SetText(tab.label)
    local tabId = tab.id  -- closure capture
    btn:SetScript("OnClick", function() SwitchTab(tabId) end)
    tabButtons[tab.id] = btn
end

-- ============================================================
-- Helper — empty tab panel
-- ============================================================
local function NewTabPanel(id)
    local p = CreateFrame("Frame", FRAME_NAME .. "Panel_" .. id, content)
    p:SetAllPoints(content)
    p:Hide()
    tabPanels[id] = p
    return p
end

-- ============================================================
-- Tab: COMBAT (live state from MCWoWBotsStatus.botData)
-- Reuses the same data table fed by MCWoWBotsStatus.lua.
-- ============================================================
local combatPanel = NewTabPanel("combat")

local COMBAT_ROW_H = 28
local COMBAT_NUM_ROWS = 12

local combatScroll = CreateFrame("ScrollFrame", FRAME_NAME .. "CombatScroll", combatPanel, "FauxScrollFrameTemplate")
combatScroll:SetPoint("TOPLEFT", combatPanel, "TOPLEFT", 0, 0)
combatScroll:SetPoint("BOTTOMRIGHT", combatPanel, "BOTTOMRIGHT", -22, 0)

local combatRows = {}

local function StateColor(state)
    if state == "COMBAT"     then return 1, 0.3, 0.3 end
    if state == "DEAD"       then return 0.5, 0.5, 0.5 end
    if state == "REACTION"   then return 1, 0.7, 0.2 end
    if state == "NON_COMBAT" then return 0.3, 1, 0.3 end
    return 0.7, 0.7, 0.7
end

local function NewCombatRow(i)
    local row = CreateFrame("Button", FRAME_NAME .. "CombatRow" .. i, combatPanel)
    row:SetWidth(FRAME_W - 70)
    row:SetHeight(COMBAT_ROW_H)
    row:SetPoint("TOPLEFT", combatScroll, "TOPLEFT", 0, -((i - 1) * COMBAT_ROW_H))

    if math.mod(i, 2) == 0 then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(row)
        bg:SetTexture(1, 1, 1, 0.04)
    end

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", row, "LEFT", 4, 4)
    row.name:SetWidth(120)
    row.name:SetJustifyH("LEFT")

    row.state = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.state:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
    row.state:SetWidth(96)
    row.state:SetJustifyH("LEFT")

    -- Mini HP bar between state and target. Background then fill texture.
    row.hpbg = row:CreateTexture(nil, "BORDER")
    row.hpbg:SetTexture(0.15, 0.15, 0.15, 0.8)
    row.hpbg:SetPoint("LEFT", row.state, "RIGHT", 4, 0)
    row.hpbg:SetWidth(70)
    row.hpbg:SetHeight(10)

    row.hp = row:CreateTexture(nil, "ARTWORK")
    row.hp:SetPoint("LEFT", row.hpbg, "LEFT", 1, 0)
    row.hp:SetHeight(8)

    row.hpText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.hpText:SetPoint("LEFT", row.hpbg, "LEFT", 0, 0)
    row.hpText:SetPoint("RIGHT", row.hpbg, "RIGHT", 0, 0)
    row.hpText:SetJustifyH("CENTER")
    row.hpText:SetTextColor(1, 1, 1)

    row.target = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.target:SetPoint("LEFT", row.hpbg, "RIGHT", 4, 0)
    row.target:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.target:SetJustifyH("LEFT")
    row.target:SetTextColor(1, 0.82, 0)

    -- LeftClick: TARGET the bot in-game (UnitID lookup via raid scan).
    -- RightClick: focus this bot in the Strategy tab.
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function()
        if not row.botName then return end
        if arg1 == "RightButton" then
            MCWoWBotsV2_FocusStrategy(row.botName)
            SwitchTab("strategy")
        else
            -- Try TargetByName which vanilla 1.12 supports for any player
            -- in the same raid/zone. Falls back silently if name not found.
            TargetByName(row.botName, true)
        end
    end)

    return row
end

for i = 1, COMBAT_NUM_ROWS do
    combatRows[i] = NewCombatRow(i)
end

-- Walk raid1..raidN once per refresh and build a name → unitID map.
-- Cheaper than calling UnitName(raid<i>) inside the per-row loop and
-- avoids O(rows × raidSize) name compares. Rebuilt every refresh so it
-- tracks group changes without an event hook.
local function BuildNameToUnitMap()
    local map = {}
    local raidSize = GetNumRaidMembers() or 0
    if raidSize > 0 then
        for i = 1, raidSize do
            local u = "raid" .. i
            local n = UnitName(u)
            if n then map[n] = u end
        end
    else
        map[UnitName("player") or ""] = "player"
        local party = GetNumPartyMembers() or 0
        for i = 1, party do
            local u = "party" .. i
            local n = UnitName(u)
            if n then map[n] = u end
        end
    end
    return map
end

local function HPColorRGB_Combat(pct)
    if pct >= 50 then
        local t = (pct - 50) / 50
        return 1 - t, 1, 0
    end
    return 1, pct / 50, 0
end

local function RefreshCombat()
    local data = MCWoWBotsStatus and MCWoWBotsStatus.botData or {}
    local names = {}
    for n in pairs(data) do table.insert(names, n) end
    table.sort(names)
    local total = table.getn(names)

    FauxScrollFrame_Update(combatScroll, total, COMBAT_NUM_ROWS, COMBAT_ROW_H)
    local offset = FauxScrollFrame_GetOffset(combatScroll)

    local nameToUnit = BuildNameToUnitMap()

    for i = 1, COMBAT_NUM_ROWS do
        local row = combatRows[i]
        local name = names[offset + i]
        if name then
            local d = data[name]
            row.botName = name
            row.name:SetText(name)
            row.state:SetText("[" .. (d.state ~= "" and d.state or "?") .. "]")
            row.state:SetTextColor(StateColor(d.state))

            -- HP bar lookup. Falls back to "??" when the bot isn't in the
            -- raid view (e.g. master is solo and the bot just despawned).
            local unit = nameToUnit[name]
            if unit and UnitExists(unit) then
                local hpCur = UnitHealth(unit) or 0
                local hpMax = UnitHealthMax(unit) or 1
                if hpMax == 0 then hpMax = 1 end
                local pct = math.floor(hpCur * 100 / hpMax)
                local barW = 68 * (hpCur / hpMax)
                if barW < 1 then barW = 1 end
                row.hp:SetWidth(barW)
                local hr, hg, hb = HPColorRGB_Combat(pct)
                row.hp:SetTexture(hr, hg, hb, 0.85)
                row.hpText:SetText(pct .. "%")
            else
                row.hp:SetWidth(1)
                row.hpText:SetText("?")
            end

            local target = d.target or ""
            local action = d.action or ""
            local right = ""
            if action ~= "" then
                right = "[" .. action .. "]"
            end
            if target ~= "" then
                if right ~= "" then right = right .. " " end
                right = right .. "> " .. target
            end
            row.target:SetText(right)
            row:Show()
        else
            row.botName = nil
            row:Hide()
        end
    end
end

combatScroll:SetScript("OnVerticalScroll", function()
    FauxScrollFrame_OnVerticalScroll(COMBAT_ROW_H)
    RefreshCombat()
end)

-- ============================================================
-- Tab: ROSTER (live per-unit table: class color name, lvl, role hint,
--             HP/Mana%, mini health bar). Updates every refresh tick.
-- ============================================================
local rosterPanel = NewTabPanel("roster")

local function ClassColorRGB(class)
    -- Vanilla 1.12 class colors
    if class == "WARRIOR" then return 0.78, 0.61, 0.43 end
    if class == "PALADIN" then return 0.96, 0.55, 0.73 end
    if class == "HUNTER"  then return 0.67, 0.83, 0.45 end
    if class == "ROGUE"   then return 1.00, 0.96, 0.41 end
    if class == "PRIEST"  then return 1.00, 1.00, 1.00 end
    if class == "SHAMAN"  then return 0.00, 0.44, 0.87 end
    if class == "MAGE"    then return 0.41, 0.80, 0.94 end
    if class == "WARLOCK" then return 0.58, 0.51, 0.79 end
    if class == "DRUID"   then return 1.00, 0.49, 0.04 end
    return 1, 1, 1
end

-- Rough role inference from class (vanilla doesn't expose role API).
-- Used only as a display hint; real role lives in the bot's strategies.
local function ClassRoleHint(class)
    if class == "WARRIOR" or class == "DRUID" then return "T/D" end
    if class == "PALADIN" or class == "PRIEST" or class == "SHAMAN" then return "H/D" end
    return "DPS"
end

local ROSTER_ROW_H = 22
local ROSTER_NUM_ROWS = 16
local rosterRows = {}
local rosterScroll = CreateFrame("ScrollFrame", FRAME_NAME .. "RosterScroll", rosterPanel, "FauxScrollFrameTemplate")
rosterScroll:SetPoint("TOPLEFT", rosterPanel, "TOPLEFT", 0, -4)
rosterScroll:SetPoint("BOTTOMRIGHT", rosterPanel, "BOTTOMRIGHT", -22, 0)

local function NewRosterRow(i)
    local row = CreateFrame("Frame", FRAME_NAME .. "RosterRow" .. i, rosterPanel)
    row:SetWidth(FRAME_W - 70)
    row:SetHeight(ROSTER_ROW_H)
    row:SetPoint("TOPLEFT", rosterScroll, "TOPLEFT", 0, -((i - 1) * ROSTER_ROW_H))

    if math.mod(i, 2) == 0 then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(row)
        bg:SetTexture(1, 1, 1, 0.03)
    end

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.name:SetWidth(130)
    row.name:SetJustifyH("LEFT")

    row.lvl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.lvl:SetPoint("LEFT", row.name, "RIGHT", 0, 0)
    row.lvl:SetWidth(28)
    row.lvl:SetJustifyH("CENTER")
    row.lvl:SetTextColor(0.85, 0.85, 0.85)

    row.role = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.role:SetPoint("LEFT", row.lvl, "RIGHT", 0, 0)
    row.role:SetWidth(36)
    row.role:SetJustifyH("CENTER")
    row.role:SetTextColor(1, 0.82, 0)

    -- Mini HP bar (texture-based, no StatusBar to keep frame count low).
    row.hpbg = row:CreateTexture(nil, "BORDER")
    row.hpbg:SetTexture(0.15, 0.15, 0.15, 0.8)
    row.hpbg:SetPoint("LEFT", row.role, "RIGHT", 4, 0)
    row.hpbg:SetWidth(140)
    row.hpbg:SetHeight(10)

    row.hp = row:CreateTexture(nil, "ARTWORK")
    row.hp:SetPoint("LEFT", row.hpbg, "LEFT", 1, 0)
    row.hp:SetHeight(8)

    row.hpText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.hpText:SetPoint("LEFT", row.hpbg, "LEFT", 0, 0)
    row.hpText:SetPoint("RIGHT", row.hpbg, "RIGHT", 0, 0)
    row.hpText:SetJustifyH("CENTER")
    row.hpText:SetTextColor(1, 1, 1)

    row.manaText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.manaText:SetPoint("LEFT", row.hpbg, "RIGHT", 6, 0)
    row.manaText:SetWidth(60)
    row.manaText:SetJustifyH("LEFT")
    row.manaText:SetTextColor(0.4, 0.6, 1)

    return row
end

for i = 1, ROSTER_NUM_ROWS do
    rosterRows[i] = NewRosterRow(i)
end

local function HPColorRGB(pct)
    -- Smooth red→yellow→green gradient for the HP bar.
    if pct >= 50 then
        local t = (pct - 50) / 50  -- 0..1 from 50% to 100%
        return 1 - t, 1, 0
    else
        local t = pct / 50  -- 0..1 from 0% to 50%
        return 1, t, 0
    end
end

local function CollectRosterUnits()
    local units = {}
    local groupSize = GetNumRaidMembers() or 0
    if groupSize > 0 then
        for i = 1, groupSize do table.insert(units, "raid" .. i) end
    else
        table.insert(units, "player")
        local party = GetNumPartyMembers() or 0
        for i = 1, party do table.insert(units, "party" .. i) end
    end
    return units
end

local function RefreshRoster()
    local units = CollectRosterUnits()
    local total = table.getn(units)
    FauxScrollFrame_Update(rosterScroll, total, ROSTER_NUM_ROWS, ROSTER_ROW_H)
    local offset = FauxScrollFrame_GetOffset(rosterScroll)

    for i = 1, ROSTER_NUM_ROWS do
        local row = rosterRows[i]
        local u = units[offset + i]
        if u and UnitExists(u) then
            local name = UnitName(u) or "?"
            local _, class = UnitClass(u)
            local lvl = UnitLevel(u) or 0
            local hpCur = UnitHealth(u) or 0
            local hpMax = UnitHealthMax(u) or 1
            if hpMax == 0 then hpMax = 1 end
            local hpPct = math.floor(hpCur * 100 / hpMax)
            local manaCur = UnitMana(u) or 0
            local manaMax = UnitManaMax(u) or 0

            local r, g, b = ClassColorRGB(class or "")
            row.name:SetText(name)
            row.name:SetTextColor(r, g, b)
            row.lvl:SetText(tostring(lvl))
            row.role:SetText(ClassRoleHint(class or ""))

            -- HP bar fill
            local barWidth = 138 * (hpCur / hpMax)
            if barWidth < 1 then barWidth = 1 end
            row.hp:SetWidth(barWidth)
            local hr, hg, hb = HPColorRGB(hpPct)
            row.hp:SetTexture(hr, hg, hb, 0.85)
            row.hpText:SetText(hpPct .. "%")

            if manaMax > 0 then
                local manaPct = math.floor(manaCur * 100 / manaMax)
                row.manaText:SetText(manaPct .. "% mp")
            else
                row.manaText:SetText("")
            end
            row:Show()
        else
            row:Hide()
        end
    end
end

rosterScroll:SetScript("OnVerticalScroll", function()
    FauxScrollFrame_OnVerticalScroll(ROSTER_ROW_H)
    RefreshRoster()
end)

-- ============================================================
-- Tab: GEAR (wraps V1 functions)
-- ============================================================
local gearPanel = NewTabPanel("gear")

local function MakeGearButton(parent, x, y, label, callback)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetWidth(160)
    b:SetHeight(24)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetText(label)
    b:SetScript("OnClick", callback)
    return b
end

-- Row 1: bulk actions
MakeGearButton(gearPanel,   0,   0, "Prepare Raid",
    function() if MCWoWBots_PrepareRaid then MCWoWBots_PrepareRaid() end end)
MakeGearButton(gearPanel, 170,   0, "Smart Roles",
    function() if MCWoWBots_SmartRoles then MCWoWBots_SmartRoles() end end)
MakeGearButton(gearPanel, 340,   0, "Revive All",
    function() if MCWoWBots_ReviveAll then MCWoWBots_ReviveAll() end end)

-- Row 2: resist sets (Apply Resist <school>)
MakeGearButton(gearPanel,   0, -34, "Fire Resist",
    function() if MCWoWBots_ApplyResist then MCWoWBots_ApplyResist("Fire") end end)
MakeGearButton(gearPanel, 170, -34, "Frost Resist",
    function() if MCWoWBots_ApplyResist then MCWoWBots_ApplyResist("Frost") end end)
MakeGearButton(gearPanel, 340, -34, "Nature Resist",
    function() if MCWoWBots_ApplyResist then MCWoWBots_ApplyResist("Nature") end end)
MakeGearButton(gearPanel,   0, -68, "Shadow Resist",
    function() if MCWoWBots_ApplyResist then MCWoWBots_ApplyResist("Shadow") end end)

-- Row 3: role assignment + bot ops
MakeGearButton(gearPanel,   0, -102, "Set Tanks",
    function() if MCWoWBots_SetTanks then MCWoWBots_SetTanks() end end)
MakeGearButton(gearPanel, 170, -102, "Set Healers",
    function() if MCWoWBots_SetHealers then MCWoWBots_SetHealers() end end)
-- Force-equip BiS overlay on the whole raid by piping `.bot bis *` through
-- the existing SAY-as-GM-command channel. The server's BiS command itself
-- iterates the group; we just trigger it once on the master.
MakeGearButton(gearPanel, 340, -102, "BiS Overlay (Raid)",
    function() SendChatMessage(".bot bis *", "SAY") end)

-- Row 4: instance teleport (dropdown + button, ported from V1)
local teleLabel = gearPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
teleLabel:SetPoint("TOPLEFT", gearPanel, "TOPLEFT", 0, -140)
teleLabel:SetText("Instance teleport:")

local teleDropdown = CreateFrame("Frame", "MCWoWBotsV2_TeleDropdown", gearPanel, "UIDropDownMenuTemplate")
teleDropdown:SetPoint("TOPLEFT", gearPanel, "TOPLEFT", 100, -132)

local selectedTeleIdx = 1
-- INSTANCE_TELEPORTS is defined in MCWoWBots.lua (V1) — we reuse the same
-- table so updating one keeps both panels consistent.
local function TeleInit()
    if not INSTANCE_TELEPORTS then return end
    for i, data in ipairs(INSTANCE_TELEPORTS) do
        local info = {}
        info.text = data[1]
        info.value = i
        info.func = function()
            selectedTeleIdx = this.value
            UIDropDownMenu_SetSelectedValue(teleDropdown, this.value)
            UIDropDownMenu_SetText(INSTANCE_TELEPORTS[this.value][1], teleDropdown)
        end
        UIDropDownMenu_AddButton(info)
    end
end
UIDropDownMenu_Initialize(teleDropdown, TeleInit)
UIDropDownMenu_SetWidth(180, teleDropdown)
if INSTANCE_TELEPORTS and INSTANCE_TELEPORTS[1] then
    UIDropDownMenu_SetSelectedValue(teleDropdown, 1)
    UIDropDownMenu_SetText(INSTANCE_TELEPORTS[1][1], teleDropdown)
end

MakeGearButton(gearPanel, 320, -136, "Teleport", function()
    if INSTANCE_TELEPORTS and INSTANCE_TELEPORTS[selectedTeleIdx] then
        local data = INSTANCE_TELEPORTS[selectedTeleIdx]
        SendChatMessage(data[2], "SAY")
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF[MCWB]|r Teleporting to " .. data[1] .. "...")
    end
end)

-- Help text
local gearHelp = gearPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
gearHelp:SetPoint("TOPLEFT", gearPanel, "TOPLEFT", 0, -180)
gearHelp:SetPoint("BOTTOMRIGHT", gearPanel, "BOTTOMRIGHT", 0, 0)
gearHelp:SetJustifyH("LEFT")
gearHelp:SetJustifyV("TOP")
gearHelp:SetTextColor(0.7, 0.7, 0.7)
gearHelp:SetText(
    "Bulk actions:\n" ..
    "  Prepare Raid  - .bot init+bis+frostres on every bot in raid\n" ..
    "  Smart Roles   - assign Tank/Healer/DPS based on spec\n" ..
    "  Revive All    - revive every dead bot (incl. resurrection sickness)\n" ..
    "  BiS Overlay   - .bot bis * (T2 set overlay on whole raid)\n\n" ..
    "Resist sets: overlay a per-school resist gear set on every group bot.\n" ..
    "  Fire for MC / Onyxia, Frost for Sapphiron/KT, Nature for Huhuran,\n" ..
    "  Shadow for Four Horsemen / Nefarian phase 2.\n\n" ..
    "Instance teleport: GM command — select dungeon, click Teleport.\n" ..
    "  Master only; bots are summoned via the cross-instance summon code."
)

-- ============================================================
-- Tab: STRATEGY (focused view of one bot)
-- ============================================================
local strategyPanel = NewTabPanel("strategy")
local focusedBot = nil  -- bot name selected via Combat row click or dropdown

local stratHeader = strategyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
stratHeader:SetPoint("TOPLEFT", strategyPanel, "TOPLEFT", 0, -4)
stratHeader:SetText("Pick a bot in the Combat tab")

local stratState = strategyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
stratState:SetPoint("TOPLEFT", strategyPanel, "TOPLEFT", 0, -28)
stratState:SetWidth(FRAME_W - 60)
stratState:SetJustifyH("LEFT")

local stratList = strategyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
stratList:SetPoint("TOPLEFT", strategyPanel, "TOPLEFT", 0, -56)
stratList:SetPoint("BOTTOMRIGHT", strategyPanel, "BOTTOMRIGHT", 0, 0)
stratList:SetJustifyH("LEFT")
stratList:SetJustifyV("TOP")
stratList:SetTextColor(0.7, 0.85, 1)

function MCWoWBotsV2_FocusStrategy(botName)
    focusedBot = botName
end

local function RefreshStrategy()
    if not focusedBot then
        stratHeader:SetText("Pick a bot in the Combat tab")
        stratState:SetText("Click a row in the Combat tab to focus that bot here.")
        stratList:SetText("")
        return
    end
    local d = MCWoWBotsStatus and MCWoWBotsStatus.botData and MCWoWBotsStatus.botData[focusedBot]
    if not d then
        stratHeader:SetText(focusedBot)
        stratState:SetText("No data yet for this bot.")
        stratList:SetText("")
        return
    end
    stratHeader:SetText(focusedBot)
    local stateText = "State: " .. (d.state ~= "" and d.state or "?")
    if d.target and d.target ~= "" then
        stateText = stateText .. "    Target: " .. d.target
    end
    if d.action and d.action ~= "" then
        stateText = stateText .. "    Action: " .. d.action
    end
    stratState:SetText(stateText)
    if d.strategies and table.getn(d.strategies) > 0 then
        local lines = { "Active strategies:" }
        for i = 1, table.getn(d.strategies) do
            table.insert(lines, "  - " .. d.strategies[i])
        end
        stratList:SetText(table.concat(lines, "\n"))
    else
        stratList:SetText("(no strategies)")
    end
end

-- ============================================================
-- Tab: LOGS (rolling buffer of state changes)
-- ============================================================
local logsPanel = NewTabPanel("logs")

local logsScroll = CreateFrame("ScrollFrame", FRAME_NAME .. "LogsScroll", logsPanel, "FauxScrollFrameTemplate")
logsScroll:SetPoint("TOPLEFT", logsPanel, "TOPLEFT", 0, 0)
logsScroll:SetPoint("BOTTOMRIGHT", logsPanel, "BOTTOMRIGHT", -22, 0)

local LOG_ROW_H = 14
local LOG_NUM_ROWS = 24
local logRows = {}

for i = 1, LOG_NUM_ROWS do
    local row = logsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row:SetPoint("TOPLEFT", logsScroll, "TOPLEFT", 0, -((i - 1) * LOG_ROW_H))
    row:SetWidth(FRAME_W - 70)
    row:SetJustifyH("LEFT")
    logRows[i] = row
end

-- Append a log entry. Called by the OnUpdate hook below when we detect a
-- state change on any tracked bot (kept extra-light: no allocations beyond
-- a single string per change).
local function AppendLog(line)
    table.insert(MCWoWBotsV2DB.logs, line)
    while table.getn(MCWoWBotsV2DB.logs) > 80 do
        table.remove(MCWoWBotsV2DB.logs, 1)
    end
end

local function RefreshLogs()
    local logs = MCWoWBotsV2DB.logs
    local total = table.getn(logs)
    FauxScrollFrame_Update(logsScroll, total, LOG_NUM_ROWS, LOG_ROW_H)
    local offset = FauxScrollFrame_GetOffset(logsScroll)
    for i = 1, LOG_NUM_ROWS do
        -- Show newest at top: invert the index
        local idx = total - (offset + i - 1)
        if idx >= 1 and idx <= total then
            logRows[i]:SetText(logs[idx])
            logRows[i]:Show()
        else
            logRows[i]:Hide()
        end
    end
end

logsScroll:SetScript("OnVerticalScroll", function()
    FauxScrollFrame_OnVerticalScroll(LOG_ROW_H)
    RefreshLogs()
end)

-- ============================================================
-- Change detection (logs feeder)
-- ============================================================
-- We keep a shadow table of the last seen state per bot. Each second we
-- diff against the current MCWoWBotsStatus.botData and append a log line
-- whenever something differs.
local lastSeen = {}
local function DetectChanges()
    local data = MCWoWBotsStatus and MCWoWBotsStatus.botData or {}
    local now = date and date("%H:%M:%S") or ""

    for name, d in pairs(data) do
        local prev = lastSeen[name]
        if not prev then
            AppendLog(now .. " [+] " .. name .. " tracked (" .. (d.state or "?") .. ")")
        else
            if prev.state ~= d.state then
                AppendLog(now .. " " .. name .. " state " .. (prev.state or "?") .. " -> " .. (d.state or "?"))
            end
            if (prev.target or "") ~= (d.target or "") and (d.target or "") ~= "" then
                AppendLog(now .. " " .. name .. " target -> " .. d.target)
            end
        end
        lastSeen[name] = { state = d.state, target = d.target }
    end
end

-- ============================================================
-- Master OnUpdate ticker (1Hz refresh of all visible panels)
-- ============================================================
local tickAcc = 0
frame:SetScript("OnUpdate", function()
    tickAcc = tickAcc + arg1
    if tickAcc < 1.0 then return end
    tickAcc = 0
    DetectChanges()
    -- Only refresh the visible panel to save cycles.
    if combatPanel:IsShown()   then RefreshCombat()   end
    if rosterPanel:IsShown()   then RefreshRoster()   end
    if strategyPanel:IsShown() then RefreshStrategy() end
    if logsPanel:IsShown()     then RefreshLogs()     end
end)

frame:SetScript("OnShow", function()
    tickAcc = 0
    DetectChanges()
    RefreshCombat()
    RefreshRoster()
    RefreshStrategy()
    RefreshLogs()
    SwitchTab(MCWoWBotsV2DB.lastTab or "roster")
end)

-- ============================================================
-- Slash command
-- ============================================================
function MCWoWBotsV2_Toggle()
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

SLASH_MCWB1 = "/mcwb"
SLASH_MCWB2 = "/mcwowbots"
SlashCmdList["MCWB"] = function()
    MCWoWBotsV2_Toggle()
end
