local DebugMode = false

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Descriptors
-------------------------------------------------------------------------------------------------------------------------------------------------------------
local SkynetDescriptorOptionsFull =
{
    VeafSkynetMonitorDescriptor.Option.Ewr,
    VeafSkynetMonitorDescriptor.Option.Sam,
    VeafSkynetMonitorDescriptor.Option.ElementTargets,
    VeafSkynetMonitorDescriptor.Option.ElementStructure,
    VeafSkynetMonitorDescriptor.Option.ElementDetail,
    VeafSkynetMonitorDescriptor.Option.NestedPointDefences
}
local SkynetDescriptorOptionsEw =
{
    VeafSkynetMonitorDescriptor.Option.Ewr,
    VeafSkynetMonitorDescriptor.Option.ElementTargets,
    VeafSkynetMonitorDescriptor.Option.ElementStructure,
    VeafSkynetMonitorDescriptor.Option.ElementDetail,
    VeafSkynetMonitorDescriptor.Option.NestedPointDefences
}
local SkynetDescriptorOptionsSam =
{
    VeafSkynetMonitorDescriptor.Option.Sam,
    VeafSkynetMonitorDescriptor.Option.ElementTargets,
    VeafSkynetMonitorDescriptor.Option.ElementStructure,
    VeafSkynetMonitorDescriptor.Option.ElementDetail,
    VeafSkynetMonitorDescriptor.Option.NestedPointDefences
}

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Tools
-------------------------------------------------------------------------------------------------------------------------------------------------------------
local function CoalitionString(iCoalition)
    if (iCoalition == coalition.side.BLUE) then
        return "Blue"
    elseif (iCoalition == coalition.side.RED) then
        return "Red"
    else
        return "unk"
    end
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Methods
-------------------------------------------------------------------------------------------------------------------------------------------------------------
local function SkynetNetworkDescriptionToLog(descriptor)
    veaf.loggers.get(veafSkynetMonitor.Id):info(descriptor:GetStringDescription())
end

local function SkynetNetworkDisable(iCoalition)
    veafSkynet.destroyCommandCentersOfCoalition(iCoalition)
end

local function SkynetNetworkDeactivate(params)
    veafSkynet.deactivateNetworkOfCoalition(params.Coalition, params.State)
end

local function SkynetNetworkReactivate(iCoalition)
    veafSkynet.delayedActivate(veafSkynet.defaultIADS[tostring(iCoalition)])
end

local function SkynetNetworkDisplayState(veafSkynetNetwork, bDisplay)
    local iads = veafSkynetNetwork.iads
    local iadsDebug = iads:getDebugSettings()

    iadsDebug.IADSStatus = bDisplay
    iadsDebug.radarWentDark = bDisplay
    iadsDebug.contacts = bDisplay
    iadsDebug.radarWentLive = bDisplay
    iadsDebug.noWorkingCommmandCenter = bDisplay
    iadsDebug.ewRadarNoConnection = false
    iadsDebug.samNoConnection = false
    iadsDebug.jammerProbability = false
    iadsDebug.addedEWRadar = false
    iadsDebug.hasNoPower = false
    iadsDebug.harmDefence = bDisplay
    iadsDebug.samSiteStatusEnvOutput = false
    iadsDebug.earlyWarningRadarStatusEnvOutput = false    
end

local function SkynetNetworkSwitchDisplayStateSwitch(iCoalition)
    local veafSkynetNetwork = veafSkynet.getNetwork(veafSkynet.defaultIADS[tostring(iCoalition)])
    if (veafSkynetNetwork == nil) then
        return
    end

    local iads = veafSkynetNetwork.iads
    local iadsDebug = iads:getDebugSettings()
    local bDisplay = not iadsDebug.IADSStatus
    SkynetNetworkDisplayState(veafSkynetNetwork, bDisplay)
end

