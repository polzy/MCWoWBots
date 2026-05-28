-- MCWoW Bot Manager
-- Manage playerbots via a simple UI panel

-- ============================================================
-- Instance teleport data: { display name, .go command }
-- ============================================================
-- Verified instance entry coordinates. Format: ".go xyz x y z mapId" (mangos syntax).
-- The bare `.go` with 4 args was sending us to the void in MC — switched to `.go xyz`
-- which is the explicit mangos sub-command for an absolute world position teleport.
local INSTANCE_TELEPORTS = {
    { "Molten Core",           ".go xyz 1093.34 -465.62 -98.40 409" },
    { "Onyxia's Lair",         ".go xyz 22.83 -67.96 -5.57 249" },
    { "Blackwing Lair",        ".go xyz -7666.18 -1102.42 400.36 469" },
    { "Zul'Gurub",             ".go xyz -11919.07 -1206.62 92.30 309" },
    { "Ruins of Ahn'Qiraj",    ".go xyz -8410.04 1498.40 27.31 509" },
    { "Temple of Ahn'Qiraj",   ".go xyz -8246.49 1982.84 129.07 531" },
    { "Naxxramas",             ".go xyz 3005.87 -3434.37 295.00 533" },
    { "Stratholme",            ".go xyz 3392.47 -3379.68 142.70 329" },
    { "Scholomance",           ".go xyz 196.37 127.05 134.91 289" },
    { "Upper Blackrock Spire", ".go xyz 78.29 -225.44 49.84 229" },
    { "Lower Blackrock Spire", ".go xyz 78.29 -225.44 49.84 229" },
    { "Blackrock Depths",      ".go xyz 458.32 26.52 -70.67 230" },
    { "Dire Maul",             ".go xyz 44.43 -155.17 -2.71 429" },
    { "Maraudon",              ".go xyz 1019.69 -458.31 -43.43 349" },
    { "Sunken Temple",         ".go xyz -315.41 99.93 -131.85 109" },
    { "Zul'Farrak",            ".go xyz 1213.52 841.59 8.93 209" },
}

-- ============================================================
-- Saved variables / state
-- ============================================================
local instanceDropdownOpen = false
local selectedInstance = 1

-- ============================================================
-- Core toggle
-- ============================================================
function MCWoWBots_Toggle()
    if MCWoWBots_MainFrame:IsShown() then
        MCWoWBots_MainFrame:Hide()
    else
        MCWoWBots_MainFrame:Show()
        MCWoWBots_UpdateStatus()
    end
end

-- ============================================================
-- Status update (group count)
-- ============================================================
function MCWoWBots_UpdateStatus()
    local numMembers = GetNumPartyMembers()
    local numRaid = GetNumRaidMembers()
    local text
    if numRaid > 0 then
        text = "Raid: " .. numRaid .. "/40"
    elseif numMembers > 0 then
        text = "Group: " .. (numMembers + 1) .. "/5"
    else
        text = "Solo (no group)"
    end
    MCWoWBots_StatusText:SetText(text)
end

-- ============================================================
-- Utility: send a dot command via chat
-- ============================================================
local function SendCmd(cmd)
    SendChatMessage(cmd, "SAY")
end

-- ============================================================
-- Button handlers: Group
-- ============================================================
function MCWoWBots_FillGroup()
    SendCmd(".bot fill 5")
    MCWoWBots_Print("Filling group with bots (5)...")
end

function MCWoWBots_FillRaid()
    SendCmd(".bot fill 40")
    MCWoWBots_Print("Filling raid with bots (40)...")
end

-- ============================================================
-- Button handlers: Setup
-- ============================================================
-- MCWoWBots_GearAll / MCWoWBots_InitAll removed: the Prepare Raid pipeline below
-- already runs `.bot init *` followed by `.bot bis *` and `.bot summon *`. Keeping
-- separate buttons just confuses the UX. The XML buttons that called these have
-- been removed too.

function MCWoWBots_SummonAll()
    SendCmd(".bot summon *")
    MCWoWBots_Print("Summoning all bots...")
end

function MCWoWBots_RemoveAll()
    SendCmd(".bot remove *")
    MCWoWBots_Print("Removing all bots...")
end

