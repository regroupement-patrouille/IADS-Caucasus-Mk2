-- Run: "C:/Program Files (x86)/Lua/5.1/lua.exe" tests/lua/test_iads_init.lua   (from the repo root)

dofile("tests/lua/stubs.lua")
local test, eq, ok = Stubs.test, Stubs.eq, Stubs.ok

local WORLD = {
  groups = {
    { name = "TBS-EW Tbilissi", units = { { name = "TBS-EW Tbilissi", type = "55G6 EWR" } } },
    { name = "TBS-SAM SA-10 Kumisi", units = { { name = "TBS-SAM SA-10 Kumisi-01", type = "S-300PS 40B6M tr" } } },
    { name = "TBS-PD SA-10 Kumisi #1", units = { { name = "TBS-PD SA-10 Kumisi #1-01", type = "CHAP_TorM2" } } },
    { name = "TBS-PD Tbilissi #1", units = { { name = "TBS-PD Tbilissi #1-01", type = "CHAP_PantsirS1" } } },
    { name = "MAP-EW Pervo", units = { { name = "MAP-EW Pervo", type = "55G6 EWR" } } },
    { name = "MAP-SAM SA-10 Gudauta", units = { { name = "MAP-SAM SA-10 Gudauta-01", type = "S-300PS 40B6M tr" } } },
    { name = "MAP-PD SA-10 Gudauta #1", units = { { name = "MAP-PD SA-10 Gudauta #1-01", type = "CHAP_TorM2" } } },
    { name = "MAP-PD Pervo #3", units = { { name = "MAP-PD Pervo #3-01", type = "CHAP_TorM2" } } },
    { name = "MAP-PD SA-2 Nowhere #1", units = { { name = "MAP-PD SA-2 Nowhere #1-01", type = "CHAP_TorM2" } } },
    { name = "MAP-SAM SA-2 Broken", units = { { name = "MAP-SAM SA-2 Broken-01", type = "Ural-375" } }, unusable = true },
    { name = "MAP-PD SA-2 Broken #1", units = { { name = "MAP-PD SA-2 Broken #1-01", type = "Ural-375" } }, unusable = true },
    { name = "Rapier Dzhvari #1", units = { { name = "Rapier Dzhvari #1-01", type = "Ural-375" } } },
  },
  statics = {
    ["TBS-CC Tbilissi"] = { x = 1, y = 0, z = 2 },
    ["TBS-CC Tbilissi Power"] = { x = 3, y = 0, z = 4 },
  },
}

local function load()
  Stubs.reset(WORLD)
  MISSION_IADS_TEST = true
  MissionIads = nil
  dofile("src/scripts/mission-iads-init.lua")
  return MissionIads
end

local function network(code)
  for _, n in ipairs(MissionIads.Networks) do if n.code == code then return n end end
end

test("test_parent_site_name", function()
  local M = load()
  eq(M.parentSiteName("TBS-PD SA-10 Kumisi #1", "TBS"), "SA-10 Kumisi")
  eq(M.parentSiteName("MAP-PD Pervo #3", "MAP"), "Pervo")
  eq(M.parentSiteName("MAP-PD SA-15 Dzhvari-4 #12", "MAP"), "SA-15 Dzhvari-4")
end)

test("test_parent_site_name_rejects_non_pd", function()
  local M = load()
  eq(M.parentSiteName("MAP-SAM SA-2 Poti", "MAP"), nil)
  eq(M.parentSiteName("TBS-PD SA-10 Kumisi #1", "MAP"), nil)
  eq(M.parentSiteName("MAP-PD SA-10 Gudauta", "MAP"), nil)
end)

test("test_network_code_of", function()
  local M = load()
  eq(M.networkCodeOf("TBS-SAM SA-10 Kumisi"), "TBS")
  eq(M.networkCodeOf("MAP-EW Awacs Mozdok"), "MAP")
  eq(M.networkCodeOf("Rapier Dzhvari #1"), nil)
  eq(M.networkCodeOf("MAPLE-SAM x"), nil)
end)

