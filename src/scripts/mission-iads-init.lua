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

local function activateAll()
  for _, network in ipairs(MissionIads.Networks) do
    if network.iads then
      network.iads:activate()
    end
  end
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
