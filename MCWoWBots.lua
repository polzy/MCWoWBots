-- MCWoW Bot Manager
-- Manage playerbots via a simple UI panel

-- ============================================================
-- Instance teleport data: { display name, .go command }
-- ============================================================
-- Verified instance entry coordinates. Format: ".go xyz x y z mapId" (mangos syntax).
-- The bare `.go` with 4 args was sending us to the void in MC — switched to `.go xyz`
-- which is the explicit mangos sub-command for an absolute world position teleport.
-- INSTANCE_TELEPORTS is intentionally GLOBAL — V2 (MCWoWBotsV2.lua) reads
-- the same table to populate its Gear-tab dropdown. Marking it local was a
-- bug (commit 2840db4 fix) — V2 saw it as nil and the dropdown was empty.
INSTANCE_TELEPORTS = {
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
    -- Normalize: V2 buttons pass "Fire" (capitalized) but SCHOOL_CMD
    -- table indexes lowercase. Pre-existing bug — V2 buttons no-oped
    -- silently with "Unknown resist school: Fire". Lowercase here is
    -- the cheapest fix; both call paths now resolve.
    local key = school and string.lower(school) or ""
    local cmd = SCHOOL_CMD[key]
    if not cmd then
        MCWoWBots_Print("Unknown resist school: " .. tostring(school))
        return
    end
    SendCmd(cmd)
    MCWoWBots_Print("Applying " .. key .. " Resist set to all bots...")
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

    -- Scale targets to group size. Smart Roles always wants ~half the cap as
    -- dedicated MT-healers and the rest as raid-healers.
    local capTanks, capHealers, totalGroup = ComputeCaps()
    local mtHealersWanted = math.max(1, math.floor(capHealers / 3))  -- ~3 for 40-man, 2 for 20-man, 1 for 10-man

    -- Main Tanks (warriors).
    for i = 1, math.min(capTanks, table.getn(warriors)) do
        SendCmd(".bot c " .. warriors[i].name .. " tank set")
        tankCount = tankCount + 1
    end

    -- Main Tank Healers: prefer paladins (better single-target heal in vanilla via FoL spam).
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

    -- Raid Healers: remaining priests + remaining paladins, capped at
    -- (capHealers - MT-healers). Extras stay DPS so the raid keeps damage output.
    local raidHealersWanted = math.max(0, capHealers - mtHealCount)
    for i = priestIdx, table.getn(priests) do
        if raidHealCount >= raidHealersWanted then break end
        SendCmd(".bot c " .. priests[i].name .. " heal raid set")
        raidHealCount = raidHealCount + 1
    end
    for i = mtHealersWanted + 1, table.getn(paladins) do
        if raidHealCount >= raidHealersWanted then break end
        SendCmd(".bot c " .. paladins[i].name .. " heal raid set")
        raidHealCount = raidHealCount + 1
    end

    MCWoWBots_Print(string.format(
        "|cff00ff00Smart Roles: %d tanks, %d MT heals, %d raid heals (group %d → tank cap %d, heal cap %d)|r",
        tankCount, mtHealCount, raidHealCount, totalGroup, capTanks, capHealers))
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
-- Raid composition caps scaled to group size. Putting every warrior as tank
-- (8+ tanks) wastes DPS and confuses threat targeting. The right number of
-- tanks/healers depends on raid size:
--
--   5-man dungeon  : 1 tank, 1 healer
--   10-man (UBRS,..): 2 tanks, 3 healers
--   20-man (ZG,AQ20): 3 tanks, 6 healers
--   40-man (MC,BWL,
--     AQ40, Naxx)  : 4 tanks, 10 healers   (Naxx Four Horsemen wants 4!)
--
-- Bots above the cap stay at their default role (DPS for extra warriors =
-- fury/arms; extra priests = shadow; extra paladins = ret). User can still
-- manually `.bot c <name> tank set` to add more if a specific encounter
-- demands it (e.g. AQ40 Twin Emperors needs 4-5 tanks total).
-- Context-aware caps: prefer per-instance tuning over raw raid size.
-- vanilla map IDs that matter:
--   249 Onyxia       — 1 MT (single dragon), 1 OT for whelps, 6 healers
--   409 Molten Core  — 2 MT (Garr/Sulfuron need add tanks), 1 OT, 8 healers
--   469 BWL          — 4 MT (Razorgore P1 needs 4 add tanks), 8 healers
--   509 AQ20         — 2 MT, 5 healers
--   531 AQ40         — 4 MT (Twin Emperors needs 2/twin), 8 healers
--   533 Naxxramas    — 4 MT (Razuvious + 4HM each need 4 tanks), 10 healers
--   309 Zul'Gurub    — 2 MT (Mandokir + Hakkar), 5 healers
-- Fallback (non-tracked map): scale by raid size as before.
local INSTANCE_CAPS = {
    [249] = { tanks = 2, healers = 6  },  -- Onyxia: MT + whelp OT
    [409] = { tanks = 3, healers = 8  },  -- Molten Core
    [469] = { tanks = 4, healers = 8  },  -- Blackwing Lair
    [509] = { tanks = 2, healers = 5  },  -- Ruins of Ahn'Qiraj
    [531] = { tanks = 4, healers = 8  },  -- Temple of Ahn'Qiraj
    [533] = { tanks = 4, healers = 10 },  -- Naxxramas
    [309] = { tanks = 2, healers = 5  },  -- Zul'Gurub
}

local function ComputeCaps()
    local raidSize = GetNumRaidMembers() or 0
    local groupSize = (GetNumPartyMembers() or 0) + 1
    local total = (raidSize > 0) and raidSize or groupSize

    -- Map ID API call. May fail outside instances (returns nil) — fall
    -- through to size-based defaults in that case.
    local mapId
    if GetCurrentMapAreaID then
        mapId = GetCurrentMapAreaID()
    end
    local override = mapId and INSTANCE_CAPS[mapId]
    if override and total >= 6 then
        -- Cap healers at total/2 so a 10-man Naxx doesn't try to assign
        -- 10 healers from a 10-person roster.
        local h = math.min(override.healers, math.floor(total / 2))
        return override.tanks, h, total
    end

    local tanks, healers
    if total >= 30 then       tanks, healers = 4, 10  -- 40-man raid
    elseif total >= 15 then   tanks, healers = 3,  6  -- 20-man raid
    elseif total >= 6  then   tanks, healers = 2,  3  -- 10-man
    else                      tanks, healers = 1,  1  -- 5-man / solo
    end
    return tanks, healers, total
end

function MCWoWBots_SetTanks()
    -- Assign tank role to up to MAX_TANKS highest-level warriors. Others stay DPS.
    local warriors = {}
    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
        for i = 1, numRaid do
            local name, _, _, level, class = GetRaidRosterInfo(i)
            if name and class == "Warrior" then
                table.insert(warriors, { name = name, lvl = level or 0 })
            end
        end
    else
        for i = 1, GetNumPartyMembers() do
            local unit = "party" .. i
            local _, class = UnitClass(unit)
            if class == "Warrior" then
                local name = UnitName(unit)
                if name then
                    table.insert(warriors, { name = name, lvl = UnitLevel(unit) or 0 })
                end
            end
        end
    end
    table.sort(warriors, function(a, b) return a.lvl > b.lvl end)
    local maxTanks, _, totalGroup = ComputeCaps()
    local cap = math.min(maxTanks, table.getn(warriors))
    for i = 1, cap do
        SendCmd(".bot c " .. warriors[i].name .. " tank set")
    end
    local extras = table.getn(warriors) - cap
    MCWoWBots_Print(string.format("Set %d warrior(s) as tank (group size %d → cap %d; %d remaining warrior(s) stay DPS).",
        cap, totalGroup, maxTanks, extras))
end

function MCWoWBots_SetHealers()
    -- Assign healer role to up to MAX_HEALERS priests/paladins. Druids/shamans
    -- can be added manually. Bots above the cap stay at their default role
    -- (shadow priest, ret paladin) and contribute damage.
    local healClasses = { ["Priest"] = true, ["Paladin"] = true }
    local healers = {}
    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
        for i = 1, numRaid do
            local name, _, _, level, class = GetRaidRosterInfo(i)
            if name and healClasses[class] then
                table.insert(healers, { name = name, lvl = level or 0 })
            end
        end
    else
        for i = 1, GetNumPartyMembers() do
            local unit = "party" .. i
            local _, class = UnitClass(unit)
            if healClasses[class] then
                local name = UnitName(unit)
                if name then
                    table.insert(healers, { name = name, lvl = UnitLevel(unit) or 0 })
                end
            end
        end
    end
    table.sort(healers, function(a, b) return a.lvl > b.lvl end)
    local _, maxHealers, totalGroup = ComputeCaps()
    local cap = math.min(maxHealers, table.getn(healers))
    for i = 1, cap do
        SendCmd(".bot c " .. healers[i].name .. " heal set")
    end
    local extras = table.getn(healers) - cap
    MCWoWBots_Print(string.format("Set %d healer(s) (group size %d → cap %d; %d remaining priest/paladin stay DPS).",
        cap, totalGroup, maxHealers, extras))
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
-- Auto-resist on map enter. When the master walks into a raid instance,
-- pre-fire the appropriate `.bot <school>res *` command so bots arrive
-- pre-equipped with the right resist gear before pull. SavedVariable
-- MCWoWBotsLastResistMap prevents re-firing on every zone change ping
-- inside the same instance. Manual `Apply Resist` button still works
-- to override or re-apply.
local AUTO_RESIST_BY_MAP = {
    [249] = "fire",   -- Onyxia (Deep Breath, Flame Breath)
    [409] = "fire",   -- Molten Core
    [469] = "fire",   -- Blackwing Lair (Vael/drakes/Nefarian fire breath)
    [509] = nil,      -- AQ20 — mixed, no single-school dominant
    [531] = "nature", -- Temple AQ40 (Huhuran berserk is nature)
    [533] = "frost",  -- Naxxramas (Sapphiron/KT) — Shadow needed for 4HM but Frost first
    [309] = nil,      -- Zul'Gurub — mixed
}

local function MCWoWBots_MaybeAutoResist()
    if not GetCurrentMapAreaID then return end
    local mapId = GetCurrentMapAreaID()
    if not mapId then return end
    local school = AUTO_RESIST_BY_MAP[mapId]
    if not school then return end
    if not MCWoWBotsLastResistMap then MCWoWBotsLastResistMap = {} end
    -- Re-fire if we're entering a NEW instance map; suppress duplicate
    -- fires on every ZONE_CHANGED ping inside the same instance.
    if MCWoWBotsLastResistMap.map == mapId and MCWoWBotsLastResistMap.school == school then
        return
    end
    MCWoWBotsLastResistMap.map = mapId
    MCWoWBotsLastResistMap.school = school
    MCWoWBots_Print(string.format(
        "|cff00ffffAuto-resist:|r entering map %d, applying %s resist to all bots.",
        mapId, school))
    MCWoWBots_ApplyResist(school)
end

-- Pre-raid buffs: force a re-eval of the non-combat strategy on every
-- bot. Bots ALREADY auto-buff each other when their auras drop, but
-- after a wipe / load / long travel the buffs lapse and the auto-cycle
-- is slow to re-arm (cooldowns + range checks). This forces a tick.
-- Mechanism: enable+disable a no-op strategy to nudge the engine; the
-- next non-combat tick re-evaluates all buff triggers.
function MCWoWBots_BuffRaid()
    if UnitAffectingCombat("player") then
        MCWoWBots_Print("|cffff5555Cannot pre-buff in combat.|r")
        return
    end
    MCWoWBots_Print("|cff00ff00Pre-buff: triggering buff re-cast cycle...|r")
    -- 1. Make sure bots are in non-combat strategy so they buff at all.
    SendCmd(".bot c * +nc")
    -- 2. Bots periodically auto-buff via their non-combat strategy;
    --    we don't need to issue a buff command per se. The +nc tick
    --    naturally re-evaluates buff aura coverage on each party member
    --    every 1-2 seconds. Within ~10s the raid is fully buffed.
    MCWoWBots_Print("|cff00ff00Pre-buff: non-combat strategy enabled. Buffs land in ~10s.|r")
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" then
        MCWoWBots_CreateInstanceDropdown()
        MCWoWBots_Print("Loaded. Type /bots to open the panel.")
        MCWoWBots_MaybeAutoResist()
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        MCWoWBots_MaybeAutoResist()
    end
    if MCWoWBots_MainFrame and MCWoWBots_MainFrame:IsShown() then
        MCWoWBots_UpdateStatus()
    end
end)