test("test_networks_definition", function()
  local M = load()
  eq(#M.Networks, 2)
  eq(M.Networks[1].code, "TBS"); eq(M.Networks[1].menu, "IADS Tbilissi")
  eq(M.Networks[1].commandCenter, "TBS-CC Tbilissi"); eq(M.Networks[1].powerSource, "TBS-CC Tbilissi Power")
  eq(M.Networks[2].code, "MAP"); eq(M.Networks[2].menu, "IADS Map"); eq(M.Networks[2].commandCenter, nil)
  eq(M.DebugMode, false); eq(M.ActivationDelay, 5)
end)

test("test_build_tbs", function()
  local M = load()
  local iads = M.build(network("TBS"))
  ok(network("TBS").iads == iads, "network.iads is set")
  ok(Stubs.called("create IADS Tbilissi"), "created")
  ok(Stubs.called("addEarlyWarningRadarsByPrefix TBS-EW"), "EW by prefix")
  ok(Stubs.called("addSAMSitesByPrefix TBS-SAM"), "SAM by prefix")
  ok(Stubs.called("addPointDefence TBS-SAM SA-10 Kumisi TBS-PD SA-10 Kumisi #1"), "PD linked to SAM parent")
  ok(Stubs.called("addPointDefence TBS-EW Tbilissi TBS-PD Tbilissi #1"), "PD linked to EW parent")
  ok(Stubs.called("addCommandCenter TBS-CC Tbilissi"), "command center")
  ok(Stubs.called("addPowerSource TBS-CC Tbilissi TBS-CC Tbilissi Power"), "power source")
  ok(not Stubs.called("addSAMSite MAP-PD SA-10 Gudauta #1"), "no MAP group in TBS")
  eq(#Stubs.warnings, 0, "warnings")
end)

test("test_build_map", function()
  local M = load()
  M.build(network("MAP"))
  ok(Stubs.called("addPointDefence MAP-SAM SA-10 Gudauta MAP-PD SA-10 Gudauta #1"), "PD to SAM")
  ok(Stubs.called("addPointDefence MAP-EW Pervo MAP-PD Pervo #3"), "PD to EW")
  ok(not Stubs.called("addCommandCenter TBS-CC Tbilissi"), "no CC in MAP")
end)

test("test_pd_without_parent_warns", function()
  local M = load()
  M.build(network("MAP"))
  local nowhere = 0
  for _, w in ipairs(Stubs.warnings) do if w:find("MAP-PD SA-2 Nowhere #1", 1, true) then nowhere = nowhere + 1 end end
  eq(nowhere, 1, "warnings naming the orphan PD")
  ok(Stubs.called("addSAMSite MAP-PD SA-2 Nowhere #1"), "orphan PD still added as a SAM site")
end)

test("test_unusable_pd_warns", function()
  local M = load()
  M.build(network("MAP"))
  local broken = 0
  for _, w in ipairs(Stubs.warnings) do if w:find("MAP-PD SA-2 Broken #1", 1, true) then broken = broken + 1 end end
  eq(broken, 1, "warning naming the unusable PD")
end)

test("test_start_builds_and_schedules_activation", function()
  local M = load()
  M.start()
  ok(network("TBS").iads and network("MAP").iads, "both built")
  eq(#Stubs.scheduled, 1, "one scheduled activation")
  eq(Stubs.scheduled[1].t, 105, "activation time")
  Stubs.scheduled[1].fn(Stubs.scheduled[1].arg, 105)
  ok(Stubs.called("activate IADS Tbilissi") and Stubs.called("activate IADS Map"), "both activated")
end)

local function menu(name)
  for _, m in ipairs(Stubs.menus) do if m.name == name then return m end end
end

local function commandNames(m)
  local names = {}
  for _, c in ipairs(m.commands) do table.insert(names, c.name) end
  return table.concat(names, " | ")
end

local function command(m, name)
  for _, c in ipairs(m.commands) do if c.name == name then return c end end
end

test("test_menus", function()
  local M = load()
  M.build(network("TBS")); M.build(network("MAP"))
  M.addMenus()
  eq(#Stubs.menus, 2, "submenus")
  eq(commandNames(menu("IADS Tbilissi")), "Display/hide Skynet status | Deactivate network | Disable network (destroy CC)")
  eq(commandNames(menu("IADS Map")), "Display/hide Skynet status | Deactivate network")
end)

test("test_menus_added_after_activation", function()
  local M = load()
  M.start()
  eq(#Stubs.menus, 0, "no menu before activation")
  Stubs.scheduled[1].fn(Stubs.scheduled[1].arg, 105)
  eq(#Stubs.menus, 2, "menus after activation")
end)

test("test_toggle_status", function()
  local M = load()
  local tbs = network("TBS")
  M.build(tbs)
  local keys = { "IADSStatus", "radarWentDark", "contacts", "radarWentLive", "noWorkingCommmandCenter", "harmDefence" }
  M.toggleStatus(tbs)
  for _, k in ipairs(keys) do eq(tbs.iads:getDebugSettings()[k], true, k) end
  M.toggleStatus(tbs)
  for _, k in ipairs(keys) do eq(tbs.iads:getDebugSettings()[k], false, k) end
end)

test("test_destroy_command_center", function()
  local M = load()
  local tbs = network("TBS")
  M.build(tbs)
  M.destroyCommandCenter(tbs)
  eq(#Stubs.explosions, 1, "explosions")
  eq(Stubs.explosions[1].power, 200, "power")
  eq(Stubs.explosions[1].p.x, 1, "x"); eq(Stubs.explosions[1].p.z, 2, "z")
end)

test("test_deactivate", function()
  local M = load()
  local map = network("MAP")
  M.build(map)
  M.deactivate(map)
  local d = Stubs.index("deactivate IADS Map")
  ok(d, "IADS deactivated")
  for _, name in ipairs({ "MAP-EW Pervo", "MAP-SAM SA-10 Gudauta", "MAP-PD SA-10 Gudauta #1" }) do
    local f, c, l = Stubs.index("finishHarmDefence " .. name), Stubs.index("cleanUp " .. name), Stubs.index("goLive " .. name)
    ok(f and c and l, name .. " finish/cleanUp/goLive")
    ok(d < f and f < c and c < l, name .. " in order")
  end
end)

test("test_file_runs_start_outside_tests", function()
  Stubs.reset(WORLD)
  MISSION_IADS_TEST = nil
  MissionIads = nil
  dofile("src/scripts/mission-iads-init.lua")
  ok(Stubs.called("create IADS Tbilissi"), "start() ran on load")
end)

Stubs.finish()