-- "Prepare Raid": full setup pipeline. Each step is dispatched server-side as a separate
-- chat command — the server processes them in order. We add small delays between phases
-- so the server's throttled queues (bot login, gear init) have time to settle before the
-- next phase starts. Total time: ~5-10 seconds depending on bot count.
function MCWoWBots_PrepareRaid()
    if UnitAffectingCombat("player") then
        MCWoWBots_Print("|cffff5555Cannot prepare raid while in combat.|r")
        return
    end
    MCWoWBots_Print("|cff00ff00Prepare Raid: starting...|r")
    -- 1. Fill the raid to 40 (no-op if already full)
    SendCmd(".bot fill 40")
    -- 2. Init (level + gear + spells + talents at appropriate level)
    -- The .bot init * command does randomize for all bots — includes gear, talents, spells.
    -- Use a coroutine-like timer so we don't blast commands in the same frame.
    -- Pipeline order: init does everything (level, random gear, talents, spells) — running
    -- gear separately before is wasted work because init blows that away. Then bis overlays
    -- the curated pre-raid pieces on top of the random gear. Summon last so bots arrive
    -- where the master is when the prep finishes.
    --
    -- Delays widened (5 / 25 / 45) because each step fans out to ~40 bots and the world
    -- thread needs breathing room between batches — observed server-wide stall at the old
    -- tight (2 / 5 / 7) cadence with 40+ bots in the raid.
    local steps = {
        { delay = 5,  cmd = ".bot init *",   msg = "Initializing all bots (gear/talents/spells)... [~20s]" },
        { delay = 25, cmd = ".bot bis *",    msg = "Overlaying BiS pre-raid gear on lvl-60 bots... [~10s]" },
        { delay = 45, cmd = ".bot summon *", msg = "Summoning all bots to your position..." },
    }
    local frame = CreateFrame("Frame")
    local elapsed = 0
    local idx = 1
    frame:SetScript("OnUpdate", function()
        elapsed = elapsed + (arg1 or 0)
        if idx > table.getn(steps) then
            MCWoWBots_Print("|cff00ff00Prepare Raid: done. Run Smart Roles next.|r")
            frame:SetScript("OnUpdate", nil)
            return
        end
        if elapsed >= steps[idx].delay then
            SendCmd(steps[idx].cmd)
            MCWoWBots_Print(steps[idx].msg)
            idx = idx + 1
        end
    end)
end

-- "Smart Roles": assign tank/heal roles based on class/spec rules for MC raid.
-- Strategy:
--   * 2 Main Tanks: pick the 2 warriors with the highest level. Set them to "tank".
--   * Main Tank Healers: pick 3 paladins (or priests if not enough) → "heal tank" rotation.
--   * Raid Healers: rest of priests + remaining paladins → "heal raid" rotation.
--   * Off-tanks: warlocks (banish/seduce), shamans (TS), druids (innervate) etc — stay default.
-- The server-side bot AI uses these role hints from `.bot c <name> <role> set` to drive
-- Apply Resist picker. The main panel's "Apply Resist" button toggles a small
-- frame with four buttons (Fire / Frost / Nature / Shadow). Each button issues
-- `.bot resist <school> *` to the server, which pulls from PlayerbotResistSet.h.
--
-- Recommended pairings (auto-generated tables from tw_world inventory):
--   Fire   -> MC, Onyxia                       (~243-339 fire res)
--   Frost  -> Naxx Sapphiron / KT              (~340-373 frost res)
--   Nature -> AQ40 Huhuran, Hydraxian dailies  (~279-337 nature res)
--   Shadow -> Naxx Four Horsemen / Maexxna     (~240-280 shadow res)
--
-- Frame is created lazily on first click so we don't pay the layout cost when the
-- player never opens it. Buttons close the picker after firing.
local resistPicker = nil

