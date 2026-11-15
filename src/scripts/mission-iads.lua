-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Initialization of the Skynet managed IADS of the mission, from the groups and units conventionally named in the editor.
--
-- Names conventions:
--   <NET>-EW ...        EW radar, matched by UNIT name (Skynet's rule)
--   <NET>-SAM ...       SAM site, matched by GROUP name
--   <NET>-PD <Site> #n  point defence of the site "<NET>-SAM <Site>" (or EW radar "<NET>-EW <Site>")
--   anything else       not in an IADS
--
-- Currently two red IADS:
--   TBS: Tbilisi, with a command center (TBS-CC Tbilissi) powered by TBS-CC Tbilissi Power
--   MAP: every other scenario, no command center
--
-- Needs skynet-iads-vendored.lua loaded before this file. Uses nothing from veafSkynet.
-------------------------------------------------------------------------------------------------------------------------------------------------------------

MissionIads = {}

MissionIads.LogPrefix = "MISSION IADS: "
MissionIads.ActivationDelay = 5 -- seconds after mission start
MissionIads.CommandCenterExplosionPower = 200 -- the default explosion may not be enough for a bunker
MissionIads.PowerSourceExplosionPower = 200
MissionIads.ManagedIads = {
  { code = "TBS", name = "IADS Tbilissi", coalition = coalition.side.RED, commandCenter = "TBS-CC Tbilissi", ccPowerSource = "TBS-CC Tbilissi Power" },
  { code = "MAP", name = "IADS Map", coalition = coalition.side.RED },
}

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Tools
-------------------------------------------------------------------------------------------------------------------------------------------------------------
function MissionIads.log(message)
  env.info(MissionIads.LogPrefix .. message)
end

function MissionIads.warn(message)
  env.warning(MissionIads.LogPrefix .. message)
end

function MissionIads.guardedCall(what, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    MissionIads.warn(string.format("%s failed: %s", what, tostring(err)))
  end
  return ok
end

function MissionIads.coalitionName(coalitionSide)
  if coalitionSide == coalition.side.RED then
    return "red"
  elseif coalitionSide == coalition.side.BLUE then
    return "blue"
  else
    return "neutral"
  end
end

--- "MAP-PD SA-10 Gudauta #1", "MAP" -> "SA-10 Gudauta"; nil when the name is not a point defence of that network.
function MissionIads.extractGroupParentSiteName(groupName, managedIadsCode)
  local escapedIadsCode = managedIadsCode:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
  return groupName:match("^" .. escapedIadsCode .. "%-PD (.-) #%d+$")
end

--- "TBS" or "MAP" for a name carrying a network prefix, else nil.
function MissionIads.extractGroupIadsCode(groupName)
  for _, managedIads in ipairs(MissionIads.ManagedIads) do
    if groupName:sub(1, #managedIads.code + 1) == managedIads.code .. "-" then
      return managedIads.code
    end
  end
  return nil
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- IADS actions
-------------------------------------------------------------------------------------------------------------------------------------------------------------
function MissionIads.setStatusDisplay(managedIads, bDisplay)
  local skynetDebugSettings = managedIads.skynetIads:getDebugSettings()
  skynetDebugSettings.IADSStatus = bDisplay
  skynetDebugSettings.radarWentDark = bDisplay
  skynetDebugSettings.contacts = bDisplay
  skynetDebugSettings.radarWentLive = bDisplay
  skynetDebugSettings.harmDefence = bDisplay
  skynetDebugSettings.samNoConnection = false
  skynetDebugSettings.jammerProbability = false
  skynetDebugSettings.addedEWRadar = false
  skynetDebugSettings.hasNoPower = false
  skynetDebugSettings.samSiteStatusEnvOutput = false
  skynetDebugSettings.earlyWarningRadarStatusEnvOutput = false
end

function MissionIads.destroyCommandCenter(managedIads)
  for _, cc in ipairs(managedIads.skynetIads:getCommandCenters() or {}) do
    local dcsObject = cc:getDCSRepresentation()
    if dcsObject and dcsObject:isExist() then
      trigger.action.explosion(dcsObject:getPosition().p, MissionIads.CommandCenterExplosionPower)
      MissionIads.log(managedIads.name .. ": command center " .. dcsObject:getName() .. " blown up")
    end
  end
end

--- Blow up every power source of every command center. A command center without power is as good as destroyed for
--- Skynet: on its next check the SAM sites lose their link and go autonomous.
function MissionIads.destroyCcPowerSource(managedIads)
  for _, cc in ipairs(managedIads.skynetIads:getCommandCenters() or {}) do
    -- Skynet keeps the DCS objects themselves (the StaticObject given to addPowerSource)
    for _, powerSource in ipairs(cc:getPowerSources() or {}) do
      if powerSource:isExist() then
        local powerSourceName = powerSource:getName()
        trigger.action.explosion(powerSource:getPosition().p, MissionIads.PowerSourceExplosionPower)
        MissionIads.log(managedIads.name .. ": power source " .. powerSourceName .. " of " .. cc:getDCSName() .. " blown up")
      end
    end
  end
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Building
-------------------------------------------------------------------------------------------------------------------------------------------------------------
function MissionIads.missionGroupNames(coalitionSide)
  local groupNames = {}
  for _, group in ipairs(coalition.getGroups(coalitionSide) or {}) do
    table.insert(groupNames, group:getName())
  end
  table.sort(groupNames)
  return groupNames
end

function MissionIads.addPointDefences(managedIads)
  local skynetIads = managedIads.skynetIads
  managedIads.pointDefences = {}
  for _, groupName in ipairs(MissionIads.missionGroupNames(managedIads.coalition)) do
    local siteName = MissionIads.extractGroupParentSiteName(groupName, managedIads.code)
    if siteName then
      local ok, pd = pcall(skynetIads.addSAMSite, skynetIads, groupName)
      if not ok or not pd then
        MissionIads.warn(string.format("%s: Skynet could not use this point defence (%s)", groupName, tostring(ok and "no usable unit" or pd)))
      else
        local parent = skynetIads:getSAMSiteByGroupName(managedIads.code .. "-SAM " .. siteName)
          or skynetIads:getEarlyWarningRadarByUnitName(managedIads.code .. "-EW " .. siteName)
        if parent then
          parent:addPointDefence(pd)
          table.insert(managedIads.pointDefences, { name = groupName, parent = parent:getDCSName() })
        else
          MissionIads.warn(string.format("%s: no site named %s-SAM/%s-EW %s; kept as a plain SAM site", groupName, managedIads.code, managedIads.code, siteName))
          table.insert(managedIads.pointDefences, { name = groupName })
        end
      end
    end
  end
end

function MissionIads.addCommandCenter(managedIads)
  local skynetIads = managedIads.skynetIads

  if not managedIads.commandCenter then
    return
  end
  local cc = StaticObject.getByName(managedIads.commandCenter)
  if not cc then
    MissionIads.warn(string.format("%s: command center %s not found", managedIads.name, managedIads.commandCenter))
    return
  end
  local skynetCc = skynetIads:addCommandCenter(cc)
  if managedIads.ccPowerSource then
    local powerSource = StaticObject.getByName(managedIads.ccPowerSource)
    if powerSource then
      skynetCc:addPowerSource(powerSource)
    else
      MissionIads.warn(string.format("%s: power source %s not found", managedIads.name, managedIads.ccPowerSource))
    end
  end
end

--- Create the IADS in Skynet and fill it from the names; stores it in managedIads.skynetIads.
function MissionIads.buildIads(managedIads)
  local skynetIads = SkynetIADS:create(managedIads.name)
  managedIads.skynetIads = skynetIads
  local ewPrefix, samPrefix = managedIads.code .. "-EW", managedIads.code .. "-SAM"
  MissionIads.guardedCall(managedIads.name .. ": EW radars " .. ewPrefix, skynetIads.addEarlyWarningRadarsByPrefix, skynetIads, ewPrefix)
  MissionIads.guardedCall(managedIads.name .. ": SAM sites " .. samPrefix, skynetIads.addSAMSitesByPrefix, skynetIads, samPrefix)
  MissionIads.guardedCall(managedIads.name .. ": point defences", MissionIads.addPointDefences, managedIads)
  MissionIads.guardedCall(managedIads.name .. ": command center", MissionIads.addCommandCenter, managedIads)
  MissionIads.guardedCall(managedIads.name .. ": debug settings", MissionIads.setStatusDisplay, managedIads, false)
  return skynetIads
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Startup report (dcs.log): what each network holds, and what is in none
-------------------------------------------------------------------------------------------------------------------------------------------------------------
function MissionIads.skynetUnitTypes()
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

function MissionIads.elementsDcsNames(elements)
  local list = {}
  for _, e in ipairs(elements or {}) do table.insert(list, e:getDCSName()) end
  table.sort(list)
  return list
end

function MissionIads.reportNetwork(managedIads)
  local skynetIads = managedIads.skynetIads
  local ews, sams = MissionIads.elementsDcsNames(skynetIads:getEarlyWarningRadars()), MissionIads.elementsDcsNames(skynetIads:getSAMSites())
  local pds = managedIads.pointDefences or {}
  MissionIads.log(string.format("%s: %d EW radars, %d SAM sites (%d of them point defences)", managedIads.name, #ews, #sams, #pds))
  MissionIads.log("  EW: " .. table.concat(ews, ", "))
  MissionIads.log("  SAM: " .. table.concat(sams, ", "))
  for _, pd in ipairs(pds) do
    MissionIads.log(string.format("  PD: %s -> %s", pd.name, pd.parent or "(no parent)"))
  end
  if managedIads.commandCenter then
    local ccs = MissionIads.elementsDcsNames(skynetIads:getCommandCenters())
    MissionIads.log(string.format("  command center %s, power %s", ccs[1] or "MISSING", managedIads.ccPowerSource or "none"))
  end

  -- prefixed names Skynet did not take
  for _, group in ipairs(coalition.getGroups(managedIads.coalition) or {}) do
    local groupName = group:getName()
    if groupName:sub(1, #managedIads.code + 5) == managedIads.code .. "-SAM " and not skynetIads:getSAMSiteByGroupName(groupName) then
      MissionIads.warn(groupName .. ": named as a SAM site, but Skynet did not take it (no usable unit?)")
    end
    for _, unit in ipairs(group:getUnits() or {}) do
      local unitName = unit:getName()
      if unitName:sub(1, #managedIads.code + 4) == managedIads.code .. "-EW " and not skynetIads:getEarlyWarningRadarByUnitName(unitName) then
        MissionIads.warn(unitName .. ": named as an EW radar, but Skynet did not take it")
      end
    end
  end

  -- Skynet takes any unit named as an EW radar, even one without a radar it knows: say so
  for _, ew in ipairs(skynetIads:getEarlyWarningRadars() or {}) do
    if #(ew:getSearchRadars() or {}) == 0 then
      MissionIads.warn(ew:getDCSName() .. ": named as an EW radar, but Skynet knows no search radar in it")
    end
  end
end

--- Type name of the first unit of the group that Skynet knows, else nil.
function MissionIads.firstSkynetUnitType(group, skynetTypes)
  for _, unit in ipairs(group:getUnits() or {}) do
    local unitType = unit:getTypeName()
    if skynetTypes[unitType] then
      return unitType
    end
  end
  return nil
end

--- Groups without a network prefix that hold at least one unit Skynet could use: probably a naming typo.
function MissionIads.reportOutsideGroups(coalitionSide)
  local skynetTypes = MissionIads.skynetUnitTypes()
  local outside = {}

  for _, group in ipairs(coalition.getGroups(coalitionSide) or {}) do
    local groupName = group:getName()
    if not MissionIads.extractGroupIadsCode(groupName) then
      local unitType = MissionIads.firstSkynetUnitType(group, skynetTypes)
      if unitType then
        table.insert(outside, groupName)
        MissionIads.warn(groupName .. ": has a unit Skynet could use (" .. unitType .. ") but no network prefix; typo?")
      end
    end
  end
  table.sort(outside)
  MissionIads.log(string.format("%d %s groups with Skynet units not in any IADS: %s", #outside, MissionIads.coalitionName(coalitionSide), table.concat(outside, ", ")))
end

function MissionIads.report()
  for _, managedIads in ipairs(MissionIads.ManagedIads) do
    if managedIads.skynetIads then
      MissionIads.reportNetwork(managedIads)
    end
  end

  MissionIads.reportOutsideGroups(coalition.side.RED)
  MissionIads.reportOutsideGroups(coalition.side.BLUE)
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- F10 menu
-------------------------------------------------------------------------------------------------------------------------------------------------------------
function MissionIads.toggleStatusDisplay(managedIads)
  MissionIads.setStatusDisplay(managedIads, not managedIads.skynetIads:getDebugSettings().IADSStatus)
end

function MissionIads.addMenus()
  for _, managedIads in ipairs(MissionIads.ManagedIads) do
    if managedIads.skynetIads then
      local menu = missionCommands.addSubMenu(managedIads.name)
      missionCommands.addCommand("Display/hide Skynet status", menu, MissionIads.toggleStatusDisplay, managedIads)
      if managedIads.commandCenter then
        missionCommands.addCommand("Disable network (destroy CC)", menu, MissionIads.destroyCommandCenter, managedIads)
      end
      if managedIads.ccPowerSource then
        missionCommands.addCommand("Disable network (destroy CC power source)", menu, MissionIads.destroyCcPowerSource, managedIads)
      end
    end
  end
end

function MissionIads.activateAll()
  for _, managedIads in ipairs(MissionIads.ManagedIads) do
    if managedIads.skynetIads then
      MissionIads.guardedCall(managedIads.name .. ": activation", managedIads.skynetIads.activate, managedIads.skynetIads)
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
  for _, managedIads in ipairs(MissionIads.ManagedIads) do
    local ok, err = pcall(MissionIads.buildIads, managedIads)
    if not ok then
      MissionIads.warn(string.format("%s: build failed: %s", managedIads.name, tostring(err)))
    end
  end
  timer.scheduleFunction(MissionIads.activateAll, nil, timer.getTime() + MissionIads.ActivationDelay)
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Main
-------------------------------------------------------------------------------------------------------------------------------------------------------------
MissionIads.start()
