# Changelog

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
