# VendorPoint

WoW Forever addon: **Vendor** and **Repair** buttons on your bag window. Click one and it pins the nearest friendly vendor or repairer on your map, with the NPC's name.

## Where the buttons go

- **EllesmereUI Bags**: in the header's icon row, left of the junk / bags / sort icons.
- **Baganator**: in the backpack's bottom-left button row, through Baganator's own button API and styled by its skin.
- **Blizzard bags**: combined bags get them left of the search box, under the portrait. Separate bags get them on the outside edge.

`/vp side bottom | top | left | right` moves them to the outside edge of any bag window; `/vp side inside` puts them back.

They show and hide with the bags. A floating frame with the same two buttons is there too if you want it (`/vp frame`).

## Using it

- **Click**: pins the nearest one. Chat says who, where, and how far you walk (`Repair #1: Name, Zone (x, y) - 140 yd by road (90 direct), in town`).
- **Shift-click**: pins the next one down the list. It starts over on a plain click or once you've moved about 50 yards.
- **Right-click**: never pick the pinned NPC again and pin the next one (`/vp unhide` undoes it).
- **Hover**: lists the three best with zone and walking distance.
- With **WaypointUI** installed the waypoint carries the NPC's name; otherwise it's a normal map pin with the tracking arrow.

## Slash commands

| Command | What it does |
| --- | --- |
| `/vp vendor`, `/vp repair` | Pin the nearest (for macros) |
| `/vp side inside \| bottom \| top \| left \| right` | Where the bag buttons sit (`inside` = in the window where there's a spot) |
| `/vp frame` | Show or hide the floating frame |
| `/vp lock`, `/vp unlock`, `/vp reset` | Floating frame position |
| `/vp hidden`, `/vp unhide` | List hidden NPCs, bring them all back |

Settings are per character; hidden NPCs are shared across your characters.

## How it picks

1. Every friendly vendor (or repairer) on your continent, nearest first as the bird flies.
2. The nearest 8 get their walk worked out: straight there if the terrain allows (cliffs, steep ground and walls block it, water is slower), otherwise along the roads.
3. Another zone counts 10% further, a town or camp 10% closer. No walk found (across the sea) counts three times the distance.
4. The shortest result is pinned.

## Travel data

`Data/Terrain.lua` and `Data/Roads.lua` are built from [AzerothGPS](https://www.curseforge.com/wow/addons/azerothgps)'s terrain, road and wall data, used with its author's permission (that data is © AzerothGPS, all rights reserved). AzerothGPS doesn't need to be installed.

To rebuild them from the latest AzerothGPS release on CurseForge:

```
python -I tools/build_nav_data.py
```

It writes nothing when the data is already from that version (`--force` rebuilds anyway; `--from <AzerothGPS folder>` uses a copy on disk). The **Travel data** GitHub workflow runs it every Monday and commits any change to `main`.

## Requirements

- [Questie](https://www.curseforge.com/wow/addons/questie) for NPC locations. VendorPoint reads the vendor and repair flags and spawn points from its database (QuestieDB), filtered to your faction.
- Optional: [WaypointUI](https://www.curseforge.com/wow/addons/waypointui) for named waypoints, EllesmereUI Bags or Baganator for the in-window buttons.

## Limits

- Walks are judged on the terrain grid (about 8-yard cells) and the road network. It doesn't plan flight paths or boats, and doesn't know building interiors or caves.
- Inside instances the game doesn't give your map position, so it can't pick one.
