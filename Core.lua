-- VendorPoint: Vendor and Repair icons on the bag window, plus an optional floating frame.
-- A click pins the nearest friendly NPC of that kind on the map, named, through WaypointUI when it's installed.
-- Shift-click pins the next-nearest one. NPC flags and spawns come from QuestieDB.
local ADDON = ...
local NN = {}
_G.VendorPoint = NN

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffVendorPoint|r: " .. tostring(msg))
end

---------------------------------------------------------------------------
-- Data from QuestieDB
---------------------------------------------------------------------------
-- Deployable bots. Questie kept spots where a player once dropped one, so they're not there.
local CAMP_BOT = {
  [14337] = true,  -- Field Repair Bot 74A
  [242498] = true, -- Reagent Bot
  [254695] = true, -- Repair Bot
}

local KINDS = {
  { key = "vendor", label = "Vendor", flag = "VENDOR", noun = "vendor" },
  { key = "repair", label = "Repair", flag = "REPAIR", noun = "repairer" },
}

-- places[kind] = { { id, name, uiMapID, x, y, cont, wx, wy }, ... }. nil until built.
local places
local building = false

local function ForMyFaction(f)
  if not f or f == "" or f == "AH" then return true end
  local mine = UnitFactionGroup("player")
  if f == "A" or f == "Alliance" then return mine == "Alliance" end
  if f == "H" or f == "Horde" then return mine == "Horde" end
  return true
end

-- Hostility from the NPC's faction template: QuestieDB ships the game's FactionTemplate
-- EnemyGroup masks (1 = players, 2 = Alliance, 4 = Horde, 8 = monsters).
local function QuestieFactionTemplates()
  local loader = QuestieLoader
  if not (loader and loader.ImportModule) then return nil end
  local ok, qdb = pcall(loader.ImportModule, loader, "QuestieDB")
  return ok and type(qdb) == "table" and type(qdb.factionTemplate) == "table" and qdb.factionTemplate or nil
end

-- Friendly to this character? friendlyToFaction ("A", "H", "AH") decides when Questie has it.
-- Without it, the faction template's enemy mask does: hostile to players or to our side = out.
-- An NPC with neither is kept, as Questie's own townsfolk map does.
local function FriendlyNpc(id, templates, myMask)
  local f = NpcDB.friendlyToFaction and NpcDB.friendlyToFaction(id)
  if f then return ForMyFaction(f) end
  local fid = templates and NpcDB.factionID and NpcDB.factionID(id)
  local enemies = fid and templates[fid]
  if type(enemies) == "number" and myMask then
    return bit.band(enemies, 1 + myMask) == 0
  end
  return true
end

local function WorldPos(uiMapID, x, y)
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
  local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, uiMapID, CreateVector2D(x / 100, y / 100))
  if ok and cont and pos then return cont, pos.x, pos.y end
end

local function QuestieZoneDB()
  local loader = QuestieLoader
  if not (loader and loader.ImportModule) then return nil end
  local ok, zone = pcall(loader.ImportModule, loader, "ZoneDB")
  if ok and type(zone) == "table" and type(zone.GetUiMapIdByAreaId) == "function" then return zone end
end

-- nil plus a reason when QuestieDB can't answer.
local function DataReady()
  if not (LibQuestieDB and NpcDB) then return nil, "Questie's database isn't loaded." end
  if type(NpcDB.GetAllIds) ~= "function" or type(NpcDB.npcFlags) ~= "function"
    or type(NpcDB.spawns) ~= "function" or type(NpcDB.name) ~= "function"
    or (LibQuestieDB.RequireContract and not LibQuestieDB.RequireContract(4)) then
    return nil, "Questie's database is too old for this addon."
  end
  local flags = LibQuestieDB.Enum and LibQuestieDB.Enum.npcFlags
  if type(flags) ~= "table" then return nil, "Questie's database has no NPC flags." end
  local zone = QuestieZoneDB()
  if not zone then return nil, "Questie isn't ready yet." end
  return flags, zone
