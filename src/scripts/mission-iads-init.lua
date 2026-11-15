-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Red IADS: two Skynet networks built from group and unit names.
--
--   TBS  Tbilisi, with a command center (TBS-CC Tbilissi) powered by TBS-CC Tbilissi Power
--   MAP  every other scenario, no command center
--
-- Names (see README and docs/superpowers/specs/2026-11-14-red-iads-networks-design.md):
--   <NET>-EW ...        EW radar, matched by UNIT name (Skynet's rule)
--   <NET>-SAM ...       SAM site, matched by GROUP name
--   <NET>-PD <Site> #n  point defence of the site "<NET>-SAM <Site>" (or EW radar "<NET>-EW <Site>")
--   anything else       not in an IADS
--
-- Needs Skynet IADS (skynet-iads-vendored.lua) loaded before this file. Uses nothing from veafSkynet.
-------------------------------------------------------------------------------------------------------------------------------------------------------------

MissionIads = {}

MissionIads.DebugMode = false
MissionIads.ActivationDelay = 5 -- seconds after mission start, as veafSkynet.DelayForStartup did

MissionIads.Networks = {
  { code = "TBS", menu = "IADS Tbilissi", commandCenter = "TBS-CC Tbilissi", powerSource = "TBS-CC Tbilissi Power" },
  { code = "MAP", menu = "IADS Map" },
}

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Tools
-------------------------------------------------------------------------------------------------------------------------------------------------------------
local LOG_PREFIX = "MISSION IADS: "

function MissionIads.log(message)
  env.info(LOG_PREFIX .. message)
end

function MissionIads.warn(message)
  env.warning(LOG_PREFIX .. message)
end

local function escapePattern(s)
  return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

--- "MAP-PD SA-10 Gudauta #1", "MAP" -> "SA-10 Gudauta"; nil when the name is not a point defence of that network.
function MissionIads.parentSiteName(groupName, code)
  return groupName:match("^" .. escapePattern(code) .. "%-PD (.-) #%d+$")
end

--- "TBS" or "MAP" for a name carrying a network prefix, else nil.
function MissionIads.networkCodeOf(name)
  for _, network in ipairs(MissionIads.Networks) do
    if name:sub(1, #network.code + 1) == network.code .. "-" then
      return network.code
    end
  end
  return nil
end

--- The same Skynet debug outputs today's missionSkynetLogic.lua toggled.
function MissionIads.setStatusDisplay(network, bDisplay)
  local debug = network.iads:getDebugSettings()
  debug.IADSStatus = bDisplay
  debug.radarWentDark = bDisplay
  debug.contacts = bDisplay
  debug.radarWentLive = bDisplay
  debug.noWorkingCommmandCenter = bDisplay
  debug.harmDefence = bDisplay
  debug.ewRadarNoConnection = false
  debug.samNoConnection = false
  debug.jammerProbability = false
  debug.addedEWRadar = false
  debug.hasNoPower = false
  debug.samSiteStatusEnvOutput = false
  debug.earlyWarningRadarStatusEnvOutput = false
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Building
-------------------------------------------------------------------------------------------------------------------------------------------------------------
local function redGroupNames()
  local names = {}
  for _, group in ipairs(coalition.getGroups(coalition.side.RED) or {}) do
    table.insert(names, group:getName())
  end
  table.sort(names)
  return names
end

local function addPointDefences(network, iads)
  network.pointDefences = {}
  for _, groupName in ipairs(redGroupNames()) do
    local siteName = MissionIads.parentSiteName(groupName, network.code)
    if siteName then
      local ok, pd = pcall(iads.addSAMSite, iads, groupName)
      if not ok or not pd then
        MissionIads.warn(string.format("%s: Skynet could not use this point defence (%s)", groupName, tostring(ok and "no usable unit" or pd)))
      else
        local parent = iads:getSAMSiteByGroupName(network.code .. "-SAM " .. siteName)
          or iads:getEarlyWarningRadarByUnitName(network.code .. "-EW " .. siteName)
        if parent then
          parent:addPointDefence(pd)
          table.insert(network.pointDefences, { name = groupName, parent = parent:getDCSName() })
        else
          MissionIads.warn(string.format("%s: no site named %s-SAM/%s-EW %s; kept as a plain SAM site", groupName, network.code, network.code, siteName))
          table.insert(network.pointDefences, { name = groupName })
        end
      end
    end
  end
end

local function addCommandCenter(network, iads)
  if not network.commandCenter then
    return
  end
  local cc = StaticObject.getByName(network.commandCenter)
  if not cc then
    MissionIads.warn(string.format("%s: command center %s not found", network.menu, network.commandCenter))
    return
  end
  local skynetCc = iads:addCommandCenter(cc)
  if network.powerSource then
    local power = StaticObject.getByName(network.powerSource)
    if power then
      skynetCc:addPowerSource(power)
    else
      MissionIads.warn(string.format("%s: power source %s not found", network.menu, network.powerSource))
    end
  end
end

--- Create the network's IADS and fill it from the names; stores it in network.iads.
function MissionIads.build(network)
  local iads = SkynetIADS:create(network.menu)
  network.iads = iads
  iads:addEarlyWarningRadarsByPrefix(network.code .. "-EW")
  iads:addSAMSitesByPrefix(network.code .. "-SAM")
  addPointDefences(network, iads)
  addCommandCenter(network, iads)
  MissionIads.setStatusDisplay(network, MissionIads.DebugMode)
  return iads
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Startup report (dcs.log): what each network holds, and what is in none
-------------------------------------------------------------------------------------------------------------------------------------------------------------
local NOT_OURS = { "^Qra_Tbilissi%-", "^veafSpawn%-" } -- red aircraft that are not IADS material

local function skynetUnitTypes()
  local types = {}
  for _, entry in pairs((SkynetIADS and SkynetIADS.database) or {}) do
    for _, list in ipairs({ "searchRadar", "trackingRadar", "launchers", "misc" }) do
      for unitType in pairs(entry[list] or {}) do
        types[unitType] = true
      end
    end
  end
  return types
end

local function names(elements)
  local list = {}
  for _, e in ipairs(elements or {}) do table.insert(list, e:getDCSName()) end
  table.sort(list)
  return list
end

local function reportNetwork(network)
  local iads = network.iads
  local ews, sams = names(iads:getEarlyWarningRadars()), names(iads:getSAMSites())
  local pds = network.pointDefences or {}
  MissionIads.log(string.format("%s: %d EW radars, %d SAM sites (%d of them point defences)", network.menu, #ews, #sams, #pds))
  MissionIads.log("  EW: " .. table.concat(ews, ", "))
  MissionIads.log("  SAM: " .. table.concat(sams, ", "))
  for _, pd in ipairs(pds) do
    MissionIads.log(string.format("  PD: %s -> %s", pd.name, pd.parent or "(no parent)"))
  end
  if network.commandCenter then
    local ccs = names(iads:getCommandCenters())
    MissionIads.log(string.format("  command center %s, power %s", ccs[1] or "MISSING", network.powerSource or "none"))
  end

  -- prefixed names Skynet did not take
  for _, group in ipairs(coalition.getGroups(coalition.side.RED) or {}) do
    local groupName = group:getName()
    if groupName:sub(1, #network.code + 5) == network.code .. "-SAM " and not iads:getSAMSiteByGroupName(groupName) then
      MissionIads.warn(groupName .. ": named as a SAM site, but Skynet did not take it (no usable unit?)")
    end
    for _, unit in ipairs(group:getUnits() or {}) do
      local unitName = unit:getName()
      if unitName:sub(1, #network.code + 4) == network.code .. "-EW " and not iads:getEarlyWarningRadarByUnitName(unitName) then
        MissionIads.warn(unitName .. ": named as an EW radar, but Skynet did not take it")
      end
    end
  end
end

function MissionIads.report()
  for _, network in ipairs(MissionIads.Networks) do
    if network.iads then
      reportNetwork(network)
    end
  end

  local skynetTypes = skynetUnitTypes()
  local outside = {}
  for _, group in ipairs(coalition.getGroups(coalition.side.RED) or {}) do
    local groupName = group:getName()
    local ours = true
    for _, pattern in ipairs(NOT_OURS) do
      if groupName:find(pattern) then ours = false end
    end
    if ours and not MissionIads.networkCodeOf(groupName) then
      table.insert(outside, groupName)
      for _, unit in ipairs(group:getUnits() or {}) do
        if skynetTypes[unit:getTypeName()] then
          MissionIads.warn(groupName .. ": has a unit Skynet could use (" .. unit:getTypeName() .. ") but no network prefix; typo?")
          break
        end
      end
    end
  end
  table.sort(outside)
  MissionIads.log(string.format("%d red groups not in any IADS: %s", #outside, table.concat(outside, ", ")))
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- F10 menu
-------------------------------------------------------------------------------------------------------------------------------------------------------------
MissionIads.CommandCenterExplosionPower = 200 -- the default explosion may not be enough for a bunker

function MissionIads.toggleStatus(network)
  MissionIads.setStatusDisplay(network, not network.iads:getDebugSettings().IADSStatus)
end

--- The IADS stops; every site goes live and fights on its own.
function MissionIads.deactivate(network)
  local iads = network.iads
  iads:deactivate()
  local elements = {}
  for _, e in ipairs(iads:getEarlyWarningRadars() or {}) do table.insert(elements, e) end
  for _, e in ipairs(iads:getSAMSites() or {}) do table.insert(elements, e) end
  for _, e in ipairs(elements) do
    e:finishHarmDefence()
    e:cleanUp()
    e:goLive() -- will not always turn the radar on, e.g. a site out of ammo stays off
  end
  MissionIads.log(network.menu .. " deactivated: every site is on its own")
end

function MissionIads.destroyCommandCenter(network)
  for _, cc in ipairs(network.iads:getCommandCenters() or {}) do
    local dcsObject = cc:getDCSRepresentation()
    if dcsObject and dcsObject:isExist() then
      trigger.action.explosion(dcsObject:getPosition().p, MissionIads.CommandCenterExplosionPower)
      MissionIads.log(network.menu .. ": command center " .. dcsObject:getName() .. " blown up")
    end
  end
end

function MissionIads.addMenus()
  for _, network in ipairs(MissionIads.Networks) do
    if network.iads then
      local menu = missionCommands.addSubMenu(network.menu)
      missionCommands.addCommand("Display/hide Skynet status", menu, MissionIads.toggleStatus, network)
      missionCommands.addCommand("Deactivate network", menu, MissionIads.deactivate, network)
      if network.commandCenter then
        missionCommands.addCommand("Disable network (destroy CC)", menu, MissionIads.destroyCommandCenter, network)
      end
    end
  end
end

local function activateAll()
  for _, network in ipairs(MissionIads.Networks) do
    if network.iads then
      network.iads:activate()
    end
  end
  local ok, err = pcall(MissionIads.report)
  if not ok then
    MissionIads.warn("report failed: " .. tostring(err))
  end
  MissionIads.addMenus()
  return nil
end

function MissionIads.start()
  for _, network in ipairs(MissionIads.Networks) do
    local ok, err = pcall(MissionIads.build, network)
    if not ok then
      MissionIads.warn(string.format("%s: build failed: %s", network.menu, tostring(err)))
    end
  end
  timer.scheduleFunction(activateAll, nil, timer.getTime() + MissionIads.ActivationDelay)
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Main
-------------------------------------------------------------------------------------------------------------------------------------------------------------
if not MISSION_IADS_TEST then
  MissionIads.start()
end
