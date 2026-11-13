# Forever Blacklist

A shared, synced blacklist for **World of Warcraft: Forever**. You can record why someone is on your list, keep track of who they are, and see where they were last spotted on the world map. Everyone you sync with sees the same information.

![interface](https://img.shields.io/badge/interface-16001-e0324b) ![game](https://img.shields.io/badge/game-WoW%20Forever-black)

## Features

### A blacklist with context
- **Reasons**: Ninja looter, Scammer, Griefer/ganker, Toxic, Quits groups, Bot/cheater, Spammer, Other. Each reason has its own colour.
- **Severity** from 1 to 5 (*Minor*, *Caution*, *Avoid*, *Dangerous*, *Never group*). You set it with clickable skull pips.
- **Comments, tags and known alts** for each entry, all searchable.
- **Character profile** recorded automatically: race, class, level, faction (including the neutral Skyborne), gender, guild and guild rank, title and PvP rank. It updates each time you see them.
- **Sighting history**: when, where (zone, subzone and coordinates), inside or outside an instance, and who spotted them.

### Last-known locations on the world map
- A pulsing skull pin marks each blacklisted player's latest sighting. The glow uses the entry's severity colour and the pin shows a class badge.
- A faint **trail** of earlier sightings appears on the same map.
- Zone sightings are also projected onto **continent maps**.
- Pins fade with age. You can filter them by maximum age and minimum severity, and change the pin size.
- A toggle button sits on the world map. **Show on Map** in an entry opens the map at that spot and highlights the pin.

### Sync
- Syncs automatically with **guild** and **party/raid** members who run the addon.
- An optional **shared hidden channel** (default `FBLSync`) lets friends in different guilds share one list.
- **Live updates**: new entries, edits and sightings go out as they happen. On login the addon pulls only what changed since your last sync.
- **Trust controls**: you can accept from *Everyone*, *Guild, friends & trusted* or *Trusted only*.
- **Review inbox**: new entries from other players wait for you to Accept or Reject them.
- A removal is only honoured when it comes from the person who added the entry or from someone you trust.
- **Import/export** strings let you share a list by copy and paste.

### Alerts and protection
- When a blacklisted player is **targeted, moused over, seen on a nameplate, heard in /say or /yell, or joins your group**, you get a slide-in toast, an optional screen-edge flash in the severity colour, a sound and a clickable chat line.
- Each player has an alert cooldown, and you can set a minimum severity for alerts.
- **Auto-decline** group invites and duels, and **auto-cancel** trades (or just get a warning).
- **Tag** their chat messages with a skull, or **hide their whispers** entirely.
- **Tooltip** lines show the reason, severity, comment and who added them.
- **Nameplate marker**: a pulsing skull appears above their nameplate.
- An optional message to your group when a blacklisted player joins.
- **Right-click menus** on any player (target, party, raid, chat names, guild roster) offer *Add to blacklist*, *Edit*, *Remove*, *Trust for sync* and *Sync with player*.

## Installation
1. Download this repository as a ZIP, or grab a release.
2. Copy the **`ForeverBlacklist`** folder (the one containing `ForeverBlacklist.toc`) into your WoW Forever `Interface/AddOns/` directory.
3. Restart the game or `/reload`.

## Usage
| Command | What it does |
|---|---|
| `/fbl` | Open or close the window |
| `/fbl add [name] [what happened]` | Blacklist your target, or a name |
| `/fbl remove name` | Remove someone |
| `/fbl check name` | Check a name (works on your target with no name) |
| `/fbl map [name]` | Toggle map pins, or jump to someone's last sighting |
| `/fbl sync [name]` | Announce to your sync network, or pull from one player |
| `/fbl trust name` | Trust a player for sync |
| `/fbl inbox` · `/fbl options` · `/fbl export` · `/fbl import` | |

On the minimap button: **left-click** opens the window, **Shift-click** blacklists your target, **right-click** opens options, and you can **drag** it to move it.

## How sync works
All messages use the addon prefix `FBLv1`. They are compressed when the client supports it and split into 255-byte chunks.

1. On login, each client says hello on guild, group and the shared channel. The hello includes a timestamp of its newest data.
2. If a peer has newer data than you last synced from them, you whisper them a request. They reply with only the entries changed since then.
3. Requests run one at a time so a full guild logging in doesn't flood the server.
4. Entries merge by field group. The *reason* fields use the newest edit. The *profile* fields use the freshest sighting. *Sightings* from everyone are combined.

A sighting can never change the reason someone is listed.

## Notes and limits
- A sighting records **your** position at the moment you saw them. The game doesn't let addons read other players' positions.
- WoW Forever uses Midnight's addon security ("secret values"). During restricted moments, such as some combat situations in instances, the game may hide unit names. Detection pauses then and picks up again afterwards.
- Trial accounts can't send addon messages, so they can't sync.

## Development
`tests/sync_sim.lua` runs two simulated clients against the core files. It covers the serializer, name normalisation, the full sync handshake, live edits, sightings, the inbox, trust and delete rules, and import/export. It needs any Lua 5.3+ interpreter:

```sh
lua tests/sync_sim.lua ForeverBlacklist
```