-- Each school maps to a server-side bot command. Using `.bot resist <school> *`
-- failed because the bot-command dispatcher consumes the FIRST whitespace token as
-- the bot name (so "fire" was interpreted as a character to look up — "character
-- not found"). Workaround: per-school command aliases registered server-side.
local SCHOOL_CMD = {
    fire   = ".bot fr *",
    frost  = ".bot frostres *",
    nature = ".bot natres *",
    shadow = ".bot shadowres *",
}

function MCWoWBots_ApplyResist(school)
    local cmd = SCHOOL_CMD[school]
    if not cmd then
        MCWoWBots_Print("Unknown resist school: " .. tostring(school))
        return
    end
    SendCmd(cmd)
    MCWoWBots_Print("Applying " .. school .. " Resist set to all bots...")
    if resistPicker then resistPicker:Hide() end
end

function MCWoWBots_ToggleResistPicker()
    if not resistPicker then
        -- Vanilla 1.12 caveats: SetBackdrop on a bare "Frame" worked inconsistently
        -- on the Turtle client. Anchor the picker to MCWoWBots_MainFrame and skip
        -- the backdrop entirely — the UIPanelButtonTemplate buttons paint their own
        -- background, so a transparent container frame is fine.
        resistPicker = CreateFrame("Frame", "MCWoWBots_ResistPicker", MCWoWBots_MainFrame)
        resistPicker:SetWidth(120)
        resistPicker:SetHeight(112)
        resistPicker:SetPoint("TOPLEFT", MCWoWBots_FireResBtn, "TOPRIGHT", 4, 0)

        local schools = { "fire", "frost", "nature", "shadow" }
        local labels  = { "Fire",  "Frost", "Nature", "Shadow" }
        for i = 1, 4 do
            local b = CreateFrame("Button", "MCWoWBots_ResistBtn" .. i, resistPicker, "UIPanelButtonTemplate")
            b:SetWidth(110)
            b:SetHeight(22)
            b:SetPoint("TOP", resistPicker, "TOP", 0, -4 - (i - 1) * 26)
            b:SetText(labels[i])
            -- WoW 1.12 Lua 5.0 closures do NOT reliably capture for-loop upvalues
            -- (the original `local school = schools[i]` version errored with
            -- "attempt to concatenate local 'school' (a nil value)" — the closure
            -- saw a stale binding). Workaround: stash the school on the frame
            -- itself and read it from `this` inside the OnClick handler.
            b.school = schools[i]
            b:SetScript("OnClick", function() MCWoWBots_ApplyResist(this.school) end)
        end
        resistPicker:Hide()
    end
    if resistPicker:IsShown() then resistPicker:Hide()
    else resistPicker:Show() end
end

-- threat/healing target priority and stance/form/aura choices.
function MCWoWBots_SmartRoles()
    local function each(callback)
        local n = GetNumRaidMembers()
        if n > 0 then
            for i = 1, n do
                local name, _, _, level, class = GetRaidRosterInfo(i)
                if name then callback(name, class, level) end
            end
        else
            for i = 1, GetNumPartyMembers() do
                local unit = "party" .. i
                local name = UnitName(unit)
                local _, class = UnitClass(unit)
                local level = UnitLevel(unit)
                if name then callback(name, class, level) end
            end
        end
    end

    -- Bucket by class so we can pick tanks/heals strategically.
    local warriors, paladins, priests, shamans, druids = {}, {}, {}, {}, {}
    each(function(name, class, lvl)
        if class == "Warrior" then table.insert(warriors, { name = name, lvl = lvl or 0 })
        elseif class == "Paladin" then table.insert(paladins, { name = name, lvl = lvl or 0 })
        elseif class == "Priest" then table.insert(priests, { name = name, lvl = lvl or 0 })
        elseif class == "Shaman" then table.insert(shamans, { name = name, lvl = lvl or 0 })
        elseif class == "Druid" then table.insert(druids, { name = name, lvl = lvl or 0 })
        end
    end)

    local function byLevel(a, b) return a.lvl > b.lvl end
    table.sort(warriors, byLevel)
    table.sort(paladins, byLevel)
    table.sort(priests, byLevel)

    local tankCount, mtHealCount, raidHealCount = 0, 0, 0

    -- 2 Main Tanks (warriors).
    for i = 1, math.min(2, table.getn(warriors)) do
        SendCmd(".bot c " .. warriors[i].name .. " tank set")
        tankCount = tankCount + 1
    end

    -- 3 Main Tank Healers: prefer paladins (better single-target heal in vanilla via FoL spam).
    local mtHealersWanted = 3
    for i = 1, math.min(mtHealersWanted, table.getn(paladins)) do
        SendCmd(".bot c " .. paladins[i].name .. " heal tank set")
        mtHealCount = mtHealCount + 1
    end
    -- Fill remaining MT heal slots with priests if not enough paladins.
    local priestIdx = 1
    while mtHealCount < mtHealersWanted and priestIdx <= table.getn(priests) do
        SendCmd(".bot c " .. priests[priestIdx].name .. " heal tank set")
        mtHealCount = mtHealCount + 1
        priestIdx = priestIdx + 1
    end

    -- Raid Healers: remaining priests + remaining paladins.
    for i = priestIdx, table.getn(priests) do
        SendCmd(".bot c " .. priests[i].name .. " heal raid set")
        raidHealCount = raidHealCount + 1
    end
    for i = mtHealersWanted + 1, table.getn(paladins) do
        SendCmd(".bot c " .. paladins[i].name .. " heal raid set")
        raidHealCount = raidHealCount + 1
    end

    MCWoWBots_Print(string.format("|cff00ff00Smart Roles: %d tanks, %d MT heals, %d raid heals|r",
        tankCount, mtHealCount, raidHealCount))
end

-- Revive all dead bots in the current group/raid.
-- 1.12 vanilla compat: UnitAffectingCombat exists; also check PlayerFrame.inCombat as belt+braces.
-- Use UIErrorsFrame for the in-combat message so the player sees it overlaid (same UI channel
-- as Blizzard's "You are in combat" rejection) instead of buried in chat.
function MCWoWBots_ReviveAll()
    local inCombat = UnitAffectingCombat("player")
    if not inCombat and PlayerFrame and PlayerFrame.inCombat then
        inCombat = true
    end
    if inCombat then
        if UIErrorsFrame then
            UIErrorsFrame:AddMessage("Cannot revive while in combat.", 1.0, 0.1, 0.1, 1.0, 4)
        end
        MCWoWBots_Print("|cffff5555Cannot revive while in combat.|r")
        return
    end
    if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then
        MCWoWBots_Print("|cffff5555You are not in a group/raid.|r")
        return
    end
    SendCmd(".bot revive")
    MCWoWBots_Print("Reviving all dead bots in your " .. (GetNumRaidMembers() > 0 and "raid" or "group") .. "...")
end

-- ============================================================
-- Button handlers: Roles
-- ============================================================
function MCWoWBots_SetTanks()
    -- Assign tank role to warriors in the group/raid
    local numRaid = GetNumRaidMembers()
    local assigned = 0
    if numRaid > 0 then
        for i = 1, numRaid do
            local name, _, _, _, class = GetRaidRosterInfo(i)
            if name and class == "Warrior" then
                SendCmd(".bot c " .. name .. " tank set")
                assigned = assigned + 1
            end
        end
    else
        for i = 1, GetNumPartyMembers() do
            if UnitClass("party" .. i) == "Warrior" then
                local name = UnitName("party" .. i)
                if name then
                    SendCmd(".bot c " .. name .. " tank set")
                    assigned = assigned + 1
                end
            end
        end
    end
    MCWoWBots_Print("Set " .. assigned .. " warrior(s) as tank.")
end

function MCWoWBots_SetHealers()
    -- Assign healer role to priests and paladins in the group/raid
    local healClasses = { ["Priest"] = true, ["Paladin"] = true }
    local numRaid = GetNumRaidMembers()
    local assigned = 0
    if numRaid > 0 then
        for i = 1, numRaid do
            local name, _, _, _, class = GetRaidRosterInfo(i)
            if name and healClasses[class] then
                SendCmd(".bot c " .. name .. " heal set")
                assigned = assigned + 1
            end
        end
    else
        for i = 1, GetNumPartyMembers() do
            local class = UnitClass("party" .. i)
            if class and healClasses[class] then
                local name = UnitName("party" .. i)
                if name then
                    SendCmd(".bot c " .. name .. " heal set")
                    assigned = assigned + 1
                end
            end
        end
    end
    MCWoWBots_Print("Set " .. assigned .. " priest/paladin(s) as healer.")
end

-- ============================================================
-- Button handlers: Commands
-- ============================================================
function MCWoWBots_Attack()
    SendChatMessage("attack", "RAID")
    MCWoWBots_Print("Bots: ATTACK!")
end

function MCWoWBots_Follow()
    SendChatMessage("follow", "RAID")
    MCWoWBots_Print("Bots: FOLLOW!")
end

function MCWoWBots_Stop()
    SendChatMessage("stay", "RAID")
    MCWoWBots_Print("Bots: STOP!")
end

-- ============================================================
-- Instance teleport dropdown
-- ============================================================
function MCWoWBots_CreateInstanceDropdown()
    -- Create a simple dropdown frame for instance selection
    local dropdown = CreateFrame("Frame", "MCWoWBots_InstanceDropdown", MCWoWBots_MainFrame, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOP", MCWoWBots_TeleHeader, "BOTTOM", 0, -2)

    local function OnClick()
        selectedInstance = this.value
        UIDropDownMenu_SetSelectedValue(MCWoWBots_InstanceDropdown, this.value)
        UIDropDownMenu_SetText(INSTANCE_TELEPORTS[this.value][1], MCWoWBots_InstanceDropdown)
    end

    local function Initialize()
        for i, data in ipairs(INSTANCE_TELEPORTS) do
            local info = {}
            info.text = data[1]
            info.value = i
            info.func = OnClick
            UIDropDownMenu_AddButton(info)
        end
    end

    UIDropDownMenu_Initialize(MCWoWBots_InstanceDropdown, Initialize)
    UIDropDownMenu_SetWidth(200, MCWoWBots_InstanceDropdown)
    UIDropDownMenu_SetSelectedValue(MCWoWBots_InstanceDropdown, 1)
    UIDropDownMenu_SetText(INSTANCE_TELEPORTS[1][1], MCWoWBots_InstanceDropdown)

    -- Teleport button
    local teleBtn = CreateFrame("Button", "MCWoWBots_TeleportBtn", MCWoWBots_MainFrame, "UIPanelButtonTemplate")
    teleBtn:SetWidth(120)
    teleBtn:SetHeight(24)
    teleBtn:SetPoint("TOP", dropdown, "BOTTOM", 0, -2)
    teleBtn:SetText("Teleport")
    teleBtn:SetScript("OnClick", function()
        local data = INSTANCE_TELEPORTS[selectedInstance]
        if data then
            SendCmd(data[2])
            MCWoWBots_Print("Teleporting to " .. data[1] .. "...")
        end
    end)
end

-- ============================================================
-- Chat output helper
-- ============================================================
function MCWoWBots_Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[MCWoWBots]|r " .. msg)
end

-- ============================================================
-- Slash command
-- ============================================================
SLASH_MCWOWBOTS1 = "/bots"
SLASH_MCWOWBOTS2 = "/mcwowbots"
SlashCmdList["MCWOWBOTS"] = function(msg)
    if msg == "fill" then
        MCWoWBots_FillGroup()
    elseif msg == "raid" then
        MCWoWBots_FillRaid()
    elseif msg == "prep" or msg == "prepare" then
        MCWoWBots_PrepareRaid()
    elseif msg == "fr" or msg == "fireres" then
        MCWoWBots_ApplyResist("fire")
    elseif msg == "frostres" or msg == "frost" then
        MCWoWBots_ApplyResist("frost")
    elseif msg == "natres" or msg == "nature" then
        MCWoWBots_ApplyResist("nature")
    elseif msg == "shadowres" or msg == "shadow" then
        MCWoWBots_ApplyResist("shadow")
    elseif msg == "summon" then
        MCWoWBots_SummonAll()
    elseif msg == "remove" then
        MCWoWBots_RemoveAll()
    elseif msg == "attack" then
        MCWoWBots_Attack()
    elseif msg == "follow" then
        MCWoWBots_Follow()
    elseif msg == "stop" then
        MCWoWBots_Stop()
    else
        MCWoWBots_Toggle()
    end
end

-- ============================================================
-- Event frame for periodic status updates
-- ============================================================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" then
        MCWoWBots_CreateInstanceDropdown()
        MCWoWBots_Print("Loaded. Type /bots to open the panel.")
    end
    if MCWoWBots_MainFrame and MCWoWBots_MainFrame:IsShown() then
        MCWoWBots_UpdateStatus()
    end
end)
