-- MCWoWBotsStatus — companion to MCWoWBots.lua
--
-- Receives bot status snapshots from the server via the BotStatusBroadcaster
-- channel (whisper-with-prefix, see playerbot/BotStatusBroadcaster.h). The
-- payloads are filtered out of the chat display so the master doesn't see
-- "Polz whispers: MCWBS\tS|Polz|COMBAT:onyxia,..." spam.
--
-- Public read API for other addon files:
--   MCWoWBotsStatus.botData[botName] = {
--       state = "COMBAT" | "NON_COMBAT" | "REACTION" | "DEAD" | "",
--       strategies = { "onyxia", "dps assist", ... },
--       target = "Lord Victor Nefarius",  -- empty if no target
--       lastUpdate = <GetTime()>,
--   }
--
-- Slash commands:
--   /mcwbs all        list every tracked bot, state and strategy count
--   /mcwbs <name>     dump the full row for one bot

MCWoWBotsStatus = MCWoWBotsStatus or {}
MCWoWBotsStatus.botData = MCWoWBotsStatus.botData or {}

-- ============================================================
-- Payload parser
-- ============================================================
-- Payload format after the "MCWBS\t" prefix has been stripped:
--   "S|<bot>|<state>:<strat,strat,...>"   strategy snapshot
--   "T|<bot>|<target name>"               current target
local function Split(s, sep)
    local out = {}
    local start = 1
    local sepLen = string.len(sep)
    while true do
        local pos = string.find(s, sep, start, true)
        if not pos then
            table.insert(out, string.sub(s, start))
            break
        end
        table.insert(out, string.sub(s, start, pos - 1))
        start = pos + sepLen
    end
    return out
end

function MCWoWBotsStatus:Handle(sender, payload)
    -- payload starts at the char AFTER "MCWBS\t" (so first byte is the type code)
    local kind = string.sub(payload, 1, 1)
    local rest = string.sub(payload, 3)  -- skip "S|" or "T|"
    local parts = Split(rest, "|")
    if table.getn(parts) < 2 then
        return
    end
    local botName = parts[1]
    local body = parts[2]

    local row = self.botData[botName]
    if not row then
        row = { state = "", strategies = {}, target = "", lastUpdate = 0 }
        self.botData[botName] = row
    end
    row.lastUpdate = GetTime()

    if kind == "S" then
        -- body is "STATE:strat1,strat2,..." or "" if no current engine
        local colon = string.find(body, ":", 1, true)
        if colon then
            row.state = string.sub(body, 1, colon - 1)
            local stratCsv = string.sub(body, colon + 1)
            row.strategies = stratCsv ~= "" and Split(stratCsv, ",") or {}
        else
            row.state = body
            row.strategies = {}
        end
    elseif kind == "T" then
        row.target = body
    elseif kind == "A" then
        -- Current action name. "" means engine has no last-executed action.
        row.action = body
    end
end

-- ============================================================
-- Chat-frame filter
-- ============================================================
-- The ChatFrame_OnEvent global dispatches every ChatFrame's CHAT_MSG_* events.
-- We hook it once on file load: if the message starts with "MCWBS\t", parse it
-- and return WITHOUT calling the original — so the line never reaches AddMessage
-- and the master sees nothing in chat.
--
-- arg1 = message text, arg2 = sender name (vanilla 1.12 implicit-arg convention).
local PREFIX = "MCWBS\t"
local PREFIX_LEN = string.len(PREFIX)

-- Guard against multiple /reload re-hooking. Each /reload re-runs the file
-- chunk; without this gate, `origChatFrame_OnEvent` captures the previous
-- already-hooked function, growing a 1-deep extra call per reload. After
-- many reloads, every whisper traverses an O(N) chain. The gate keeps the
-- original captured exactly once per session.
if not MCWoWBotsStatus._hooked then
    MCWoWBotsStatus._origChatFrame_OnEvent = ChatFrame_OnEvent

    function ChatFrame_OnEvent(event)
        if event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_WHISPER_INFORM" then
            local msg = arg1
            if msg and string.len(msg) > PREFIX_LEN and string.sub(msg, 1, PREFIX_LEN) == PREFIX then
                MCWoWBotsStatus:Handle(arg2 or "", string.sub(msg, PREFIX_LEN + 1))
                return  -- swallow, don't pass to original
            end
        end
        return MCWoWBotsStatus._origChatFrame_OnEvent(event)
    end

    MCWoWBotsStatus._hooked = true
end

-- ============================================================
-- Slash command
-- ============================================================
local function PrintRow(botName, row)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF[MCWBS]|r " .. botName
        .. " [" .. (row.state ~= "" and row.state or "?") .. "]"
        .. " target=" .. (row.target ~= "" and row.target or "-"))
    if row.strategies and table.getn(row.strategies) > 0 then
        local list = table.concat(row.strategies, ", ")
        DEFAULT_CHAT_FRAME:AddMessage("|cFF888888  strats:|r " .. list)
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cFF888888  strats:|r (none)")
    end
end

SLASH_MCWBS1 = "/mcwbs"
SlashCmdList["MCWBS"] = function(msg)
    msg = msg or ""
    -- trim
    msg = string.gsub(msg, "^%s+", "")
    msg = string.gsub(msg, "%s+$", "")

    if msg == "" or msg == "help" then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF[MCWBS]|r usage:")
        DEFAULT_CHAT_FRAME:AddMessage("  /mcwbs all        - list tracked bots")
        DEFAULT_CHAT_FRAME:AddMessage("  /mcwbs <name>     - dump one bot")
        DEFAULT_CHAT_FRAME:AddMessage("  /mcwbs clear      - forget all tracked data")
        return
    end

    if msg == "clear" then
        MCWoWBotsStatus.botData = {}
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF[MCWBS]|r cleared.")
        return
    end

    if msg == "all" then
        local n = 0
        for name, row in pairs(MCWoWBotsStatus.botData) do
            n = n + 1
            PrintRow(name, row)
        end
        if n == 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF[MCWBS]|r no bots tracked yet. (server must be on the new build, and bots must have updated since login)")
        end
        return
    end

    -- Treat as bot name
    local row = MCWoWBotsStatus.botData[msg]
    if not row then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF[MCWBS]|r no data for '" .. msg .. "'")
        return
    end
    PrintRow(msg, row)
end
