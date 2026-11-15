-- Fake DCS and Skynet APIs for tests/lua/test_iads_init.lua (Lua 5.1, outside DCS).
-- Stubs.reset(world) installs a red side made of world.groups = { { name = ..., units = { {name=, type=}, ... }, unusable = bool } }
-- and world.statics = { [name] = { x =, y =, z = } }. Every call the code makes is recorded in Stubs.calls.

Stubs = {}

local function record(...)
  table.insert(Stubs.calls, table.concat({ ... }, " "))
end

local function element(name, kind)
  local e = { name = name, kind = kind, pointDefences = {}, powerSources = {} }
  function e:getDCSName() return self.name end
  function e:addPointDefence(pd) table.insert(self.pointDefences, pd); record("addPointDefence", self.name, pd.name) end
  function e:getPointDefences() return self.pointDefences end
  function e:addPowerSource(ps) table.insert(self.powerSources, ps); record("addPowerSource", self.name, ps.name) end
  function e:finishHarmDefence() record("finishHarmDefence", self.name) end
  function e:cleanUp() record("cleanUp", self.name) end
  function e:goLive() record("goLive", self.name) end
  return e
end

local function startsWith(s, prefix) return s:sub(1, #prefix) == prefix end

function Stubs.reset(world)
  Stubs.calls, Stubs.infos, Stubs.warnings, Stubs.menus, Stubs.scheduled, Stubs.explosions = {}, {}, {}, {}, {}, {}
  Stubs.world = world

  local groupsByName = {}
  local groups = {}
  for _, g in ipairs(world.groups or {}) do
    local units = {}
    for _, u in ipairs(g.units) do
      local unit = { name = u.name, type = u.type }
      function unit:getName() return self.name end
      function unit:getTypeName() return self.type end
      table.insert(units, unit)
    end
    local group = { name = g.name, units = units, unusable = g.unusable, category = g.category or 2 }
    function group:getName() return self.name end
    function group:getUnits() return self.units end
    function group:getCategory() return self.category end
    groupsByName[g.name] = group
    table.insert(groups, group)
  end

  coalition = { side = { NEUTRAL = 0, RED = 1, BLUE = 2 } }
  function coalition.getGroups(side) return side == coalition.side.RED and groups or {} end
  Group = { getByName = function(name) return groupsByName[name] end }
  StaticObject = {
    getByName = function(name)
      local p = (world.statics or {})[name]
      if not p then return nil end
      local s = { name = name, p = p }
      function s:getName() return self.name end
      function s:isExist() return true end
      function s:getPosition() return { p = self.p } end
      return s
    end,
  }
  env = {
    info = function(s) table.insert(Stubs.infos, s) end,
    warning = function(s) table.insert(Stubs.warnings, s) end,
    error = function(s) table.insert(Stubs.warnings, s) end,
  }
  timer = {
    getTime = function() return 100 end,
    scheduleFunction = function(fn, arg, t) table.insert(Stubs.scheduled, { fn = fn, arg = arg, t = t }) end,
  }
  trigger = { action = { explosion = function(p, power) table.insert(Stubs.explosions, { p = p, power = power }) end } }
  missionCommands = {
    addSubMenu = function(name, parent)
      local m = { name = name, commands = {} }
      table.insert(Stubs.menus, m)
      return m
    end,
    addCommand = function(name, parent, fn, arg) table.insert(parent.commands, { name = name, fn = fn, arg = arg }) end,
  }

  SkynetIADS = {}
  function SkynetIADS:create(name)
    record("create", name)
    local iads = { name = name, samSites = {}, ews = {}, ccs = {}, debug = { IADSStatus = false } }
    function iads:addEarlyWarningRadarsByPrefix(prefix)
      record("addEarlyWarningRadarsByPrefix", prefix)
      for _, g in ipairs(groups) do
        for _, u in ipairs(g.units) do
          if startsWith(u.name, prefix) then table.insert(self.ews, element(u.name, "EW")) end
        end
      end
    end
    function iads:addSAMSite(groupName)
      record("addSAMSite", groupName)
      local g = groupsByName[groupName]
      if not g or g.unusable then return nil end
      local e = element(groupName, "SAM")
      table.insert(self.samSites, e)
      return e
    end
    function iads:addSAMSitesByPrefix(prefix)
      record("addSAMSitesByPrefix", prefix)
      for _, g in ipairs(groups) do
        if startsWith(g.name, prefix) and not g.unusable then table.insert(self.samSites, element(g.name, "SAM")) end
      end
    end
    function iads:getSAMSiteByGroupName(n)
      for _, e in ipairs(self.samSites) do if e.name == n then return e end end
    end
    function iads:getEarlyWarningRadarByUnitName(n)
      for _, e in ipairs(self.ews) do if e.name == n then return e end end
    end
    function iads:addCommandCenter(static)
      record("addCommandCenter", static:getName())
      local cc = element(static:getName(), "CC")
      cc.dcs = static
      table.insert(self.ccs, cc)
      return cc
    end
    function iads:getSAMSites() return self.samSites end
    function iads:getEarlyWarningRadars() return self.ews end
    function iads:getCommandCenters() return self.ccs end
    function iads:getDebugSettings() return self.debug end
    function iads:activate() record("activate", self.name) end
    function iads:deactivate() record("deactivate", self.name) end
    return iads
  end
end

function Stubs.called(line)
  for _, c in ipairs(Stubs.calls) do if c == line then return true end end
  return false
end

function Stubs.index(line)
  for i, c in ipairs(Stubs.calls) do if c == line then return i end end
end

-- Minimal test runner
local passed, failed = 0, 0
function Stubs.test(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
function Stubs.eq(actual, expected, what)
  if actual ~= expected then
    error((what or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end
function Stubs.ok(cond, what) if not cond then error(what or "assertion failed", 2) end end
function Stubs.finish()
  print(string.format("%d passed, %d failed", passed, failed))
  if failed > 0 then os.exit(1) end
end
