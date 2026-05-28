# MCWoWBots

In-game raid management UI for cmangos/playerbots on **Turtle WoW 1.18.1**.

Companion addon for the server-side bot integration documented at
[polzy/tortoise-wow](https://github.com/polzy/tortoise-wow). The addon is a thin
client over the `.bot` chat-command dispatcher — every button issues a `SendChatMessage`
prefixed with `.bot …` that the server-side bot manager picks up.

## Install

Drop the `MCWoWBots/` folder into your client's addon path:

```
<turtle-wow client>/Interface/AddOns/MCWoWBots/
```

`/console reloadui` and the addon's panel is bound to:
- Minimap button
- `/bots` slash command (alias `/mcwowbots`)

## Features

| Section          | Buttons                                       | Behavior |
|------------------|-----------------------------------------------|----------|
| Group / Raid     | Fill Group (5), Fill Raid (40)                | Auto-pick complementary classes from the bot pool |
| Setup            | Summon All, Remove All                        | `.bot summon *` / `.bot remove *` |
| Commands         | Attack!, Follow!, Stop!                       | Issue the corresponding `.bot` command to all bots |
| Raid Prep        | Prepare Raid                                  | `init` → wait 25s → `bis` → wait 20s → `summon` |
|                  | Smart Roles                                   | Auto-assign 2 MT + 3 MT heals + raid heals from class composition |
|                  | Apply Resist (picker)                         | Popup with Fire / Frost / Nature / Shadow → `.bot fr` / `.bot frostres` / `.bot natres` / `.bot shadowres` |
|                  | Revive All                                    | `.bot revive` (disabled while master is in combat) |
| Instance Teleport| Dropdown + Teleport button                    | Pre-seeded coords for MC, Onyxia, BWL, AQ, Naxx |

### Slash commands

```
/bots fill            Fill group (5)
/bots raid            Fill raid (40)
/bots prep            Prepare Raid pipeline
/bots fr              Apply Fire resist
/bots frost           Apply Frost resist
/bots nature          Apply Nature resist
/bots shadow          Apply Shadow resist
/bots summon          Summon all
/bots attack          Attack target
/bots follow          Follow master
/bots stop            Stop everything
/bots remove          Remove all bots
```

## Why this addon needs server patches

Several panels rely on commands that aren't in upstream cmangos/playerbots:
`.bot bis`, `.bot fr` / `.bot frostres` / `.bot natres` / `.bot shadowres`,
`.bot inspect`, the smart-roles role detection — all live in the patched server fork.
The addon is intentionally dumb (no logic, just chat dispatch); the server is where the
actual bot orchestration happens.

## Constraints (WoW 1.12 client)

- Lua 5.0 — for-loop upvalues are not reliably captured inside `OnClick` closures
  (the picker stashes data on the frame and reads `this.field` to work around it).
- `SetBackdrop` doesn't work cleanly on bare `CreateFrame("Frame", …)` — addon avoids
  it in favor of inheriting `UIPanelButtonTemplate` for visual chrome.
- Inspect is gated by `UnitInParty` (party only, never raid). The addon does NOT try to
  hook the inspect UI; use `.bot inspect <botname>` to get the gear in chat.

## Configuration

The pipeline delays (Prepare Raid) are tuned for ~40 bots; if you run smaller raids
edit the `delays = {…}` table near the top of `MCWoWBots.lua`. No external config.

## License

Inherits the **AGPL-3.0** from the server-side project. The addon is plain Lua/XML so
distribution is just the folder above.
