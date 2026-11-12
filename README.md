# VendorPoint

WoW Forever addon: **Vendor** and **Repair** buttons on your bag window. Click one and it pins the nearest friendly vendor or repairer on your map, with the NPC's name.

## Where the buttons go

- **EllesmereUI Bags**: in the header's icon row, left of the junk / bags / sort icons.
- **Baganator**: in the backpack's bottom-left button row, through Baganator's own button API and styled by its skin.
- **Blizzard bags**: combined bags get them left of the search box, under the portrait. Separate bags get them on the outside edge.

`/vp side bottom | top | left | right` moves them to the outside edge of any bag window; `/vp side inside` puts them back.

They show and hide with the bags. A floating frame with the same two buttons is there too if you want it (`/vp frame`).

## Using it

- **Click**: pins the nearest one. Chat says who, where, and how far (`Repair #1: Name, Zone (x, y) - 140 yd`).
- **Shift-click**: pins the next-nearest one. It starts over on a plain click or once you've moved about 50 yards.
- **Hover**: lists the three nearest with zone and distance.
- With **WaypointUI** installed the waypoint carries the NPC's name; otherwise it's a normal map pin with the tracking arrow.

## Slash commands

| Command | What it does |
| --- | --- |
| `/vp vendor`, `/vp repair` | Pin the nearest (for macros) |
| `/vp side inside \| bottom \| top \| left \| right` | Where the bag buttons sit (`inside` = in the window where there's a spot) |
| `/vp frame` | Show or hide the floating frame |
| `/vp lock`, `/vp unlock`, `/vp reset` | Floating frame position |

Settings are per character.

## Requirements

- [Questie](https://www.curseforge.com/wow/addons/questie) for NPC locations. VendorPoint reads the vendor and repair flags and spawn points from its database (QuestieDB), filtered to your faction.
- Optional: [WaypointUI](https://www.curseforge.com/wow/addons/waypointui) for named waypoints, EllesmereUI Bags or Baganator for the in-window buttons.

## Limits

- "Nearest" is straight-line distance on your current continent. It doesn't know about walls, cliffs or flight paths.
- Inside instances the game doesn't give your map position, so it can't pick one.