local function SkynetNetworkKillAwacs(iCoalition)
    if (iCoalition == coalition.side.RED) then
        Group.destroy(Group.getByName("Awacs #1"))
        Group.destroy(Group.getByName("Awacs #2"))
        Group.destroy(Group.getByName("Awacs #3"))    
    end
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------------------------------------------------------------------------------------
local function VeafSkynetNetworkFinalize(iCoalition)
    local veafSkynetNetwork = veafSkynet.getNetwork(veafSkynet.defaultIADS[tostring(iCoalition)])
    if (veafSkynetNetwork == nil) then
        return
    end

    local iads = veafSkynetNetwork.iads

    --veafSkynet.addCommandCenterOfCoalition(iCoalition, "CommandCenter" .. CoalitionString(iCoalition))
    SkynetNetworkDisplayState(veafSkynetNetwork, DebugMode)
    
    local skynetDescriptorFull = VeafSkynetMonitorDescriptor:Create(iads, SkynetDescriptorOptionsFull)
    local skynetDescriptorEw = VeafSkynetMonitorDescriptor:Create(iads, SkynetDescriptorOptionsEw)
    local skynetDescriptorSam = VeafSkynetMonitorDescriptor:Create(iads, SkynetDescriptorOptionsSam)
    local skynetDescriptorSa2 = VeafSkynetMonitorDescriptor:Create(iads, SkynetDescriptorOptionsSam)
    skynetDescriptorSa2.FilterNatoName = {"SA-2"}
    local skynetDescriptorSa5 = VeafSkynetMonitorDescriptor:Create(iads, SkynetDescriptorOptionsSam)
    skynetDescriptorSa5.FilterNatoName = {"SA-5"}
    local skynetDescriptorSa6 = VeafSkynetMonitorDescriptor:Create(iads, SkynetDescriptorOptionsSam)
    skynetDescriptorSa6.FilterNatoName = {"SA-6"}
    local skynetDescriptorSa10 = VeafSkynetMonitorDescriptor:Create(iads, SkynetDescriptorOptionsSam)
    skynetDescriptorSa10.FilterNatoName = {"SA-10"}
    local skynetDescriptorSa11 = VeafSkynetMonitorDescriptor:Create(iads, SkynetDescriptorOptionsSam)
    skynetDescriptorSa11.FilterNatoName = {"SA-11"}

    local sSubMenu = "Skynet " .. CoalitionString(iads:getCoalition())
    local sCommandDescription = "Network desc to log: "
    local menuVeafSkynet

    menuVeafSkynet = missionCommands.addSubMenu(sSubMenu)

    missionCommands.addCommand("Display/hide skynet status", menuVeafSkynet, SkynetNetworkSwitchDisplayStateSwitch, iCoalition)
    --missionCommands.addCommand(sCommandDescription .. "FULL", menuVeafSkynet, SkynetNetworkDescriptionToLog, skynetDescriptorFull)
    missionCommands.addCommand(sCommandDescription .. "EWR", menuVeafSkynet, SkynetNetworkDescriptionToLog, skynetDescriptorEw)
    missionCommands.addCommand(sCommandDescription .. "SAM", menuVeafSkynet, SkynetNetworkDescriptionToLog, skynetDescriptorSam)
    missionCommands.addCommand(sCommandDescription .. "SA-2", menuVeafSkynet, SkynetNetworkDescriptionToLog, skynetDescriptorSa2)
    missionCommands.addCommand(sCommandDescription .. "SA-5", menuVeafSkynet, SkynetNetworkDescriptionToLog, skynetDescriptorSa5)
    --missionCommands.addCommand(sCommandDescription .. "SA-6", menuVeafSkynet, SkynetNetworkDescriptionToLog, skynetDescriptorSa6)
    missionCommands.addCommand(sCommandDescription .. "SA-10", menuVeafSkynet, SkynetNetworkDescriptionToLog, skynetDescriptorSa10)
    --missionCommands.addCommand(sCommandDescription .. "SA-11", menuVeafSkynet, SkynetNetworkDescriptionToLog, skynetDescriptorSa11)
    missionCommands.addCommand("Disable network (destroy CC)", menuVeafSkynet, SkynetNetworkDisable, iCoalition)           
    --missionCommands.addCommand("Deactivate network (autonomous)", menuVeafSkynet, SkynetNetworkDeactivate, {Coalition = iCoalition, State = veafSkynet.SkynetElementStates.Autonomous})
    missionCommands.addCommand("Deactivate network", menuVeafSkynet, SkynetNetworkDeactivate, {Coalition = iCoalition, State = veafSkynet.SkynetElementStates.Live})           
    --missionCommands.addCommand("Deactivate network (dark)", menuVeafSkynet, SkynetNetworkDeactivate, {Coalition = iCoalition, State = veafSkynet.SkynetElementStates.Dark})           
    --missionCommands.addCommand("Reactivate network", menuVeafSkynet, SkynetNetworkReactivate, iCoalition)           
    
end

local function VeafSkynetFinalizeTask(_, time)
    if (not veafSkynet) then
        return nil
    end

    if (veafSkynet.initialized) then
        VeafSkynetNetworkFinalize(coalition.side.RED)
        return nil
    end

    veaf.loggers.get(veafSkynet.Id):trace("FinalizeVeafSkynetTask - waiting for Skynet IADS helpers to finish initialization")
    return time + 10
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------------------------------------------------------------------------------------

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Main logic
-------------------------------------------------------------------------------------------------------------------------------------------------------------
veaf.loggers.get(veafSkynetMonitor.Id):setLevel("info")
if (DebugMode) then
    --veaf.loggers.get(veaf.Id):setLevel("trace")
    veaf.loggers.get(veafSkynet.Id):setLevel("trace")
    veaf.loggers.get(veafSkynetMonitor.Id):setLevel("trace")
end

-- The mission starts Skynet itself (mission.yaml: SKYNET.initialized_by_mission), after
-- skynet-iads-3.6.0.lua has replaced the Skynet version bundled with VEAF MCT.
veafSkynet.PointDefenceMode = veafSkynet.PointDefenceModes.Skynet
veafSkynet.initialize(
    false, --includeRedInRadio
    false, --debugRed
    false, --includeBlueInRadio
    false  --debugBlue
)

timer.scheduleFunction(VeafSkynetFinalizeTask, nil, timer.getTime() + veafSkynet.DelayForStartup + 2)