end

local canPin = {}
local function CanPinMap(uiMap)
  local v = canPin[uiMap]
  if v == nil then
    if C_Map.CanSetUserWaypointOnMap then
      local ok, can = pcall(C_Map.CanSetUserWaypointOnMap, uiMap)
      v = ok and can and true or false
    else
      v = true
    end
    canPin[uiMap] = v
  end
  return v
end

-- One pass over every NPC, spread over frames. Calls done(ok, err) when finished.
local doneCallbacks = {}
local function Build(done)
  if places then if done then done(true) end return end
  if done then doneCallbacks[#doneCallbacks + 1] = done end
  if building then return end

  local flags, zone = DataReady()
  if not flags then
    local cbs = doneCallbacks; doneCallbacks = {}
    for _, cb in ipairs(cbs) do cb(false, zone) end
    return
  end

  local masks = {}
  for _, k in ipairs(KINDS) do masks[k.key] = flags[k.flag] end
  local out = { vendor = {}, repair = {} }
  local ids = NpcDB.GetAllIds()
  local templates = QuestieFactionTemplates()
  local mine = UnitFactionGroup("player")
  local myMask = (mine == "Alliance" and 2) or (mine == "Horde" and 4) or nil
  building = true

  local co = coroutine.create(function()
    for i = 1, #ids do
      local id = ids[i]
      local f = not CAMP_BOT[id] and NpcDB.npcFlags(id)
      if type(f) == "number" and f > 0 then
        local isVendor = masks.vendor and bit.band(f, masks.vendor) ~= 0
        local isRepair = masks.repair and bit.band(f, masks.repair) ~= 0
        if isVendor or isRepair then
          local name = NpcDB.name(id)
          if type(name) == "string" and name ~= "" and name:sub(1, 5) ~= "[DND]"
            and FriendlyNpc(id, templates, myMask) then
            local spawns = NpcDB.spawns(id)
            if type(spawns) == "table" then
              for areaId, spots in pairs(spawns) do
                local okMap, uiMap = pcall(zone.GetUiMapIdByAreaId, zone, areaId)
                if okMap and type(uiMap) == "number" and uiMap > 0 and type(spots) == "table" and CanPinMap(uiMap) then
                  for s = 1, #spots do
                    local spot = spots[s]
                    local x, y = type(spot) == "table" and spot[1], type(spot) == "table" and spot[2]
                    if type(x) == "number" and type(y) == "number" and x > 0 and x <= 100 and y > 0 and y <= 100 then
                      local cont, wx, wy = WorldPos(uiMap, x, y)
                      if cont then
                        local p = { id = id, name = name, uiMapID = uiMap, x = x, y = y, cont = cont, wx = wx, wy = wy }
                        if isVendor then out.vendor[#out.vendor + 1] = p end
                        if isRepair then out.repair[#out.repair + 1] = p end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
      if i % 500 == 0 then coroutine.yield() end
    end
  end)

  local ticker
  ticker = C_Timer.NewTicker(0, function()
    local ok, err = coroutine.resume(co)
    local finished = coroutine.status(co) == "dead"
    if not ok or finished then
      ticker:Cancel()
      building = false
      if ok then places = out end
      local cbs = doneCallbacks; doneCallbacks = {}
      for _, cb in ipairs(cbs) do cb(ok, not ok and ("lookup failed: " .. tostring(err)) or nil) end
    end
  end)
end

---------------------------------------------------------------------------
-- Nearest
---------------------------------------------------------------------------
local function PlayerWorld()
  local mapID = C_Map.GetBestMapForUnit("player")
  local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
  if not pos then return nil end
  local x, y = pos:GetXY()
  return WorldPos(mapID, x * 100, y * 100)
end

local function ZoneName(uiMapID)
  local info = C_Map.GetMapInfo(uiMapID)
  return info and info.name or ("map " .. tostring(uiMapID))
end

-- This continent's NPCs of `kind`, nearest first, one entry per NPC (its closest spawn).
-- nil plus a reason when there's no player position.
local function Ranked(kind)
  local pc, px, py = PlayerWorld()
  if not pc then return nil, "Can't tell where you are here." end
  local best = {}
  for _, p in ipairs(places[kind]) do
    if p.cont == pc then
      local d = math.sqrt((p.wx - px) ^ 2 + (p.wy - py) ^ 2)
      local b = best[p.id]
      if not b or d < b.dist then best[p.id] = { place = p, dist = d } end
    end
  end
  local list = {}
  for _, e in pairs(best) do list[#list + 1] = e end
  table.sort(list, function(a, b) return a.dist < b.dist end)
  return list
end

local function Pin(p)
  if not (C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
    Print("Map pins aren't available in this client.")
    return false
  end
  -- WaypointUI names the waypoint. A plain Blizzard pin has no name, and WaypointUI would
  -- show it as "Map Pin". WaypointUI's call also sets the Blizzard pin. Coordinates are 0-100.
  local nav = WaypointUIAPI and WaypointUIAPI.Navigation
  local named = false
  if nav and nav.NewUserNavigation then
    local ok, res = pcall(nav.NewUserNavigation, { name = p.name, mapID = p.uiMapID, x = p.x, y = p.y })
    named = ok and res ~= nil
  end
  if not named then
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(p.uiMapID, p.x / 100, p.y / 100))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
      C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
  end
  return true
end

-- Shift-click steps down the list. It starts over on a plain click or after you move ~50 yards.
local cycle = { kind = nil, index = 0, wx = nil, wy = nil }

local function PinNearest(kindInfo, next)
  local list, why = Ranked(kindInfo.key)
  if not list then Print(why) return end
  if #list == 0 then Print("No " .. kindInfo.noun .. " on this continent in Questie's data.") return end

  local _, px, py = PlayerWorld()
  local moved = not cycle.wx or math.sqrt((px - cycle.wx) ^ 2 + (py - cycle.wy) ^ 2) > 50
  if next and cycle.kind == kindInfo.key and not moved then
    cycle.index = cycle.index % #list + 1
  else
    cycle.index = 1
    cycle.wx, cycle.wy = px, py
  end
  cycle.kind = kindInfo.key

  local e = list[cycle.index]
  local p = e.place
  if Pin(p) then
    Print(string.format("%s #%d: %s, %s (%.0f, %.0f) - %d yd.", kindInfo.label, cycle.index, p.name,
      ZoneName(p.uiMapID), p.x, p.y, e.dist))
  end
end

local function OnKindClick(kindInfo)
  local next = IsShiftKeyDown()
  if places then PinNearest(kindInfo, next) return end
  Print("Reading Questie's NPC list...")
  Build(function(ok, err)
    if ok then PinNearest(kindInfo, next) else Print(err) end
  end)
end

---------------------------------------------------------------------------
-- Tooltip (shared by the bag icons and the floating frame)
---------------------------------------------------------------------------
local function ShowTooltip(btn, kindInfo, anchor)
  GameTooltip:SetOwner(btn, anchor or "ANCHOR_TOP")
  GameTooltip:AddLine("Nearest " .. kindInfo.noun)
  if places then
    local list = Ranked(kindInfo.key)
    if list and #list > 0 then
      for i = 1, math.min(3, #list) do
        local p = list[i].place
        GameTooltip:AddDoubleLine(p.name, string.format("%s  %d yd", ZoneName(p.uiMapID), list[i].dist), 1, 1, 1, 0.8, 0.8, 0.8)
      end
    else
      GameTooltip:AddLine("None on this continent.", 0.8, 0.8, 0.8)
    end
  else
    GameTooltip:AddLine("Click to look it up.", 0.8, 0.8, 0.8)
  end
  GameTooltip:AddLine("Click: pin the nearest. Shift-click: the next one.", 0.5, 0.8, 1, true)
  GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Bag window icons
---------------------------------------------------------------------------
-- Two icon buttons that sit on the edge of whichever bag window is open:
-- EllesmereUI Bags, Baganator, or Blizzard's (combined or backpack). They show and
-- hide with it. Nothing is changed inside those addons' frames.
local bagBar
local inBaganatorRow = false -- true once our buttons are in Baganator's bottom row
local hooked = {}   -- frames we've hooked OnShow/OnHide on
local candidates = {}

local SIDES = {
  bottom = { "TOPLEFT", "BOTTOMLEFT", 0, -2, "LEFT", "RIGHT", 2, 0, "ANCHOR_BOTTOM" },
  top    = { "BOTTOMLEFT", "TOPLEFT", 0, 2, "LEFT", "RIGHT", 2, 0, "ANCHOR_TOP" },
  left   = { "TOPRIGHT", "TOPLEFT", -2, 0, "TOP", "BOTTOM", 0, -2, "ANCHOR_LEFT" },
  right  = { "TOPLEFT", "TOPRIGHT", 2, 0, "TOP", "BOTTOM", 0, -2, "ANCHOR_RIGHT" },
}

local function Side()
  return SIDES[VendorPointCharDB.side or "bottom"] or SIDES.bottom
end

-- Bag windows in order of preference. Baganator names its frames per skin
-- ("Baganator_SingleViewBackpackViewFrame" .. skin), so those are found by prefix.
local function FindCandidates()
  local list = {}
  local function add(f)
    if type(f) == "table" and f.IsVisible and f.HookScript then list[#list + 1] = f end
  end
  add(_G.EUI_MainBagFrame)
  -- Baganator gets its own buttons in its bottom row instead (RegisterBaganator).
  if not inBaganatorRow then
    for name, f in pairs(_G) do
      if type(name) == "string" and (name:find("^Baganator_SingleViewBackpackViewFrame")
        or name:find("^Baganator_CategoryViewBackpackViewFrame")) then
        add(f)
      end
    end
  end
  add(_G.ContainerFrameCombinedBags)
  add(_G.ContainerFrame1)
  return list
end

local function LayoutButtons(w, h, point, relPoint, dx, dy)
  local prev
  for _, b in ipairs(bagBar.buttons) do
    b:SetSize(w, h)
    b:ClearAllPoints()
    if prev then b:SetPoint(point, prev, relPoint, dx, dy) else b:SetPoint(point, bagBar) end
    prev = b
  end
end

-- EllesmereUI Bags: sit in the header's icon row, left of the leftmost shown icon
-- (Sell Junk / junk coin / Quick Actions / Show Bags / Sort). Then whatever EllesmereUI
-- bounds by that edge (the search box on its Forever skin, the title otherwise)
-- is pointed at our icons instead. Runs after every SyncHeaderIcons.
local function PlaceInEUIHeader()
  local eui = _G.EUI_Bags
  local header = eui and eui.Header
  if not (header and eui._bagsBtn) then return false end
  local edge
  for _, b in ipairs({ eui._sellJunkBtn, eui._junkBtn, eui._quickBtn, eui._bagsBtn, eui._sortBtn }) do
    if b and b:IsShown() then edge = b; break end
  end
  edge = edge or eui._searchBox
  if not edge then return false end

  bagBar:SetParent(header)
  bagBar:ClearAllPoints()
  bagBar:SetPoint("RIGHT", edge, "LEFT", -6, 0)
  bagBar:SetFrameLevel(header:GetFrameLevel() + 5)
  bagBar:SetSize(28 * #bagBar.buttons + 4 * (#bagBar.buttons - 1), 22)
  LayoutButtons(28, 22, "LEFT", "RIGHT", 4, 0)
  bagBar.tipAnchor = "ANCHOR_BOTTOM"
  bagBar:Show()

  local search = eui._searchBox
  if header._foreverToolsY and search and edge ~= search then
    search:ClearAllPoints()
    search:SetPoint("LEFT", header, "TOPLEFT", 45, header._foreverToolsY)
    search:SetPoint("RIGHT", bagBar, "LEFT", -6, 0)
  elseif not header._foreverToolsY and eui.FitHeaderText then
    eui._hdrEdge = bagBar
    pcall(eui.FitHeaderText, eui)
  end
  return true
end

-- Blizzard's combined bags: in the gap left of the search box, under the portrait.
-- Button width fits whatever room the search box leaves.
local function PlaceInCombinedBags(target)
  local search = _G.BagItemSearchBox
  if not (search and search:IsVisible()) then return false end
  local sl, tl = search:GetLeft(), target:GetLeft()
  if not (sl and tl) or sl <= tl then return false end
  local n = #bagBar.buttons
  local room = sl - tl - 14            -- frame border on the left, gap before the search
  local w = math.min(28, math.floor((room - 2 * (n - 1)) / n))
  if w < 16 then return false end
  bagBar:SetParent(target)
  bagBar:ClearAllPoints()
  bagBar:SetPoint("RIGHT", search, "LEFT", -8, 0)
  bagBar:SetFrameLevel(target:GetFrameLevel() + 20)
  bagBar:SetSize(w * n + 2 * (n - 1), 20)
  LayoutButtons(w, 20, "LEFT", "RIGHT", 2, 0)
  bagBar.tipAnchor = "ANCHOR_TOP"
  bagBar:Show()
  return true
end

local LOW_STRATA = { BACKGROUND = true, LOW = true, MEDIUM = true }

local function Place()
  if not bagBar then return end
  local target
  for _, f in ipairs(candidates) do
    if f:IsVisible() then target = f; break end
  end
  if not target then bagBar:Hide(); return end

  if not VendorPointCharDB.side then
    if target == _G.EUI_MainBagFrame and PlaceInEUIHeader() then return end
    if target == _G.ContainerFrameCombinedBags and PlaceInCombinedBags(target) then return end
  end

  local s = Side()
  bagBar:SetParent(UIParent)
  bagBar:ClearAllPoints()
  bagBar:SetPoint(s[1], target, s[2], s[3], s[4])
  -- Outside the window there's other UI around (action bar art). Sit above it.
  local strata = target:GetFrameStrata()
  bagBar:SetFrameStrata(LOW_STRATA[strata] and "HIGH" or strata)
  bagBar:SetFrameLevel(target:GetFrameLevel() + 20)
  if s[5] == "LEFT" then bagBar:SetSize(66, 24) else bagBar:SetSize(32, 50) end
  LayoutButtons(32, 24, s[5], s[6], s[7], s[8])
  bagBar.tipAnchor = s[9]
  bagBar:Show()
end

-- Runs a frame later: a parent's OnShow fires before its children report visible.
local function PlaceSoon() C_Timer.After(0, Place) end

local euiHooked = false
local function Rescan()
  candidates = FindCandidates()
  for _, f in ipairs(candidates) do
    if not hooked[f] then
      hooked[f] = true
      f:HookScript("OnShow", PlaceSoon)
      f:HookScript("OnHide", PlaceSoon)
    end
  end
  -- EllesmereUI re-lays its header icons on merchant open/close, option changes and
  -- profile swaps. Follow it so our icons stay left of the leftmost one.
  if not euiHooked and type(_G.EUI_Bags) == "table" and type(_G.EUI_Bags.SyncHeaderIcons) == "function" then
    euiHooked = true
    hooksecurefunc(_G.EUI_Bags, "SyncHeaderIcons", function() Place() end)
  end
  Place()
end

-- The game's own map symbols for these NPCs (Questie's townsfolk menu uses the same
-- tracking art), so the vendor bag isn't mistaken for EllesmereUI's junk coin.
local BAG_ICONS = {
  vendor = "Interface\\GossipFrame\\VendorGossipIcon",
  repair = "Interface\\Minimap\\Tracking\\Repair",
}

local function CreateBagBar()
  bagBar = CreateFrame("Frame", "VendorPointBagBar", UIParent)
  bagBar:SetSize(54, 26)
  bagBar.buttons = {}
  for _, k in ipairs(KINDS) do
    -- The game's red panel button with the symbol on it, same as in Baganator's row.
    local b = CreateFrame("Button", nil, bagBar, "UIPanelButtonTemplate")
    b:SetSize(28, 22)
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetSize(16, 16)
    b.icon:SetPoint("CENTER")
    b.icon:SetTexture(BAG_ICONS[k.key])
    b:SetScript("OnClick", function() OnKindClick(k) end)
    b:SetScript("OnEnter", function(self) ShowTooltip(self, k, bagBar.tipAnchor) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnMouseDown", function(self) self.icon:SetPoint("CENTER", 1, -1) end)
    b:SetScript("OnMouseUp", function(self) self.icon:SetPoint("CENTER") end)
    bagBar.buttons[#bagBar.buttons + 1] = b
  end
  bagBar:Hide()
end

-- Baganator: two buttons in its backpack's bottom-left row, through its own API
-- (Baganator.API.RegisterRegion), styled by the active Baganator skin like its others.
local function RegisterBaganator()
  local api = Baganator and Baganator.API
  if not (api and api.RegisterRegion) then return end
  -- Built under a hidden holder so they never flash on screen; Baganator reparents
  -- them into its row (it only places buttons whose own shown flag is set).
  local holder = CreateFrame("Frame")
  holder:Hide()
  for _, k in ipairs(KINDS) do
    local b = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
    b:SetSize(32, 22)
    b.Icon = b:CreateTexture(nil, "ARTWORK")
    b.Icon:SetSize(16, 16)
    b.Icon:SetPoint("CENTER")
    b.Icon:SetTexture(BAG_ICONS[k.key])
    if Baganator.Skins and Baganator.Skins.AddFrame then
      pcall(Baganator.Skins.AddFrame, "IconButton", b, { "vendorpoint" })
    end
    b:SetScript("OnClick", function() OnKindClick(k) end)
    b:SetScript("OnEnter", function(self) ShowTooltip(self, k, "ANCHOR_TOP") end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    api.RegisterRegion("VendorPoint " .. k.label, "vendorpoint_" .. k.key, "backpack", "bottom_left", b)
  end
  inBaganatorRow = true
  if api.RequestLayoutUpdate then api.RequestLayoutUpdate() end
end

---------------------------------------------------------------------------
-- Floating frame (off by default; /vp frame)
---------------------------------------------------------------------------
local frame

local function SavePos()
  local point, _, relPoint, x, y = frame:GetPoint(1)
  VendorPointCharDB.pos = { point, relPoint, x, y }
end

local function ApplyPos()
  frame:ClearAllPoints()
  local p = VendorPointCharDB.pos
  if p then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
end

local function CreateFloating()
  frame = CreateFrame("Frame", "VendorPointFrame", UIParent, "BackdropTemplate")
  frame:SetSize(172, 34)
  frame:SetFrameStrata("DIALOG")
  frame:SetClampedToScreen(true)
  frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  frame:SetBackdropColor(0, 0, 0, 0.7)
  frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  local function StartMove() if not VendorPointCharDB.locked then frame:StartMoving() end end
  local function StopMove() frame:StopMovingOrSizing(); SavePos() end
  frame:SetScript("OnDragStart", StartMove)
  frame:SetScript("OnDragStop", StopMove)

  local prev
  for _, k in ipairs(KINDS) do
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(78, 22)
    b:SetText(k.label)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("LEFT", frame, "LEFT", 6, 0) end
    b:SetScript("OnClick", function() OnKindClick(k) end)
    b:SetScript("OnEnter", function(self) ShowTooltip(self, k) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", StartMove)
    b:SetScript("OnDragStop", StopMove)
    prev = b
  end

  ApplyPos()
  frame:SetShown(VendorPointCharDB.floating == true)
end

---------------------------------------------------------------------------
-- Events and slash command
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    self:UnregisterEvent("ADDON_LOADED")
    VendorPointCharDB = VendorPointCharDB or {}
    VendorPointCharDB.hidden = nil -- 0.1.0 key, replaced by .floating
    local ok, err = pcall(CreateBagBar)
    if not ok then Print("Couldn't build the bag icons: " .. tostring(err)) end
    ok, err = pcall(RegisterBaganator)
    if not ok then Print("Couldn't add the Baganator buttons: " .. tostring(err)) end
    ok, err = pcall(CreateFloating)
    if not ok then Print("Couldn't build the frame: " .. tostring(err)) end
  elseif event == "PLAYER_ENTERING_WORLD" then
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    -- Bag addons build their windows at login. Look twice in case one is late.
    C_Timer.After(1, Rescan)
    C_Timer.After(6, Rescan)
    -- Baganator replaces ToggleAllBags at login, so hook it after that. A bag window
    -- built on first open is picked up here.
    C_Timer.After(2, function()
      for _, fn in ipairs({ "ToggleAllBags", "OpenAllBags", "ToggleBackpack", "OpenBackpack" }) do
        if type(_G[fn]) == "function" then hooksecurefunc(fn, function() C_Timer.After(0, Rescan) end) end
      end
    end)
    -- Build the NPC list in the background so the first click and tooltip are instant.
    -- A miss here (Questie still starting) is fine: the first click tries again.
    C_Timer.After(8, function() if not places then Build() end end)
  end
end)

local function Help()
  Print("/vp vendor | repair - pin the nearest")
  Print("/vp side inside | bottom | top | left | right - where the bag icons sit")
  Print("/vp frame - show/hide the floating frame; /vp lock | unlock | reset")
end

SLASH_VENDORPOINT1 = "/vp"
SLASH_VENDORPOINT2 = "/vendorpoint"
SlashCmdList.VENDORPOINT = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  local cmd, arg = msg:match("^(%S*)%s*(.-)$")
  if cmd == "vendor" or cmd == "repair" then
    for _, k in ipairs(KINDS) do if k.key == cmd then OnKindClick(k) end end
  elseif cmd == "side" then
    if arg == "header" or arg == "inside" then
      VendorPointCharDB.side = nil; Place(); Print("Bag icons back inside the bag window where there's a spot for them.")
    elseif SIDES[arg] then
      VendorPointCharDB.side = arg; Place(); Print("Bag icons now sit " .. arg .. " of the bag window.")
    else
      Print("/vp side inside | bottom | top | left | right")
    end
  elseif not frame then
    Print("The floating frame wasn't built. Check chat for the error from login.")
  elseif cmd == "frame" then
    VendorPointCharDB.floating = not frame:IsShown()
    frame:SetShown(VendorPointCharDB.floating)
    Print(VendorPointCharDB.floating and "Floating frame shown." or "Floating frame hidden.")
  elseif cmd == "lock" then
    VendorPointCharDB.locked = true; Print("Frame locked.")
  elseif cmd == "unlock" then
    VendorPointCharDB.locked = false; Print("Frame unlocked. Drag it to move.")
  elseif cmd == "reset" then
    VendorPointCharDB.pos = nil; VendorPointCharDB.floating = true
    ApplyPos(); frame:Show(); Print("Floating frame reset to the middle of the screen.")
  else
    Help()
  end
end
