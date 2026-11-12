# Changelog

## 1.2.0

- **Picks by the walk, not just the bird.** The 8 nearest as the bird flies get their walking distance worked out, and the shortest walk wins:
  - a straight walk where the terrain allows it (steep ground, cliffs and drawn walls block it; water counts as slower swimming),
  - otherwise along the roads, with straight walks on and off them.
  - A vendor in another zone counts 10% further (zone edges are often ridges), one in a town or camp 10% closer (two or more other townsfolk within 80 yards). A vendor with no walk found (across the sea, say) counts three times its distance.
- Chat and the tooltip show the walk: `140 yd by road (90 direct)`, and `in town`.
- **Right-click** a button: never pick the pinned NPC again, and pin the next one. `/vp hidden` lists them, `/vp unhide` brings them all back. Hidden NPCs are shared across your characters.
- Terrain, roads and walls come built in (Data/), from AzerothGPS's data with its author's permission: no other addon needed for this. `tools/build_nav_data.py` rebuilds them from the latest AzerothGPS release on CurseForge, and a weekly GitHub workflow does that on its own and commits any change.

## 1.1.1

- Stricter faction check. NPCs Questie doesn't tag Alliance or Horde used to count as friendly. Their faction template (the game's own hostility data, shipped with QuestieDB) now decides: anything hostile to players or to your side is skipped. Neutral NPCs, like goblin vendors, still count.

## 1.1.0

- Blizzard's combined bags: the buttons now sit inside the window, left of the search box under the portrait. They shrink to fit the room the search box leaves.
- Buttons on the outside edge of a bag window now draw above action bar art (the gryphons) instead of behind it.
- `/vp side inside` puts the buttons back inside the bag window (`/vp side header` still works).

## 1.0.0

First release, under the name VendorPoint (was NearestNPC while in testing).

- **Vendor** and **Repair** buttons that pin the nearest friendly vendor or repairer on the map, named through WaypointUI when it's installed. Shift-click pins the next-nearest; hover lists the nearest three.
- Buttons live on the bag window:
  - EllesmereUI Bags: in the header icon row, left of the junk / bags / sort icons. They follow EllesmereUI as it re-lays the row (merchant open, option changes), and its title and search box make room.
  - Baganator: in the backpack's bottom-left row, through `Baganator.API.RegisterRegion`, styled by the active Baganator skin.
  - Blizzard bags: on the outside edge, placed with `/vp side`.
- Icons are the game's own vendor-bag and repair-anvil map symbols on red panel buttons.
- NPC data comes from QuestieDB's NPC flags and spawns (Forever's VENDOR and REPAIR flags), filtered to your faction, skipping deployable repair/reagent bots. The list is built in the background after login.
- Optional floating frame (`/vp frame`), off by default.
- `/vp` (or `/vendorpoint`) for commands. Settings are per character.
